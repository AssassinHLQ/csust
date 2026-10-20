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
	# ── 画面：2026-10-20 用户要求 **不再用「一档画质全包」** ──
	# 「画质不要这样子调，要单独调帧率、单独调分辨率、单独调抗锯齿之类的。」
	# 于是原来的 `render_quality`（极致/高/中/低/省电，一档同时改缩放+SSAO+辉光+限帧）
	# 被拆成下面这些**各自独立**的旋钮，互不覆盖。
	"resolution_scale": "1.00",
	"fps_limit": "60",
	"vsync": true,
	"aa_mode": "off",
	"shadow_quality": "high",
	"ssao": true,
	"glow": true,
	"ssr": false,
	"fog": true,
	"window_mode": "maximized",
}

## 数值型设置的 [最小值, 最大值, 步长]
const RANGES := {
	"mouse_sensitivity": [0.0005, 0.0060, 0.0001],
	"fov": [50.0, 90.0, 1.0],
	"master_volume": [0.0, 1.0, 0.05],
}

## ── 画面各旋钮的取值 ──
##
## 为什么拆开：GPU 占用几乎只由「每帧画多少像素」决定，而像素数 = 分辨率缩放 ×
## 抗锯齿的采样倍数 × 阴影图。以前它们被绑成一个「画质档位」，想单独把 MSAA 关掉
## 降发热就必须连缩放一起掉；用户明确说不要这样。
##
## 每个键都**独立**落盘、独立生效（`game.gd::_apply_render` 里一个个读）。
## 默认值对应以前的高档：原生缩放 + 60 fps + 无 AA + 高阴影 + SSAO/辉光/雾开。
const RES_CHOICES := ["0.50", "0.60", "0.75", "0.85", "1.00"]
const FPS_CHOICES := ["30", "45", "60", "90", "120", "144", "240", "unlimited"]
const AA_CHOICES := ["off", "fxaa", "msaa2", "msaa4", "msaa8", "taa"]
const SHADOW_CHOICES := ["off", "low", "medium", "high"]
const WINDOW_CHOICES := ["windowed", "maximized", "fullscreen", "exclusive"]

## 离散型设置：值只能取列表里的那些。设置界面据此画**分段按钮**而不是滑块/开关。
const CHOICES := {
	"resolution_scale": RES_CHOICES,
	"fps_limit": FPS_CHOICES,
	"aa_mode": AA_CHOICES,
	"shadow_quality": SHADOW_CHOICES,
	"window_mode": WINDOW_CHOICES,
}

## 设置界面里显示的名字
const LABELS := {
	"mouse_sensitivity": "鼠标灵敏度",
	"fov": "视野 FOV",
	"master_volume": "主音量",
	"companion_fire": "同伴开火",
	"boss_attack": "Boss 攻击",
	"resolution_scale": "3D 渲染缩放",
	"fps_limit": "帧率上限",
	"vsync": "垂直同步",
	"aa_mode": "抗锯齿",
	"shadow_quality": "阴影质量",
	"ssao": "环境光遮蔽 SSAO",
	"glow": "辉光",
	"ssr": "屏幕空间反射 SSR",
	"fog": "雾",
	"window_mode": "窗口模式",
}

## 「画面」分组：设置界面在这些键之前插一个小标题
const RENDER_KEYS := ["resolution_scale", "fps_limit", "vsync", "aa_mode",
	"shadow_quality", "ssao", "glow", "ssr", "fog", "window_mode"]

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


## 离散型的显示名（内部值是代号，界面上要写人话）
static func choice_label(key: String, v: Variant) -> String:
	var s := str(v)
	match key:
		"resolution_scale":
			return "%s×" % s
		"fps_limit":
			return "不限" if s == "unlimited" else "%s fps" % s
		"aa_mode":
			return {"off": "关", "fxaa": "FXAA", "msaa2": "MSAA 2×",
				"msaa4": "MSAA 4×", "msaa8": "MSAA 8×", "taa": "TAA"}.get(s, s)
		"shadow_quality":
			return {"off": "关", "low": "低", "medium": "中", "high": "高"}.get(s, s)
		"window_mode":
			return {"windowed": "窗口", "maximized": "最大化",
				"fullscreen": "全屏", "exclusive": "独占全屏"}.get(s, s)
	return s


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
