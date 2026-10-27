extends SceneTree
## 验：校园泼溅抬到广场层 + 隐形大板能走。
##   _tools/run_shot.sh res://scripts/_probe_campus_walk.gd -- --no-capture

func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(name)
	root.get_texture().get_image().save_png(out)
	print("[截图] %s" % out)


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	for _i in 30:
		await process_frame
	var campus := level.get_node("Campus")
	var t0 := Time.get_ticks_msec()
	while not bool(campus.call("is_ready")) and Time.get_ticks_msec() - t0 < 240000:
		await process_frame
	var box: AABB = campus.call("content_world_aabb")
	print("[campus] 内容盒 pos %s size %s（顶 %.2f，底 %.2f）"
		% [str(box.position.snappedf(0.1)), str(box.size.snappedf(0.1)),
			box.position.y + box.size.y, box.position.y])
	var player := level.get_node("Player") as CharacterBody3D
	# 站上校园地面
	player.global_position = Vector3(0.0, 1.5, -120.0)
	player.velocity = Vector3.ZERO
	for _i in 40:
		await physics_frame
	print("[campus] 玩家站到 (0, 1.5, -120) → %s  on_floor=%s"
		% [str(player.global_position.snappedf(0.01)), str(player.is_on_floor())])
	# 从广场走过去（跨过 z=-60 的接缝）
	player.global_position = Vector3(10.0, 0.2, -50.0)
	for _i in 20:
		await physics_frame
	Input.action_press("move_forward")
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 8000:
		await physics_frame
		if player.global_position.z < -85.0:
			break
	Input.action_release("move_forward")
	print("[campus] 从广场往北走 → %s  on_floor=%s"
		% [str(player.global_position.snappedf(0.1)), str(player.is_on_floor())])

	for c in level.find_children("*", "CanvasLayer", true, false):
		var cl := c as CanvasLayer
		if cl != null:
			cl.visible = false
	var cam := Camera3D.new()
	cam.fov = 72.0
	level.add_child(cam)
	cam.current = true
	# 广场北沿看校园
	cam.global_position = Vector3(10.0, 4.0, -54.0)
	cam.look_at(Vector3(4.0, 3.0, -120.0))
	await _shot("_campus_north_edge.png")
	# 校园里回看大厅
	cam.global_position = Vector3(0.0, 6.0, -130.0)
	cam.look_at(Vector3(8.0, 2.0, -55.0))
	await _shot("_campus_look_back.png")
	quit(0)
