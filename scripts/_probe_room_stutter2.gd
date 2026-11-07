extends SceneTree
## WS 角（部室东侧靠窗那一角）顿卡定位：逐朝向报 p99 / max，
## 再分三轮（全开 / 关电竞房 / 关太阳阴影）看谁触发。
##   _tools/run_shot.sh res://scripts/_probe_room_stutter2.gd -- --splat=off --story=off


const ROOM := "GameDevRoom"
const DIRS := 12
const WARM := 8
const SAMPLE := 18


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var hit := _find_mesh(c)
		if hit != null:
			return hit
	return null


func _sweep(tag: String, cam: Camera3D, eye: Vector3, centre: Vector3) -> void:
	var worst_p99 := 0.0
	var worst_dir := -1
	var spikes := 0
	for k in DIRS:
		cam.global_position = eye
		cam.look_at(centre, Vector3.UP)
		cam.rotate_object_local(Vector3.UP, TAU * float(k) / float(DIRS))
		await _wait(WARM)
		var frames: Array = []
		var prev := Time.get_ticks_usec()
		for _i in SAMPLE:
			await process_frame
			var now := Time.get_ticks_usec()
			frames.append(float(now - prev) / 1000.0)
			prev = now
		frames.sort()
		var n := frames.size()
		var p99 := float(frames[int(n * 0.99)])
		var mx := float(frames[n - 1])
		for f in frames:
			if float(f) > 30.0:
				spikes += 1
		if p99 > worst_p99:
			worst_p99 = p99
			worst_dir = k
		print("[dir] %-10s k=%2d p99=%6.1fms max=%6.1fms" % [tag, k, p99, mx])
	print("[dir] %-10s 最差朝向 k=%d p99=%.1fms  >30ms 共 %d 帧" % [tag, worst_dir, worst_p99, spikes])


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(150)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var player := game.get_node_or_null("Player") as Node3D
	var room := game.get_node_or_null(ROOM) as Node3D
	var mi := _find_mesh(room) if room != null else null
	if player == null or mi == null:
		print("[dir] 缺 Player 或部室网格")
		quit(1)
		return
	var a := mi.get_aabb()
	var xf := mi.global_transform
	var centre := xf * Vector3(a.get_center().x, 1.2, a.get_center().z)

	const INSET := 0.9
	var local := Vector3(a.end.x - INSET, 0.1, a.end.z - INSET)
	player.global_position = xf * local
	player.set("velocity", Vector3.ZERO)
	await _wait(120)

	var eye := xf * Vector3(local.x, 1.6, local.z)
	var cam := Camera3D.new()
	cam.far = 400.0
	cam.near = 0.05
	cam.fov = 70.0
	root.add_child(cam)
	cam.current = true

	await _sweep("all_on", cam, eye, centre)

	var esports := game.get_node_or_null("EsportsRoom") as Node3D
	if esports != null:
		esports.visible = false
		await _sweep("esports_off", cam, eye, centre)
		esports.visible = true

	var sun := game.get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.shadow_enabled = false
		await _sweep("sun_off", cam, eye, centre)
		sun.shadow_enabled = true
	quit(0)