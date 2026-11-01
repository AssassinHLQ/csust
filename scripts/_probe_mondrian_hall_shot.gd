extends SceneTree
## 验图 + 验数：第二关（蒙德里安建筑）。
##   _tools/run_shot.sh res://scripts/_probe_mondrian_hall_shot.gd
## 输出：_arisu_captures/_mondrian_hall/*.png
##
## 除了出图，还驱真玩家爬两段斜坡、站上终点台，打印 y 证明坡道真能走。

func _initialize() -> void:
	_run.call_deferred()


func _shoot(cam: Camera3D, out: String, nm: String) -> void:
	cam.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, nm])


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(level)
	for _i in 120:
		await process_frame
	paused = false
	for _f in 20:
		await process_frame

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_mondrian_hall")
	DirAccess.make_dir_recursive_absolute(out)
	for c in level.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false

	var hall := level.get_node_or_null("Hall") as Node3D
	if hall == null:
		print("[错误] 关卡里没有 Hall")
		quit(1)
		return
	var bb := AABB()
	var first := true
	var n_mesh := 0
	for mi in hall.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var a: AABB = m.global_transform * m.mesh.get_aabb()
		bb = a if first else bb.merge(a)
		first = false
		n_mesh += 1
	print("Hall 网格 %d 个，世界包围盒 x %.2f~%.2f  y %.2f~%.2f  z %.2f~%.2f"
		% [n_mesh, bb.position.x, bb.end.x, bb.position.y, bb.end.y,
			bb.position.z, bb.end.z])

	var cam := Camera3D.new()
	cam.near = 0.05
	cam.far = 600.0
	root.add_child(cam)

	# ① 正立面（南面，正门那侧）
	cam.fov = 46.0
	cam.global_position = Vector3(-1.0, 9.0, 42.0)
	cam.look_at(Vector3(-1.0, 7.0, 2.0), Vector3.UP)
	await _shoot(cam, out, "01_ext_front")

	# ② 三分之四鸟瞰
	cam.fov = 50.0
	cam.global_position = Vector3(34.0, 22.0, 38.0)
	cam.look_at(Vector3(-1.0, 6.0, 2.0), Vector3.UP)
	await _shoot(cam, out, "02_ext_hero")

	# ③ 一层：站在门口往里
	cam.fov = 70.0
	cam.global_position = Vector3(-2.0, 2.0, 7.2)
	cam.look_at(Vector3(-3.0, 2.4, -6.0), Vector3.UP)
	await _shoot(cam, out, "03_l1_inside")

	# ④ 一层看斜坡井
	cam.fov = 70.0
	cam.global_position = Vector3(-2.5, 2.0, 3.0)
	cam.look_at(Vector3(-6.25, 3.0, -1.5), Vector3.UP)
	await _shoot(cam, out, "04_l1_ramp")

	# ⑤ 二层
	cam.fov = 70.0
	cam.global_position = Vector3(-6.5, 6.4, -2.0)
	cam.look_at(Vector3(3.0, 6.8, -6.0), Vector3.UP)
	await _shoot(cam, out, "05_l2")

	# ⑥ 三层 + 终点台
	cam.fov = 70.0
	cam.global_position = Vector3(-2.0, 11.0, 3.6)
	cam.look_at(Vector3(2.6, 11.4, -4.9), Vector3.UP)
	await _shoot(cam, out, "06_l3_goal")

	# ⑦ 终点台近景
	cam.fov = 65.0
	cam.global_position = Vector3(2.6, 12.4, -0.5)
	cam.look_at(Vector3(2.6, 11.5, -4.9), Vector3.UP)
	await _shoot(cam, out, "07_goal_close")

	# ── 驱真玩家 ──
	var player := level.get("_player") as CharacterBody3D
	if player == null:
		print("[错误] 拿不到玩家")
		quit(1)
		return

	print("\n—— 斜坡 1：一层 z=4.6 → 二层 ——")
	player.global_position = Vector3(-6.25, 0.70, 4.6)
	player.velocity = Vector3.ZERO
	for _f in 30:
		await process_frame
	print("起点 y=%.3f z=%.2f" % [player.global_position.y, player.global_position.z])
	Input.action_press("move_forward")
	var best := 0.0
	for _f in 360:
		await process_frame
		best = maxf(best, player.global_position.y)
	Input.action_release("move_forward")
	for _f in 20:
		await process_frame
	print("结束 y=%.3f z=%.2f（最高 %.3f）" % [player.global_position.y,
		player.global_position.z, best])

	print("\n—— 斜坡 2：二层 z=-3.6 → 三层 ——")
	player.global_position = Vector3(4.25, 4.95, -3.6)
	player.velocity = Vector3.ZERO
	for _f in 30:
		await process_frame
	print("起点 y=%.3f z=%.2f" % [player.global_position.y, player.global_position.z])
	Input.action_press("move_back")
	best = 0.0
	for _f in 360:
		await process_frame
		best = maxf(best, player.global_position.y)
	Input.action_release("move_back")
	for _f in 20:
		await process_frame
	print("结束 y=%.3f z=%.2f（最高 %.3f）" % [player.global_position.y,
		player.global_position.z, best])

	print("\n—— 站上终点台 ——")
	player.global_position = Vector3(2.6, 11.6, -4.9)
	player.velocity = Vector3.ZERO
	for _f in 30:
		await process_frame
	print("终点台 y=%.3f（期望 11.30）" % player.global_position.y)

	# ── 打通全流程：击破 3 个机关 → 终点解锁 + 北门下沉 → 踩终点 ──
	print("\n—— 关卡流程 ——")
	var n := 0
	for c in level.get_children():
		if c is Target:
			(c as Target).died.emit(100.0)
			n += 1
	for _f in 10:
		await process_frame
	var goal := level.get_node("Goal") as Area3D
	var door := level.get_node("ExitDoor") as Node3D
	print("触发机关 %d 个；终点 monitoring=%s；北门 y=%.2f"
		% [n, str(goal.monitoring), door.position.y])
	for _f in 140:
		await process_frame
	print("1.8 s 后北门 y=%.2f（下沉动画）" % door.position.y)
	player.global_position = Vector3(2.6, 11.6, -4.9)
	player.velocity = Vector3.ZERO
	for _f in 60:
		await process_frame
	print("踩终点完成 = %s" % str(level.get("_complete")))

	quit(0)
