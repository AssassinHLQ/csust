extends SceneTree
## 看：collider-forge 的碰撞网格长什么样、和泼溅对不对齐。
##   _tools/run_shot.sh res://scripts/_probe_campus_collider_vis.gd -- --no-capture
## 出图：
##   _campus_mesh_overlay_above.png   半透明红覆盖（俯视）
##   _campus_mesh_overlay_street.png  街道平视，红面与建筑对齐
##   _campus_mesh_alone.png           只显示碰撞网格（灰），看重建质量

func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(name)
	root.get_texture().get_image().save_png(out)
	print("[vis] 截图 %s" % out)


func _disable_boxes(n: Node) -> void:
	for c in n.get_children():
		if c is StaticBody3D:
			(c as StaticBody3D).collision_layer = 0
			(c as StaticBody3D).collision_mask = 0
		_disable_boxes(c)


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	var campus := level.get_node("Campus")
	campus.call("force_start")
	var t0 := Time.get_ticks_msec()
	while not bool(campus.call("is_ready")) and Time.get_ticks_msec() - t0 < 180000:
		await process_frame
	if not bool(campus.call("is_ready")):
		quit(1)
		return
	var boxes := level.get_node_or_null("CampusCollision")
	if boxes != null:
		_disable_boxes(boxes)
	var mesh_body := (load("res://scenes/campus_collision_mesh.scn") as PackedScene).instantiate()
	level.add_child(mesh_body)

	var glb := "C:/Users/WY157/Desktop/GODOT/_arisu_captures/campus_collider_forge.glb"
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var vis: Node3D = null
	if doc.append_from_file(glb, st) == OK:
		vis = doc.generate_scene(st)
		level.add_child(vis)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1.0, 0.18, 0.12, 0.30)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		for c in vis.find_children("*", "MeshInstance3D", true, false):
			(c as MeshInstance3D).material_override = mat
			(c as MeshInstance3D).cast_shadow = 0
	for c in level.find_children("*", "CanvasLayer", true, false):
		var cl := c as CanvasLayer
		if cl != null:
			cl.visible = false
	var cam := Camera3D.new()
	cam.fov = 68.0
	level.add_child(cam)
	cam.current = true

	cam.global_position = Vector3(120.0, 190.0, 30.0)
	cam.look_at(Vector3(0.0, 0.0, -260.0))
	await _shot("_campus_mesh_overlay_above.png")

	cam.global_position = Vector3(72.3, 10.0, -350.0)
	cam.look_at(Vector3(72.3, 16.0, -430.0))
	cam.fov = 72.0
	await _shot("_campus_mesh_overlay_street.png")

	# 只显示碰撞网格：藏掉泼溅
	var node := campus.get("splat_node") as Node3D
	if node != null:
		node.visible = false
	if vis != null:
		for c in vis.find_children("*", "MeshInstance3D", true, false):
			var mi := c as MeshInstance3D
			var gray := StandardMaterial3D.new()
			gray.albedo_color = Color(0.72, 0.72, 0.74)
			gray.roughness = 0.9
			mi.material_override = gray
			mi.cast_shadow = 1
	cam.global_position = Vector3(120.0, 190.0, 30.0)
	cam.look_at(Vector3(0.0, 0.0, -260.0))
	await _shot("_campus_mesh_alone.png")
	quit(0)
