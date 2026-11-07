extends SceneTree
## 部室「站角落」顿卡复现：把玩家真的传到四个角，等同伴跟过来，
## 再用自由相机在每个角扫 8 个朝向，逐帧记真实帧间隔，报 p50/p95/p99/最大值。
##   _tools/run_shot.sh res://scripts/_probe_room_stutter.gd -- --splat=off --story=off
##
## 平均 FPS 看不出顿卡；这里看的是「最慢的那几帧」。


const ROOM := "GameDevRoom"
const WARM := 20
const SAMPLE := 15
const SETTLE := 90


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
		print("[stutter] 缺 Player 或部室网格")
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

	const INSET := 0.9
	var corners := [
		["WN", Vector3(a.position.x + INSET, 0.1, a.position.z + INSET)],
		["EN", Vector3(a.end.x - INSET, 0.1, a.position.z + INSET)],
		["WS", Vector3(a.position.x + INSET, 0.1, a.end.z - INSET)],
		["ES", Vector3(a.end.x - INSET, 0.1, a.end.z - INSET)],
	]
	for c in corners:
		var tag := String(c[0])
		var pos := (xf * (c[1] as Vector3)) as Vector3
		player.global_position = pos
		player.set("velocity", Vector3.ZERO)
		await _wait(SETTLE)
		var eye := (xf * Vector3((c[1] as Vector3).x, 1.6, (c[1] as Vector3).z)) as Vector3
		var frames: Array = []
		for k in 8:
			cam.global_position = eye
			cam.look_at(centre, Vector3.UP)
			cam.rotate_object_local(Vector3.UP, TAU * float(k) / 8.0)
			await _wait(WARM)
			var prev := Time.get_ticks_usec()
			for _i in SAMPLE:
				await process_frame
				var now := Time.get_ticks_usec()
				frames.append(float(now - prev) / 1000.0)
				prev = now
		frames.sort()
		var n := frames.size()
		var over := 0
		for f in frames:
			if float(f) > 25.0:
				over += 1
		print("[stutter] %s frames=%d p50=%5.1fms p95=%5.1fms p99=%5.1fms max=%5.1fms >25ms=%d" % [
			tag, n, float(frames[n / 2]), float(frames[int(n * 0.95)]),
			float(frames[int(n * 0.99)]), float(frames[n - 1]), over])
	quit(0)