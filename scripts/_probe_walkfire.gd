extends SceneTree
## 探针（要真渲染）：「走打」到底播了什么 —— 走（不按 Shift）+ 开火，侧视连拍。
##
## 背景：2026-10-18 用户报「跑打修好了，但是走打又出问题了」。
## 跑打改成整身动作 `RunFire_Ing` 之后，`request_fire()` 只按
## `_speed > IDLE_SPEED` 就整身切过去，**走（2.4 m/s）和蹲行也走了这条路** ——
## 而那条动作的腿是跑步的（标称 5.2 m/s），倍速压到 0.46 之后就是
## 「用跑步的前倾姿势慢慢挪」。这个探针把三档速度各拍一遍并打出实际 clip：
##
##   站（0）  → 应该是叠加层 `Normal_Attack_Ing`（站桩）
##   走（2.4）→ 修好后应该是 `Cafe_Walk` + 叠加层；修之前是整身 `RunFire_Ing`
##   跑（6.8）→ 整身 `RunFire_Ing`
##
## 用法（别加 --headless）：
##   godot --path <工程> --script res://scripts/_probe_walkfire.gd -- --splat=off
## 输出：`_arisu_captures/_walkfire/`

const OUT_DIR := "_arisu_captures/_walkfire"
const SIZE := Vector2i(640, 720)

var _sk: Skeleton3D
var _ap: AnimationPlayer
var _cam: Camera3D
var _height := 0.56


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = SIZE
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out)

	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(40)
	var p := game.get_node_or_null("Player") as Player
	if p == null or p.anim == null:
		print("[wf] !! 没有 Player/AnimDriver")
		quit(1)
		return
	p.set_physics_process(false)
	var anim := p.anim as AnimDriver
	_sk = anim.skeleton
	_ap = anim.player
	print("[wf] has_runfire=%s extra_clip=%s" % [anim.has_runfire(), anim.extra_clip])

	_cam = Camera3D.new()
	_cam.name = "ProbeCam"
	_cam.fov = 40.0
	root.add_child(_cam)
	await _frame_camera(p)

	# ① 站着开火（对照）
	await _shoot(out.path_join("stand_0.png"), anim, 0.0, false, true, "站着开火")
	# ② 走着开火
	await _shoot(out.path_join("walk_0.png"), anim, 2.4, false, true, "走着开火")
	# ③ 跑着开火
	await _shoot(out.path_join("run_0.png"), anim, 6.8, false, true, "跑着开火")
	print("[wf] 输出目录 %s" % out)
	quit(0)


## 用「速度 → set_locomotion」这一条**真接口**驱动，不走 physics
func _shoot(file: String, anim: AnimDriver, speed: float, _jump: bool,
		fire: bool, tag: String) -> void:
	anim.reset_state()
	_ap.speed_scale = 1.0
	for _i in 20:
		anim.set_locomotion(speed, true, 0.0)
		await process_frame
	var before := _ap.current_animation
	if fire:
		anim.request_fire()
		for _i in 8:
			anim.set_locomotion(speed, true, 0.0)
			await process_frame
	var trunk := _trunk()
	print("[wf] %-6s 速度 %.1f  →  基础层 %-12s 叠加层 %-18s 状态 %-10s trunk %.3f"
		% [tag, speed, _ap.current_animation,
		"无" if anim.upper_clip() == "" else anim.upper_clip(),
		anim.current_state_name(), trunk])
	print("[wf]        开火前基础层 %s，speed_scale %.2f" % [before, _ap.speed_scale])
	await _frame_camera(anim.skeleton.get_parent_node_3d() as Node3D, true)
	for _i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(file)


func _trunk() -> float:
	var pelvis := _bone_world("Bip001 Pelvis")
	var head := _bone_world("Bip001 Head")
	return Vector3.UP.dot((head - pelvis).normalized())


func _frame_camera(node: Node3D, keep := false) -> void:
	var head := _bone_world("Bip001 Head")
	var feet := (_bone_world("Bip001 L Foot") + _bone_world("Bip001 R Foot")) * 0.5
	if not keep:
		_height = maxf(head.y - feet.y, 0.5)
	var center: Vector3 = (head + feet) * 0.5
	var dist := _height * 2.7
	_cam.global_position = center + Vector3(dist, _height * 0.45, 0.0)
	_cam.look_at(center + Vector3(0.0, _height * 0.1, 0.0), Vector3.UP)
	_cam.make_current()


func _bone_world(bone: String) -> Vector3:
	var i := _sk.find_bone(bone)
	if i < 0:
		return Vector3.INF
	return _sk.global_transform * _sk.get_bone_global_pose(i).origin


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
