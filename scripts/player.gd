class_name Player
extends CharacterBody3D
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

# --- 移动手感（米 / 秒）---
const SPEED_WALK := 2.0
const SPEED_RUN := 5.2
const SPEED_CROUCH := 1.1
const SPEED_AIM := 1.6
const ACCEL_GROUND := 12.0
const ACCEL_AIR := 3.0
const FRICTION := 20.0
const GRAVITY := 22.0
const JUMP_VELOCITY := 6.2
const TURN_SMOOTH := 14.0
## 开火/开镜时的转身速度（比平时快，否则「点了没反应」的迟滞感明显）
const TURN_SMOOTH_FIRE := 26.0

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
@export var cam_lerp := 12.0

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

@onready var rig: Node3D = $CameraRig
@onready var spring: SpringArm3D = $CameraRig/SpringArm3D
@onready var cam: Camera3D = $CameraRig/SpringArm3D/Camera3D
@onready var model_root: Node3D = $Arisu
@onready var anim: Node = $Arisu/Model/AnimDriver
@onready var weapon: Node = $Weapon


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# 出生朝向：相机绕角 0 → 相机在角色背后（+Z 侧）往场地深处（-Z）看，
	# 靶区（z = -3 … -16）正好在画面正前方，角色背对镜头面朝靶区。
	# 这就是「一进场就能看见靶子」的初始视角。
	_yaw = 0.0
	_facing_yaw = _yaw + CAMERA_FORWARD_OFFSET
	model_root.rotation.y = _facing_yaw
	rig.rotation.y = _yaw
	_zoom_distance = hip_distance
	_apply_camera(1.0)


func _input(event: InputEvent) -> void:
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
		if key == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE \
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
			return
		if key == KEY_R and weapon:
			weapon.try_reload()
			return

	# --- 鼠标按键：只处理「按下」这一沿，松开用 poll ---
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_RIGHT:
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


func _physics_process(delta: float) -> void:
	_poll_mouse_buttons()
	# 鼠标被释放（按了 Esc）时，右键按住也要能开镜
	if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and _aim_held and not aiming:
		_set_aiming(true)

	# --- 重力与跳跃 ---
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = JUMP_VELOCITY

	# --- 期望移动方向（相对相机）---
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (rig.global_basis.x * input.x + rig.global_basis.z * input.y)
	dir.y = 0.0
	if dir.length_squared() > 1.0:
		dir = dir.normalized()

	crouching = Input.is_action_pressed("crouch")
	sprinting = Input.is_action_pressed("sprint") and not aiming and not crouching \
		and input.y < 0.1 and dir.length_squared() > 0.01

	var target_speed := SPEED_WALK
	if crouching:
		target_speed = SPEED_CROUCH
	elif aiming:
		target_speed = SPEED_AIM
	elif sprinting:
		target_speed = SPEED_RUN

	# --- 水平加速 / 摩擦 ---
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	var accel := ACCEL_GROUND if is_on_floor() else ACCEL_AIR
	if dir.length_squared() > 0.01:
		horiz = horiz.move_toward(dir * target_speed, accel * delta)
	else:
		horiz = horiz.move_toward(Vector3.ZERO, FRICTION * delta)

	velocity.x = horiz.x
	velocity.z = horiz.z
	move_and_slide()

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
	var want_face_aim := aiming or _fire_held
	if want_face_aim:
		_facing_yaw = _yaw + CAMERA_FORWARD_OFFSET
	elif horiz.length_squared() > 0.25:
		_facing_yaw = atan2(horiz.x, horiz.z)

	# 开火转身要快一点，不然「点了没反应」的感觉很明显
	var turn_speed := TURN_SMOOTH_FIRE if want_face_aim else TURN_SMOOTH
	model_root.rotation.y = _lerp_angle_smooth(model_root.rotation.y, _facing_yaw, turn_speed, delta)
	rig.rotation.y = _yaw

	_apply_camera(delta)

	if anim and anim.has_method("set_locomotion"):
		anim.set_locomotion(Vector2(horiz.x, horiz.z).length(), is_on_floor(), velocity.y)


## 相机平滑：开镜时拉近、抬高、右肩偏移、缩 FOV
func _apply_camera(delta: float) -> void:
	var t := clampf(cam_lerp * delta, 0.0, 1.0)
	spring.spring_length = lerpf(spring.spring_length, aim_distance if aiming else _zoom_distance, t)
	spring.position.x = lerpf(spring.position.x, -(aim_shoulder if aiming else hip_shoulder), t)
	rig.position.y = lerpf(rig.position.y, aim_height if aiming else hip_height, t)
	cam.fov = lerpf(cam.fov, aim_fov if aiming else hip_fov, t)

	_recoil_pitch = lerpf(_recoil_pitch, 0.0, clampf(9.0 * delta, 0.0, 1.0))
	_recoil_yaw = lerpf(_recoil_yaw, 0.0, clampf(9.0 * delta, 0.0, 1.0))

	spring.rotation.x = _pitch + _recoil_pitch
	spring.rotation.y = _recoil_yaw
	rig.rotation.y = _yaw


func add_recoil(pitch: float, yaw: float) -> void:
	_recoil_pitch += pitch
	_recoil_yaw += yaw


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
