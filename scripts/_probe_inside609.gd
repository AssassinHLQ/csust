extends SceneTree
## 在 609 室内（泼溅可见）量帧率 —— 用户日志里「开场 10.3 s / 34 帧」= 3.3 fps 就是在这里。
##   _tools/run_shot.sh res://scripts/_probe_inside609.gd -- --story=off
##
## 三处对比：609 室内（泼溅可见）/ 609 室内但强藏泼溅 / 部室（泼溅被藏）。


const SPOT_609 := Vector3(0.0, 0.6, 6.0)
const SPOT_ROOM := Vector3(54.87, 0.6, 3.38)
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
	var f0 := Engine.get_physics_frames()
	var t0 := Time.get_ticks_usec()
	for _i in SAMPLE:
		await process_frame
	var dt := float(Time.get_ticks_usec() - t0) / 1000000.0
	print("[in609] %-24s fps=%6.1f 帧=%7.2fms 步/帧=%4.2f draws=%4d prims=%8d" % [
		tag, float(SAMPLE) / maxf(dt, 0.0001), dt / float(SAMPLE) * 1000.0,
		float(Engine.get_physics_frames() - f0) / float(SAMPLE),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))])


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(200)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var player := game.get_node_or_null("Player") as Node3D
	if player == null:
		print("[in609] 缺 Player")
		quit(1)
		return

	# 等泼溅就绪（start_delay 10 s / 距离 22 m，玩家在出生点就够近）
	for _i in 40:
		var rs = game.get("_room_scene")
		if rs != null and bool(rs.call("is_ready")):
			break
		await _wait(30)
	var rs = game.get("_room_scene")
	if rs == null:
		print("[in609] 泼溅始终没加载")
		quit(1)
		return
	var splat := rs.get("splat_node") as Node3D

	player.global_position = SPOT_609
	player.set("velocity", Vector3.ZERO)
	await _wait(60)
	print("[in609] 609 室内：泼溅节点 visible=%s vram=%.0f MiB" % [
		str(splat.visible), float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0])
	await _measure("609 室内 泼溅可见")

	splat.visible = false
	await _measure("609 室内 强藏泼溅")
	splat.visible = true
	await _measure("609 室内 再开泼溅")

	player.global_position = SPOT_ROOM
	player.set("velocity", Vector3.ZERO)
	await _wait(90)
	await _measure("部室 泼溅被游戏藏")
	quit(0)