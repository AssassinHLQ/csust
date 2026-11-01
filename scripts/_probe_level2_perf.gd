extends SceneTree
## 量第二关进场开销：实例化耗时、前 15 秒的掉帧尖峰、GGS 就绪时刻、Boss 建模时刻。
##   _tools/run_shot.sh res://scripts/_probe_level2_perf.gd

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var packed := load("res://scenes/next_level.tscn") as PackedScene
	var t_load := Time.get_ticks_msec()
	var level := packed.instantiate() as Node3D
	var t_inst := Time.get_ticks_msec()
	root.add_child(level)
	var t_ready := Time.get_ticks_msec()
	print("[perf] load(packed)=%d ms  instantiate=%d ms  add_child(+_ready)=%d ms"
		% [t_inst - t_load, t_ready - t_inst, t_ready - t_inst])

	var t0 := Time.get_ticks_msec()
	var last := t0
	var spikes: Array = []
	var ggs := level.get_node_or_null("CampusGGS")
	var ggs_at := -1
	var boss_at := {}
	var fps_min := 999.0
	for i in 900:
		await process_frame
		var now := Time.get_ticks_msec()
		var dt := now - last
		last = now
		if dt >= 34:
			spikes.append([i, dt])
		if ggs != null and ggs_at < 0 and bool(ggs.get("_active")):
			ggs_at = now - t0
		for nm in ["TrexBossA", "TrexBossB", "TrexBossC"]:
			if not boss_at.has(nm):
				var b := level.get_node_or_null(nm)
				if b != null and b.get("model") != null:
					boss_at[nm] = now - t0
		if i > 120:
			fps_min = minf(fps_min, 1000.0 / maxf(dt, 1.0))

	spikes.sort_custom(func(a, b): return a[1] > b[1])
	print("[perf] 15 s 内 ≥34 ms 的帧 %d 个，最长的 8 个：" % spikes.size())
	for k in range(mini(8, spikes.size())):
		print("[perf]   帧 #%d  %d ms" % [spikes[k][0], spikes[k][1]])
	print("[perf] GGS 就绪 = %s ms" % ("—" if ggs_at < 0 else str(ggs_at)))
	print("[perf] Boss 建模 = %s" % str(boss_at))
	print("[perf] 稳定后最低帧率 ≈ %.1f fps（跳过前 2 s）" % fps_min)
	print("[perf] 显存 %.0f MB" % (Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0))
	quit(0)
