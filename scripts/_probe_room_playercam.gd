extends SceneTree
## 用**玩家自己的相机**（SpringArm3D）复现「站角落持续低帧」。
##   _tools/run_shot.sh res://scripts/_probe_room_playercam.gd -- --splat=off --story=off
##
## 检查两件事：① 角落里弹簧臂是不是收缩到贴脸；② 贴脸时角色/透明头发是否吃满屏幕。


const ROOM := "GameDevRoom"
const WARM := 60
const SAMPLE := 45


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


func _measure(tag: String, player: Node3D, cam: Camera3D, spring: SpringArm3D) -> void:
	await _wait(WARM)
	var t0 := Time.get_ticks_usec()
	for _i in SAMPLE:
		await process_frame
	var fps := float(SAMPLE) / maxf(float(Time.get_ticks_usec() - t0) / 1000000.0, 0.0001)
	print("[pcam] %-10s fps=%6.1f draws=%4d prims=%7d proc=%5.1fms phys=%5.1fms arm=%.2f cam=%s d=%.2f" % [
		tag, fps,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0,
		float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0,
		spring.spring_length, str(cam.global_position.snappedf(0.01)),
		cam.global_position.distance_to(player.global_position)])


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(150)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var player := game.get_node_or_null("Player") as Node3D
	var cam := player.get_node_or_null("CameraRig/SpringArm3D/Camera3D") as Camera3D if player != null else null
	var spring := player.get_node_or_null("CameraRig/SpringArm3D") as SpringArm3D if player != null else null
	var room := game.get_node_or_null(ROOM) as Node3D
	var mi := _find_mesh(room) if room != null else null
	if player == null or cam == null or spring == null or mi == null:
		print("[pcam] 缺 Player/Camera/相机臂/部室网格")
		quit(1)
		return
	var a := mi.get_aabb()
	var xf := mi.global_transform

	await _measure("spawn", player, cam, spring)

	const INSET := 0.9
	var spots := [
		["center", Vector3(a.get_center().x, 0.1, a.get_center().z)],
		["WN", Vector3(a.position.x + INSET, 0.1, a.position.z + INSET)],
		["EN", Vector3(a.end.x - INSET, 0.1, a.position.z + INSET)],
		["WS", Vector3(a.position.x + INSET, 0.1, a.end.z - INSET)],
		["ES", Vector3(a.end.x - INSET, 0.1, a.end.z - INSET)],
	]
	for s in spots:
		player.global_position = xf * (s[1] as Vector3)
		player.set("velocity", Vector3.ZERO)
		await _measure(String(s[0]), player, cam, spring)

	# 最挤的那一面：贴着墙站（0.5 m），看弹簧臂贴脸时角色自己吃多少
	player.global_position = xf * Vector3(a.end.x - 0.5, 0.1, a.end.z - 0.5)
	player.set("velocity", Vector3.ZERO)
	await _measure("pressed", player, cam, spring)
	player.visible = false
	await _measure("pressed_noplayer", player, cam, spring)
	player.visible = true
	quit(0)