extends SceneTree
## 探针（要真渲染）：**用玩家自己的相机**，拍「开火一次 → 再走路」到底长什么样。
##
## 本轮目标（用户原话）：「现在只要修这个了，先开火一次，在走路就变成这样子
## 右侧身子螃蟹平移」，并附了一张玩家视角的截图。
##
## 前面的探针都在**模型空间**里量（肩线、脚横纵比），但用户看的是**画面**。
## 这个探针只干一件事：把玩家自己的相机画面按时间拍下来 + 同时打三个读数：
##   · 髋骨偏航：骨盆的「左右轴」相对角色朝向轴转了多少度
##     （人朝前走、骨盆却拧着 ⇒ 腿会横着迈 = 螃蟹）
##   · 头相对骨盆侧偏（整条脊柱歪多少）
##   · 脚的横/纵位移比（Σ|lateral| / Σ|forward|，螃蟹 → 1）
##
## 用法（要真渲染）：
##   godot --path <工程> --script res://scripts/_probe_after_fire_view.gd -- --splat=off
## 输出：`_arisu_captures/_afterfire/`

const OUT_DIR := "_arisu_captures/_afterfire"
const SPOT := Vector3(-14.0, 0.1, -12.0)
const SIZE := Vector2i(1000, 700)

var _p: Player
var _anim: AnimDriver
var _wpn: Weapon
var _sk: Skeleton3D
var _out := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = SIZE
	_out = ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(_out)

	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 30:
		await process_frame
	paused = false
	_p = game.get_node_or_null("Player") as Player
	_anim = _p.anim as AnimDriver
	_sk = _anim.skeleton
	_wpn = game.get_node_or_null("Player/Weapon") as Weapon
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for n in game.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	# ⚠️ **不能**关 `_physics_process`：玩家的移动/朝向/`_fire_held` 全在里面，
	#    关掉之后按 W 也不动（第一版就栽在这，量出来速度 0.00）。
	_p.global_position = SPOT
	# 让相机弹簧自己收拢到角色背后
	for _i in 90:
		_p.global_position = Vector3(SPOT.x, _p.global_position.y, SPOT.z)
		await process_frame

	# ① 只走
	_drive_walk()
	for _i in 60:
		await process_frame
	await _row("1_walk")
	await _shot("1_walk.png")
	await _fixed_shots("1_walk")

	# ② 站着点一下火，然后立刻走路（用户的原话顺序）
	_anim.reset_state()
	_p.velocity = Vector3.ZERO
	for _i in 30:
		await process_frame
	_wpn.trigger_down()
	for _i in 6:
		await process_frame
	_wpn.trigger_up()
	_drive_walk()
	for _i in 20:
		await process_frame
	await _row("2_walk_after_fire")
	await _shot("2_walk_after_fire.png")
	await _fixed_shots("2_walk_after_fire")
	# ③ 再走 60 帧（攻击应该已经演完）
	for _i in 60:
		await process_frame
	await _row("3_walk_settled")
	await _shot("3_walk_settled.png")
	await _fixed_shots("3_walk_settled")

	# ④ 按住左键走路（走打开火）
	_wpn.trigger_down()
	for _i in 40:
		await process_frame
		_pin()
	await _row("4_walk_fire_held")
	await _fixed_shots("4_walk_fire_held")
	_wpn.trigger_up()
	for _i in 20:
		await process_frame
	await _row("5_released")

	print("[afterfire] 输出 %s" % _out)
	quit(0)


## 固定机位：角色背后上方俯视（≈用户截图的角度）
func _fixed_shots(tag: String) -> void:
	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.far = 200.0
	root.add_child(cam)
	cam.make_current()
	var fwd: Vector3 = _p.model_root.global_transform.basis.z.normalized()
	var right: Vector3 = _p.model_root.global_transform.basis.x.normalized()
	var chest: Vector3 = _p.global_position + Vector3.UP * 1.0
	for sh in [
		["topback", chest - fwd * 1.9 + Vector3.UP * 1.5],
		["left", chest - right * 2.0 + Vector3.UP * 0.6],
	]:
		cam.global_position = sh[1]
		cam.look_at(chest, Vector3.UP)
		await _shot("%s_%s.png" % [tag, String(sh[0])])
	cam.queue_free()


func _pin() -> void:
	if _p.global_position.y < SPOT.y:
		_p.global_position = SPOT
	else:
		_p.global_position = Vector3(SPOT.x, _p.global_position.y, SPOT.z)


func _drive_walk() -> void:
	Input.action_press("move_forward")


func _row(tag: String) -> void:
	var lat := 0.0
	var fwd := 0.0
	var prev := _model_pos("Bip001 L Toe0")
	var hip_yaw := 0.0
	var head_lat := 0.0
	for _i in 30:
		await process_frame
		_p.global_position = SPOT if _p.global_position.y < SPOT.y \
			else Vector3(SPOT.x, _p.global_position.y, SPOT.z)
		var cur := _model_pos("Bip001 L Toe0")
		var d := cur - prev
		lat += absf(d.x)
		fwd += absf(d.z)
		prev = cur
		hip_yaw += _hip_yaw()
		head_lat += _head_lateral()
	print("  [%s] clip=%-13s state=%-10s 髋偏航 %+6.1f°  头侧偏 %+6.1f°  脚横/纵 %.2f  "
		% [tag, _anim.current_clip(), _anim.current_state_name(), hip_yaw / 30.0,
		head_lat / 30.0, lat / maxf(fwd, 0.0001)] +
		"速度 %.2f  枪骨缩 %.2f" % [_speed(), _weapon_scale()])


## 骨盆的「左右轴」相对角色朝向轴拧了多少度（正 = 骨盆朝右拧）
func _hip_yaw() -> float:
	var i := _sk.find_bone("Bip001 L Thigh")
	var j := _sk.find_bone("Bip001 R Thigh")
	if i < 0 or j < 0:
		return 0.0
	var a := _model_pos("Bip001 L Thigh")
	var b := _model_pos("Bip001 R Thigh")
	var axis := (a - b)
	axis.y = 0.0
	if axis.length() < 0.0001:
		return 0.0
	axis = axis.normalized()
	# 正常时「左髋 − 右髋」= 角色的 −X 方向
	return rad_to_deg(atan2(axis.cross(Vector3.LEFT).y, axis.dot(Vector3.LEFT)))


func _head_lateral() -> float:
	var h := _model_pos("Bip001 Head")
	var p := _model_pos("Bip001 Pelvis")
	var v := h - p
	if v.length() < 0.001:
		return 0.0
	return rad_to_deg(asin(clampf(v.x / v.length(), -1.0, 1.0)))


func _model_pos(bone: String) -> Vector3:
	var i := _sk.find_bone(bone)
	if i < 0:
		return Vector3.ZERO
	var w: Vector3 = _sk.global_transform * _sk.get_bone_global_pose(i).origin
	return _p.model_root.global_transform.affine_inverse() * w


func _weapon_scale() -> float:
	var i := _sk.find_bone(AnimDriver.GUN_BONE)
	if i < 0:
		return 0.0
	var b: Basis = (_sk.global_transform * _sk.get_bone_global_pose(i)).basis
	return b.get_scale().length() / sqrt(3.0)


func _speed() -> float:
	return Vector2(_p.velocity.x, _p.velocity.z).length()


func _shot(file: String) -> void:
	for _i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join(file))
	print("  [img] %s" % _out.path_join(file))
