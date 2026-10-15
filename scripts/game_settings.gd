class_name GameSettings
extends RefCounted
## 全局设置：存值 + 落盘（`user://settings.cfg`）+ 变更广播。
##
## ⚠️ **为什么是纯静态类，而不是 autoload**（这一条是踩出来的）：
##    自检是用 `godot --script res://scripts/_verify_xxx.gd` 跑的，而在**这个模式下
##    autoload 的名字并不是编译期可见的全局标识符** —— 只要产品脚本里写了
##    `GameSettings.value(...)`，`--script` 就会
##        `Compile Error: Identifier not found: GameSettings`
##    于是 `player.gd` 整份编译失败、Player 退化成裸 `CharacterBody3D`，
##    所有自检跟着崩（正常启动反而没事，所以只有自检中招）。
##    改成 `class_name` + 全静态成员后，**两种启动方式都能编译**。
##    代价：静态类**不能声明 `signal`**，广播改用静态回调表（见 `listen()`）。
##
## ⚠️ 加一条新设置要动三处：
##   1. `DEFAULTS`（默认值）——**这里是唯一的真相来源**，「恢复默认」就是重铺这张表
##   2. `RANGES`（滑块范围）——只有数值型才需要；不写就当布尔开关处理
##   3. **要用它的那个系统**里的 `_apply_settings()` + 对 `listen()` 的注册

const PATH := "user://settings.cfg"
const SECTION := "settings"

const DEFAULTS := {
	"mouse_sensitivity": 0.0022,
	"fov": 62.0,
	"master_volume": 1.0,
	"companion_fire": true,
	"boss_attack": true,
	"render_quality": "high",
}

## 数值型设置的 [最小值, 最大值, 步长]
const RANGES := {
	"mouse_sensitivity": [0.0005, 0.0060, 0.0001],
	"fov": [50.0, 90.0, 1.0],
	"master_volume": [0.0, 1.0, 0.05],
}

## ── 画质档位 ──
##
## 为什么要有这个：GPU 占用完全由「每帧要画多少像素」决定，而那个旋钮
## （`Viewport.scaling_3d_scale`）以前是代码里写死的。实测：2560×1440 + 原生 +
## Compute 后端下 GPU 恒在 100%（每帧 16.2 ms / 预算 16.67 ms，刚好追得上 60 fps），
## 所以「降一档」能直接换回一半的功耗。
##
## 字段含义：
##   scale  乘到 `scaling_3d_scale` 上（1.0 = 原生；只乘，不会被放大过 1.0）
##   ssao   屏幕空间环境光遮蔽（全屏 pass）
##   glow   辉光
##   fps    `Engine.max_fps`；0 = 不限帧（交给垂直同步）
##
## ⚠️ `ultra`/`high` 就是本工程验证过的画面（README §6.6 / §6.11 的对照图）；
##    `medium` 以下只是为省电，画质会明显下降。
const QUALITY := {
	"ultra": {"label": "极致", "scale": 1.00, "ssao": true, "glow": true, "fps": 0},
	"high": {"label": "高", "scale": 1.00, "ssao": true, "glow": true, "fps": 60},
	"medium": {"label": "中", "scale": 0.85, "ssao": false, "glow": true, "fps": 60},
	"low": {"label": "低", "scale": 0.70, "ssao": false, "glow": false, "fps": 60},
	"saver": {"label": "省电", "scale": 0.60, "ssao": false, "glow": false, "fps": 30},
}
## 界面上的先后顺序（也是默认档 `high` 的位置：第二档）
const QUALITY_ORDER := ["ultra", "high", "medium", "low", "saver"]

## 离散型设置：值只能取列表里的那些。设置界面据此画**分段按钮**而不是滑块/开关。
## ⚠️ 顺序有讲究：`QUALITY_ORDER` 必须先于它声明。
const CHOICES := {
	"render_quality": QUALITY_ORDER,
}

## 设置界面里显示的名字
const LABELS := {
	"mouse_sensitivity": "鼠标灵敏度",
	"fov": "视野 FOV",
	"master_volume": "主音量",
	"companion_fire": "同伴开火",
	"boss_attack": "Boss 攻击",
	"render_quality": "画质",
}

static var _values := {}
static var _loaded := false
static var _listeners: Array[Callable] = []


## 注册变更回调（静态类没有 `signal`，这是它的替代品）。
## 回调签名：`func(key: String, value: Variant) -> void`
static func listen(cb: Callable) -> void:
	if not _listeners.has(cb):
		_listeners.append(cb)


static func unlisten(cb: Callable) -> void:
	_listeners.erase(cb)


static func value(key: String, fallback: Variant = null) -> Variant:
	_ensure()
	if _values.has(key):
		return _values[key]
	if DEFAULTS.has(key):
		return DEFAULTS[key]
	return fallback


static func set_value(key: String, v: Variant) -> void:
	_ensure()
	if not DEFAULTS.has(key):
		push_warning("[GameSettings] 未知设置项：%s" % key)
		return
	if CHOICES.has(key) and not (v in CHOICES[key]):
		push_warning("[GameSettings] %s 不接受「%s」，可选：%s" % [key, str(v), str(CHOICES[key])])
		return
	if _values.get(key) == v:
		return
	_values[key] = v
	if key == "master_volume":
		_apply_audio()
	_save()
	_emit(key, v)


## 「恢复默认」：把 DEFAULTS 整张表重铺一遍（逐项走 set_value，所以每一项都会广播）
static func reset_all() -> void:
	for key in DEFAULTS.keys():
		set_value(key, DEFAULTS[key])


## 数值型的 [min, max, step]；布尔型返回空数组（调用方据此决定用滑块还是开关）
static func spec(key: String) -> Array:
	return RANGES.get(key, [])


static func is_numeric(key: String) -> bool:
	return RANGES.has(key)


## 离散型（画质档位这类）—— 取值必须来自 `choices(key)`
static func is_choice(key: String) -> bool:
	return CHOICES.has(key)


static func choices(key: String) -> Array:
	return CHOICES.get(key, [])


## 离散型的显示名（画质档位 -> 「极致 / 高 / 中 / 低 / 省电」）
static func choice_label(key: String, v: Variant) -> String:
	if key == "render_quality":
		return String((QUALITY.get(str(v), {}) as Dictionary).get("label", str(v)))
	return str(v)


## 当前画质档位的参数表。值非法（比如手改过 settings.cfg）就退回默认档。
static func quality_spec() -> Dictionary:
	var key := str(value("render_quality"))
	if not QUALITY.has(key):
		key = str(DEFAULTS["render_quality"])
	return QUALITY[key]


static func label(key: String) -> String:
	return LABELS.get(key, key)


static func keys() -> Array:
	return DEFAULTS.keys()


## 懒加载：静态类没有 `_ready()`，所以第一次访问时把盘上的值读进来。
## ⚠️ 必须先置 `_loaded` 再 `_load()` / `_apply_audio()` —— 后两者都会回调 `value()`，
##    不先置位就会递归回来（虽然 `_loaded` 一置就断，但顺序反了会真的绕一圈）。
static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	_values = DEFAULTS.duplicate()
	_load()
	_apply_audio()


static func _emit(key: String, v: Variant) -> void:
	for cb in _listeners:
		if cb.is_valid():
			cb.call(key, v)


## 主音量作用在 Master 总线上。0 要真的静音 ——
## ⚠️ `linear_to_db(0)` 是 -inf，会污染总线；所以先判静音，再对下限取 max。
static func _apply_audio() -> void:
	var v := clampf(float(value("master_volume")), 0.0, 1.0)
	var bus := AudioServer.get_bus_index("Master")
	if bus < 0:
		return
	AudioServer.set_bus_mute(bus, v <= 0.001)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(v, 0.001)))


static func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for key in DEFAULTS.keys():
		if cfg.has_section_key(SECTION, key):
			_values[key] = cfg.get_value(SECTION, key)


static func _save() -> void:
	var cfg := ConfigFile.new()
	for key in _values.keys():
		cfg.set_value(SECTION, key, _values[key])
	cfg.save(PATH)
