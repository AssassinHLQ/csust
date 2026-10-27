extends SceneTree
## 量：构成主义关卡里校园泼溅的「可见性闸门」到底省了多少。
##   _tools/run_shot.sh res://scripts/_probe_level_perf.gd -- --no-capture

func _initialize() -> void:
	_run.call_deferred()


func _measure(tag: String, seconds := 2.0) -> float:
	await process_frame
	var frames := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(seconds * 1000.0):
		await process_frame
		frames += 1
	var fps := float(frames) / (float(Time.get_ticks_msec() - t0) / 1000.0)
	print("[perf] %-30s %.1f fps" % [tag, fps])
	return fps


func _run() -> void:
	root.size = Vector2i(1600, 900)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	for _i in 30:
		await process_frame
	var campus := level.get_node("Campus")
	var t0 := Time.get_ticks_msec()
	while not bool(campus.call("is_ready")) and Time.get_ticks_msec() - t0 < 240000:
		await process_frame
	var node := campus.get("splat_node") as Node3D
	var player := level.get_node("Player") as CharacterBody3D

	player.global_position = Vector3(0.0, 0.2, 6.8)   # 大厅里
	for _i in 30:
		await physics_frame
	print("[perf] 大厅里：校园节点 visible=%s" % str(node.visible))
	await _measure("大厅里（闸门应隐藏校园）")

	player.global_position = Vector3(10.0, 0.2, -58.0)  # 广场北沿朝校园
	player.set("_yaw", 0.0)
	for _i in 30:
		await physics_frame
	print("[perf] 广场边朝北：校园节点 visible=%s" % str(node.visible))
	await _measure("广场边朝校园（显示）")

	player.set("_yaw", PI)   # 原地转身背对校园
	for _i in 30:
		await physics_frame
	print("[perf] 广场边背对：校园节点 visible=%s" % str(node.visible))
	await _measure("广场边背对校园（隐藏）")
	print("[perf] draw calls=%d  图元=%d"
		% [int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))])
	quit(0)
