class_name Sfx
extends RefCounted
## 音效库：**逻辑名 → 一批候选文件**，播放时随机挑一条 + 轻微音高抖动。
##
## ── 为什么是纯静态类，而不是 autoload ──
## 和 `GameSettings` / `UiSkin` / `StoryScript` 同一个理由，也是踩出来的：
## 自检用 `godot --script res://scripts/_verify_xxx.gd` 跑，而在**这个模式下 autoload
## 的名字并不是编译期可见的全局标识符** —— 产品脚本里只要写了 `Sfx.play(...)`，
## 整份脚本就会 `Compile Error: Identifier not found: Sfx`，只有自检中招。
## （详见 `game_settings.gd` 开头那段。）
##
## ── 宿主节点是懒创建的 ──
## 静态类没有 `_ready()`，所以第一次 `play()` 时才把宿主 `Node` 挂到
## `Engine.get_main_loop().root` 底下。这样**既不用 autoload、也不改任何 .tscn**，
## 而且在 `--script` 自检里照样能用。
##
## ── 三条刻意的取舍 ──
## 1. **文件缺失 = 静默**（只在第一次 push_warning 一次），绝不报错、绝不影响玩法。
##    克隆者删了 `assets/sfx/` 也照样能跑。
## 2. **暂停时照样响**：宿主与播放器的 `process_mode` 都是 `ALWAYS` ——
##    设置菜单开着时整个世界是暂停的，而那正是 UI 音效最多的时候
##    （`settings_menu.gd` / `dialogue_box.gd` / `splat_scene.gd` 都栽在同一个坑上）。
## 3. **玩家自己的枪用 2D（非定位）**：枪永远「在耳边」，用 3D 定位反而会随镜头
##    左右漂。世界里的声音（命中、Boss、脚步）走 `play_at()`。
##
## ── 加一条新音效要动两处 ──
##     `assets/sfx/` 里放文件 + 下面 `SPEC` 加一行；然后 `--headless --path . --import`。
##     **调用点不用改** —— 它们只认逻辑名。见 `assets/sfx/README.md`。

## 音效文件目录
const DIR := "res://assets/sfx/"

## 2D / 3D 播放池的上限。池满了就抢最早的那个（轮转），宁可截断旧的一声，
## 也不让新的不响 —— 打枪时丢一声比叠一声难听得多。
const MAX_2D := 12
const MAX_3D := 8

## 逻辑名 → {files: [候选文件...], db: 基准音量, pitch: 音高抖动幅度, gap_ms: 最小间隔}
##
##   files    随机挑一条：同一种声音多条候选能避免「连发听起来像复读机」
##   db       基准音量分贝（负数是变小）。**再叠加 GameSettings 的主音量**
##   pitch    音高随机范围 ±，0.08 ≈ 起落 8%，人的耳朵听不出音高、只觉得「不重复」
##   gap_ms   同一个逻辑名两次播放的最小间隔；防同帧重复触发，也是「空仓」那种
##            「按住不放会一直响」的场合的节流阀
##
## 现在只接了第一批（用户选的两组）：武器 + 界面。加新音效就在这张表里加一行，
## `_verify_sfx.gd` 会核对「表里写的文件在不在」和「调用点写的名字在不在表里」。
const SPEC := {
	# ── 武器 ──
	"fire": {
		"files": ["laserSmall_000.ogg", "laserSmall_001.ogg", "laserSmall_002.ogg",
			"laserSmall_003.ogg", "laserSmall_004.ogg"],
		"db": -7.0, "pitch": 0.08, "gap_ms": 25,
	},
	"empty": {"files": ["click_001.ogg"], "db": -5.0, "pitch": 0.20, "gap_ms": 150},
	"reload_out": {"files": ["metalLatch.ogg"], "db": -4.0, "pitch": 0.04, "gap_ms": 0},
	"reload_in": {"files": ["metalClick.ogg"], "db": -4.0, "pitch": 0.04, "gap_ms": 0},
	# ── 界面（音量压得比武器低一截：界面音该是「垫底」的）──
	"ui_press": {"files": ["click_002.ogg"], "db": -9.0, "pitch": 0.04, "gap_ms": 40},
	"ui_toggle": {"files": ["toggle_001.ogg"], "db": -9.0, "pitch": 0.04, "gap_ms": 40},
	"ui_slider": {"files": ["tick_002.ogg"], "db": -14.0, "pitch": 0.10, "gap_ms": 60},
	"ui_open": {"files": ["open_001.ogg"], "db": -8.0, "pitch": 0.0, "gap_ms": 0},
	"ui_close": {"files": ["close_001.ogg"], "db": -8.0, "pitch": 0.0, "gap_ms": 0},
}

static var _host: Node = null
static var _pool2d: Array[AudioStreamPlayer] = []
static var _pool3d: Array[AudioStreamPlayer3D] = []
## 路径 → AudioStream（加载失败缓存 null，不反复重试）
static var _cache: Dictionary = {}
## 逻辑名 → 上次播放的毫秒
static var _last_ms: Dictionary = {}
static var _next2d := 0
static var _next3d := 0
static var _miss: Array[String] = []
## 上一次 `play*()` **没有响**的原因（响了就是 "ok"）。
## 排查「怎么没声音」时先看它 —— 比在脑子里过一遍 gap/文件/宿主三条路快得多。
static var _last_reason := "还没播过"


# --- 查询 ---------------------------------------------------------------------

static func names() -> Array:
	return SPEC.keys()


static func has(name: StringName) -> bool:
	return SPEC.has(String(name))


## 这个逻辑名的候选文件（拼好的 `res://` 路径）
static func files(name: StringName) -> Array[String]:
	var out: Array[String] = []
	var sp: Dictionary = SPEC.get(String(name), {})
	for f in sp.get("files", []):
		out.append(DIR + String(f))
	return out


static func spec(name: StringName) -> Dictionary:
	return SPEC.get(String(name), {})


## 加载失败过的文件（自检与控制台排查用）
static func missing_files() -> Array[String]:
	return _miss.duplicate()


## 上一次 `play*()` 的结果说明：`"ok"` = 响了；否则是没响的原因。
static func last_reason() -> String:
	return _last_reason


# --- 播放 ---------------------------------------------------------------------

## 播一个「不带方位」的音效（界面、玩家自己的枪）。返回有没有真的响。
static func play(name: StringName, extra_db := 0.0) -> bool:
	return _emit(String(name), Vector3.ZERO, false, extra_db)


## 播一个「在世界里某个位置」的音效（命中、Boss、脚步）。返回有没有真的响。
static func play_at(name: StringName, pos: Vector3, extra_db := 0.0) -> bool:
	return _emit(String(name), pos, true, extra_db)


static func stop_all() -> void:
	for p in _pool2d:
		if is_instance_valid(p):
			p.stop()
	for p in _pool3d:
		if is_instance_valid(p):
			p.stop()


## 当前正在响的播放器数量（自检用）
static func active_count() -> int:
	var n := 0
	for p in _pool2d:
		if is_instance_valid(p) and p.playing:
			n += 1
	for p in _pool3d:
		if is_instance_valid(p) and p.playing:
			n += 1
	return n


## 清空冷却与缓存（**只给自检用**：不然「同一个名字连播两次」会被 gap_ms 吃掉）
##
## ⚠️⚠️ **这个方法绝对不能改名叫 `reset_state()`** —— 这是本工程踩过最阴的一个坑：
##
##     `Script` / `GDScript` **自带一个原生方法就叫 `reset_state`**（实测：
##     `ClassDB.class_has_method("Script", "reset_state") == true`，而 `Object` 没有）。
##     而 `class_name Sfx` 的**类名本身就是那个脚本对象** —— 于是 `Sfx.reset_state()`
##     会解析到**原生方法**上去：你自己写的静态函数**一行都不执行，也不报任何错**。
##     本喵当时在自检里连函数体第一行的 `print` 都看不到，白查了三轮。
##
##     同理要避开的是**所有 `Script` / `GDScript` 的原生方法名**（不是 `Object` 的）——
##     `play` / `stop_all` / `has` / `names` 这些就都没事。
static func reset_for_test() -> void:
	_last_ms.clear()
	_cache.clear()
	_miss.clear()
	_next2d = 0
	_next3d = 0


# --- 内部 ---------------------------------------------------------------------

static func _emit(name: String, pos: Vector3, spatial: bool, extra_db: float) -> bool:
	if not SPEC.has(name):
		_last_reason = "库表里没有「%s」（可用的：%s）" % [name, str(SPEC.keys())]
		push_warning("[Sfx] 没有这个音效：%s" % name)
		return false
	var sp: Dictionary = SPEC[name]
	var gap := int(sp.get("gap_ms", 0))
	var now := Time.get_ticks_msec()
	if gap > 0 and now - int(_last_ms.get(name, -1000000)) < gap:
		_last_reason = "被 gap_ms=%d 节流（距上次 %d ms）" % [gap, now - int(_last_ms[name])]
		return false
	var list: Array = sp.get("files", [])
	if list.is_empty():
		_last_reason = "「%s」在库表里没有候选文件" % name
		return false
	var stream := _stream(String(list[randi() % list.size()]))
	if stream == null:
		_last_reason = "文件加载失败（见 missing_files()）"
		return false
	if not _ensure_host():
		_last_reason = "拿不到 SceneTree，宿主建不起来"
		return false

	var pitch := 1.0 + randf_range(-float(sp.get("pitch", 0.0)), float(sp.get("pitch", 0.0)))
	var db := float(sp.get("db", 0.0)) + extra_db
	if spatial:
		var p := _take3d()
		p.global_position = pos
		p.stream = stream
		p.volume_db = db
		p.pitch_scale = pitch
		p.play()
	else:
		var q := _take2d()
		q.stream = stream
		q.volume_db = db
		q.pitch_scale = pitch
		q.play()
	_last_ms[name] = now
	_last_reason = "ok"
	return true


## 懒创建宿主。返回能不能用（`--script` 下没有 SceneTree 就返回 false，静默）。
static func _ensure_host() -> bool:
	if _host != null and is_instance_valid(_host):
		return true
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return false
	_host = Node.new()
	_host.name = "SfxHost"
	# ⚠️ 世界暂停时（设置菜单开着 / 剧情播着）UI 音效照样要响。
	_host.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(_host)
	_pool2d.clear()
	_pool3d.clear()
	return true


static func _take2d() -> AudioStreamPlayer:
	for p in _pool2d:
		if not p.playing:
			return p
	if _pool2d.size() < MAX_2D:
		var p := AudioStreamPlayer.new()
		p.name = "Sfx2D_%d" % _pool2d.size()
		p.bus = "Master"
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		_host.add_child(p)
		_pool2d.append(p)
		return p
	var victim := _pool2d[_next2d]
	_next2d = (_next2d + 1) % _pool2d.size()
	victim.stop()
	return victim


static func _take3d() -> AudioStreamPlayer3D:
	for p in _pool3d:
		if not p.playing:
			return p
	if _pool3d.size() < MAX_3D:
		var p := AudioStreamPlayer3D.new()
		p.name = "Sfx3D_%d" % _pool3d.size()
		p.bus = "Master"
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		_host.add_child(p)
		_pool3d.append(p)
		return p
	var victim := _pool3d[_next3d]
	_next3d = (_next3d + 1) % _pool3d.size()
	victim.stop()
	return victim


## 按需加载并缓存。**加载不到不报错**（只记一条 warning + 进 `missing_files()`）：
## 缺几个音效不该让游戏跑不起来。
static func _stream(file: String) -> AudioStream:
	var key := DIR + file
	if _cache.has(key):
		return _cache[key]
	var res: Resource = load(key) if ResourceLoader.exists(key) else null
	var stream := res as AudioStream
	if stream == null and not _miss.has(key):
		_miss.append(key)
		push_warning("[Sfx] 加载不到音效文件：%s（游戏照常跑，只是没声音）" % key)
	_cache[key] = stream
	return stream
