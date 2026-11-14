extends SceneTree
## Fixed native-scan wall/trunk samples, selected independently of the candidate.
var _scene := "res://scenes/campus_splattransform.tscn"

func _initialize() -> void:
	if DisplayServer.get_name() != "headless" or not OS.get_cmdline_user_args().has("--no-capture"):
		quit(2)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--scene="):
			_scene = argument.trim_prefix("--scene=")
	_run.call_deferred()

func _run() -> void:
	AudioServer.set_bus_mute(0, true)
	var world := Node3D.new()
	root.add_child(world)
	world.add_child((load(_scene) as PackedScene).instantiate())
	for i in 5:
		await physics_frame
	var space := world.get_world_3d().direct_space_state
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/fixtures/campus_structure.json"))
	var sphere := SphereShape3D.new()
	# Production capsule radius plus the bake's 5 cm simplification tolerance.
	sphere.radius = .35
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.collision_mask = 1
	var missing: Array = []
	var total := 0
	for coordinates in fixture["points"]:
		var base := Vector3(coordinates[0], coordinates[1], coordinates[2])
		for height in [.65, 1.3, 2.0]:
			query.transform.origin = base + Vector3.UP * height
			total += 1
			var retained := not space.intersect_shape(query, 1).is_empty()
			# A witness can lie inside a sealed 0.5 m base: a small sphere
			# inside a concave closed box never touches its exterior faces.
			# Require a local blocking surface on a horizontal crossing too.
			for axis in [Vector3.RIGHT, Vector3.BACK]:
				var at := query.transform.origin
				var ray := PhysicsRayQueryParameters3D.create(at - axis * .75, at + axis * .75, 1)
				ray.hit_back_faces = true
				if not space.intersect_ray(ray).is_empty():
					retained = true
			if not retained:
				missing.append({"base": coordinates, "height": height})
	print("[structure] %d / %d native wall and trunk samples retained; missing %s" % [total - missing.size(), total, missing])
	quit(0 if missing.is_empty() and total == 192 else 1)
