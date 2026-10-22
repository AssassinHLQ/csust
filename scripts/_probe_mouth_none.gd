extends SceneTree
## 探针：把十个嘴型全部塌掉（权重 1），看「o」还在不在 —— 判断嘴是网格还是身体贴图
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
		(m as MeshInstance3D).set_blend_shape_value(0, 1.0)
	var cam := Camera3D.new()
	cam.fov = 34.0
	cam.near = 0.01
	cam.far = 40.0
	root.add_child(cam)
	var anchor := Vector3(33.0549, 1.2542, -15.3)
	cam.global_position = anchor + Vector3(-0.85, 0.09, 0.0)
	cam.look_at(anchor + Vector3(0, 0.02, 0), Vector3.UP)
	cam.make_current()
	for _i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures")
	root.get_texture().get_image().save_png(out.path_join("_mouth_none.png"))
	# 顺便把身体那张 EyeMouth 贴图存出来看看
	var body := clerk.find_child("Serika_Original_Body2", true, false) as MeshInstance3D
	if body != null:
		var mat := body.get_active_material(4) as StandardMaterial3D
		if mat != null and mat.albedo_texture != null:
			var img := mat.albedo_texture.get_image()
			img.save_png(out.path_join("_eyemouth_tex.png"))
			print("EyeMouth 贴图 %s → 已存" % str(img.get_size()))
	print("done")
	quit(0)
