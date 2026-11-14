extends SceneTree
## Add world-space outline guards and visible bridge to a staged campus bake.

func _initialize() -> void:
	if DisplayServer.get_name() != "headless" or not OS.get_cmdline_user_args().has("--no-capture"):
		quit(2)
		return
	_run.call_deferred()

func _faces(path: String) -> PackedVector3Array:
	var floats := FileAccess.get_file_as_bytes(path).to_float32_array()
	var faces := PackedVector3Array()
	faces.resize(floats.size() / 3)
	for i in faces.size():
		faces[i] = Vector3(floats[i * 3], floats[i * 3 + 1], floats[i * 3 + 2])
	return faces

func _visual(faces: PackedVector3Array, color: Color) -> MeshInstance3D:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = faces
	var normals := PackedVector3Array()
	normals.resize(faces.size())
	for i in range(0, faces.size(), 3):
		var normal := (faces[i + 2] - faces[i]).cross(faces[i + 1] - faces[i]).normalized()
		for k in 3:
			normals[i + k] = normal
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .8
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, material)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	return visual

func _run() -> void:
	var input := ""
	var target := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--input="):
			input = arg.trim_prefix("--input=")
		elif arg.begins_with("--target="):
			target = arg.trim_prefix("--target=")
	if input.is_empty() or target.is_empty() or not FileAccess.file_exists(target + "/manifest.json"):
		quit(2)
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(target + "/manifest.json"))
	var access: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(input + "/access.json"))
	for name in ["ScanBoundary", "CampusBridgeExtension"]:
		var path: String = target + "/" + name + ".scn"
		if FileAccess.file_exists(path):
			push_error("Refusing to overwrite " + path)
			quit(2)
			return
		var faces := _faces(input + "/" + name + ".faces.f32")
		var body := StaticBody3D.new()
		body.name = name
		var collision := CollisionShape3D.new()
		collision.name = "Collision"
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces)
		collision.shape = shape
		body.add_child(collision)
		collision.owner = body
		if name == "CampusBridgeExtension":
			for part in ["BridgeDeck", "BridgeRails"]:
				var color := Color(.25, .32, .39) if part == "BridgeDeck" else Color(.93, .75, .26)
				var visual := _visual(_faces(input + "/" + part + ".faces.f32"), color)
				visual.name = part
				body.add_child(visual)
				visual.owner = body
		var packed := PackedScene.new()
		var error := packed.pack(body)
		if error == OK:
			error = ResourceSaver.save(packed, path, ResourceSaver.FLAG_COMPRESS)
		body.free()
		if error != OK:
			quit(1)
			return
		manifest["tiles"].append({"name": name, "triangles": faces.size() / 3, "role": "outline guard" if name == "ScanBoundary" else "access bridge"})
		manifest["triangles"] += faces.size() / 3
	# Keep the same distributed edge candidates for reproducible acceptance
	# without shipping the full intermediate sampling report.
	var edges: Array = access["edges"]
	var test_edges: Array = []
	for i in range(0, edges.size(), maxi(1, edges.size() / 600)):
		test_edges.append(edges[i])
	access["guard_test_edges"] = test_edges
	access.erase("edges")
	manifest["access"] = access
	var file := FileAccess.open(target + "/manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	var header := "[gd_scene load_steps=%d format=3]\n\n" % [manifest["tiles"].size() + 1]
	var nodes := "[node name=\"CampusSplatTransform\" type=\"Node3D\"]\n"
	for tile in manifest["tiles"]:
		var name: String = tile["name"]
		header += "[ext_resource type=\"PackedScene\" path=\"%s/%s.scn\" id=\"%s\"]\n" % [target, name, name]
		nodes += "\n[node name=\"%s\" parent=\".\" instance=ExtResource(\"%s\")]\n" % [name, name]
	file = FileAccess.open(target + ".tscn", FileAccess.WRITE)
	file.store_string(header + "\n" + nodes)
	file.close()
	print("[access] installed guards and bridge: ", target, " triangles ", manifest["triangles"])
	quit()
