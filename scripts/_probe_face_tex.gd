extends SceneTree
## 把 Serika 身上所有贴图 dump 出来（找嘴在哪张图上）
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 40:
		await process_frame
	var clerk := game.get_node_or_null("Shop/ClerkSerika") as Node3D
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_tex")
	DirAccess.make_dir_recursive_absolute(out)
	var seen := {}
	for mi in clerk.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var mat := m.get_active_material(s) as StandardMaterial3D
			if mat == null or mat.albedo_texture == null:
				continue
			var tex := mat.albedo_texture
			var key := str(tex.get_size()) + str(tex.get_instance_id())
			if seen.has(key):
				continue
			seen[key] = true
			var nm := "%s_%s_s%d" % [m.name, mat.resource_name, s]
			tex.get_image().save_png(out.path_join("%s.png" % nm))
			print("  %s → %s" % [nm, str(tex.get_size())])
	print("[dump] %s" % out)
	quit(0)
