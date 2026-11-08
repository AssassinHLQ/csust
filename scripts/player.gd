class_name Player
extends CharacterBody3D

## 上台阶辅助。用 `preload` 而不是 `class_name` 引用 —— 见 `step_climb.gd` 文件头第一条。
const StepClimb := preload("res://scripts/step_climb.gd")
## 第三人称主角控制器。
##
## 输入：
##   WASD / 方向键  相对相机方向的移动
##   Shift          跑动
##   Ctrl           蹲行
##   空格           跳跃
##   鼠标移动       视角
##   右键           开镜瞄准
##   左键           开火
##   R              换弹
##   Esc            释放 / 再次捕获鼠标
##
## ⚠️ 输入为什么写在 _input 而不是 _unhandled_input：
##    实测（Godot 4.7.1，真窗口下 Input.mouse_mode=CAPTURED、窗口已获焦），
##    _unhandled_input 收不到鼠标移动与鼠标按键事件——视角完全转不动、左键不开火。
##    改用 _input 后正常。_input 在 GUI 之前收到事件，不会被 UI 吃掉。
##    左键的「按下 / 松开」用 poll 的按键状态做边沿判断，不依赖事件里的 pressed 字段。

signal aim_changed(aiming: bool)
signal health_changed(current: float, maximum: float)
## 血量归零。关卡接这个信号做自己的善后（进度清零 / 提示），
## 真正的传送和回血由 `_respawn_now()` 在 0.6 s 后完成。
signal died

@export var max_health := 250.0
var health := 250.0
## 倒下后送回哪儿。**一个场景一个存档点**：由各关卡在进场景时设一次
## （`set_respawn_transform`），默认取 _ready 时的位置。
var _respawn_xform := Transform3D.IDENTITY
var _dying := false
## 2026-10-20 用户：「爱丽丝增强，血量变成 250」—— 原来是 100（盖特 Boss 一下 26、
## 倭瓜优香的天降一击 40，所以 250 才够吃几下）。注意 `health` 的初值也要跟着改，
## 否则 `_ready()` 里 `health = max_health` 之前 HUD 会闪一帧 100。

# --- 移动手感（米 / 秒）---
#
# ⚠️ 这一组是**整体调过一轮**的（用户报：加速度少 / 机动性差 / 跳不高 / 要更快 /
#    往后不能跑 / 转向不灵活）。改之前先看这四条约束，**别只动一个数**：
#
#   1. **动画那边只有 `Normal_Idle` / `Move_Ing` 两条循环**：走 / 跑 / 蹲 / 开镜
#      **都用 `Move_Ing`**（战斗动画，两只手在枪上），快慢只靠 `speed_scale` 区分。
#      ⚠️ **不要再按速度去切 `Cafe_Walk`** —— BA 的咖啡厅动画**不拿武器**
#      （素材把武器骨的 scale 缩到 ≈0，小桃小绿手里还会多出个游戏机），
#      详见 `anim_driver.gd` 的 `CYCLE_SPEED` 上面那段与 README §1.17。
#   2. 动画的 `speed_scale = 速度 / CYCLE_SPEED[clip]`，那是**按实际位移补脚步**
#      （防止脚底打滑）。所以**改了速度不要跟着改 `CYCLE_SPEED`** —— 那个数是
#      「这条动画按多快的地面速度录的」，不是「想让玩家跑多快」。
#      7.1 / 6.8 之类改完，播的是同一条动画、只是踩得更快，步幅不变。
#   3. 跳跃高度 = `JUMP² / (2 × GRAVITY)`，滞空 = `2 × JUMP / GRAVITY`。
#      现在 7.1² / 40 = **1.26 m**（改之前 6.2² / 44 = 0.87 m），滞空 0.71 s。
#   4. 转身是**指数逼近**（每帧 lerp `TURN_SMOOTH × delta`），不是恒速：
#      24 在 60 fps 下每帧走 40%，约 5 帧收到 5° 以内。
#
# 这些数字都有自检守着（`_verify_move_feel.gd` 把「手感」量成具体数值），
# 别靠感觉改。
const SPEED_WALK := 2.4        # 2.0 → 2.4
const SPEED_RUN := 6.8         # 5.2 → 6.8（+31%）
const SPEED_CROUCH := 1.3      # 1.1 → 1.3
const SPEED_AIM := 1.9         # 1.6 → 1.9
## 地面加速度。26 在 60 fps 下是每帧 +0.43 m/s → 约 0.27 s 加到满速（原来 12 → 0.57 s）
const ACCEL_GROUND := 26.0     # 12 → 26
## 空中加速度。原来只有 3，跳起来几乎没法修正落点 —— 这是「机动性差」的主因之一
const ACCEL_AIR := 9.0         # 3 → 9
## 地面摩擦（松开方向键后的减速度）。**刻意略大于 ACCEL_GROUND**：起步比刹车慢一点，
## 换向才干脆 —— 这是「转向灵活」里除转身速度之外的另一半
const FRICTION := 30.0         # 20 → 30
const GRAVITY := 20.0          # 22 → 20（配合下面的跳跃速度一起给高度）
const JUMP_VELOCITY := 7.1     # 6.2 → 7.1（跳高 0.87 → 1.26 m，+45%）
const TURN_SMOOTH := 24.0      # 14 → 24
## 开火/开镜时的转身速度（比平时快，否则「点了没反应」的迟滞感明显）
const TURN_SMOOTH_FIRE := 34.0 # 26 → 34

## ── 机甲（载具）飞行时另行一套水平数值 ─────────────────────────────────────
##
## 2026-11-08 用户两条反馈，根子是同一个：
##   「打得到霸王龙，但是人飞不过去」
##   「我不能同时加速前进与下降」
##
## ① 为什么「飞不过去」：飞行时原本整段沿用**地面**数值 —— 空中 `is_on_floor()`
##    为 false 走 `ACCEL_AIR`，目标速度是 `SPEED_WALK = 2.4 m/s`（不按 Shift 时）。
##    而第二关的三只霸王龙在 (-95,-96) / (-120,-115) / (-135,-140)，离出生点
##    **137 / 168 / 197 米**；`Weapon.range_meters = 300`，所以「站着就能打中」，
##    但要飞过去得先飞 137 m —— 按 2.4 m/s 是 **57 秒**。这就是「打得到但过不去」。
##
## ② 为什么「不能同时加速与下降」：`Ctrl`（crouch）是飞行的下降键，而地面上
##    `crouching` 会把目标速度压成 `SPEED_CROUCH = 1.3 m/s`、并且
##    `sprinting = ... and not crouching` 直接掐掉冲刺。
##    于是「Shift 加速 + Ctrl 下降」永远只能拿到 1.3 m/s。
##    修法：飞行期间 `crouching` 恒为 false（`Ctrl` 只当「下降」用，见
##    `carrier_form.gd::_tick_flight()`），加速度/摩擦也换成空中那套。
##
## ⚠️ 这几个数只影响 `_flight_lock == true` 的分支，地面手感一个都没有动
##    （`_verify_move_feel.gd` 那套断言照旧）。
const SPEED_FLY := 11.0        ## 巡航（≈ 40 km/h）
const SPEED_FLY_BOOST := 19.0  ## Shift 加力：137 m 约 7 秒到达
## 飞行时的水平加速度。和地面同档（26）：机甲推进器不是滑翔机，要跟手。
const ACCEL_FLY := 26.0
## 飞行时松开方向键的减速度。比地面（30）小一半：空中要留一点惯性，
## 不然松手的瞬间像撞在空气墙上。
const FRICTION_FLY := 12.0

## 开火方向与角色朝向的夹角小于这个值（弧度）才算「转到位」。
##
## ⚠️ 这个容差是按 model_root.rotation.y 的角度差算的，**不能用眼睛骨去量**：
##    眼骨在头局部带横向偏移，头部动画又一直在动，实测哪怕站得笔直，
##    「眼睛中点 - 头骨」这个方向与真实朝向也恒定差约 46°。
##    拿它当判据会把容差设得比测量下限还小，导致永远判定「没对准」。
##    所以：判定用可控的 rotation.y（下面几行），眼睛骨只用于定性的可视化核对。
## 0.38 rad ≈ 22°。
const FIRE_ALIGN_TOLERANCE := 0.38

## 相机视线 与 相机绕角 的换算偏移。**实测出来的，改动前务必读这段。**
##
## 实测（headless 打印 + 四方位渲图，见 README §1.4）：
##   相机在 rig 本地坐标 ≈ (-0.42, 0.17, +4.2)，即挂在 rig 的 **+Z** 侧，
##   而它看向 rig 的 -Z。于是：
##       相机视线 camera_forward() = -(sin(_yaw), 0, cos(_yaw))
##   同时（把独立相机放到角色 +Z 侧渲图，看到的是正脸）：
##       角色脸朝向 = (sin(_facing_yaw), 0, cos(_facing_yaw))
##
## 结论：要让角色「朝着准星、背对镜头」，就是
##       _facing_yaw = _yaw + PI
## 曾经写成 _facing_yaw = _yaw，正好差 180° —— 表现就是「开火前强制转向
## 反而让她转过来面对镜头」「按 W 朝前跑、开火一瞬间人整个翻过去」。
const CAMERA_FORWARD_OFFSET := PI

# --- 相机 ---
@export var mouse_sensitivity := 0.0022
@export var pitch_min := -1.15
@export var pitch_max := 1.15
@export var hip_distance := 4.2
## 滚轮能拉到的最近 / 最远距离（米）。**这一条以前只在 README 和 HUD 提示里写着，
## 代码里根本没实现** —— 用户报「滚轮的摄像头远近没有生效」就是这个。
@export var zoom_min := 1.8
@export var zoom_max := 9.0
## 滚轮每格改变多少米
@export var zoom_step := 0.35
## 平视高度。跑动动画本身前倾偏大，相机压低一点（且俯角小）能明显减轻
## 「人像在往前栽」的观感 —— 这是目前最有效的调节项。
@export var hip_height := 1.62
@export var hip_shoulder := 0.42
@export var aim_distance := 2.3
@export var aim_height := 1.38
@export var aim_shoulder := 0.58
@export var hip_fov := 62.0
@export var aim_fov := 34.0
## 开镜 FOV 相对腰射 FOV 的比例。设置界面只暴露**一个**「视野 FOV」，
## 开镜按这个比例跟着走（默认 34 / 62 ≈ 0.548），否则调 FOV 会把
## 「腰射 / 开镜」的观感关系搞乱。
const AIM_FOV_RATIO := 0.55
@export var cam_lerp := 12.0

## ── 上台阶的相机缓冲（用户 2026-10-26：「上楼梯生硬」）──
##
## `step_climb.gd` 把人**一帧之内**抬上台阶：实测爬蒙德里安那段 21 级楼梯，
## 单帧最大抬升 **0.239 m**，整段 77 次跳变。相机挂在玩家身上 → 一级一「啪」。
## 这里把那一次抬升记成 `_step_lag`（负值），再由 `_apply_camera()` 按指数曲线
## 放掉：物理上人已经站上去了（脚仍踩在踏面上），**相机是滑上去的**。
##
## `STEP_LAG_TAU`：时间常数（秒）。0.075 ≈ 4~5 帧回到 63%，肉眼就是「顺」；
##                 给 0.2 会明显觉得镜头黏在下面。
## `STEP_LAG_MAX`：一次最多缓冲多高（米）。连续上台阶时防止越积越多变成弹簧。
const STEP_LAG_TAU := 0.075
const STEP_LAG_MAX := 0.45
var _step_lag := 0.0
var _stuck_t := 0.0
var _unstick_cool := 0.0

var aiming := false
var sprinting := false
var crouching := false
var _pitch := -0.04
var _yaw := 0.0
## 角色自己的朝向。**必须独立于 _yaw**——
## 之前每帧写 `var desired_yaw := _yaw`，松开移动键后 horiz 归零，
## desired_yaw 就回落成相机朝向，角色会自己转回去面对镜头。
var _facing_yaw := 0.0
var _recoil_pitch := 0.0
var _recoil_yaw := 0.0
var _fire_held := false
var _aim_held := false
## 滚轮调出来的「腰射距离」，独立于 hip_distance（开镜时仍然走 aim_distance）
var _zoom_distance := 0.0
## 剧情镜头锁定：还剩多少秒（0 = 没锁）／要盯着看的目标（例如登场的倭瓜优香）
var _lock_target: Node3D
var _lock_left := 0.0

@onready var rig: Node3D = $CameraRig
@onready var spring: SpringArm3D = $CameraRig/SpringArm3D
@onready var cam: Camera3D = $CameraRig/SpringArm3D/Camera3D
@onready var model_root: Node3D = $Arisu
@onready var anim: Node = $Arisu/Model/AnimDriver
@onready var weapon: Node = $Weapon


func _ready() -> void:
	add_to_group("player")
	# 2026-10-29 用户：「爱丽丝爬坡能力加强一点点」。
	# CharacterBody3D 默认 floor_max_angle = 45°，校园里那些 45° 出头的路肩/坡道
	# 会直接把人挡住或往下滑。放到 52°（仍然上不了垂直墙），台阶也从 0.32 提到 0.38。
	floor_max_angle = deg_to_rad(52.0)
	floor_snap_length = 0.45
	# 用户 2026-10-21：「每次你运行游戏都会抢占鼠标一瞬间，然后我就点不到下面的任务栏了」
	# → 两道闸：
	#   ① 探针 / 自检一律带 `--no-capture`（写在 `--` 之后），**根本不收鼠标**；
	#   ② 正常启动时，只有窗口**已经拿到焦点**才收 —— 后台起来的窗口不该动用户的鼠标。
	if _may_capture():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# 出生朝向：相机绕角 0 → 相机在角色背后（+Z 侧）往场地深处（-Z）看，
	# 靶区（z = -3 … -16）正好在画面正前方，角色背对镜头面朝靶区。
	# 这就是「一进场就能看见靶子」的初始视角。
	_yaw = 0.0
	_facing_yaw = _yaw + CAMERA_FORWARD_OFFSET
	model_root.rotation.y = _facing_yaw
	rig.rotation.y = _yaw
	_zoom_distance = hip_distance
	health = max_health
	_apply_camera(1.0)
	health_changed.emit(health, max_health)
	_respawn_xform = global_transform
	# 设置（Esc 菜单）：先读一次初值，之后跟着变
	GameSettings.listen(_on_setting_changed)
	_apply_settings()
	_setup_face_fill()


## ── 贴脸补光只照角色 ──
##
## 2026-11-03 用户指着墙上一团光斑问「这个光是什么」—— 就是 `FaceFill`
## （`3b9ffb4` 加的贴脸补光）。它本来只想照亮脸，但点光源连墙一起照：
## 贴着墙站时距离不到 1 m，平方衰减直接过曝，墙上就留一团跟着人走的光斑。
##
## 做法：把玩家自己的网格放到 `1 + 专用层`，再把这盏灯的 `light_cull_mask`
## 只留专用层。**其余灯（太阳、屋里吸顶灯）和相机一律不动** —— 它们默认照所有层，
## 所以角色受光跟以前完全一样，只是这盏灯照不到墙。
## 仍然保留第 1 层，是为了万一别处按层剔除时角色不会消失。
const FACE_FILL_LAYER := 2


func _setup_face_fill() -> void:
	var fill := get_node_or_null("FaceFill") as OmniLight3D
	if fill == null:
		return
	var bit := 1 << (FACE_FILL_LAYER - 1)
	for n in find_children("*", "MeshInstance3D", true, false):
		(n as VisualInstance3D).layers = 1 | bit
	fill.light_cull_mask = bit


## 窗口重新获得焦点时把鼠标收回来。
##
## ⚠️ 为什么需要：`_ready()` 里那一次 `Input.mouse_mode = CAPTURED` 在**窗口还没获焦**
## 时会被系统丢掉 —— 从编辑器 F5 起来、游戏窗口没抢到前台时，症状正好是
## 「鼠标能看见、WASD 按了没反应」（键盘事件全给了编辑器）。
## 这是「进游戏动不了」最常见的两个原因之一（另一个是 Esc 菜单开着，见 settings_menu.gd）。
##
## 菜单开着的时候不收：那正是它故意 `MOUSE_MODE_VISIBLE` 的状态。
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		var tree := get_tree()
		if tree != null and not tree.paused and _may_capture():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# 失去焦点（Alt+Tab、点任务栏、被别的窗口盖住）→ **立刻放开鼠标**，
	# 否则鼠标被困在游戏里，任务栏都点不动（用户 2026-10-21 报的就是这个）。
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## 能不能收鼠标：带 `--no-capture` 的探针/自检永远不收；
## 正常启动还要求窗口已经拿到焦点（后台窗口不抢鼠标）。
func _may_capture() -> bool:
	if OS.get_cmdline_user_args().has("--no-capture"):
		return false
	return DisplayServer.window_is_focused()


## 这个鼠标按钮是不是滚轮（上 / 下 / 左 / 右）。
##
## 单独拎出来是因为「按类型放行 `InputEventMouseButton`」会把**左键开火**一起放进来 ——
## 火箭上不该开火（见 `_input()` 那段）。Godot 4 里滚轮没有专门的子类，
## 就是 `InputEventMouseButton` 带 `BUTTON_WHEEL_*` 的 `button_index`。
func _is_wheel(mb: InputEventMouseButton) -> bool:
	return mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
		MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]


func _input(event: InputEvent) -> void:
	# 火箭骑乘期间：**允许转视角**（用户 2026-11-07：「起飞不能转动视角」）。
	# 只屏蔽开火 / 开镜这些**战斗**操作键。
	#
	# ⚠️ 2026-11-08 用户：「在火箭上面虽然可以自由转视角但是不能滚轮缩放了」——
	#    这里原来写的是 `if _ride_active and not (event is InputEventMouseMotion): return`，
	#    把所有非鼠标移动的事件一律吃掉，**滚轮也在里面**（当时那段注释还明说
	#    「只屏蔽开火 / 开镜 / 滚轮缩放这些操作键」）。但滚轮在火箭上其实很有用：
	#    42 m 的箭体能拉远了看全貌，也能拉近看发动机段。所以现在放行滚轮。
	#
	# 判据用 `button_index` 白名单而不是 `event is InputEventMouseButton`：
	# 左键（开火）也是 InputEventMouseButton，按类型放行会连开火一起放进来。
	if _ride_active and not (event is InputEventMouseMotion):
		if not (event is InputEventMouseButton and _is_wheel(event as InputEventMouseButton)):
			return

	# --- 鼠标移动：转视角 ---
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - mm.relative.y * mouse_sensitivity, pitch_min, pitch_max)
		return

	# --- 鼠标滚轮：拉近 / 拉远 ---
	# 只在鼠标被捕获（真正在玩）时响应；按 Esc 释放鼠标后滚动页面不该动相机。
	if event is InputEventMouseButton and event.pressed \
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_distance = clampf(_zoom_distance - zoom_step, zoom_min, zoom_max)
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_distance = clampf(_zoom_distance + zoom_step, zoom_min, zoom_max)
			return

	# --- 键盘 ---
	if event is InputEventKey and (event as InputEventKey).pressed \
		and not (event as InputEventKey).echo:
		var key := (event as InputEventKey).keycode
		# ⚠️ Esc **不在这里处理**：它归设置界面（scripts/settings_menu.gd）。
		#    菜单打开时游戏是暂停的、player 收不到输入，也就没法负责「关掉菜单」——
		#    由菜单自己监听（PROCESS_MODE_ALWAYS）才能一开一关都稳。
		if key == KEY_R and weapon:
			weapon.try_reload()
			return

	# --- 鼠标按键：只处理「按下」这一沿，松开用 poll ---
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_RIGHT:
				# 用户 2026-11-04：「右键不触发瞄准，而是拾取这些」。
				# 站在可拾取物（9950X3D）的提示范围内时，右键让给拾取，
				# **不开镜**；不在范围内时右键还是原来的开镜。
				if _pickup_prompting():
					return
				_set_aiming(true)
			elif mb.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				_fire_held = true
				if weapon:
					weapon.trigger_down()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_set_aiming(false)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_fire_held = false
			if weapon:
				weapon.trigger_up()


## 现在有没有「可拾取物正在提示」？有的话右键要交出去。
##
## 判据走 `ParkourFutures.prompt_owner()`（提示系统只有一个 owner），
## 再看那个 owner 是不是 CPU —— 别的提示（开终端之类）不该抢右键。
func _pickup_prompting() -> bool:
	var fut := get_tree().get_first_node_in_group("futures")
	if fut == null:
		return false
	var owner_obj: Object = fut.call("prompt_owner")
	var n := owner_obj as Node
	return n != null and n.is_in_group("ryzen9950x3d")


## 兜底：万一某个按键的「松开」事件丢了，用 poll 纠正状态
func _poll_mouse_buttons() -> void:
	var left := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var right := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if _fire_held and not left:
		_fire_held = false
		if weapon:
			weapon.trigger_up()
	if _aim_held and not right:
		_set_aiming(false)
	_aim_held = right


func _set_aiming(on: bool) -> void:
	if aiming == on:
		return
	aiming = on
	aim_changed.emit(aiming)
	if anim and anim.has_method("set_aiming"):
		anim.set_aiming(aiming)


## ── 跳跃缓冲 / 土狼时间（2026-10 加，用户报「跑酷里有时候跳不起来」）──
##
## ⚠️ 原来是「`if not is_on_floor(): 重力 elif is_action_just_pressed("jump"): 跳`」——
##    **单帧脉冲** 且 **必须当帧在地面**，两个条件凑一起就很脆：
##    `is_action_just_pressed` 只在按下那一帧为真，而站在跑酷落脚板上时身体会
##    **穿透微弹**（`is_on_floor()` 逐帧 true/false 交替，实测 y 在台面与台面+0.04
##    之间来回，见 `_probe_tower_hop.gd`），脉冲正好落在 false 那帧就**整个丢掉**。
##    体感就是「明明按了却没跳」。自检也栽在这上面：塔内 11 跳有 6 次按不出来。
##
## 修法是标准做法：**按下之后 JUMP_BUFFER_MS 内**、以及**离地之后 JUMP_COYOTE_MS 内**，
## 跳都算数。按键不会因为「早了/晚了一帧」被吞掉，手感也更跟手。
const JUMP_BUFFER_MS := 180.0
const JUMP_COYOTE_MS := 100.0

var _jump_at := -99999.0        ## 上次按下跳跃键的毫秒时刻
var _air_since := -99999.0      ## 上次离地的毫秒时刻
var _was_on_floor := true       ## 上一帧的 `is_on_floor()`
## 上一帧「想走却没走动」—— 上台阶只在被挡住时才试（见 `step_climb.gd`）
var _blocked_last_frame := false


# ── 火箭骑乘锁（`scripts/rocket_ride.gd` 调用）────────────────────────────
#
# 为什么不用 `set_physics_process(false)`：那样 `_apply_camera()` 也一起停摆，
# 镜头会僵住，重新打开时弹簧臂还要长跳一帧。这里保留物理循环，只跳过
# 「输入 + `move_and_slide()`」两段，相机照常平滑跟随。
#
# 和 `look_at_node()` 的区别：那是「盯着某个物件看一秒」，人还能跑能跳；
# 这里是「人整个不归自己管了」，位置由火箭每帧直接写入 `global_position`。
## 是否被火箭锁住（锁着时不吃输入、不落重力、不做 move_and_slide）
var _ride_active := false
## 骑乘期间相机想朝向的 yaw（由火箭按飞行方向给，弧度，约定同 `_apply_camera()`）
var _ride_yaw := 0.0


## 火箭起飞 / 落地收尾时调用：锁住或放开玩家。
func set_ride_lock(on: bool) -> void:
	_ride_active = on
	velocity = Vector3.ZERO
	_aim_held = false
	_fire_held = false
	# 骑乘期间把角色网格藏起来。用户 2026-11-07：「起飞后爱丽丝还是看得见」——
	# 相机是第三人称弹簧臂、就架在她身后，不藏的话画面里就是一个站在火箭尖上的人。
	# 相机挂在 `rig` 上，藏网格不影响取景。
	if model_root != null:
		model_root.visible = not on
	if on:
		_ride_yaw = _yaw
		if anim != null and anim.has_method("set_locomotion"):
			anim.set_locomotion(0.0, true, 0.0)


## 骑乘期间让镜头转到某个朝向（弧度）。火箭拿水平飞行方向算出来喂进来。
func set_ride_yaw(yaw: float) -> void:
	_ride_yaw = yaw


## 现在是不是被火箭锁着（自检用）
func is_riding() -> bool:
	return _ride_active


# ── 载具飞行接管（`scripts/carrier_form.gd` 调用）──────────────────────────
#
# 和上面的 `_ride_active` **不是一回事**：
#   · `_ride_active`（火箭）：连位置都由外部写，人整个不归自己管；
#   · `_flight_lock`（机甲飞行）：**只交出垂直方向**，水平输入 / 加速 / 刹车 /
#     上台阶 / 卡角自救全都还在，所以飞起来仍能贴墙、仍能在平台上落脚。
#
# 只关掉「重力 + 跳跃」这两段（见 `_physics_process()` 里那一段），
# 垂直速度完全由 `carrier_form.gd::_apply_flight()` 每帧平滑控制。
var _flight_lock := false
## 巡航者模式的飞行加速倍率（`carrier_form.gd::set_cruise()` 设置）。1.0 = 平常。
var _fly_scale := 1.0


## 巡航者模式：飞得更快（用户 2026-11-08：「按 T 启动巡航者模式关闭武器能够更快飞行」）。
func set_flight_speed_scale(x: float) -> void:
	_fly_scale = maxf(x, 0.1)


## 载具起落时调用：true = 由机甲接管垂直运动。
func set_flight_lock(on: bool) -> void:
	_flight_lock = on


## 现在垂直方向是不是被机甲接管（自检用）
func is_flight_locked() -> bool:
	return _flight_lock


func _physics_process(delta: float) -> void:
	if _ride_active:
		# 人挂在火箭上：不落重力、不吃移动输入、不做 move_and_slide。
		# 位置由 `rocket_ride.gd::_carry_player()` 每帧写入，这里只管相机。
		#
		# ⚠️ 用户 2026-11-07：「起飞不能转动视角」。之前这里每帧把 `_yaw` 拉向
		#    `_ride_yaw`，等于把玩家刚用鼠标转出来的角度立刻抹掉 —— 表现就是转不动。
		#    现在只在**起飞那一刻**由 `set_ride_yaw()` 定一次初值，之后完全交给玩家。
		velocity = Vector3.ZERO
		rig.rotation.y = _yaw
		_apply_camera(delta)
		if anim != null and anim.has_method("set_locomotion"):
			anim.set_locomotion(0.0, true, 0.0)
		return

	_poll_mouse_buttons()
	# 鼠标被释放（按了 Esc）时，右键按住也要能开镜
	if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and _aim_held and not aiming:
		_set_aiming(true)

	# --- 重力与跳跃（带缓冲 / 土狼时间，见上面那段注释）---
	#
	# ⚠️ 载具飞行形态（`scripts/carrier_form.gd`）期间**整段跳过**：
	#    那段每帧也在写 `velocity.y`（`_apply_flight()` 用 `move_toward` 平滑逼近
	#    上升/悬停/下降的目标速度）。两边都写的话，这里每帧再减一次
	#    `GRAVITY * delta`、而且按住空格还会把 `velocity.y` 直接砸成 `JUMP_VELOCITY`，
	#    飞行就变成「一摁空格往上弹一下、松手立刻往下掉」——
	#    这正是本喵第一版探针量出来的现象（vy 从 3.9 掉到 −0.12）。
	#    开关由 `carrier_form.gd` 通过 `set_flight_lock()` 置位。
	if not _flight_lock:
		var now_ms := float(Time.get_ticks_msec())
		if Input.is_action_just_pressed("jump"):
			_jump_at = now_ms
		if not is_on_floor():
			if _was_on_floor:
				_air_since = now_ms
			velocity.y -= GRAVITY * delta
		_was_on_floor = is_on_floor()
		if now_ms - _jump_at <= JUMP_BUFFER_MS \
				and (is_on_floor() or now_ms - _air_since <= JUMP_COYOTE_MS):
			velocity.y = JUMP_VELOCITY
			_jump_at = -99999.0
			_air_since = -99999.0

	# --- 期望移动方向（相对相机）---
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (rig.global_basis.x * input.x + rig.global_basis.z * input.y)
	dir.y = 0.0
	if dir.length_squared() > 1.0:
		dir = dir.normalized()

	# ⚠️ 飞行期间**不认 crouch**：`Ctrl` 在机甲形态下是「下降」，不是「蹲」。
	#    这里不清掉的话，`Ctrl` 会把目标速度压到 `SPEED_CROUCH`、还会掐掉冲刺 ——
	#    用户 2026-11-08 报的「不能同时加速前进与下降」就是这一句。
	crouching = Input.is_action_pressed("crouch") and not _flight_lock
	# ⚠️ 这里**曾经有一句 `input.y < 0.1`**，本意是「不许倒着跑」。但用户要的正是
	#    「往后也能跑」，而且它挡掉的不只是 Shift —— `move_back` 的 `input.y` 是 **+1**，
	#    所以按 S 永远拿不到跑速，表现就是「往后走不能跑步」。现在四个方向一视同仁。
	#    （`_verify_move_feel.gd` 有一条专门盯着这件事，别再把它加回来。）
	sprinting = Input.is_action_pressed("sprint") and not aiming and not crouching \
		and dir.length_squared() > 0.01

	var target_speed := SPEED_WALK
	if _flight_lock:
		# 飞行：巡航 / 加力两档。开镜时收一半，让「边飞边瞄」不至于太快。
		# `_fly_scale` 是**巡航者模式**的加速（`carrier_form.gd` 按 T 时设成 1.6）。
		if aiming:
			target_speed = SPEED_FLY * 0.5
		elif sprinting:
			target_speed = SPEED_FLY_BOOST
		else:
			target_speed = SPEED_FLY
		target_speed *= _fly_scale
	elif crouching:
		target_speed = SPEED_CROUCH
	elif aiming:
		target_speed = SPEED_AIM
	elif sprinting:
		target_speed = SPEED_RUN

	# --- 水平加速 / 摩擦 ---
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	var accel := ACCEL_FLY if _flight_lock \
		else (ACCEL_GROUND if is_on_floor() else ACCEL_AIR)
	var brake := FRICTION_FLY if _flight_lock else FRICTION
	if dir.length_squared() > 0.01:
		horiz = horiz.move_toward(dir * target_speed, accel * delta)
	else:
		horiz = horiz.move_toward(Vector3.ZERO, brake * delta)

	velocity.x = horiz.x
	velocity.z = horiz.z
	# 上台阶：`CharacterBody3D` 自己不会，Godot 也没有内置开关（见 `step_climb.gd`）。
	#
	# 顺序要紧 —— **先抬上去、再 `move_and_slide()`**：先把人放到台阶顶面，
	# 这一帧的滑移就在平地上做，不会撞到踢面；反过来先滑再抬，这一帧已经被挡住，
	# 抬起来也只剩 0 位移可用。
	#
	# 只在「上一帧想走却没走动」时才试，所以平地上零开销、原手感一点不动
	# （`_verify_move_feel.gd` 那套断言照旧）。
	var before := global_position
	if _blocked_last_frame and horiz.length_squared() > 0.01:
		var y0 := global_position.y
		if StepClimb.try_step(self, horiz * delta):
			# ── 上台阶的**相机缓冲**（用户 2026-10-26：「上楼梯生硬」）──
			#
			# `step_climb` 是**一帧之内**把人抬上去的：实测爬那段 21 级楼梯，
			# 单帧最大抬升 **0.239 m**、一分钟里跳 77 次 —— 相机挂在人身上，
			# 于是跟着一级一级「啪」地跳，这就是「生硬」。
			# 这里只把**抬升量**记进 `_step_lag`（水平位移照旧即时，不然人会慢半拍），
			# 由 `_apply_camera()` 按指数曲线放掉：物理上她已经站上去了，脚仍然踩在
			# 踏面上；但**相机是滑上去的**。
			_step_lag = maxf(_step_lag - maxf(global_position.y - y0, 0.0), -STEP_LAG_MAX)
		before = global_position
	move_and_slide()
	_blocked_last_frame = StepClimb.blocked(
		global_position - before, horiz * delta)

	# ── 卡角自救（2026-11-02 用户：「卡在这个角落居然出不来」）──
	# 家具碰撞是轴对齐盒，桌子和椅子之间可能留下 < 胶囊直径的 V 形口袋；
	# 同时贴两面墙、推了 0.8 s 还几乎没动，就沿两面法线之和轻推 0.28 m 出来。
	_unstick_cool = maxf(_unstick_cool - delta, 0.0)
	var hs := Vector2(velocity.x, velocity.z).length()
	var pushing := dir.length_squared() > 0.01
	if is_on_floor() and pushing and hs < 0.20:
		_stuck_t += delta
	else:
		_stuck_t = 0.0
	if _stuck_t > 1.0 and _unstick_cool <= 0.0:
		# 先按墙法线退；法线拿不到就沿输入反方向退
		var away := Vector3.ZERO
		for ci in get_slide_collision_count():
			away += get_slide_collision(ci).get_normal()
		away.y = 0.0
		if away.length_squared() < 0.01:
			away = -dir
			away.y = 0.0
		if away.length_squared() > 0.01:
			var was := global_position
			global_position += away.normalized() * 0.22
			velocity = Vector3.ZERO
			_stuck_t = 0.0
			_unstick_cool = 1.2
			print("[Player] 卡角自救：%s → %s" % [str(was.snappedf(0.01)), str(global_position.snappedf(0.01))])

	# --- 角色朝向：开火/开镜时必对准准星，否则对着移动方向 ---
	#
	# ⚠️ 模型朝向约定（实测出来的，改动前务必看这段）
	#
	# 铁证（把相机放到角色 +Z 侧渲图，看到的是正脸）：
	#   model_root.rotation.y = 0  →  脸朝世界 +Z
	#   所以「脸朝向」= (sin(rotation.y), cos(rotation.y))
	#   要让脸对着方向 dir，就是 rotation.y = atan2(dir.x, dir.z)
	#
	# 曾经踩过的坑：对「移动方向」而言 atan2(-dir.x,-dir.z) 和额外 +PI 都是反的；
	# 判据别用 shoulder×up 之类的叉乘，用眼睛骨做定性核对或直接渲图。
	#
	# 开火强制转向（需求）：只要扳机按着（或开镜），朝向就必须对准准星方向，
	# 转到位之前武器系统不会开火（见 Weapon.is_aim_aligned()）。
	# 等式右侧是「相机视线方向」= _yaw + PI（相机挂在 rig 的 +Z 侧看向 -Z，
	# 见 CAMERA_FORWARD_OFFSET 那段注释），别写成 _yaw（那样是背对准星）。
	# 剧情锁定（拾到 5090 → 镜头自动怼到倭瓜优香身上 1 秒，见 `look_at_node()`）
	_update_look_lock(delta)

	var locked := _lock_left > 0.0
	var want_face_aim := aiming or _fire_held
	if locked:
		pass                     # 锁定期间朝向由 `_update_look_lock()` 决定
	elif want_face_aim:
		_facing_yaw = _yaw + CAMERA_FORWARD_OFFSET
	elif dir.length_squared() > 0.01:
		# ⚠️ 有输入就**立刻朝意图方向**，不要等速度转过来 —— 速度受加速度限制，
		#    换向时要拖小半秒才拐过去，那正是「转向不灵活」的观感。
		#    `dir` 是相对相机的**输入**方向，`horiz` 是**当前速度**；方向不变时两者
		#    相同，所以「跑动时脸朝移动方向」那条断言照样成立（见 _verify_final §4）。
		_facing_yaw = atan2(dir.x, dir.z)
	elif horiz.length_squared() > 0.25:
		# 没输入但在滑行：保持朝滑行方向，**不要**回落到相机朝向
		# （那正是 `_facing_yaw` 那段注释里踩过的坑：松手后角色自己转回去面对镜头）
		_facing_yaw = atan2(horiz.x, horiz.z)

	# 开火转身要快一点，不然「点了没反应」的感觉很明显（剧情锁定也用快的那档）
	var turn_speed := TURN_SMOOTH_FIRE if (want_face_aim or locked) else TURN_SMOOTH
	model_root.rotation.y = _lerp_angle_smooth(model_root.rotation.y, _facing_yaw, turn_speed, delta)
	rig.rotation.y = _yaw

	_apply_camera(delta)

	if anim and anim.has_method("set_locomotion"):
		anim.set_locomotion(Vector2(horiz.x, horiz.z).length(), is_on_floor(), velocity.y)


## 相机平滑：开镜时拉近、抬高、右肩偏移、缩 FOV
func _apply_camera(delta: float) -> void:
	var t := clampf(cam_lerp * delta, 0.0, 1.0)
	# 上台阶缓冲（见 `_physics_process` 里记 `_step_lag` 那段）：指数衰减，
	# 帧率无关。它**加在** rig 的基准高度上，所以不干扰蹲/开镜的高度插值。
	_step_lag = lerpf(_step_lag, 0.0, 1.0 - exp(-delta / STEP_LAG_TAU))
	# ⚠️ 腰射的最近距离**不是固定 zoom_min**：还要满足「看得见全身」，
	#    见 `min_zoom_for_full_body()`。
	var want := aim_distance if aiming else maxf(_zoom_distance, min_zoom_for_full_body())
	spring.spring_length = lerpf(spring.spring_length, want, t)
	spring.position.x = lerpf(spring.position.x, -(aim_shoulder if aiming else hip_shoulder), t)
	rig.position.y = lerpf(rig.position.y, aim_height if aiming else hip_height, t) + _step_lag
	cam.fov = lerpf(cam.fov, aim_fov if aiming else hip_fov, t)

	_recoil_pitch = lerpf(_recoil_pitch, 0.0, clampf(9.0 * delta, 0.0, 1.0))
	_recoil_yaw = lerpf(_recoil_yaw, 0.0, clampf(9.0 * delta, 0.0, 1.0))

	spring.rotation.x = _pitch + _recoil_pitch
	spring.rotation.y = _recoil_yaw
	rig.rotation.y = _yaw


## 滚轮能拉到多近，还能看见**全身**。
##
## 相机在 `hip_height`（1.62 m）高度平视，脚在它正下方 1.62 m 处；
## 要在垂直半视角 θ = fov/2 里看见脚，水平距离至少 `hip_height / tan(θ)`。
## fov 62° → 2.70 m（再加 0.30 m 余量 = 3.0 m）。用户把 FOV 调小（视野拉近）时
## 这个数会变大，所以最近距离**必须跟着 FOV 走** —— 固定 1.8 m 时相机已经贴到
## 后背，画面只剩头发和肩膀（用户 2026-10-20：「fov 拉近就看不见爱丽丝全身了，
## 要能够看见全身的」）。
func min_zoom_for_full_body() -> float:
	var half := deg_to_rad(clampf(hip_fov, 20.0, 120.0) * 0.5)
	return hip_height / tan(half) + 0.30


## 剧情演出：**强制镜头看向某个物体**（默认 1 秒），期间鼠标转不动。
##
## 2026-10-20 用户：「真正拾取 5090 后视角强制锁定倭瓜优香一秒钟」——
## `parkour.gd::_spawn_avenger()` 在倭瓜优香出场那一帧调用它。
##
## ⚠️ 角度换算（改之前先看 `_apply_camera()` 里那条推导）：
##    相机挂在 rig 的 +Z 侧、看向 −Z，所以**视线方向** = −(sin yaw, 0, cos yaw)；
##    俯仰 p 时视线 = (sin yaw·cos p 的横向分量, **sin p**, …)，即竖直分量就是 sin p。
##    于是「看向 d」⇔ `yaw = atan2(−d.x, −d.z)`、`pitch = asin(d.y)`。
##    （写成 atan2(d.x, d.z) 会正好差 180°，镜头会怼到反方向 —— 和
##    `CAMERA_FORWARD_OFFSET` 那条坑同源。）
func look_at_node(target: Node3D, duration := 1.0) -> void:
	if target == null or not is_instance_valid(target):
		return
	_lock_target = target
	_lock_left = maxf(duration, 0.01)


## 镜头现在是不是被剧情锁着（自检 / HUD 用）
func look_locked() -> bool:
	return _lock_left > 0.0


## 每帧把 `_yaw` / `_pitch` 拉向目标。用 16/s 的指数逼近而不是瞬移，
## 1 秒里大约 0.3 s 就转到，剩下 0.7 s 稳稳盯着 —— 比硬切好看，也不会转晕。
func _update_look_lock(delta: float) -> void:
	if _lock_left <= 0.0:
		return
	_lock_left = maxf(_lock_left - delta, 0.0)
	if _lock_target == null or not is_instance_valid(_lock_target):
		_lock_left = 0.0
		return
	# 盯胸口偏上（Boss 高 4.5 m，盯脚会看成一堵墙；太顶又会出画）
	var aim := _lock_target.global_position + Vector3(0.0, 1.6, 0.0)
	var d := aim - cam.global_position
	if d.length_squared() < 0.04:
		return
	d = d.normalized()
	var want_yaw := atan2(-d.x, -d.z)
	var want_pitch := clampf(asin(clampf(d.y, -1.0, 1.0)), pitch_min, pitch_max)
	var t := clampf(16.0 * delta, 0.0, 1.0)
	_yaw = lerp_angle(_yaw, want_yaw, t)
	_pitch = lerpf(_pitch, want_pitch, t)
	# 人也转过去（锁定期间 `_physics_process` 不会再用移动输入覆盖朝向）
	_facing_yaw = atan2(d.x, d.z)


func take_damage(amount: float, hit_from := Vector3.ZERO, knockback := 0.0) -> void:
	if amount <= 0.0 or health <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	if knockback > 0.0:
		var away := global_position - hit_from
		away.y = 0.0
		if away.length_squared() > 0.001:
			velocity += away.normalized() * knockback
		else:
			# 正好站在爆心（天降砸脚下）：随机往一边弹 —— 否则「大力击退」会变成原地不动
			var a := randf() * TAU
			velocity += Vector3(cos(a), 0.0, sin(a)) * knockback
	health_changed.emit(health, max_health)
	if health <= 0.0:
		# 血量见底 = 像掉进虚空一样被送回本场景的存档点，不再原地回血。
		_die_and_respawn()


## 关卡进场景时调一次，把「这个场景的存档点」定下来。
func set_respawn_transform(xf: Transform3D) -> void:
	_respawn_xform = xf


func set_respawn_point(p: Vector3) -> void:
	_respawn_xform = Transform3D(_respawn_xform.basis, p)


func respawn_point() -> Vector3:
	return _respawn_xform.origin


## 倒下 → 短促停顿 → 送回存档点并回满血。0.6 s 的停顿是为了让击杀有一拍反馈，
## 同时给关卡接 `died` 信号做善后（清进度、弹提示）。
func _die_and_respawn() -> void:
	if _dying:
		return
	_dying = true
	velocity = Vector3.ZERO
	died.emit()
	await get_tree().create_timer(0.6).timeout
	if not is_instance_valid(self):
		return
	global_transform = _respawn_xform
	velocity = Vector3.ZERO
	health = max_health
	health_changed.emit(health, max_health)
	_dying = false


func heal(amount: float) -> void:
	if amount <= 0.0:
		return
	health = minf(health + amount, max_health)
	health_changed.emit(health, max_health)


func add_recoil(pitch: float, yaw: float) -> void:
	_recoil_pitch += pitch
	_recoil_yaw += yaw


# --- 设置（Esc 菜单 / scripts/game_settings.gd）---

## 把设置页管得着的那几项应用到本节点。
## ⚠️ 只碰 `mouse_sensitivity` / `hip_fov` / `aim_fov` —— 相机高度、转身平滑、
##    移速这些仍然由场景与脚本说了算，不属于「设置界面」的范围。
func _apply_settings() -> void:
	mouse_sensitivity = float(GameSettings.value("mouse_sensitivity"))
	var fov := float(GameSettings.value("fov"))
	hip_fov = fov
	aim_fov = fov * AIM_FOV_RATIO
	_apply_camera(1.0)


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "mouse_sensitivity" or key == "fov":
		_apply_settings()


## 当前「应该朝」的方向（弧度）。
##
## 开火/开镜时必须现算 = _yaw + PI。**不能**用上一物理帧缓存的 _facing_yaw：
## 甩镜头 + 点左键时，_input 里 _fire_held 立刻变 true，武器 _process 可能
## 排在角色 _physics_process 之前，那一刻缓存的 _facing_yaw 还是旧值，
## 于是「朝旧方向漏出一发」——正好是「明明背对着却打出去了」这种毛病。
func aim_facing_yaw() -> float:
	if aiming or _fire_held:
		return _yaw + CAMERA_FORWARD_OFFSET
	return _facing_yaw


## 角色朝向是否已经对准准星（射击方向）
func is_aim_aligned() -> bool:
	if model_root == null:
		return true
	var face := atan2(sin(aim_facing_yaw()), cos(aim_facing_yaw()))
	var cur := atan2(sin(model_root.rotation.y), cos(model_root.rotation.y))
	return absf(angle_difference(face, cur)) <= FIRE_ALIGN_TOLERANCE


## 当前朝向与目标朝向差多少度（调试/测试用）
func align_error_deg() -> float:
	if model_root == null:
		return 0.0
	return rad_to_deg(absf(angle_difference(
		atan2(sin(aim_facing_yaw()), cos(aim_facing_yaw())),
		atan2(sin(model_root.rotation.y), cos(model_root.rotation.y)))))


## 开镜时视线收敛到的世界点（准星位置）
func aim_point(distance := 200.0) -> Vector3:
	return cam.global_position - cam.global_transform.basis.z * distance


func camera_forward() -> Vector3:
	return -cam.global_transform.basis.z


func _lerp_angle_smooth(from: float, to: float, speed: float, delta: float) -> float:
	return lerp_angle(from, to, clampf(speed * delta, 0.0, 1.0))
