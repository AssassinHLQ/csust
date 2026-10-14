class_name Companion
extends CharacterBody3D
## 同伴 NPC：跟着玩家走位，**不开火**（本阶段是纯观赏，行为以后再加）。
##
## 为什么要单独占一个「朋友层」（collision_layer = 2，见 weapon.gd）：
##   1. **子弹要穿透同伴。** Weapon 的射线用 PhysicsRayQueryParameters3D.create()，
##      默认 collision_mask 是全部层；同伴又跟得近，不屏蔽的话玩家会一直打在
##      自己人背上。weapon.gd 用 `Companion.LAYER` 反选屏蔽（改这里两边一起变）。
##   2. **玩家不该被同伴顶住。** 玩家 collision_mask 是默认的 1，碰不到第 2 层；
##      相机 SpringArm 的 mask 也是 1，所以同伴也不会把镜头顶出去。
##   于是同伴只跟「世界层 1」（地板/墙/护栏/靶子/Boss）碰撞，彼此之间也不挤。
##
## 朝向约定：三只 GLB 的本体都朝 −Z（跟 Arisu 同一套导出），Rig 上补 180° 之后
## 「节点 +Z = 脸朝的方向」，于是 rotation.y = atan2(dir.x, dir.z) 就是脸朝 dir。
## 依据不是眼睛看出来的，是 Toe−Foot 骨向量实测（见 _probe_companion.gd）：
##   Mika/Yuuka/Noa 的 (Toe − Foot) 全在 −Z 半轴；而飞猪优香那个 FBX 是 +Z。

## 朋友层的位掩码值。weapon.gd 拿它做射线反选屏蔽。
const LAYER := 2
## 与 player.gd 的 GRAVITY 保持一致，免得同伴的下落手感跟主角不一样
const GRAVITY := 22.0
const ACCEL := 14.0
const FRICTION := 20.0
## 转身平滑
const TURN_SMOOTH := 9.0

@export_file("*.glb") var model_path := ""
@export var display_name := "同伴"
## 站位，玩家局部坐标：+X 右，**+Z 是玩家背后（也就是镜头那一侧）**。
##
## ⚠️ 站位有一条硬约束：**别落在「相机 ↔ 玩家」之间**。
##    相机在玩家背后 3.4~4.2 m、FOV 62°（垂直）→ 水平半视角约 47°。
##    实测：站位若放在正后方 2.4 m，同伴距相机只剩 1.8 m，
##    一块 1.6 m 高的人形在画面里能占掉近一半高度，整个视野被自己人挡死。
##    所以三名同伴都在**侧后方**：横向 2.0~3.0 m、纵向 −0.9~+0.9 m。
##    自检里有一条「同伴不能出现在画面中心区域」就是守这条约束的。
@export var slot := Vector3(-2.0, 0.0, 0.9)
@export var player_path := NodePath("../Player")
## 走过去的速度。**刻意压在 2.4 以下**：AnimDriver 在 2.4 m/s 才切到 Move_Ing，
## 高于这个值的话，站位差 1 m 的微调也会播「跑步」，看起来像在打滑。
@export var walk_speed := 2.2
## 差得远时改用这个速度追（超过 2.4 → 播 Move_Ing，速度感才对）
@export var run_speed := 6.4
## 离站位近于这个距离就停下（免得在目标点上来回抖）
@export var stop_distance := 0.45
## 差得比这个远就改跑
@export var run_distance := 1.6
## 差得比这个远（或者掉出平台）就直接拉回玩家身边
@export var teleport_distance := 26.0
## 掉到这个高度以下就拉回（跟 game.gd 的 FALL_LIMIT 同源）
@export var fall_limit := -60.0
## GLB 原点比脚底高一点点，与 player.tscn 里 Arisu 的 −0.035 一致
@export var model_y_offset := -0.035

var rig: Node3D
var model: Node3D
var anim: Node

var _player: Player
var _speed := 0.0
var _rescues := 0


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = 1
	_player = get_node_or_null(player_path) as Player
	if _player == null:
		push_warning("[Companion %s] 找不到玩家节点：%s" % [display_name, player_path])
	rig = get_node_or_null("Rig") as Node3D
	_build_model()


func _build_model() -> void:
	if model_path.is_empty() or not ResourceLoader.exists(model_path):
		push_error("[Companion %s] 找不到模型：%s" % [display_name, model_path])
		return
	if rig == null:
		push_error("[Companion %s] 场景里没有 Rig 节点" % display_name)
		return
	model = (load(model_path) as PackedScene).instantiate() as Node3D
	model.position.y = model_y_offset
	rig.add_child(model)
	# GLB 本体朝 −Z → 补 180°，让「节点 +Z」成为脸朝的方向
	rig.rotation.y = PI

	# 动画驱动：两个 NodePath 故意留空，让它自己在**模型子树**里找
	# AnimationPlayer / Skeleton3D（三只 GLB 的内部节点名各不相同，写死会互相冲突）
	anim = AnimDriver.new()
	anim.name = "AnimDriver"
	model.add_child(anim)
	print("[Companion %s] 模型就位：%s" % [display_name, model_path.get_file()])


func _physics_process(delta: float) -> void:
	if _player == null:
		return

	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	var want := slot_position()
	var flat := Vector3(want.x - global_position.x, 0.0, want.z - global_position.z)
	var dist := flat.length()

	# 保险：掉出平台或者被甩太远，直接拉回玩家身边
	if dist > teleport_distance or global_position.y < fall_limit:
		_rescues += 1
		global_position = want + Vector3.UP * 0.2
		velocity = Vector3.ZERO
		flat = Vector3.ZERO
		dist = 0.0
		print("[Companion %s] 第 %d 次被拉回玩家身边（距离 %.1f m）" % [
			display_name, _rescues, dist])

	var target_speed := 0.0
	if dist > stop_distance:
		target_speed = walk_speed if dist < run_distance else run_speed
	var dir := flat.normalized() if dist > 0.001 else Vector3.ZERO

	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if target_speed > 0.0:
		horiz = horiz.move_toward(dir * target_speed, ACCEL * delta)
	else:
		horiz = horiz.move_toward(Vector3.ZERO, FRICTION * delta)
	velocity.x = horiz.x
	velocity.z = horiz.z
	move_and_slide()
	_speed = Vector2(velocity.x, velocity.z).length()

	# 朝向：走着朝走的方向；站住时跟玩家看同一个方向（像一队人）
	var face := rotation.y
	if _speed > 0.25:
		face = atan2(velocity.x, velocity.z)
	elif _player:
		face = _player.model_root.rotation.y
	rotation.y = lerp_angle(rotation.y, face, clampf(TURN_SMOOTH * delta, 0.0, 1.0))

	if anim and anim.has_method("set_locomotion"):
		anim.set_locomotion(_speed, is_on_floor(), velocity.y)


## 站位世界坐标：把 slot 按玩家的**相机绕角**转一下。
## 用相机绕角而不是角色朝向，是为了让「左右两侧」永远跟着镜头 ——
## 玩家甩视角时同伴绕到新的侧后方，而不是绕进画面正中央。
func slot_position() -> Vector3:
	var base := _player.global_position
	var yaw := _player.rig.rotation.y
	var c := cos(yaw)
	var s := sin(yaw)
	# 绕 Y 转 yaw：局部 (x, 0, z) → 世界 (x·cos + z·sin, 0, −x·sin + z·cos)
	return base + Vector3(slot.x * c + slot.z * s, 0.0, -slot.x * s + slot.z * c)


## 当前速度（水平，米/秒）—— 自检用
func speed() -> float:
	return _speed


## 与站位的距离 —— 自检用
func slot_distance() -> float:
	return global_position.distance_to(slot_position())
