extends SceneTree
## 验：校园分块（9 块）加载、对齐、逐块剔除的帧率。
##   _tools/run_shot.sh res://scripts/_probe_campus_chunks.gd -- --no-capture
## 首次要解码 9 个 chunk（会写 user://splat_cache），耐心等。

func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(name)
	root.get_texture().get_image().save_png(out)
	print("[截图] %s" % out)


func _measure(tag: String, seconds := 2.0) -> void:
	await process_frame
	var frames := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(seconds * 1000.0):
		await process_frame
		frames += 1
	print("[perf] %-28s %.1f fps"
		% [tag, float(frames) / (float(Time.get_ticks_msec() - t0) / 1000.0)])


func _run() -> void:
	root.size = Vector2i(1600, 900)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	for _i in 30:
		await process_frame
	var chunks := level.get_node("CampusChunks")
	var list: Array[Node] = []
	for c in chunks.get_children():
		list.append(c)
	print("[chunks] %d 块" % list.size())
	var t0 := Time.get_ticks_msec()
	var done := 0
	while done < list.size() and Time.get_ticks_msec() - t0 < 300000:
		await process_frame
		done = 0
		for c in list:
			if bool(c.call("is_ready")):
				done += 1
	print("[chunks] 全部就绪 %d/%d，用时 %.1f s" % [done, list.size(),
		float(Time.get_ticks_msec() - t0) / 1000.0])
	# 对齐：所有块的世界包围盒并集
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for c in list:
		if not bool(c.call("is_ready")):
			continue
		var b: AABB = c.call("content_world_aabb")
		lo = lo.min(b.position)
		hi = hi.max(b.position + b.size)
	print("[chunks] 并集 pos %s size %s（顶 %.2f）" % [
		str(lo.snappedf(0.1)), str((hi - lo).snappedf(0.1)), hi.y])
	await create_timer(6.0, true).timeout
	print("[chunks] 稳定 6 s 后 显存 %.1f MiB（纹理 %.1f / 缓冲 %.1f）" % [
		float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0,
		float(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)) / 1048576.0,
		float(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)) / 1048576.0])

	var player := level.get_node("Player") as CharacterBody3D
	player.global_position = Vector3(10.0, 0.3, -58.0)
	player.set("_yaw", 0.0)
	for _i in 30:
		await physics_frame
	for _i in 10:
		await process_frame
	await _measure("广场边正对校园")
	await _shot("_campus_chunks_edge.png")

	player.global_position = Vector3(0.0, 0.3, 6.8)
	for _i in 30:
		await physics_frame
	for _i in 10:
		await process_frame
	await _measure("大厅里")
	await create_timer(2.0, true).timeout
	print("[chunks] 全隐藏后 显存 %.1f MiB（缓冲 %.1f）" % [
		float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0,
		float(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)) / 1048576.0])
	quit(0)
