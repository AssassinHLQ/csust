extends SceneTree
## 现场同配置复现：泼溅真加载、1920×1080、同伴跟到部室里。
##   _tools/run_shot.sh res://scripts/_probe_scene_perf.gd -- --story=off
##
## 除了帧率，还记「每帧跑了几个物理步」——用户现场 p50 133 ms ≈ 8 步 × 1/60 s，
## 如果真是 8 步/帧，就是物理跟不上导致的雪球。
## 然后 A/B：强行藏掉泼溅节点 / 关掉同伴物理 / 步上限降到 2。


const SPOT := Vector3(54.87, 0.6, 3.38)
const WARM := 120
const SAMPLE := 40


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _measure(tag: String) -> void:
	await _wait(WARM)
	var phys := 0.0
	var steps := 0
	var f0 := Engine.get_physics_frames()
	var t0 := Time.get_ticks_usec()
	for _i in SAMPLE:
		await process_frame
		phys += float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
	var dt := float(Time.get_ticks_usec() - t0) / 1000000.0
	steps = Engine.get_physics_frames() - f0
	var fps := float(SAMPLE) / maxf(dt, 0.0001)
	print("[perf] %-22s fps=%6.1f 帧=%6.1fms 物理=%6.2fms 步/帧=%.2f draws=%4d vram=%5.0fMiB" % [
		tag, fps, dt / float(SAMPLE) * 1000.0, phys / float(SAMPLE),
		float(steps) / float(SAMPLE),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0])


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(200)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	# 逼 609 泼溅现在就开始加载（场景里 start_delay = 10 s / start_distance = 22 m）
	var room_splat := game.get_node_or_null("Room609/Splat") as Node3D
	if room_splat == null:
		for c in game.get_children():
			if c.get_class() == "Node3D" and c.find_children("*", "SplatScene", true, false).size() > 0:
				room_splat = c
				break
	print("[perf] 找 609 泼溅节点：%s" % (str(room_splat) if room_splat else "没找到"))

	var player := game.get_node_or_null("Player") as Node3D
	if player == null:
		print("[perf] 缺 Player")
		quit(1)
		return
	player.global_position = SPOT
	player.set("velocity", Vector3.ZERO)
	await _wait(240)
	print("[perf] 泼溅 loaded=%s vram=%.0f MiB" % [
		str(game.get("_room_scene") != null and bool(game.get("_room_scene").call("is_ready"))),
		float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0])

	await _measure("基线")

	var splat_node: Node3D = null
	var rs = game.get("_room_scene")
	if rs != null:
		splat_node = rs.get("splat_node") as Node3D
		if splat_node != null:
			print("[perf] 泼溅节点 visible=%s" % str(splat_node.visible))
			splat_node.visible = false
			await _measure("强藏泼溅节点")
			splat_node.visible = true
	else:
		print("[perf] _room_scene 还是空（没加载完）")

	var comps: Array = []
	for c in game.get_children():
		if c is CharacterBody3D and String(c.name).begins_with("Companion"):
			comps.append(c)
	for c in comps:
		(c as Node).set_physics_process(false)
	await _measure("关同伴物理(%d)" % comps.size())
	for c in comps:
		(c as Node).set_physics_process(true)

	var steps0 := Engine.max_physics_steps_per_frame
	Engine.max_physics_steps_per_frame = 2
	await _measure("步上限=2")
	Engine.max_physics_steps_per_frame = steps0
	quit(0)