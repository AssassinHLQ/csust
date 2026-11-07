extends SceneTree
## 定位部室（GameDevRoom）里「站到某个角落就掉帧」。
##   _tools/run_shot.sh res://scripts/_probe_gamedev_corner.gd -- --splat=off --story=off
##
## v2：关掉 vsync，用真实帧间隔算 FPS（v1 被 60 Hz 钳死看不出差别）。
## 只挪自由相机、不动玩家：先分离「视角相关的渲染/剔除开销」。
## 每个点空转 30 帧再量 45 帧，报 平均 FPS / 平均 process / 峰值 draw call。


const ROOM := "GameDevRoom"
const OUTDOOR := ["Parkour", "LotEast", "MondrianHouse", "Shop", "RoomProxy", "MeshHut"]
const EYE := 1.6
const WARM := 30
const SAMPLE := 45


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _measure(tag: String, cam: Camera3D) -> float:
	await _wait(WARM)
	var proc := 0.0
	var draws := 0
	var prims := 0
	var t0 := Time.get_ticks_usec()
	for _i in SAMPLE:
		await process_frame
		proc += float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
		draws = maxi(draws, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		prims = maxi(prims, int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	var dt := float(Time.get_ticks_usec() - t0) / 1000000.0
	var fps := float(SAMPLE) / maxf(dt, 0.0001)
	print("[corner] %-16s fps=%5.1f process=%5.2fms draws=%4d prims=%7d pos=%s" % [
		tag, fps, proc / float(SAMPLE), draws, prims, str(cam.global_position.snappedf(0.1))])
	return fps


func _find_mesh(n: Node) -> MeshInstance3D:
	if n == null:
		return null
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
	var mi := _find_mesh(room)
	if mi == null:
		print("[corner] 找不到部室网格")
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

	cam.global_position = Vector3(52.0, 3.0, 40.0)
	cam.look_at(Vector3(52.0, 3.0, 60.0), Vector3.UP)
	await _measure("baseline", cam)

	const INSET := 0.8
	var xs := [a.position.x + INSET, a.get_center().x, a.end.x - INSET]
	var zs := [a.position.z + INSET, a.get_center().z, a.end.z - INSET]
	var tagx := ["W", "M", "E"]
	var tagz := ["N", "M", "S"]
	var worst := {"fps": 1e9, "pos": Vector3.ZERO, "tag": ""}
	for i in 3:
		for j in 3:
			cam.global_position = xf * Vector3(xs[i], EYE, zs[j])
			cam.look_at(centre, Vector3.UP)
			var fps := await _measure("room_%s%s" % [tagx[i], tagz[j]], cam)
			if fps < float(worst["fps"]):
				worst = {"fps": fps, "pos": cam.global_position, "tag": "room_%s%s" % [tagx[i], tagz[j]]}

	print("[corner] 最差格 %s fps=%.1f pos=%s" % [
		worst["tag"], float(worst["fps"]), str((worst["pos"] as Vector3).snappedf(0.1))])
	cam.global_position = worst["pos"]
	cam.look_at(centre, Vector3.UP)
	await _measure("worst:base", cam)

	var we := game.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var sun := game.get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.shadow_enabled = false
		await _measure("worst:sun_off", cam)
		sun.shadow_enabled = true

	var hidden: Array[Node] = []
	for n in OUTDOOR:
		var node := game.get_node_or_null(n)
		if node != null and (node as Node3D).visible:
			(node as Node3D).visible = false
			hidden.append(node)
	await _measure("worst:outdoor_off", cam)
	for node in hidden:
		(node as Node3D).visible = true
	await _measure("worst:restored", cam)
	quit(0)