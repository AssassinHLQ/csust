extends SceneTree
## 不碰窗口尺寸，量分块加载稳定后的显存（排除「两种视口尺寸各建一套 state」的假象）。
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	for _i in 30:
		await process_frame
	var chunks := level.get_node("CampusChunks")
	var t0 := Time.get_ticks_msec()
	while true:
		var done := 0
		for c in chunks.get_children():
			if bool(c.call("is_ready")):
				done += 1
		if done == chunks.get_child_count() or Time.get_ticks_msec() - t0 > 300000:
			break
		await process_frame
	await create_timer(5.0, true).timeout
	print("[vram] 窗口 %s，块 %d，加载 %.1f s，显存 %.1f MiB（纹理 %.1f / 缓冲 %.1f）" % [
		str(root.size), chunks.get_child_count(),
		float(Time.get_ticks_msec() - t0) / 1000.0,
		float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0,
		float(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)) / 1048576.0,
		float(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)) / 1048576.0])
	quit(0)
