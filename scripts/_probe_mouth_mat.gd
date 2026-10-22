extends SceneTree
## 探针：嘴型网格的材质到底差在哪（贴图 / uv 偏移 / 颜色）
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 40:
		await process_frame
	var clerk := game.get_node_or_null("Shop/ClerkSerika") as Node3D
	for nm in ["Mouth_401", "Mouth_607", "Mouth_701"]:
		var m := clerk.find_child(nm, true, false) as MeshInstance3D
		if m == null:
			continue
		var mat := m.get_active_material(0) as StandardMaterial3D
		print("== %s ==" % nm)
		if mat == null:
			print("  材质 null")
			continue
		print("  albedo 贴图 = %s" % ("null" if mat.albedo_texture == null else str(mat.albedo_texture.get_size())))
		print("  uv1_scale=%s uv1_offset=%s" % [str(mat.uv1_scale), str(mat.uv1_offset)])
		print("  transparency=%d cull=%d" % [mat.transparency, mat.cull_mode])
	var body := clerk.find_child("Serika_Original_Body2", true, false) as MeshInstance3D
	if body != null:
		for s in body.mesh.get_surface_count():
			var mat2 := body.get_active_material(s) as StandardMaterial3D
			if mat2 != null:
				print("  body surf%d %s -> tex %s" % [s, mat2.resource_name,
					"null" if mat2.albedo_texture == null else str(mat2.albedo_texture.get_size())])
	quit(0)
