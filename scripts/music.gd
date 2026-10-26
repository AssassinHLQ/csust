class_name Music
extends RefCounted
## 背景音乐：**逻辑名 → 文件**，同一时刻只放一首，带淡入淡出。
##
## ── 为什么和 `sfx.gd` 分开 ──
## 音效是「一次响一声、允许叠、池子里轮转」；音乐是「一首循环、独占、要淡入淡出」，
## 两者的生命周期完全不同。混在一个类里会让 `play()` 的语义变成两种。
##
## ── 和 `sfx.gd` 一样的三个取舍（理由见那个文件开头）──
##   1. 纯静态类、不用 autoload —— `--script` 自检模式下 autoload 的名字不是编译期
##      可见的标识符，产品脚本里写 `Sfx.xxx` / `Music.xxx` 会整份编译失败。
##   2. 宿主节点懒创建，第一次 `play()` 时才挂到 `root` 底下，不改任何 .tscn。
##   3. 宿主 `process_mode = ALWAYS` —— 设置菜单/剧情把世界暂停时，音乐照常播。
##
## ── 循环从哪来 ──
## **不在代码里设**：循环是 Godot 的 ogg 导入选项（`.import` 里的 `loop=true`）。
## 代码只负责「播放 / 停止 / 交叉淡入淡出」。理由：导入期就定好循环点，
## 运行期不用每帧盯 `finished` 信号再 `play()` 一次，也不会有那一帧的空隙。

## 音乐文件目录
const DIR := "res://assets/music/"

## 逻辑名 → {file, db}
##   db  基准音量（负数是变小）。再叠加 `GameSettings` 的主音量（走 Master 总线）
const TRACKS := {
	# 商店（天使24）的 BGM。素材：UNDERTALE「Tem Shop」。
	# ⚠️ 源文件 45.44 s，**只取前 40.2094 s** —— 那个长度是把整段做自相关之后
	#    定出来的循环点：曲子自身的循环周期是 5.0262 s，40.2094 = 5.0262 × 8
	#    （误差 0.2 ms）。直接按整数 40.000 s 切，接缝处与开头的相关系数只有
	#    +0.06、跳变是曲子内部平均跳变的 1.8 倍（会「咔」一下）；
	#    切在 40.2094 s 上相关系数 +0.66，再做过 25 ms 环绕交叉淡化。
	#    生成脚本与推导见 `_tools` 旁边的说明，或本条提交信息。
	"shop": {"file": "shop_theme.ogg", "db": -13.0},
}

## 默认淡入/淡出时长（秒）
const FADE_DEFAULT := 1.2

static var _host: Node
static var _player: AudioStreamPlayer
static var _tween: Tween
static var _current := ""
static var _cache := {}
static var _missing := {}


## 播一首。同一首已经在放就什么都不做（不会重头开始）。
static func play(track: String, fade: float = FADE_DEFAULT) -> bool:
	if not TRACKS.has(track):
		push_warning("[Music] 没有这首：%s" % track)
		return false
	if track == _current and _player != null and _player.playing:
		return true
	if not _ensure_host():
		return false
	var stream := _load_stream(track)
	if stream == null:
		return false
	var info: Dictionary = TRACKS[track]
	var db := float(info.get("db", -12.0))
	_player.stream = stream
	# 先开声再淡入：`volume_db` 从很低起步，避免第一帧「啪」地全音量出来
	if _player.playing:
		# 换曲：先停旧的（这里不做交叉淡化，直接切 + 淡入，听感上够用）
		_player.stop()
	_player.volume_db = db - 40.0
	_player.play()
	_fade_to(db, fade)
	_current = track
	print("[Music] 播放 `%s`（%s，音量 %.1f dB，淡入 %.1f s，循环 %s）" % [
		track, String(info.get("file", "?")), db, fade, str(_is_looping(stream))])
	return true


## 停。`fade` 秒内降到静音再真的 `stop()`。
static func stop(fade: float = FADE_DEFAULT) -> void:
	if _player == null or not _player.playing:
		_current = ""
		return
	var from_db := _player.volume_db
	if fade <= 0.0:
		_player.stop()
		_current = ""
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = _host.create_tween()
	_tween.tween_property(_player, "volume_db", -60.0, fade)
	_tween.tween_callback(func() -> void:
		if _player != null:
			_player.stop()
		_current = "")
	_current = ""


## 当前正在放的逻辑名（没在放就是空串）
static func current() -> String:
	return _current


static func is_playing() -> bool:
	return _player != null and _player.playing


## 自检用：列出表里所有的逻辑名
static func names() -> Array:
	return TRACKS.keys()


## 自检用：表里写的文件全部存在吗（返回缺失的那些）
static func missing_files() -> Array:
	var out: Array = []
	for k in TRACKS:
		var f := String(TRACKS[k].get("file", ""))
		if f.is_empty() or not ResourceLoader.exists(DIR + f):
			out.append("%s → %s" % [k, f])
	return out


# ────────────────────────── 内部 ──────────────────────────

static func _fade_to(db: float, fade: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if fade <= 0.0:
		_player.volume_db = db
		return
	_tween = _host.create_tween()
	_tween.tween_property(_player, "volume_db", db, fade)


static func _load_stream(track: String) -> AudioStream:
	if _cache.has(track):
		return _cache[track]
	var f := String(TRACKS[track].get("file", ""))
	var path := DIR + f
	if not ResourceLoader.exists(path):
		if not _missing.has(path):
			_missing[path] = true
			push_warning("[Music] 找不到 %s，这首不播" % path)
		return null
	var s := load(path) as AudioStream
	_cache[track] = s
	return s


## 只是打印用：告诉调用者这首到底会不会循环。
## 循环来自 `.import` 里的 `loop=true`，这里只读一下，**不改**。
static func _is_looping(stream: AudioStream) -> bool:
	var ogg := stream as AudioStreamOggVorbis
	if ogg != null:
		return ogg.loop
	var wav := stream as AudioStreamWAV
	if wav != null:
		return wav.loop_mode != AudioStreamWAV.LOOP_DISABLED
	return false


static func _ensure_host() -> bool:
	if _host != null and is_instance_valid(_host):
		return true
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return false
	_host = Node.new()
	_host.name = "MusicHost"
	# 世界暂停时（设置菜单 / 剧情）音乐不停
	_host.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(_host)
	_player = AudioStreamPlayer.new()
	_player.name = "Bgm"
	_player.bus = "Master"
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_host.add_child(_player)
	return true
