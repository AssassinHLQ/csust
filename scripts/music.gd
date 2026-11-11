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
	# 商店（柴关电脑城）的 BGM。素材：UNDERTALE「Tem Shop」。
	# ⚠️ 源文件 45.44 s，**只取前 40.2094 s** —— 那个长度是把整段做自相关之后
	#    定出来的循环点：曲子自身的循环周期是 5.0262 s，40.2094 = 5.0262 × 8
	#    （误差 0.2 ms）。直接按整数 40.000 s 切，接缝处与开头的相关系数只有
	#    +0.06、跳变是曲子内部平均跳变的 1.8 倍（会「咔」一下）；
	#    切在 40.2094 s 上相关系数 +0.66，再做过 25 ms 环绕交叉淡化。
	#    生成脚本与推导见 `_tools` 旁边的说明，或本条提交信息。
	"shop": {"file": "shop_theme.ogg", "db": -13.0},
	# 游戏开发部活动室的 BGM（用户 2026-11-11：「音乐需要增加」）。
	# 素材：「碧蓝档案OST Vol.1（320K）」P70「Pixel Time（游戏开发部）」。
	# ⚠️ 循环点 = **游戏里原本的循环点**（用户 2026-11-11：「只需要裁掉最后两秒
	#    就可以循环，就是游戏里面的效果」）：源文件 131.1927 s，
	#    取**前 129.2292 s**（裁掉最后 1.9635 s），硬裁、不做交叉淡化 ——
	#    这个点的环绕跳变 0.003693 只有曲子内部相邻样点平均跳变（0.043299）的
	#    **0.085 倍**，斜率差 0.00058，本来就是能直接接上的。
	#    实测 128.9 ~ 129.3 s 之间按「环绕跳变 + 斜率差」精扫（0.2 ms 步长），
	#    这个点最干净；距「正好裁 2.000 s」只差 36 ms，听不出长短差别。
	# 📌 早先那版切在 119.9993 s（15 × 8 s 周期）是**错的**：多切掉了最后 9 秒
	#    的曲子内容，而那 9 秒本来就是循环的一部分。
	"gamedev": {"file": "gamedev_theme.ogg", "db": -13.0},
	# 电竞房的 BGM（用户 2026-11-11：「Colorful Mess 这个放电竞房里面」）。
	# 素材：「碧蓝档案OST Vol.1（320K）」P8「Colorful Mess」。
	# ⚠️ 这首**不是**规整周期曲：自相关最强峰在 22.3256 s 但相关只有 0.40，
	#    而且**结尾没有淡出**（末 10 s 的 RMS 0.145 ≈ 全曲 0.155）—— 直接整首循环
	#    会从响亮的结尾硬切回安静的前奏。所以在曲子内部切：
	#    取 L = 92.0700 s（全曲 111.8293 s 的 82%，4.12 × P），
	#    这一段与开头 4 s 的相关系数 +0.5647（全长度扫描里最高的一档），
	#    尾部 25 ms 环绕交叉淡化后环绕断点 0.002878，只有曲子内部相邻样点平均跳变
	#    （0.038819）的 **0.07 倍**。切掉的末尾约 19.8 s 里主要是收尾段落。
	"esports": {"file": "esports_theme.ogg", "db": -13.0},
	# 画室 609 的 BGM（用户 2026-11-11：「Lemonade Diary 这个换画室609的音乐，
	# 范围就是按照出门来定」）。
	# 素材：「碧蓝档案OST Vol.1（320K）」P37「Lemonade Diary（咖啡厅）」。
	# ⚠️ 源文件 154.1547 s，取**前 143.9998 s**（裁掉最后 10.1549 s）：
	#    这首的循环周期又是规整的 8.00000 s（自相关零误差），
	#    143.9998 = **18.00 × P** —— 正好是歌曲自身的整周期，
	#    而末尾那 10.15 s 是收尾段落 + 淡出到数字静音（153.6 s 之后就没声了）。
	#
	# 📌 2026-11-11 追加（用户：「结束处接1分16左右一直循环可以做到吗」）：
	#    改成 **「前奏 + 循环体」** 结构 —— 整首只播一次前奏，
	#    播到 143.9998 s 就跳回 **76.6102 s**（1:16.61）反复。
	#    用的是 Godot 导入期的 `loop_offset`（见 `art609_theme.ogg.import`），
	#    音频文件本身不用改，代码也不用管循环 —— 引擎自己跳。
	#    为什么是 76.6102 而不是整 76.000：76.000 那个点上波形是断的
	#    （跳变 0.196 = 内部平均跳变的 ×20，会「咔」），
	#    而 76.6102 处跳变 0.000046（×0.005）、斜率差 0.002121 —— 本来就接得上。
	#    实测过 Godot 的绕回确实生效：播放位置跑到 3.997 s（文件尾）后
	#    准确跳回 loop_offset（见提交说明里的短文件实测）。
	"room609": {"file": "art609_theme.ogg", "db": -13.0},
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
	# ⚠️ 这里必须用 `is_instance_valid`，不能写 `== null`：被 `queue_free()` 的节点
	#    **引用还在、但不是 null**，读 `.playing` 会抛 "previously freed instance"。
	#    退出游戏时 `GameDevRoom::_exit_tree()` 可能赶在 `MusicHost` 已经释放之后
	#    调到这里（同类问题在 `sfx.gd` 有过）。
	if not is_instance_valid(_player) or not _player.playing:
		_current = ""
		return
	if not is_instance_valid(_host):
		_player.stop()
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
		if is_instance_valid(_player):
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
