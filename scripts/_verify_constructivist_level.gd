extends SceneTree
## 验构成主义关卡（scenes/next_level.tscn）：
##   1. 平台/坡道碰撞顶面高度
##   2. 3 个靶子 → 击破 → 终点解锁
##   3. 踩上终点圆盘 → 「关卡完成」
##   4. 红楔坡道能走上去
## 顺带出三张图。
##   _tools/run_shot.sh res://scripts/_verify_constructivist_level.gd -- --no-capture

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
	print("  [%s] %s" % ["PASS" if ok else "FAIL", what])


func _ground_y(space: PhysicsDirectSpaceState3D, x: float, z: float, top := 9.5) -> float:
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(x, top, z), Vector3(x, -2.0, z))
	var hit := space.intersect_ray(q)
	return float(hit.position.y) if not hit.is_empty() else -999.0


func _shot(file_name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(file_name)
	root.get_texture().get_image().save_png(out)
	print("[截图] %s" % out)


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	for _i in 60:
		await process_frame

	var player := level.get_node_or_null("Player") as Node3D
	var space := player.get_world_3d().direct_space_state
	var goal := level.get_node_or_null("Goal") as Area3D
	var score := level.get_node_or_null("Scoreboard") as Label3D
	var msg := level.get_node_or_null("LevelUI/Message") as Label

	print("=== 1. 平台/坡道碰撞 ===")
	for spec in [["平台A", -10.5, -5.3, 3.2], ["平台B", -5.8, -7.0, 4.2],
			["终点台", 1.0, -8.2, 5.2]]:
		var y := _ground_y(space, float(spec[1]), float(spec[2]))
		print("  %s 顶面 y=%.2f（应 %.1f）" % [spec[0], y, float(spec[3])])
		_check(absf(y - float(spec[3])) < 0.05, "%s 碰撞顶面正确" % spec[0])
	# 坡道：低端 0、中段 ~1.6、高端 ~3.2
	for spec in [[0.9, 0.95], [-0.4, 1.6], [-3.2, 3.0]]:
		var y := _ground_y(space, -10.5, float(spec[0]))
		print("  坡道 z=%.1f 表面 y=%.2f（约 %.1f）" % [spec[0], y, float(spec[1])])
		_check(absf(y - float(spec[1])) < 0.25, "坡道 z=%.1f 高度近似正确" % spec[0])

	print("\n=== 2. 靶子与终点锁 ===")
	var targets: Array = []
	for c in level.get_children():
		if c is Target:
			targets.append(c)
	_check(targets.size() == 3, "场上 3 个靶子（实际 %d）" % targets.size())
	_check(not goal.monitoring, "终点初始锁定（monitoring = false）")
	print("  计分牌：%s" % score.text)
	_check(score.text == "机关 3 / 3", "计分牌初始 3/3")
	# 机关没破之前东门挡着拱门
	var q0 := PhysicsRayQueryParameters3D.create(Vector3(10, 0.3, 3), Vector3(70, 0.3, 3))
	q0.collide_with_areas = false
	var h0 := space.intersect_ray(q0)
	var door_x := float(h0.position.x) if not h0.is_empty() else 999.0
	print("  机关未破时往东打射线 → x=%.1f（应被东门挡在 ~14）" % door_x)
	_check(door_x < 15.0, "机关未破时东门锁着")

	# 先踩一次：锁着的时候不该完成
	player.global_position = Vector3(1.0, 5.3, -8.2)
	for _i in 12:
		await physics_frame
	await process_frame
	_check(not msg.text.begins_with("关卡完成"), "靶子没清空前踩终点不算完成（提示：%s）" % msg.text)
	# 从终点台下来，免得解锁那一刻人正好站在圆盘上
	player.global_position = Vector3(0.0, 0.1, 4.0)
	for _i in 10:
		await physics_frame

	print("\n=== 3. 击破全部靶子 ===")
	for t in targets:
		t.take_damage(10000.0)
	for _i in 10:
		await process_frame
	print("  计分牌：%s  终点 monitoring=%s" % [score.text, str(goal.monitoring)])
	_check(score.text == "机关 0 / 3", "计分牌归零")
	_check(goal.monitoring, "靶子清空后终点解锁")
	_check(msg.text.begins_with("机关全部击破"), "提示切换到「东门开启」")

	print("\n=== 4. 踩终点 ===")
	player.global_position = Vector3(1.0, 5.3, -8.2)
	for _i in 20:
		await physics_frame
	await process_frame
	print("  提示：%s" % msg.text)
	_check(msg.text.begins_with("关卡完成"), "踩上圆盘 → 关卡完成")

	print("\n=== 5. 红楔坡道实走 ===")
	player.global_position = Vector3(-10.5, 0.10, 3.6)
	player.set("velocity", Vector3.ZERO)
	for _i in 20:
		await physics_frame
	Input.action_press("move_forward")
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 8000:
		await physics_frame
		if player.global_position.y >= 3.1:
			break
	Input.action_release("move_forward")
	print("  终点 y=%.2f（%.1f s）"
		% [player.global_position.y, float(Time.get_ticks_msec() - t0) / 1000.0])
	_check(player.global_position.y >= 3.1, "能沿红楔坡道走上平台 A")

	print("
=== 6. 广场 / 东拱门 / 坠落保护 / 校园泼溅 ===")
	await create_timer(2.0, true).timeout
	var door := level.get_node_or_null("ExitDoor") as Node3D
	print("  东门 y=%.2f（下沉 1.8 s 后应 < −3）" % (door.position.y if door else 999.0))
	_check(door != null and door.position.y < -3.0, "三个机关破完，东门下沉")

	var y_plaza := _ground_y(space, 30.0, 30.0, 6.0)
	print("  广场地面 y=%.2f（应 −0.02）" % y_plaza)
	_check(absf(y_plaza + 0.02) < 0.05, "广场地面高度正确")
	var q := PhysicsRayQueryParameters3D.create(Vector3(10, 0.3, 3), Vector3(70, 0.3, 3))
	q.collide_with_areas = false
	var h := space.intersect_ray(q)
	var hit_x := float(h.position.x) if not h.is_empty() else 999.0
	print("  大厅内往 +X 打射线 → 命中 x=%.1f（拱门开着应打到广场护栏 ~60）" % hit_x)
	_check(hit_x > 50.0, "东墙拱门通向外广场")
	# 广场→校园的桥、以及校园的隐形地面板
	var y_bridge := _ground_y(space, 10.0, -67.0, 5.0)
	print("  桥面 y=%.2f（应 −0.02）" % y_bridge)
	_check(absf(y_bridge + 0.02) < 0.05, "广场到校园的桥面高度正确")
	var y_campus := _ground_y(space, 0.0, -120.0, 5.0)
	print("  校园地面板 y=%.2f（应 −0.02）" % y_campus)
	_check(absf(y_campus + 0.02) < 0.05, "校园隐形地面板高度正确（可走）")
	var campus := level.get_node_or_null("Campus")
	_check(campus != null, "场景里有校园泼溅节点")
	if campus != null:
		print("  校园：start_delay=%.1f  preload_on_gate=%s"
			% [float(campus.get("start_delay")), str(campus.get("preload_on_gate"))])
		_check(float(campus.get("start_delay")) > 0.0, "校园泼溅延后加载")
		_check(not bool(campus.get("preload_on_gate")), "校园泼溅不在门切换的黑屏里预载")
		_check(is_equal_approx(float(campus.get("world_scale")), 75.0),
			"校园放大 3 倍（world_scale=75，实测 %.1f）" % float(campus.get("world_scale")))
	var col := level.get_node_or_null("CampusCollisionMesh")
	if col == null:
		col = level.get_node_or_null("CampusCollision")
	_check(col != null, "场景里有校园碰撞体")
	if col != null:
		var shapes := 0
		var tris := 0
		for c in col.find_children("*", "CollisionShape3D", true, false):
			var cs := c as CollisionShape3D
			shapes += 1
			if cs.shape is ConcavePolygonShape3D:
				tris += (cs.shape as ConcavePolygonShape3D).get_faces().size() / 3
			elif cs.shape is BoxShape3D:
				tris += 12
		print("  校园碰撞：%d 个形状，约 %d 个三角面" % [shapes, tris])
		_check(shapes >= 1 and tris > 100, "校园碰撞体有实际几何（%d 形状 / %d 面）" % [shapes, tris])
	var preview := level.get_node_or_null("Campus/CampusPreview")
	_check(preview != null, "有编辑器用的校园点云预览")
	if preview != null:
		_check(not (preview as Node3D).visible, "点云预览在运行时自动隐藏")
	player.global_position = Vector3(0.0, -59.0, 0.0)
	for _i in 30:
		await physics_frame
	print("  坠落测试后落点 %s" % str(player.global_position.snappedf(0.1)))
	_check(player.global_position.z > 5.0 and player.global_position.y < 1.5,
		"掉出广场会被送回大厅")

	# ══ 出图 ══
	for c in level.find_children("*", "CanvasLayer", true, false):
		var cl := c as CanvasLayer
		if cl != null:
			cl.visible = false
	var cam := Camera3D.new()
	cam.fov = 68.0
	level.add_child(cam)
	cam.current = true
	cam.global_position = Vector3(0.0, 2.3, 8.0)
	cam.look_at(Vector3(0.0, 4.6, -6.0))
	await _shot("_constructivist_entry.png")

	cam.global_position = Vector3(7.5, 7.0, 6.5)
	cam.look_at(Vector3(-7.0, 3.0, -6.0))
	cam.fov = 74.0
	await _shot("_constructivist_hall.png")

	cam.global_position = Vector3(3.5, 7.2, 2.5)
	cam.look_at(Vector3(0.5, 5.0, -8.4))
	await _shot("_constructivist_goal.png")

	# 广场上回看大厅东立面（拱门 + 红门套）
	cam.global_position = Vector3(34.0, 3.4, 16.0)
	cam.look_at(Vector3(14.0, 5.0, 3.0))
	cam.fov = 70.0
	await _shot("_constructivist_exterior.png")

	print("\n=== 结果：%d 项失败 ===" % _fails)
	quit(0 if _fails == 0 else 1)