extends SceneTree
## 窗+储物柜那一角的「持续低帧」拆项：关 SSAO / 藏壁挂机箱 / 藏整个部室 / 换分辨率。
##   _tools/run_shot.sh res://scripts/_probe_room_corner_split.gd -- --splat=off --story=off


const ROOM := "GameDevRoom"
const WARM := 25
const SAMPLE := 45


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _measure(tag: String, res: Vector2i = Vector2i.ZERO) -> void:
	if res != Vector2i.ZERO:
		root.size = res
	await _wait(WARM)
	var t0 := Time.get_ticks_usec()
	for _i in SAMPLE:
		await process_frame
	var fps := float(SAMPLE) / maxf(float(Time.get_ticks_usec() - t0) / 1000000.0, 0.0001)
	print("[split] %-22s %s fps=%6.1f draws=%4d prims=%7d" % [
		tag, str(root.size), fps,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))])


func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var hit := _find_mesh(c)
		if hit != null:
			return hit
	return null


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(150)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var room := game.get_node_or_null(ROOM) as Node3D
	var mi := _find_mesh(room) if room != null else null
	if mi == null:
		print("[split] 缺部室网格")
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

	# 用户说的角：窗 + 储物柜那一侧（局部 z 最大 = 世界 x 最大），靠南端
	const INSET := 0.9
	cam.global_position = xf * Vector3(a.end.x - INSET, 1.6, a.end.z - INSET)
	cam.look_at(centre, Vector3.UP)
	await _measure("corner_base")

	var rig := game.get_node_or_null("GameDevRoom/PC5090Rig") as Node3D
	if rig != null:
		rig.visible = false
		await _measure("corner_no_pcrig")
		rig.visible = true

	var we := game.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		we.environment.ssao_enabled = false
		await _measure("corner_no_ssao")
		we.environment.ssao_enabled = true

	if room != null:
		room.visible = false
		await _measure("corner_no_room")
		room.visible = true

	# 贴到机箱跟前（半米），看近距离是否另有开销
	cam.global_position = xf * Vector3(a.end.x - 0.35, 1.6, a.end.z - 0.35)
	cam.look_at(centre, Vector3.UP)
	await _measure("corner_pressed")

	# 用户真实视口：1600×900
	cam.global_position = xf * Vector3(a.end.x - INSET, 1.6, a.end.z - INSET)
	cam.look_at(centre, Vector3.UP)
	await _measure("corner_base", Vector2i(1600, 900))
	cam.global_position = xf * Vector3(a.get_center().x, 1.6, a.get_center().z)
	cam.look_at(centre, Vector3.UP)
	await _measure("center_1600", Vector2i(1600, 900))
	quit(0)