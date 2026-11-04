extends SceneTree
## 换完平滑熊之后，整间部室的验收照（干净机位，不开碰撞调试）。
##   _tools/run_shot.sh res://scripts/_probe_room_bear_view.gd -- --splat=off --story=off


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(200)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var mi: MeshInstance3D = null
	var best_vol := 0.0
	var room := game.get_node_or_null("GameDevRoom") as Node3D
	if room != null:
		# 挑体积最大的那个网格（= 房间 GLB；最小的是灯柱之类）
		for n in room.find_children("*", "MeshInstance3D", true, false):
			var m := n as MeshInstance3D
			if m.mesh == null:
				continue
			var bb := m.get_aabb()
			var vol := bb.size.x * bb.size.y * bb.size.z
			if vol > best_vol:
				best_vol = vol
				mi = m
	if mi == null:
		print("[rv] 部室网格没加载（模型是运行时挂的）")
		quit(1)
		return
	var a := mi.get_aabb()
	var xf := mi.global_transform
	var c := xf * a.get_center()
	print("[rv] 部室网格 AABB size=%s" % str(a.size.snappedf(0.01)))

	var cam := Camera3D.new()
	cam.far = 400.0
	cam.near = 0.05
	cam.fov = 70.0
	root.add_child(cam)
	cam.current = true

	# 站在西南墙角往东北看（和用户最早那张截图接近的取景）
	cam.global_position = xf * Vector3(a.position.x + 1.2, 1.55, a.position.z + 1.2)
	cam.look_at(c, Vector3.UP)
	await _wait(25)
	root.get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://_log/room_after_smooth.png"))
	print("[rv] → res://_log/room_after_smooth.png")

	# 熊特写
	var bear := xf * Vector3(-2.51, 1.2, 5.22)
	cam.global_position = bear + (xf.basis * Vector3(0.0, 0.2, -2.0))
	cam.look_at(bear, Vector3.UP)
	await _wait(20)
	root.get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://_log/bear_in_room.png"))
	print("[rv] → res://_log/bear_in_room.png")
	quit(0)