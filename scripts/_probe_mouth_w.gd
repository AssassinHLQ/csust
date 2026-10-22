extends SceneTree
## 探针：十个嘴型的形态键权重（哪个是"展开"的），并按正确方法逐个渲染
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(720, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 40:
		await process_frame
	var clerk := game.get_node_or_null("Shop/ClerkSerika") as Node3D
	var mouths: Array = clerk.find_children("Mouth*", "MeshInstance3D", true, false)
	for m in mouths:
		print("  %-10s 形态键权重 = %s" % [m.name, str((m as MeshInstance3D).get_blend_shape_value(0))])

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_facemenu2")
	DirAccess.make_dir_recursive_absolute(out)
	var cam := Camera3D.new()
	cam.fov = 34.0
	cam.near = 0.01
	cam.far = 40.0
	root.add_child(cam)
	var anchor := Vector3(33.0549, 1.2542, -15.3)
	cam.global_position = anchor + Vector3(-0.85, 0.09, 0.0)
	cam.look_at(anchor + Vector3(0, 0.02, 0), Vector3.UP)
	cam.make_current()
	for m in mouths:
		for o in mouths:
			(o as MeshInstance3D).set_blend_shape_value(0, 0.0 if o == m else 1.0)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join("m_%s.png" % m.name))
	print("[截图] %s" % out)
	quit(0)
