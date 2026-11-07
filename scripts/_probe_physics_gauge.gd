extends SceneTree
## 判定 `TIME_PHYSICS_PROCESS` 的口径：改物理步频，看读数涨不涨。
##   _tools/run_shot.sh res://scripts/_probe_physics_gauge.gd -- --splat=off --story=off
##
## 若读数随步数同比放大 → 它是「每帧合计」；若基本不动 → 它是「每步」。
## 这决定了用户现场 65~82 ms 到底意味着什么。


const SPOT := Vector3(54.87, 0.6, 3.38)
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
	var phys := 0.0
	var f0 := Engine.get_physics_frames()
	var t0 := Time.get_ticks_usec()
	for _i in SAMPLE:
		await process_frame
		phys += float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
	var dt := float(Time.get_ticks_usec() - t0) / 1000000.0
	var steps := float(Engine.get_physics_frames() - f0) / float(SAMPLE)
	print("[gauge] %-18s fps=%6.1f 帧=%6.2fms 物理读数=%6.2fms 步/帧=%.2f 每步≈%.2fms" % [
		tag, float(SAMPLE) / maxf(dt, 0.0001), dt / float(SAMPLE) * 1000.0,
		phys / float(SAMPLE), steps,
		(phys / float(SAMPLE)) / maxf(steps, 0.001)])


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(180)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var player := game.get_node_or_null("Player") as Node3D
	if player == null:
		print("[gauge] 缺 Player")
		quit(1)
		return
	player.global_position = SPOT
	player.set("velocity", Vector3.ZERO)

	var hz0 := Engine.physics_ticks_per_second
	for hz in [60, 120, 240]:
		Engine.physics_ticks_per_second = hz
		await _measure("步频=%d" % hz)
	Engine.physics_ticks_per_second = hz0
	quit(0)