extends SceneTree
## Import native SplatTransform faces already in campus world coordinates.
## --in=<faces.f32> --out=res://...scn -- --no-capture (with --headless).

func _initialize() -> void:
	if DisplayServer.get_name() != "headless" or not OS.get_cmdline_user_args().has("--no-capture"):
		push_error("Requires --headless and -- --no-capture")
		quit(2)
		return
	AudioServer.set_bus_mute(0, true)
	_run.call_deferred()


func _run() -> void:
	var input := ""
	var output := ""
	var directory := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--in="):
			input = arg.substr(5)
		elif arg.begins_with("--out="):
			output = arg.substr(6)
		elif arg.begins_with("--directory="):
			directory = arg.substr(12).trim_suffix("/")
	if not directory.is_empty():
		_import_directory(directory)
		return
	if not FileAccess.file_exists(input) or not output.ends_with(".scn") or FileAccess.file_exists(output):
		push_error("Requires existing input and a new .scn output")
		quit(2)
		return
	var bytes := FileAccess.get_file_as_bytes(input)
	if bytes.is_empty() or bytes.size() % 36 != 0:
		push_error("Input must contain complete float32 triangles")
		quit(2)
		return
	var floats := bytes.to_float32_array()
	bytes.clear()
	var faces := PackedVector3Array()
	faces.resize(floats.size() / 3)
	for i in faces.size():
		faces[i] = Vector3(floats[i * 3], floats[i * 3 + 1], floats[i * 3 + 2])
		if not faces[i].is_finite():
			push_error("Nonfinite collision coordinate")
			quit(2)
			return
	floats.clear()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var body := StaticBody3D.new()
	body.name = "CampusSplatTransform"
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = shape
	body.add_child(collision)
	collision.owner = body
	var packed := PackedScene.new()
	var error := packed.pack(body)
	if error == OK:
		error = ResourceSaver.save(packed, output, ResourceSaver.FLAG_COMPRESS)
	print("[splattransform] triangles=%d output=%s error=%d" % [faces.size() / 3, output, error])
	body.free()
	quit(0 if error == OK else 1)


func _import_directory(directory: String) -> void:
	var manifest_path := directory + "/manifest.json"
	if not FileAccess.file_exists(manifest_path):
		push_error("Missing complete bake manifest")
		quit(2)
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if manifest.get("partial", false):
		push_error("Cannot import an incomplete campus bake")
		quit(2)
		return
	var header := "[gd_scene load_steps=%d format=3]\n\n" % [manifest["tiles"].size() + 1]
	var nodes := "[node name=\"CampusSplatTransform\" type=\"Node3D\"]\n"
	var total := 0
	for tile in manifest["tiles"]:
		var name: String = tile["name"]
		var path := directory + "/" + name + ".scn"
		if FileAccess.file_exists(path):
			push_error("Refusing to overwrite candidate tile " + path)
			quit(2)
			return
		var bytes := FileAccess.get_file_as_bytes(directory + "/" + name + ".faces.f32")
		if bytes.is_empty() or bytes.size() != int(tile["triangles"]) * 36:
			push_error("Missing or incomplete tile input: " + name)
			quit(2)
			return
		var values := bytes.to_float32_array()
		bytes.clear()
		var faces := PackedVector3Array()
		faces.resize(values.size() / 3)
		for i in faces.size():
			faces[i] = Vector3(values[i * 3], values[i * 3 + 1], values[i * 3 + 2])
			if not faces[i].is_finite():
				push_error("Nonfinite vertex in " + name)
				quit(2)
				return
		values.clear()
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces)
		var body := StaticBody3D.new()
		body.name = name
		var cs := CollisionShape3D.new()
		cs.name = "Collision"
		cs.shape = shape
		body.add_child(cs)
		cs.owner = body
		var packed := PackedScene.new()
		var error := packed.pack(body)
		if error == OK:
			error = ResourceSaver.save(packed, path, ResourceSaver.FLAG_COMPRESS)
		body.free()
		if error != OK:
			push_error("Tile save failed: %s error %d" % [name, error])
			quit(1)
			return
		total += faces.size() / 3
		faces.clear()
		header += "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"%s\"]\n" % [path, name]
		nodes += "\n[node name=\"%s\" parent=\".\" instance=ExtResource(\"%s\")]\n" % [name, name]
		print("[splattransform] imported ", name, " total triangles ", total)
	var wrapper := FileAccess.open(directory + ".tscn", FileAccess.WRITE)
	if wrapper == null:
		push_error("Cannot save wrapper")
		quit(1)
		return
	wrapper.store_string(header + "\n" + nodes)
	wrapper.close()
	print("[splattransform] complete: %d tiles, %d triangles, %s.tscn" % [manifest["tiles"].size(), total, directory])
	quit(0)
