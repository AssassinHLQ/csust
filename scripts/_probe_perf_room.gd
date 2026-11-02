extends SceneTree
## 粗测：部室开着 / 隐藏时，同一机位的 FPS 与 draw call 差多少。
##   _tools/run_shot.sh res://scripts/_probe_perf_room.gd -- --splat=off --story=off

func _wait(n: int) -> void:
	for _i in n:
		await process_frame

func _measure(tag: String) -> void:
	await _wait(90)
	var fps := Engine.get_frames_per_second()
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var objs := int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var prims := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var phys := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	print("[perf] %-14s fps=%5.1f draws=%4d objs=%4d prims=%7d physics=%.2fms focus=%s" % [
		tag, fps, draws, objs, prims, phys, str(DisplayServer.window_is_focused())])


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(150)
	var cam := Camera3D.new()
	cam.far = 400.0
	cam.near = 0.05
	root.add_child(cam)
	cam.current = true

	var room := game.get_node_or_null("GameDevRoom") as Node3D

	# 机位 1：小屋门口（看不到部室）
	cam.global_position = Vector3(2.0, 2.2, -12.0)
	cam.look_at(Vector3(20.0, 2.5, -14.0), Vector3.UP)
	await _measure("hut_view")

	# 机位 2：正对部室
	cam.global_position = Vector3(42.0, 2.6, -6.0)
	cam.look_at(Vector3(54.0, 2.6, 0.0), Vector3.UP)
	await _measure("room_on")

	# 机位 3：同一位置，隐藏部室
	if room != null:
		room.visible = false
	await _measure("room_off")
	if room != null:
		room.visible = true

	# 机位 4：再开一次（材质/着色器已经编译过）
	await _measure("room_on_again")
	await _measure("room_on_again2")

	quit(0)


func _initialize() -> void:
	_run.call_deferred()
