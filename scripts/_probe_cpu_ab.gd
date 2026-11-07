extends SceneTree
## 同一机位交替 A/B：149 颗 9950X3D「按 22 m 剔除」vs「不剔除」，抵消机器噪声。
##   _tools/run_shot.sh res://scripts/_probe_cpu_ab.gd -- --splat=off --story=off


const CAM_POS := Vector3(58.0, 1.6, 0.0)
const CAM_LOOK := Vector3(52.0, 1.2, 0.0)
const NEAR_POS := Vector3(2.0, 1.6, 6.0)
const WARM := 25
const SAMPLE := 40


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _measure(tag: String) -> float:
	await _wait(WARM)
	var t0 := Time.get_ticks_usec()
	for _i in SAMPLE:
		await process_frame
	var dt := float(Time.get_ticks_usec() - t0) / 1000000.0
	var fps := float(SAMPLE) / maxf(dt, 0.0001)
	print("[ab] %-18s fps=%6.1f draws=%4d prims=%7d" % [tag, fps,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))])
	return fps


func _set_cull(cpus: Node, on: bool) -> void:
	for n in cpus.find_children("*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).visibility_range_end = 22.0 if on else 0.0


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(150)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var cpus := game.get_node_or_null("Room609Cpus")
	if cpus == null:
		print("[ab] 没有 Room609Cpus")
		quit(1)
		return
	var cam := Camera3D.new()
	cam.far = 400.0
	cam.near = 0.05
	cam.fov = 70.0
	root.add_child(cam)
	cam.current = true

	cam.global_position = CAM_POS
	cam.look_at(CAM_LOOK, Vector3.UP)
	var on_a := 0.0
	var off_a := 0.0
	for r in 2:
		_set_cull(cpus, true)
		on_a += await _measure("round%d cull22m" % r)
		_set_cull(cpus, false)
		off_a += await _measure("round%d no_cull" % r)
	print("[ab] 远处机位：剔除 %.1f fps / 不剔除 %.1f fps" % [on_a * 0.5, off_a * 0.5])

	# 近处确认没被误杀：站到屋顶上（约 5 m）看 CPU
	cam.global_position = NEAR_POS
	cam.look_at(Vector3(0.0, 0.3, 0.0), Vector3.UP)
	_set_cull(cpus, true)
	await _measure("near cull22m")
	_set_cull(cpus, false)
	await _measure("near no_cull")
	quit(0)