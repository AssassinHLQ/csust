extends SceneTree
## 按用户真实配置复测：开泼溅（不传 --splat=off）、1600×900。
##   _tools/run_shot.sh res://scripts/_probe_room_faithful.gd -- --story=off
##
## 目的：确认「站窗+储物柜那一角持续低帧」在真实配置下能不能复现。
## 注意：泼溅加载要十几秒，变量用法在 SPLAT 开关上。


const ROOM := "GameDevRoom"
const WARM := 30
const SAMPLE := 45


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _measure(tag: String, size: Vector2i = Vector2i.ZERO) -> void:
	if size != Vector2i.ZERO:
		await _resize(size)
	await _wait(WARM)
	var t0 := Time.get_ticks_usec()
	for _i in SAMPLE:
		await process_frame
	var fps := float(SAMPLE) / maxf(float(Time.get_ticks_usec() - t0) / 1000000.0, 0.0001)
	print("[faithful] %-12s %s fps=%6.1f draws=%4d prims=%7d vram=%6.0fMiB" % [
		tag, str(root.size), fps,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0])


func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var hit := _find_mesh(c)
		if hit != null:
			return hit
	return null


func _resize(size: Vector2i) -> void:
	root.size = size
	await process_frame
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(240)
	await _resize(Vector2i(1600, 900))

	var room := game.get_node_or_null(ROOM) as Node3D
	var mi := _find_mesh(room) if room != null else null
	if mi == null:
		print("[faithful] 缺部室网格")
		quit(1)
		return
	var a := mi.get_aabb()
	var xf := mi.global_transform
	var centre := xf * Vector3(a.get_center().x, 1.2, a.get_center().z)

	var cam := Camera3D.new()
	cam.far = 400.0
	cam.near = 0.05
	cam.fov = 70.0
	root.add_child(cam)
	cam.current = true

	cam.global_position = xf * Vector3(a.end.x - 0.9, 1.6, a.end.z - 0.9)
	cam.look_at(centre, Vector3.UP)
	await _measure("corner_1600")

	cam.global_position = xf * Vector3(a.position.x + 0.9, 1.6, a.position.z + 0.9)
	cam.look_at(centre, Vector3.UP)
	await _measure("corner_far")

	cam.global_position = Vector3(52.0, 3.0, 40.0)
	cam.look_at(Vector3(52.0, 3.0, 60.0), Vector3.UP)
	await _measure("outside")

	cam.global_position = xf * Vector3(a.end.x - 0.9, 1.6, a.end.z - 0.9)
	cam.look_at(centre, Vector3.UP)
	await _measure("corner_720", Vector2i(1280, 720))
	quit(0)