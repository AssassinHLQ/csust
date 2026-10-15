extends Node3D
## 玩法场景总控：把 Player / Weapon / HUD / 高斯泼溅校园接起来，记账击杀。

## 掉到这个高度以下就判定「掉出悬浮平台」，送回出生点（护栏之外的保险）
const FALL_LIMIT := -60.0

## 设计分辨率（project.godot 的 window/size/viewport_*）。见 _fit_render_scale()。
const DESIGN_VIEWPORT := Vector2(1600, 900)

var _player: Player
var _weapon: Weapon
var _hud: CanvasLayer
## 场上所有泼溅场地（现在是校园 + 画室609 两份；按类型收，不写死节点名）
var _splats: Array[SplatScene] = []
## 场上所有 Boss「木桩」（现在是霸王龙优香 + 飞猪优香两位）
var _bosses: Array[Boss] = []
var _companions: Array[Companion] = []
var _spawn := Vector3.ZERO
var _score := 0
var _shots := 0
var _hits := 0
## 输入自检用：累计收到的真实键盘按下事件数（见 _input）。一直 0 就说明
## 按键事件压根没进 Godot，而不是 InputMap 没匹配上。
var _keys_seen := 0


## 输入自检：把「窗口到底有没有拿到前台焦点」打出来，并尽力抢一次前台。
##
## ⚠️ 为什么必须由**游戏自己**报，而不是写个探针去测：
## `Input.action_press()` 与 `Input.parse_input_event()` 都是**直接往 Godot 的
## Input 单例里塞事件**，绕过「操作系统 → 窗口 → Godot」这一整段。所以完全可能
## 「探针里 WASD 走得飞起、真人按下去毫无反应」—— 缺的正是这一段。
## 本喵为此误判过两轮。
##
## 症状特征（用来和别的病因区分）：
##   场上其它角色照常走动/播动画，**只有键鼠没反应**，鼠标也没被捕获
##   ⇒ 游戏逻辑和帧率都正常，纯粹是窗口收不到操作系统的输入事件。
##   对照：物理时间被稀释时（见 _fit_render_scale 的注释）是**所有东西一起变慢**。
##
## 自检运行（`--script`）时不抢前台、也不打印：13 套自检各自开一个窗口，
## 抢前台会互相干扰，而且它们自己会注入事件、不需要焦点。
func _watch_input() -> void:
	if OS.get_cmdline_args().has("--script"):
		return
	_report_input.call_deferred()


## 数「收到的真实按键事件」。
##
## ⚠️ 这是唯一能回答「键盘到底有没有到 Godot」的办法：
## `Input.is_action_pressed()` 为 false 有两种完全不同的原因 ——
##   ① 按键事件压根没进 Godot（操作系统/焦点层面的问题）
##   ② 事件进来了，但 InputMap 没匹配上动作（映射问题）
## 看这个计数就知道是哪种：一直 0 就是①，在涨就是②。
func _input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed:
		_keys_seen += 1


func _report_input() -> void:
	for i in 12:
		await get_tree().create_timer(1.0).timeout
		var focus := DisplayServer.window_is_focused()
		var note := ""
		if not focus:
			note = "   ← ⚠️ **窗口没有前台焦点：键鼠都收不到，点一下游戏窗口即可**"
		elif get_tree().paused:
			note = "   ← 游戏被暂停（Esc 设置菜单开着）"
		elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			# 自愈：有焦点、没暂停、鼠标却没被捕获 ⇒ 自己收回来。
			# （焦点丢失时 Godot 会把鼠标放出来且**不会自动收回**；player.gd 的
			#   _notification 只在「重新获得焦点」那一刻收，漏了就一直是 VISIBLE。）
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			note = "   ← 有焦点却没捕获，已自动收回 mouse_mode=%d" % Input.mouse_mode
		print("[Game] 输入自检 第 %2d 秒：focused=%s  mouse_mode=%d  paused=%s  累计按键事件=%d" % [
			i + 1, str(focus), Input.mouse_mode, str(get_tree().paused), _keys_seen])
		print("[Game]            └─ Player：%s%s" % [_player_state(), note])


## Player 节点还活不活 —— 这是把「两个症状是不是同一个原因」分开的关键。
##
## 如果 `player.gd` 的 `_ready()` 根本没跑，那么「没捕获鼠标」和「WASD 不动」
## 就是**同一个原因**（脚本没执行）；而如果它活得好好的，两个症状就得分开查。
## 只看鼠标模式是分不出来的 —— 默认值本来就是 0（VISIBLE）。
func _player_state() -> String:
	var pl := get_node_or_null("Player")
	if pl == null:
		return "**节点不存在**"
	var s := "script=%s  is_physics_processing=%s  is_processing_input=%s  vel=%s  pos=%s" % [
		"有" if pl.get_script() != null else "**无**",
		str(pl.is_physics_processing()), str(pl.is_processing_input()),
		str((pl as CharacterBody3D).velocity.snappedf(0.01)),
		str((pl as Node3D).global_position.snappedf(0.01))]
	return s


## 视口比设计分辨率大不少时，按比例**只缩小 3D 渲染**分辨率（UI 仍全分辨率）。
##
## ⚠️ 为什么必须有这个 —— 本喵在这里翻过一次车，症状极具误导性：
## `project.godot` 打开全屏后，`canvas_items` 拉伸模式下 3D 视口 = 窗口尺寸，
## 于是 2560×1440 的渲染面积是 1600×900 的 **2.56 倍**。在画室609（277 万高斯、
## 重 overdraw）上实测：
##     2560×1440 → 渲染 **2.0 fps**，物理 **16 帧/秒**，玩家 **0.11 m/s**
##     1600×900 → 渲染  20.0 fps，物理  64 帧/秒，玩家  1.98 m/s ✅
## 而 Godot 每帧最多跑 `max_physics_steps_per_frame`（默认 8）步物理 —— 渲染一慢，
## **物理时间就被稀释**：2 fps × 8 步 = 16 步/秒，只有额定 60 的 1/3.75，
## 玩家真实速度被打成 **1/18**。
##
## 症状是「WASD 按了几乎不动」，和「输入坏了」一模一样，本喵因此误判过一轮
## （先用 `Input.action_press` 测出能走 1.93 m，就以为输入没问题 —— 可那次是
## **窗口化**跑的，换成全屏才暴露出来）。诊断办法见
## scripts/_probe_gameplay_input.gd：**位移必须和帧率、物理帧数一起报**。
##
## 只在视口面积明显大于设计分辨率时才降 3D 分辨率；否则**显式设回 1.0**。
##
## ⚠️ 两个都踩过的坑：
##   1. 不能只在 `_ready()` 里算一次 —— 那一刻窗口还没变成全屏尺寸（实测还没
##      2560×1440），算出来是「不用缩放」。所以挂在 `Viewport.size_changed` 上，
##      尺寸一变就重算。自检会事后 `root.size = 1600×900`，正好也走这条信号。
##   2. 尺寸回到设计分辨率时必须**显式设回 1.0**，不能「提前 return 什么都不做」——
##      否则全屏时设下的 0.625 会一直留着，自检拿到的就是被降过分辨率的画面。
func _fit_render_scale() -> void:
	var vp := get_viewport()
	# ⚠️ 必须用 `vp.size`（= Window.size，就是**渲染目标**的像素数），
	#    **不能**用 `vp.get_visible_rect().size` —— 在 `canvas_items` 拉伸模式下
	#    后者返回的是**画布矩形**（= 设计分辨率 1600×900），跟真实渲染尺寸无关。
	#    本喵第一版就是用它，于是在 2560×1440 全屏下算出「不用缩放」，白改一轮。
	var size := Vector2(vp.size)
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var ratio := (DESIGN_VIEWPORT.x * DESIGN_VIEWPORT.y) / (size.x * size.y)
	var s := 1.0
	if ratio < 0.8:
		s = clampf(sqrt(ratio), 0.5, 1.0)
	print("[Game] _fit_render_scale：渲染尺寸 %s → 目标缩放 %.3f（当前 %.3f）" % [
		str(size), s, vp.scaling_3d_scale])
	if is_equal_approx(vp.scaling_3d_scale, s):
		return
	vp.scaling_3d_scale = s


func _ready() -> void:
	var vp := get_viewport()
	if not vp.size_changed.is_connected(_fit_render_scale):
		vp.size_changed.connect(_fit_render_scale)
	_fit_render_scale()
	_watch_input()
	_player = $Player
	_weapon = $Player/Weapon
	_hud = $HUD
	_spawn = _player.global_position

	_hud.bind(_player, _weapon)

	# 泼溅场地也是一场一行：两份（校园 / 画室609）同时解码时，玩家得分清
	# 是哪一份在等。HUD 侧 bind_splats() 按传入顺序从上往下排。
	for child in get_children():
		if child is SplatScene:
			_splats.append(child as SplatScene)
	if not _splats.is_empty():
		if _hud.has_method("bind_splats"):
			_hud.bind_splats(_splats)
		elif _hud.has_method("bind_splat"):
			_hud.bind_splat(_splats[0])

	# Boss 与同伴都是场景里的直接子节点，按类型收一遍（不写死节点名，
	# 以后再加一位 Boss / 一名同伴只要往场景里摆就行）
	for child in get_children():
		if child is Boss:
			var boss := child as Boss
			_bosses.append(boss)
			boss.died.connect(_on_target_died)
		elif child is Companion:
			_companions.append(child as Companion)
	if not _bosses.is_empty() and _hud.has_method("bind_bosses"):
		_hud.bind_bosses(_bosses)
	_weapon.fired.connect(func(_i: int) -> void: _shots += 1)

	for target in get_tree().get_nodes_in_group("targets"):
		if target.has_signal("died"):
			target.died.connect(_on_target_died)
	# 场景里的靶子没进组也接一下
	for child in get_children():
		if child is Target and not child.is_in_group("targets"):
			child.died.connect(_on_target_died)


func _process(_delta: float) -> void:
	if _player and _player.global_position.y < FALL_LIMIT:
		_player.global_position = _spawn
		_player.velocity = Vector3.ZERO
		print("[game] 掉出平台，已送回出生点")


func _on_target_died(_by: float) -> void:
	_score += 1
	_hits += 1


func stats() -> Dictionary:
	return {
		"score": _score,
		"shots": _shots,
		"hits": _hits,
		"accuracy": 0.0 if _shots == 0 else float(_hits) / float(_shots),
	}
