extends SceneTree
## 探针：芹香十个嘴型各渲一张脸，拼成对照表 —— 挑一个「微笑」。
##   godot --path . --script res://scripts/_probe_face_menu.gd -- --splat=off
## 输出：_arisu_captures/_facemenu/mouth_<名字>.png
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(720, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 60:
		await process_frame
	paused = false
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_facemenu")
	DirAccess.make_dir_recursive_absolute(out)

	var clerk := game.get_node_or_null("Shop/ClerkSerika") as Node3D
	if clerk == null:
		print("没有 ClerkSerika")
		quit(1)
		return
	var mouths: Array = []
	for mi in clerk.find_children("Mouth*", "MeshInstance3D", true, false):
		mouths.append(mi)
	print("嘴型 %d 个：%s" % [mouths.size(), str(mouths.map(func(m): return m.name))])

	# 相机正对她的脸（她朝 -X）
	var cam := Camera3D.new()
	cam.fov = 34.0
	cam.near = 0.01
	cam.far = 40.0
	root.add_child(cam)
	# 用 607 号嘴（当前默认那个「o」）的世界位置当对焦点，保证每次都框在嘴上
	var anchor := Vector3.ZERO
	var ref := clerk.get_node_or_null("Serika_Original_Body/Serika_Original_Body2/Mouth_607") as Node3D
	if ref == null:
		for m in mouths:
			if String(m.name) == "Mouth_607":
				ref = m as Node3D
	if ref != null:
		var a := (ref as MeshInstance3D).global_transform * (ref as MeshInstance3D).mesh.get_aabb()
		anchor = a.get_center()
	print("对焦点 %s" % str(anchor.snappedf(0.001)))
	cam.global_position = anchor + Vector3(-0.85, 0.06, 0.0)
	cam.look_at(anchor, Vector3.UP)
	cam.make_current()
	# 关掉 HUD，照片干净
	var hud := game.get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		hud.visible = false

	for m in mouths:
		for o in mouths:
			(o as Node3D).visible = (o == m)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join("mouth_%s.png" % m.name))
		print("  %s" % m.name)
	print("[截图] %s" % out)
	quit(0)
