class_name Player
extends CharacterBody3D

## 上台阶辅助。用 `preload` 而不是 `class_name` 引用 —— 见 `step_climb.gd` 文件头第一条。
const StepClimb := preload("res://scripts/step_climb.gd")
## 开发者快捷键（F3/F4/F5/F6）用到的两个静态工具
const DevMode := preload("res://scripts/dev_mode.gd")
const SceneFlowDev := preload("res://scripts/scene_flow.gd")
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
@export var zoom_min := 1.1
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
## 相机避墙的阻尼时间常数（秒）。见 `_collide_camera_arm()`。
##
## ⚠️ 这两个值**不能差太多**。曾经是 0.045 / 0.22（差 5 倍），结果墙的边缘
##    正好在"打中/打不中"之间时：打中 → 快速缩进，打不中 → 慢慢退出，
##    退一半又打中 → 再缩进，表现为**一前一后地摆**。
##    现在压到 0.09 / 0.14（差 1.5 倍）：拉近仍然比拉远快，但迟滞小到这个量级，
##    不会再形成"缩进去—退出来"的往复。
const CAM_IN_TAU := 0.09
const CAM_OUT_TAU := 0.14
## 目标长度比当前值变化不到这个量（米）时**完全不动** —— 死区。
## 墙的边缘在射线命中临界点上抖动时，这一条直接把微小的来回翻转吃掉。
const CAM_DEAD_ZONE := 0.02
## 相机臂长每帧的**绝对位移上限**（米/秒）。指数阻尼在 `want` 和目标差很大时
## 单帧位移会很凶（9.0 → 2.0 差 7 m，一帧能走 2 m），低帧时直接跨过一堵墙。
## 32 m/s 对 60 fps 是每帧 0.53 m，对 30 fps 是 1.07 m —— 都小于常见墙厚，
## 而且远快于玩家跑动速度（约 6 m/s），实际观感仍然很跟手。
const CAM_MAX_STEP_SPEED := 32.0
## 相机离墙至少留这么多（米）。太小会露出墙的内侧面，太大在窄走廊里怼脸更狠。
@export var cam_wall_margin := 0.25
## 相机探测器用的球形半径。给一点半径，墙角/门框才不会从缝里钻过去。
@export var cam_probe_radius := 0.18
## 相机避墙射线打哪些层。默认 layer 1（世界）。
## `SpringArm3D.collision_mask` 会在 `_ready()` 里被置 0 —— 内置收缩由
## `_collide_camera_arm()` 接管（原因见那个函数上面的注释）。
@export_flags_3d_physics var cam_wall_mask := 1
var _wall_mask := 1

## ── 近景：滚轮推近时**把相机支点降下来**（用户 2026-11-09）──
##
## 用户原话：「滚轮推进拉远视角，推进视角还不够近，而且推进方向还得偏一点，
## 要能够欣赏完整爱丽丝」。
##
## 真因（`_probe_body_extent.gd` 实测骨骼）：**爱丽丝是 Q 版，不是真人身高** ——
##   脚趾骨 y = −0.041、头骨 y = 0.570、光环顶 y = 1.024
## 也就是说她整个人只有 1.0 m 出头（含光环），而 `hip_height` = 1.62 ——
## **支点在她头顶上方 0.6 m**。相机在 1.62 m 平视，她就只能缩在画面下半截：
## `_probe_zoom_fit.gd` 量出来最贴近（当时被公式卡在 3.00 m）时，
## 头顶在画面 67%、脚底 95%，上面 2/3 全是空墙 —— 又不够近、又偏。
##
## 修法：滚轮越近，支点从 `hip_height` 平滑降到 `zoom_look_height`（她的身体中心），
## 这样 1.1 m 就能把她**整只**装进画幅。
##
## 肩偏移（用户 2026-11-10：「别让她压在准星正中」）：
##   原来近景收到 0.10，等于把她摆回准星上 —— 1.1 m 时横向只偏 68 px / 1600（4.3%），
##   准星正好落在她的头发边缘，观感是「被十字压在脸上」。
##   现在近景保留 0.30（过肩视感）：1.1 m 偏 204 px（12.8%）、1.6 m 偏 153 px（9.5%），
##   准星落在她身侧的空白地面上，全身照样在画幅里。
##   数值是 `_probe_zoom_fit.gd --shoulders=0.10,0.22,0.30,0.38` 扫出来挑的：
##   0.22 分离感不够、0.38 她贴到画面右缘还把身后的人挡住。
##
## 数值来源：`_probe_body_extent.gd` 量骨骼 → `body_bottom` / `body_top`；
##          之后任何距离的「至少多远才看得见全身」由 `min_zoom_for_full_body()` 按这两条算，
##          所以把 FOV 调小（视野变窄）时最近距离会**自动**跟着退，不会再切脚。
@export var body_bottom := -0.05
@export var body_top := 1.05
@export var zoom_look_height := 0.52
@export var zoom_shoulder_close := 0.30
## 超过这个距离就完全回到原来的平视取景（`hip_height` / `hip_shoulder`）。
## 取 3.2：腰射默认 4.2 m、往里滚两格左右还在原来的构图里，再往里才开始「降支点」。
@export var zoom_close_full := 3.2
## 全身刚好装进画幅之后再多留一点余量（米），免得她贴着上下边缘。
@export var zoom_fit_margin := 0.12

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

## ── EX 必杀系统（2026-11-09）──
## 用户：「按 EX 连按释放必杀技能：普通状态是蓄力激光球，机甲状态是蓄力激光巨型连续轨道炮。
##        EX 充能是随着时间增加的」
## 由本脚本在 `_ready()` 里**动态创建**（不写进 player.tscn：
## 那个场景文件会被很多会话同时改，加节点容易冲突）。
const ExSystem := preload("res://scripts/ex_system.gd")
var ex: Node3D = null


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
	# 相机避墙：关掉 SpringArm3D 内置的收缩，改由 `_collide_camera_arm()` 接管。
	# 内置收缩每帧直接把 Camera3D 摆到命中点、不可插值 —— 那正是
	# 「穿过窄走廊镜头突然怼脸」（用户 2026-11-10）的直接原因。
	_wall_mask = cam_wall_mask
	spring.collision_mask = 0
	_apply_camera(1.0)
	health_changed.emit(health, max_health)
	_respawn_xform = global_transform
	# 设置（Esc 菜单）：先读一次初值，之后跟着变
	GameSettings.listen(_on_setting_changed)
	_apply_settings()
	_setup_face_fill()

	# 用户 2026-11-09：「爱丽丝普通状态,攻击从机枪变成激光机枪」。
	# 普通状态默认就是激光枪（单枪口、照常扣弹匣）；机甲形态另有 `beam_mode`
	# 走两门肩炮 + 无限弹，两条路互不影响（见 `weapon.gd::set_laser_gun`）。
	if weapon != null and weapon.has_method("set_laser_gun"):
		weapon.call("set_laser_gun", true)

	_setup_ex()


## 建 EX 系统（见文件头 `ExSystem` 那段说明）。
## 放在玩家自己身上，跟着玩家走；`carrier` 需要拿来做形态判定。
func _setup_ex() -> void:
	ex = ExSystem.new() as Node3D
	if ex == null:
		push_warning("[EX] 建不出 ex_system，必杀不可用")
		return
	ex.name = "ExSystem"
	add_child(ex)
	ex.call("setup", self, weapon, get_node_or_null("Arisu/CarrierForm"))


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


## 滚轮一格：`dir` = −1 拉近 / +1 拉远，夹在 `zoom_min` … `zoom_max` 之间。
##
## 单独拎成方法是为了让自检**不依赖鼠标捕获**也能真测它：headless 下
## `Input.mouse_mode` 赋值成 CAPTURED 读回来还是 VISIBLE（`_probe_ride_zoom.gd`
## 文件头量过），于是 `_input()` 那条滚轮分支永远进不去 ——
## `_verify_facing.gd` 里「下滚没有改变距离 / zoom_max / zoom_min / 拉近没生效」
## 四条因此一直红，红的不是功能而是测法。现在自检改调这个方法，四条能真跑。
func wheel_zoom(dir: int) -> void:
	_zoom_distance = clampf(_zoom_distance + float(dir) * zoom_step, zoom_min, zoom_max)


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
			wheel_zoom(-1)
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			wheel_zoom(1)
			return

	# --- 键盘 ---
	if event is InputEventKey and (event as InputEventKey).pressed \
		and not (event as InputEventKey).echo:
		var key := (event as InputEventKey).keycode
		# ── 开发者快捷键（用户 2026-11-08）──
		# ⚠️ 必须放在下面 `KEY_R` 换弹之前：开发者模式下这几键要优先被吃掉。
		#
		# ⚠️ 2026-11-10：**F3 完全交给 `game.gd`**，这里不再处理。
		#
		#   原因：两个脚本的 `_input` 都想吃 F3，而**谁先谁后由树序决定**
		#   （Player 在前），加上每边一个 `set_input_as_handled()`，
		#   就变成「只有一个能跑」——
		#     · player 先吃 → `game.gd` 收不到 → **帧率浮层打不开**
		#     · 反过来 → 开发者模式开不了
		#   而且 Player 是 PAUSABLE：开菜单/播剧情时它压根收不到 `_input`，
		#   于是 F3 的行为还随「有没有暂停」变。用户报的「F3 不见了」
		#   就是这一堆顺序问题的综合症状。
		#
		#   现在：由 `game.gd` 一处处理（开浮层 + 切开发者模式），
		#   本脚本只认领 F4/F5/F6 并吃掉它们。
		if _dev_key(key):
			get_viewport().set_input_as_handled()
			return
		# ⚠️ Esc **不在这里处理**：它归设置界面（scripts/settings_menu.gd）。
		#    菜单打开时游戏是暂停的、player 收不到输入，也就没法负责「关掉菜单」——
		#    由菜单自己监听（PROCESS_MODE_ALWAYS）才能一开一关都稳。
		if key == KEY_R and weapon:
			weapon.try_reload()
			return
		# ── EX 必杀（2026-11-10 按用户更正：连按 E → X）──
		# 用户原话：「连续按键盘 E X 触发,消耗 6 cost,不需要充能条和蓄力时间,
		#            就是按完 E X 键盘就是最大功率发射」
		# 所以这里只做一件事：把 E / X 两个键喂给 ex_system 的搓招状态机。
		# ⚠️ 必须放在 `_dev_key` **之后**：开发者模式的 F 键优先级更高；
		#    但要在换弹 `KEY_R` 之后 —— 两者不冲突（R 不参与 E/X 序列）。
		if (key == KEY_E or key == KEY_X) and ex != null:
			if bool(ex.call("feed_key", key)):
				get_viewport().set_input_as_handled()
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


## ── 开发者快捷键（用户 2026-11-08）────────────────────────────────────────
##
##   F3 → **不在本脚本处理**（见 `_input` 里那段注释，现在归 `game.gd`）
##   F4 → 直接切到另一个场景（在 `game.tscn` 就跳 `next_level.tscn`，反之亦然）
##   F5 → 秒杀场上所有 `bosses` 分组里的敌人
##   F6 → 角色速度 ×3 / 恢复（调试用）
##
## F4/F5/F6 **只在开发者模式打开后生效**，避免正常玩的时候误触。
## 返回 true 表示这个键被吃掉了。
func _dev_key(key: int) -> bool:
	match key:
		KEY_F4:
			if not DevMode.is_on():
				return false
			var cur := ""
			var cs := get_tree().current_scene
			if cs != null:
				cur = cs.scene_file_path
			var nxt := "res://scenes/next_level.tscn" if cur.ends_with("game.tscn") \
				else "res://scenes/game.tscn"
			if SceneFlowDev.switching:
				return true
			print("[Dev] F4：%s → %s" % [cur, nxt])
			SceneFlowDev.switch_scene(nxt, "", "DevF4", false)
			return true
		KEY_F5:
			if not DevMode.is_on():
				return false
			var n := 0
			for b in get_tree().get_nodes_in_group("bosses"):
				if b.has_method("take_damage"):
					# 给一个绝对够的伤害，走 Boss 自己的 `_die()` 流程
					# （闪白 / 掉落 / 重生判定都在那边，不要绕过它）
					b.call("take_damage", 1.0e9, global_position, Vector3.ZERO)
					n += 1
			print("[Dev] F5 秒杀：场上 %d 个敌人" % n)
			return true
		KEY_F6:
			if not DevMode.is_on():
				return false
			_dev_speed_scale = 1.0 if _dev_speed_scale > 1.5 else 3.0
			print("[Dev] F6 角色速度 ×%.1f" % _dev_speed_scale)
			return true
	return false


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
## 开发者模式 F6 的整体倍速（地面 + 飞行都吃）。1.0 = 关。
var _dev_speed_scale := 1.0


## 巡航者模式：飞得更快（用户 2026-11-08：「按 T 启动巡航者模式关闭武器能够更快飞行」）。
func set_flight_speed_scale(x: float) -> void:
	_fly_scale = maxf(x, 0.1)


## 载具起落时调用：true = 由机甲接管垂直运动。
func set_flight_lock(on: bool) -> void:
	_flight_lock = on


## 现在垂直方向是不是被机甲接管（自检用）
func is_flight_locked() -> bool:
	return _flight_lock


## 机甲形态标志（`carrier_form.gd::set_form()` 置位）。
##
## ⚠️ **和 `_flight_lock` 是两件事**，别合并：
##   · `_flight_lock` = 「**此刻**在飞」—— 落地就清掉（`_land()`）；
##   · `_carrier_on`  = 「**这局**是机甲形态」—— 从变形到变回一直为真。
##
## 用户 2026-11-09：「在地上怎么飞这么慢，不应该也是飞吗，为什么不和天上一个速度」。
## 病根就是这两件事被混用了：机甲一落地 `_land()` 把 `_flight_lock` 清掉，
## 速度立刻从 `SPEED_FLY 11` 掉回 `SPEED_WALK 2.4`（慢 4.6 倍），
## 而玩家看到的还是一台机甲 —— 它凭什么要按步兵速度挪。
##
## 所以速度判据改成 **`_flight_lock or _carrier_on`**：机甲形态不论地上空中都吃
## 飞行那一档（11 / 19）。垂直方向仍由 `_flight_lock` 管，落地抬升/重力照旧。
var _carrier_on := false


func set_carrier_form(on: bool) -> void:
	_carrier_on = on


## 现在是不是机甲形态（自检用）
func is_carrier_form() -> bool:
	return _carrier_on


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
	# ⚠️ 机甲形态（`_carrier_on`）同样不认 crouch：它落地了也不该蹲下去。
	crouching = Input.is_action_pressed("crouch") and not _flight_lock and not _carrier_on
	# ⚠️ 这里**曾经有一句 `input.y < 0.1`**，本意是「不许倒着跑」。但用户要的正是
	#    「往后也能跑」，而且它挡掉的不只是 Shift —— `move_back` 的 `input.y` 是 **+1**，
	#    所以按 S 永远拿不到跑速，表现就是「往后走不能跑步」。现在四个方向一视同仁。
	#    （`_verify_move_feel.gd` 有一条专门盯着这件事，别再把它加回来。）
	sprinting = Input.is_action_pressed("sprint") and not aiming and not crouching \
		and dir.length_squared() > 0.01

	var target_speed := SPEED_WALK
	# ⚠️ 判据是 `_flight_lock or _carrier_on`，**不是**只看 `_flight_lock`：
	#    机甲落地后 `_land()` 会清掉 `_flight_lock`，只看它速度就掉回步兵档。
	#    `_carrier_on` 保证「只要是机甲形态」，地上也吃飞行那一档（用户 2026-11-09）。
	if _flight_lock or _carrier_on:
		# 飞行：巡航 / 加力两档。开镜时收一半，让「边飞边瞄」不至于太快。
		# `_fly_scale` 是**巡航者模式**的加速（`carrier_form.gd` 按 T 时设成 2.6）。
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

	# 开发者模式 F6 的整体倍速（地面和飞行一起吃）
	target_speed *= _dev_speed_scale

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
##
## ── 「穿窄走廊相机突然怼脸」的修法（用户 2026-11-10）──
##
## `SpringArm3D` 撞墙时**自己**在内部把子节点位置缩到交点前，这一步不接受任何
## 插值 —— 它每帧直接把 Camera3D 摆到命中点上。所以只要射线打中墙，镜头就是
## 一帧之内从 3.4 m 掉到 0.x m，表现为「进走廊瞬间怼脸」。
##
## 修法：**不再让 SpringArm3D 移动镜头**。把 `spring_length` 设成一个固定够长的
## 值（让它永远够不着墙，即不参与收缩），改成我们自己用 `intersect_ray` 探墙，
## 再按「拉近快、拉远慢」的指数阻尼走过去：
##   - 拉近（被墙推近）τ = `CAM_IN_TAU`，快一点，避免镜头穿进墙里；
##   - 拉远（离开墙）  τ = `CAM_OUT_TAU`，慢一点，不会「啪」地弹回去。
## 这条路帧率无关（`1 - exp(-dt/τ)`），低帧时也不会一帧跨完。
func _apply_camera(delta: float) -> void:
	var t := clampf(cam_lerp * delta, 0.0, 1.0)
	# 上台阶缓冲（见 `_physics_process` 里记 `_step_lag` 那段）：指数衰减，
	# 帧率无关。它**加在** rig 的基准高度上，所以不干扰蹲/开镜的高度插值。
	_step_lag = lerpf(_step_lag, 0.0, 1.0 - exp(-delta / STEP_LAG_TAU))
	# 近景取景：滚轮越近，支点越低、肩偏移越小（见 `zoom_look_height` 那段注释）。
	# 开镜是另一套固定取景，不参与这段插值。
	var near_k := _zoom_near_k()
	var look := lerpf(zoom_look_height, hip_height, near_k)
	var shoulder := lerpf(zoom_shoulder_close, hip_shoulder, near_k)
	# ⚠️ 腰射的最近距离**不是固定 zoom_min**：还要满足「看得见全身」，
	#    见 `min_zoom_for_full_body()`。
	var want := aim_distance if aiming else maxf(_zoom_distance, min_zoom_for_full_body(look))
	# ⚠️ 这里**不能再做一次 lerp**（用户 2026-11-10：「摄像头总是突然一前一后」）。
	#    之前的写法是 `want_smooth = lerpf(spring.spring_length, want, t)` 再交给
	#    `_collide_camera_arm`，等于**两段 lerp 串联，而且第二段的起点是上一帧的
	#    实际值** —— 正反馈，静止不动也会以两帧周期来回摆（实测峰峰 0.15 m、
	#    90 帧反向 20 次，空地上也一样，和墙无关）。
	#    现在把平滑**全部**交给 `_collide_camera_arm()`，它直接拿原始 `want` 当目标，
	#    从「当前实际长度」朝它走一步 —— 单一阻尼、单一目标、无级联。
	spring.spring_length = _collide_camera_arm(want, delta)
	spring.position.x = lerpf(spring.position.x, -(aim_shoulder if aiming else shoulder), t)
	rig.position.y = lerpf(rig.position.y, aim_height if aiming else look, t) + _step_lag
	cam.fov = lerpf(cam.fov, aim_fov if aiming else hip_fov, t)

	_recoil_pitch = lerpf(_recoil_pitch, 0.0, clampf(9.0 * delta, 0.0, 1.0))
	_recoil_yaw = lerpf(_recoil_yaw, 0.0, clampf(9.0 * delta, 0.0, 1.0))

	spring.rotation.x = _pitch + _recoil_pitch
	spring.rotation.y = _recoil_yaw
	rig.rotation.y = _yaw


## 相机避墙：把「想拉到的长度」按墙的位置压回去，并带阻尼。
##
## ⚠️ 为什么不用 `SpringArm3D` 自带的收缩：它每帧**直接把 Camera3D 摆到命中点**，
##    这一步不可插值 —— 撞墙就是一瞬间掉到 0.x m。这里改用自己打射线，
##    只动 `spring_length` 这个**数值**，再让它以指数阻尼逼近，镜头才是滑过去的。
##
## ⚠️ `spring.collision_mask` 必须置 0（在 `_ready()` 里做），否则内置收缩会
##    抢在阻尼之前把镜头一帧怼到墙上 —— 两套机制同时生效就白改了。
##
## ── 只打一条中心射线为什么不够（用户 2026-11-10 第二轮反馈）──
##
## 用户原话：「摄像机会穿过碰撞了，这样子我把视野角拉大，滚轮缩到最大视野范围，
##            经常会超出建筑物看不见角色」。
##
## 真因两条：
##   ① **FOV 拉大后画面边缘比中心宽得多**。只沿中心轴打一条射线，中心擦过墙角
##      就算"没挡住"，可画面左右两侧早已看穿墙外 —— 表现出来就是"相机钻进墙里"。
##      修法：沿**近平面四角**（不是中心）各打一条，取最短的那个。
##   ② **阻尼太快会跳过墙体**。`want` 从 9.0 掉到 2.0 时，过去按 CAM_IN_TAU
##      一帧就走 31%（≈2 m），低帧时直接跨过一堵墙。修法：给每帧的**绝对位移**
##      加上限（`CAM_MAX_STEP`），再快也只是一帧一小步。
##
## 探测器：从支点出发，沿弹簧臂方向分别在近平面四角方向上打射线。
## 近平面大小由当前 FOV 和宽高比决定 —— 这样 FOV 越大，探测越"宽"，
## 画面边缘也不会漏墙。
func _collide_camera_arm(want: float, delta: float) -> float:
	var space := get_world_3d().direct_space_state
	if space == null:
		return want

	# 支点：就是 SpringArm3D 自己所在的位置。
	var origin := spring.global_position
	# 从支点指向相机的那一侧（弹簧臂的长轴）。
	var axis := -spring.global_transform.basis.z.normalized()

	var exclude: Array[RID] = [get_rid()]
	# ⚠️ 探测长度用 `want`，**不是**当前 `spring_length`：
	#    用当前长度当探测范围会形成循环依赖（臂变短 → 探测范围变小 → 探不到墙
	#    → 臂回弹 → 又探到），那就是「一前一后」的第二个来源。
	#    `want` 是滚轮/开镜决定的**外部目标**，与臂的实际状态无关，天然稳定。
	var reach := want + cam_probe_radius + cam_wall_margin
	var best := INF
	for d: Vector3 in _camera_probe_dirs(axis, want):
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
				origin, origin + d * reach, _wall_mask, exclude))
		if hit.is_empty():
			continue
		# ⚠️ 只认**竖直墙面**，不认地板和天花板（探针实测 2026-11-10：
		#    近平面四角里的下面两条射线会撞到地板，`best` 被地板锁在 ~2.1 m，
		#    墙怎么移都不动 —— 表现为臂长"卡住"）。
		#    判据：命中法线的**水平分量**足够大，或者射线本身接近水平
		#    （天花板正上方、地板正下方这种纯垂直面直接跳过）。
		var n: Vector3 = hit.get("normal", Vector3.UP)
		if absf(n.y) > 0.85:
			# 接近水平的地板 / 天花板面 —— 相机滑着过去就行，不该缩短臂长。
			# 用一点余量把它吸开，避免镜头贴地时"无限往下压"。
			continue
		# 命中的**长轴投影长度**才是臂长的上限：斜着打到墙不等于臂能伸那么长。
		var along: float = origin.distance_to(hit["position"]) * d.dot(axis)
		best = minf(best, along)

	var blocked := want
	if best < INF:
		# 扣掉探测球半径和贴墙余量；走廊再窄也不低于 zoom_min —— 不让镜头穿进角色脑袋。
		blocked = maxf(best - cam_probe_radius - cam_wall_margin, zoom_min)

	# 目标：墙允许的更短就听墙的，否则就是想要的长度。
	var target := minf(want, blocked)
	var now := spring.spring_length

	# ── 死区：目标几乎没变就不动 ──
	# 墙的边缘在射线命中临界点上时，`blocked` 会每帧微微翻动；不加死区的话
	# 镜头会跟着抖。2 cm 远小于肉眼可分辨的推拉，但足以吃掉这种抖动。
	if absf(target - now) < CAM_DEAD_ZONE:
		return now

	# ── 阻尼 + 限速，一律针对**最终的 spring_length** ──
	# ⚠️ 踩过的坑（探针 ④ 实测 9.00 → 2.06 单帧跳 1.49 m）：
	#    之前是 `lerpf(want, blocked, k)` —— 这一支的**起点是 want**，
	#    哪怕限了步长，`want` 本身每帧也在大幅变化（滚轮/平滑），
	#    结果最终 spring_length 仍然一帧跨一大段。
	#    现在改成「从当前实际长度出发，朝 target 走一步」，再对这一步限速。
	#    拉近 / 拉远用不同的时间常数，但都从 `now` 出发。
	var tau := CAM_IN_TAU if target < now else CAM_OUT_TAU
	var k := 1.0 - exp(-delta / tau)
	return _clamp_step(now, lerpf(now, target, k), delta)


## 沿弹簧臂长轴 `axis`、按当前 FOV 展开近平面四角，返回探测方向列表。
##
## 中心轴也留一条（近平面中心的投影是"沿轴直走"，比四角更直观）。
## 四角取在**近平面**上（距支点 `at` 米处），这样探测方向和实际画幅边缘一致。
## FOV 越大、宽高比越宽，四角张得越开 —— 正是"视野拉大后画面边缘先穿墙"的情形。
func _camera_probe_dirs(axis: Vector3, at: float) -> Array[Vector3]:
	var out: Array[Vector3] = [axis]
	var cam_basis := spring.global_transform.basis
	# 近平面在 `at` 处的半宽 / 半高（Godot 的 Camera3D 是竖直 FOV）。
	var d := maxf(at, 0.2)
	var half_h := d * tan(deg_to_rad(maxf(cam.fov, 1.0)) * 0.5)
	var half_w := half_h * cam.get_viewport().get_visible_rect().size.aspect()
	# 用弹簧臂的**局部** right / up 铺开四角（不受 yaw 影响）。
	var right := cam_basis.x.normalized()
	var up := cam_basis.y.normalized()
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var corner := (axis * d + right * (half_w * sx) + up * (half_h * sy)).normalized()
			out.append(corner)
	return out


## 每帧绝对位移上限：防止阻尼太快、低帧时一帧跨过一堵墙。
func _clamp_step(from: float, to: float, delta: float) -> float:
	var step := to - from
	var cap := maxf(CAM_MAX_STEP_SPEED * delta, 0.02)
	if absf(step) > cap:
		return from + signf(step) * cap
	return to


## 滚轮能拉到多近，还能看见**全身**。
##
## 判据不是「脚在支点下方多远」这一条了（那是老的、按真人身高写的算法）：
## 支点近景会降到 `zoom_look_height`（她的身体中心），所以**上下两侧**都要量：
##   上：`body_top - look`（含光环顶）      下：`look - body_bottom`（脚底）
## 谁大按谁算，垂直半视角 θ = fov/2，需要水平距离 `max(上, 下) / tan(θ)`。
##
## 实测（fov 62°、支点 0.52 m）→ 约 1.07 m，再加 `zoom_fit_margin` 就是最近距离；
## 用户把 FOV 调小（视野变窄）时 tan(θ) 变小，这个数会**自动**变大，
## 所以「fov 拉近就看不见爱丽丝全身」那条老毛病不会再回来。
##
## `look` 由调用方传（`_apply_camera()` 用它算出的那一个，保证和实际支点一致）；
## 不传就按当前滚轮距离自己算一遍。
func min_zoom_for_full_body(look := -1.0) -> float:
	if look < 0.0:
		look = _look_height_for(_zoom_distance)
	var half := deg_to_rad(clampf(hip_fov, 20.0, 120.0) * 0.5)
	var up := body_top - look
	var down := look - body_bottom
	return maxf(up, down) / maxf(tan(half), 0.01) + zoom_fit_margin


## 滚轮距离 → 「离得有多近」的 0…1（0 = 最贴近，1 = 已经是原来的平视取景）。
func _zoom_near_k() -> float:
	return _zoom_near_k_at(_zoom_distance)


func _zoom_near_k_at(d: float) -> float:
	var span := maxf(zoom_close_full - zoom_min, 0.01)
	return clampf((d - zoom_min) / span, 0.0, 1.0)


## 某个滚轮距离下的支点高度（米）。近景降下来看她，远景回到平视高度。
func _look_height_for(d: float) -> float:
	return lerpf(zoom_look_height, hip_height, _zoom_near_k_at(d))


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
