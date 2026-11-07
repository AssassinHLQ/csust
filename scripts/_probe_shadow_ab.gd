extends SceneTree
## 部室那一角的阴影开销：同一次运行里交替跑 4 个变体，抵消后台漂移。
##   _tools/run_shot.sh res://scripts/_probe_shadow_ab.gd -- --splat=off --story=off
##
##   A 现状（级联 60 m）
##   B 级联收到 30 m
##   C 远景道具不投影（cast_shadow 关掉）
##   D 太阳阴影全关（上界参考）


const ROOM := "GameDevRoom"
const OUTDOOR := ["Parkour", "LotEast", "MondrianHouse", "Shop", "RoomProxy", "MeshHut", "Room609Cpus"]
const WARM := 20
const SAMPLE := 35
const ROUNDS := 3


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _measure(tag: String) -> float:
	await _wait(WARM)
	var t0 := Time.get_ticks_usec()
	for _i in SAMPLE:
		await process_frame
	var fps := float(SAMPLE) / maxf(float(Time.get_ticks_usec() - t0) / 1000000.0, 0.0001)
	print("[shadow] %-6s fps=%6.1f draws=%4d prims=%7d" % [tag, fps,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))])
	return fps


func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var hit := _find_mesh(c)
		if hit != null:
			return hit
	return null


func _shadow_off(n: Node, state: Array) -> void:
	for mi in n.find_children("*", "GeometryInstance3D", true, false):
		var g := mi as GeometryInstance3D
		state.append([g, g.cast_shadow])
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(150)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var room := game.get_node_or_null(ROOM) as Node3D
	var mi := _find_mesh(room) if room != null else null
	var sun := game.get_node_or_null("Sun") as DirectionalLight3D
	if mi == null or sun == null:
		print("[shadow] 缺部室网格或太阳")
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

	var saved: Array = []
	for n in OUTDOOR:
		var node := game.get_node_or_null(n)
		if node != null:
			_shadow_off(node, saved)
	var umbral := saved.size()

	var sum := {"A": 0.0, "B": 0.0, "C": 0.0, "D": 0.0}
	for r in ROUNDS:
		# A：现状
		for s in saved:
			(s[0] as GeometryInstance3D).cast_shadow = s[1]
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 60.0
		sum["A"] += await _measure("A r%d" % r)

		# B：级联 30 m
		sun.directional_shadow_max_distance = 30.0
		sum["B"] += await _measure("B r%d" % r)

		# C：级联 60 m，但远景道具不投影
		sun.directional_shadow_max_distance = 60.0
		for s in saved:
			(s[0] as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sum["C"] += await _measure("C r%d" % r)

		# D：阴影全关
		for s in saved:
			(s[0] as GeometryInstance3D).cast_shadow = s[1]
		sun.shadow_enabled = false
		sum["D"] += await _measure("D r%d" % r)
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 60.0

	print("[shadow] 平均：A 现状=%.1f  B 级联30m=%.1f  C 远景不投影=%.1f  D 全关=%.1f（远景 %d 个 Geometry）" % [
		float(sum["A"]) / ROUNDS, float(sum["B"]) / ROUNDS,
		float(sum["C"]) / ROUNDS, float(sum["D"]) / ROUNDS, umbral])
	quit(0)