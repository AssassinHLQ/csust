extends SceneTree
## 物理耗时定位：部室 / 609 屋顶两处，逐项关掉嫌疑对象，看物理时间掉多少。
##   _tools/run_shot.sh res://scripts/_probe_physics_cost.gd -- --splat=off --story=off
##
## 用户现场读数：p50 132 ms、物理 65~82 ms。133 ms ≈ 8 个物理步（Godot 每帧上限 8）。
## 所以先量「每帧物理时间」，再 A/B 关掉 同伴 / 149 颗 CPU。


const SPOT_ROOM := Vector3(54.87, 0.6, 3.38)
const SPOT_ROOF := Vector3(0.0, 6.6, 0.0)
const WARM := 90
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
	var phys_sum := 0.0
	var t0 := Time.get_ticks_usec()
	for _i in SAMPLE:
		await process_frame
		phys_sum += float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
	var fps := float(SAMPLE) / maxf(float(Time.get_ticks_usec() - t0) / 1000000.0, 0.0001)
	print("[phys] %-22s fps=%6.1f  物理均值=%6.2f ms  物体=%5d  碰撞对=%5d" % [
		tag, fps, phys_sum / float(SAMPLE),
		int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
		int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS))])


func _companions(game: Node) -> Array:
	var out: Array = []
	for c in game.get_children():
		if c is CharacterBody3D and String(c.name).begins_with("Companion"):
			out.append(c)
	return out


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(180)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var player := game.get_node_or_null("Player") as Node3D
	if player == null:
		print("[phys] 缺 Player")
		quit(1)
		return
	var comps := _companions(game)
	var cpus: Array[Node] = get_nodes_in_group("ryzen9950x3d")
	print("[phys] 同伴 %d 个，9950X3D %d 颗，物理步上限=%d，步频=%d" % [
		comps.size(), cpus.size(),
		int(ProjectSettings.get_setting("physics/common/max_physics_steps_per_frame", 8)),
		int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60))])

	for spot in [["部室", SPOT_ROOM], ["609屋顶", SPOT_ROOF]]:
		var tag := String(spot[0])
		player.global_position = spot[1]
		player.set("velocity", Vector3.ZERO)
		await _measure("%s 基线" % tag)

		for c in comps:
			(c as Node).set_physics_process(false)
		await _measure("%s 关同伴" % tag)
		for c in comps:
			(c as Node).set_physics_process(true)

		for c in cpus:
			(c as Node).set_physics_process(false)
		await _measure("%s 关149颗CPU" % tag)

		for c in comps:
			(c as Node).set_physics_process(false)
		await _measure("%s 两者都关" % tag)
		for c in comps:
			(c as Node).set_physics_process(true)
		for c in cpus:
			(c as Node).set_physics_process(true)
	quit(0)