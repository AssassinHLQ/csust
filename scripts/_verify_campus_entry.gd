extends SceneTree
## Traverse the production hall exit, original bridge and scan bridge with the real player.
var _player: CharacterBody3D
var _passed := 0
var _failed := 0

func _initialize() -> void:
	if DisplayServer.get_name() != "headless" or not OS.get_cmdline_user_args().has("--no-capture"):
		quit(2)
		return
	_run.call_deferred()

func _check(ok: bool, label: String, detail: Variant = "") -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
	print("[entry] %s %s %s" % ["PASS" if ok else "FAIL", label, detail])

func _tick(frames: int) -> void:
	for i in frames:
		await physics_frame
		_player.call("_physics_process", 1.0 / 60.0)

func _keep_collisions(node: Node) -> void:
	if node is CollisionObject3D:
		node.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	for child in node.get_children():
		_keep_collisions(child)

func _run() -> void:
	AudioServer.set_bus_mute(0, true)
	root.size = Vector2i(1600, 900)
	preload("res://scripts/ui_skin.gd").ui_font().get_string_size("COST 0123456789", HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	await process_frame
	await process_frame
	var world := (load("res://scenes/next_level.tscn") as PackedScene).instantiate() as Node3D
	_keep_collisions(world)
	world.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(world)
	_player = world.get_node("Player") as CharacterBody3D
	await _tick(8)
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/campus_splattransform/manifest.json"))
	var points: Array[Vector3] = [Vector3(10, -.02, -57), Vector3(10, -.02, -60)]
	for p in meta["access"]["bridge_points"]:
		points.append(Vector3(p[0], p[1], p[2]))
	points.append(points[-1] + Vector3(0, 0, -3))
	for reverse in [false, true]:
		var route := points.duplicate()
		if reverse:
			route.reverse()
		_player.global_position = route[0] + Vector3.UP * .1
		_player.velocity = Vector3.ZERO
		await _tick(60)
		var target := 1
		var stuck := 0
		var frames := 0
		Input.action_press("move_forward")
		Input.action_press("sprint")
		while target < route.size() and frames < 4000 and stuck < 90:
			var delta: Vector3 = route[target] - _player.global_position
			var yaw := atan2(-delta.x, -delta.z)
			_player.set("_yaw", yaw)
			(_player.get("rig") as Node3D).rotation.y = yaw
			var before := _player.global_position
			await _tick(1)
			frames += 1
			stuck = stuck + 1 if before.distance_to(_player.global_position) < .003 else 0
			if Vector2(delta.x, delta.z).length() < .25:
				target += 1
		Input.action_release("move_forward")
		Input.action_release("sprint")
		var contacts: Array = []
		for i in _player.get_slide_collision_count():
			var hit := _player.get_slide_collision(i)
			contacts.append({"collider": str(hit.get_collider().get_path()), "normal": str(hit.get_normal()), "at": str(hit.get_position())})
		_check(target == route.size(), "production entrance and full bridge reverse=%s" % reverse,
			{"waypoint": target, "total": route.size(), "position": str(_player.global_position), "frames": frames, "contacts": contacts})
	_check(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "mouse remains uncaptured")
	print("[entry] RESULT %d passed / %d failed" % [_passed, _failed])
	world.free()
	quit(0 if _failed == 0 else 1)
