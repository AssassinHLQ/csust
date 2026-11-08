extends SceneTree
## 拍：**开局状态**（没成交）下，玩家站在 (49.74, 0, -6.66) 看到什么。
## 对应使用者 2026-11-08 截图：「为什么连地和游戏开发部都没有」。
##
##   & godot --script res://scripts/_probe_opening_view.gd -- --splat=off --story=off

const OUT := "res://_arisu_captures/_opening_view"


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(cam: Camera3D, p: Vector3, t: Vector3, nm: String) -> void:
	cam.global_position = p
	if p.distance_to(t) > 0.01:
		cam.look_at(t, Vector3.UP)
	await _wait(6)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var img: Image = root.get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT, nm])
	print("[open] shot %s" % nm)


func _run() -> void:
	await _wait(3)

	# 不强制成交，保持开局状态
	var game: Node = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	for _i in 60:
		await process_frame

	print("======== 开局东侧状态 ========")
	for nm in ["LotEast", "GameDevRoom", "EsportsRoom", "MondrianHouse", "Floor"]:
		var n := game.get_node_or_null(nm)
		if n == null:
			print("[open] %-16s <不存在>" % nm)
			continue
		var n3 := n as Node3D
		print("[open] %-16s visible=%-5s pos=%s"
			% [nm, str(n3.visible), str(n3.global_position)])

	# 数一下 Floor 里有多少网格、包围盒多大
	var floor_node := game.get_node_or_null("Floor")
	if floor_node != null:
		var cnt := 0
		var box := AABB()
		var first := true
		for m in floor_node.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			if mi.mesh == null:
				continue
			var a: AABB = mi.global_transform * mi.mesh.get_aabb()
			box = a if first else box.merge(a)
			first = false
			cnt += 1
		print("[open] Floor: 网格 %d 个，包围盒 size=%s" % [cnt, str(box.size) if not first else "<空>"])

	var cam := Camera3D.new()
	cam.fov = 75.0
	cam.far = 800.0
	root.add_child(cam)
	current_scene = null

	# 使用者截图里的机位：站在 (49.74, 0, -6.66)，往前上方看
	await _shot(cam, Vector3(49.74, 1.7, -6.66), Vector3(52.0, 1.7, 0.0), "01_player_eye_level")
	await _shot(cam, Vector3(49.74, 8.0, -6.66), Vector3(52.0, 0.0, 4.0), "02_player_above")
	await _shot(cam, Vector3(49.74, 1.7, -6.66), Vector3(49.74, 0.0, -6.66), "03_look_down")
	await _shot(cam, Vector3(0, 30.0, 0), Vector3(0, 0.0, 0), "04_whole_map")

	print("[open] DONE")
	quit(0)
