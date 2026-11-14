extends SceneTree
## Sample world-space campus collision without loading gameplay or opening a window.

func _initialize() -> void:
	if DisplayServer.get_name() != "headless" or not OS.get_cmdline_user_args().has("--no-capture"):
		quit(2)
		return
	_run.call_deferred()

func _run() -> void:
	var input := ""
	var output := ""
	var top := 120.0
	var bottom := -40.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="):
			input = arg.trim_prefix("--scene=")
		elif arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
		elif arg.begins_with("--top="):
			top = float(arg.trim_prefix("--top="))
		elif arg.begins_with("--bottom="):
			bottom = float(arg.trim_prefix("--bottom="))
	if not FileAccess.file_exists(input) or output.is_empty() or FileAccess.file_exists(output):
		push_error("Requires existing --scene and a new --out float32 file")
		quit(2)
		return
	var world := Node3D.new()
	root.add_child(world)
	world.add_child((load(input) as PackedScene).instantiate())
	for i in 4:
		await physics_frame
	var space := world.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = 1
	query.hit_back_faces = true
	var values := PackedFloat32Array()
	values.resize(1153 * 979)
	for z in 979:
		for x in 1153:
			query.from = Vector3(-288.0 + x * .5, top, -564.0 + z * .5)
			query.to = Vector3(query.from.x, bottom, query.from.z)
			var hit := space.intersect_ray(query)
			values[z * 1153 + x] = NAN if hit.is_empty() else float(hit["position"].y)
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_buffer(values.to_byte_array())
	file.close()
	print("[sample] ", input, " -> ", output)
	quit()
