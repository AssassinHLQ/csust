extends SceneTree
## 验：电竞房、5 屏（4 主力 + 凯伊）、8 卡 9995WX 开放架、门与碰撞。
##   _tools/run_shot.sh res://scripts/_verify_esports_room.gd -- --splat=off --story=off

func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(cam: Camera3D, p: Vector3, t: Vector3, nm: String) -> void:
	cam.global_position = p
	cam.look_at(t, Vector3.UP)
	await _wait(8)
	await RenderingServer.frame_post_draw
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_esports")
	DirAccess.make_dir_recursive_absolute(out)
	root.get_texture().get_image().save_png(out.path_join(nm + ".png"))
	print("[esports] shot ", nm)


func _run() -> void:
	ShopClerk._bought = true
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(90)
	for c in game.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false
	var room := game.get_node_or_null("EsportsRoom") as Node3D
	if room == null:
		print("[esports] 没找到 EsportsRoom")
		quit(1)
		return
	var mons := 0
	for i in 5:
		if room.get_node_or_null("Monitor%d" % i) is Node3D:
			mons += 1
	var chairs := room.find_children("*Chair*", "Node3D", false, false).size()
	var cards := room.find_children("GPU*", "Node3D", false, false).size()
	var body := room.get_node("RoomBody") as StaticBody3D
	var shapes := 0
	for c in body.get_children():
		if c is CollisionShape3D:
			shapes += 1
	print("[esports] pos=", room.global_position.snappedf(0.01),
		" 显示器=", mons, " 椅子=", chairs, " 显卡=", cards, " 碰撞=", shapes)
	var box := AABB()
	var first := true
	for mi in room.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var b: AABB = m.global_transform * m.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	print("[esports] AABB pos=", box.position.snappedf(0.01),
		" size=", box.size.snappedf(0.01))
	for i in 5:
		var mon := room.get_node_or_null("Monitor%d" % i) as Node3D
		if mon != null:
			print("  Monitor", i, " pos=", mon.global_position.snappedf(0.01))

	var cam := Camera3D.new()
	cam.near = 0.05
	root.add_child(cam)
	cam.current = true
	cam.fov = 58.0
	await _shot(cam, Vector3(40.5, 2.0, 12.2), Vector3(44.2, 2.0, 13.0), "50_esports_exterior")
	cam.fov = 62.0
	await _shot(cam, Vector3(44.8, 1.75, 13.0), Vector3(58.5, 1.2, 13.0), "51_esports_inside")
	cam.fov = 55.0
	await _shot(cam, Vector3(54.2, 1.55, 13.0), Vector3(59.4, 1.1, 13.0), "52_esports_main")
	cam.fov = 50.0
	await _shot(cam, Vector3(51.4, 1.6, 12.6), Vector3(51.0, 1.15, 8.65), "53_esports_kei")
	cam.fov = 52.0
	await _shot(cam, Vector3(51.2, 1.7, 13.0), Vector3(48.4, 1.15, 17.4), "54_esports_frame")
	cam.fov = 70.0
	await _shot(cam, Vector3(44.3, 1.8, 13.0), Vector3(52.0, 1.2, 13.0), "55_esports_wide")

	var player := game.get_node("Player") as CharacterBody3D
	player.global_position = Vector3(43.2, 0.8, 13.0)
	player.velocity = Vector3.ZERO
	player.set("_yaw", -PI * 0.5)
	player.set("_pitch", 0.0)
	await _wait(20)
	Input.action_press("move_forward")
	for _f in 140:
		await process_frame
	Input.action_release("move_forward")
	await _wait(8)
	print("[esports] 进门后 x=", player.global_position.x)

	player.global_position = Vector3(57.2, 0.8, 13.0)
	player.velocity = Vector3.ZERO
	await _wait(20)
	Input.action_press("move_forward")
	for _f in 140:
		await process_frame
	Input.action_release("move_forward")
	await _wait(8)
	print("[esports] 撞桌后 x=", player.global_position.x)
	quit(0)
