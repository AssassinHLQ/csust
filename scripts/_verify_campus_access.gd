extends SceneTree
## Headless acceptance of the real player on the access bridge and scan guards.
const SCENE := "res://scenes/campus_splattransform.tscn"
var _world: Node3D
var _player: CharacterBody3D
var _space: PhysicsDirectSpaceState3D
var _passed := 0
var _failed := 0
var _results: Array = []
var _access := "res://scenes/campus_splattransform/manifest.json"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--access="):
			_access = arg.trim_prefix("--access=")
	if DisplayServer.get_name() != "headless" or not OS.get_cmdline_user_args().has("--no-capture"):
		quit(2)
		return
	_run.call_deferred()

func _check(ok: bool, label: String, detail: Variant = "") -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
	_results.append({"ok": ok, "label": label, "detail": detail})
	print("[access] %s %s %s" % ["PASS" if ok else "FAIL", label, str(detail)])

func _ray(at: Vector3, top := 8.0) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(Vector3(at.x, top, at.z), Vector3(at.x, -40.0, at.z), 1)
	query.exclude = [_player.get_rid()]
	return _space.intersect_ray(query)

func _direction(to: Vector3) -> void:
	var d := to - _player.global_position
	d.y = 0.0
	if d.length_squared() > .00001:
		var yaw := atan2(-d.x, -d.z)
		_player.set("_yaw", yaw)
		(_player.get("rig") as Node3D).rotation.y = yaw

func _settle(at: Vector3) -> void:
	for action in ["move_forward", "sprint", "jump"]:
		Input.action_release(action)
	_player.global_position = at + Vector3.UP * .08
	_player.velocity = Vector3.ZERO
	for i in 120:
		await physics_frame
		_player.call("_physics_process", 1.0 / 60)

func _run() -> void:
	AudioServer.set_bus_mute(0, true)
	_world = Node3D.new()
	root.add_child(_world)
	_world.add_child((load(SCENE) as PackedScene).instantiate())
	_player = (load("res://scenes/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	_player.safe_margin = .004
	_world.add_child(_player)
	_player.set_physics_process(false)
	_player.set_process_input(false)
	_player.set_process_unhandled_input(false)
	var carrier := _player.get_node_or_null("Arisu/CarrierForm")
	if carrier != null:
		carrier.process_mode = Node.PROCESS_MODE_DISABLED
	for i in 6:
		await physics_frame
	_space = _world.get_world_3d().direct_space_state
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_access))
	if meta.has("access"):
		meta = meta["access"]
	var points: Array[Vector3] = []
	for p in meta["bridge_points"]:
		points.append(Vector3(p[0], p[1], p[2]))
	# Include the actual transition from the bridge to the original street.
	var end := points[-1] + Vector3(0, 0, -3)
	var ground := _ray(end)
	_check(not ground.is_empty(), "bridge joins measured scan ground")
	if not ground.is_empty():
		end.y = ground["position"].y
		points.append(end)
	points[0] = points[0].lerp(points[1], .2)
	for sprint in [false, true]:
		for reverse in [false, true]:
			var route := points.duplicate()
			if reverse:
				route.reverse()
			await _follow_bridge(route, sprint, reverse)
	await _guards(meta["guard_test_edges"] if meta.has("guard_test_edges") else meta["edges"])
	_check(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "mouse stays uncaptured")
	var report := {"passed": _passed, "failed": _failed, "checks": _results, "rendering": "headless; no rendered FPS measured"}
	var file := FileAccess.open("res://_tools/_tmp/collision_validation/campus_access.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("[access] RESULT %d passed / %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func _follow_bridge(points: Array, sprint: bool, reverse: bool) -> void:
	await _settle(points[0])
	var ok := _player.is_on_floor()
	var min_clearance := 0.0
	var target := 1
	var frames := 0
	var last := _player.global_position
	var stagnant := 0
	Input.action_press("move_forward")
	if sprint:
		Input.action_press("sprint")
	while target < points.size() and frames < 9000 and stagnant < 180:
		_direction(points[target])
		await physics_frame
		_player.call("_physics_process", 1.0 / 60)
		frames += 1
		var delta := _player.global_position - last
		stagnant = stagnant + 1 if Vector2(delta.x, delta.z).length() < .004 else 0
		last = _player.global_position
		var a: Vector3 = points[target - 1]
		var b: Vector3 = points[target]
		var flat := Vector2(b.x - a.x, b.z - a.z)
		var fraction := clampf(Vector2(last.x - a.x, last.z - a.z).dot(flat) / flat.length_squared(), 0, 1)
		var expected_y := lerpf(a.y, b.y, fraction)
		min_clearance = minf(min_clearance, last.y - expected_y)
		if last.y < expected_y - .6:
			ok = false
			break
		if Vector2(last.x - b.x, last.z - b.z).length() < .25:
			target += 1
	Input.action_release("move_forward")
	Input.action_release("sprint")
	_check(ok and target == points.size(), "bridge traversal sprint=%s reverse=%s" % [sprint, reverse], {"waypoint": target, "total": points.size(), "end": str(last), "frames": frames, "min_clearance": min_clearance})

func _guards(edges: Array) -> void:
	var candidates: Array = []
	var capsule := CapsuleShape3D.new()
	capsule.radius = .3
	capsule.height = 1.5
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1
	query.exclude = [_player.get_rid()]
	for k in range(0, edges.size(), maxi(1, edges.size() / 600)):
		var edge: Dictionary = edges[k]
		var y: float = edge["surface_y"]
		if y < -8.0 or y > 6.0:
			continue
		var outward := Vector3(edge["outward"][0], 0, edge["outward"][1])
		var center := Vector3((edge["a"][0] + edge["b"][0]) * .5, y, (edge["a"][1] + edge["b"][1]) * .5)
		var start := center - outward * .8
		var hit := _ray(start)
		if hit.is_empty() or absf(float(hit["position"].y) - y) > .7:
			continue
		start.y = float(hit["position"].y)
		query.transform.origin = start + Vector3.UP * .85
		if not _space.intersect_shape(query, 1).is_empty():
			continue
		candidates.append({"start": start, "direction": outward})
		if candidates.size() >= 32:
			break
	_check(candidates.size() >= 16, "distributed guard motion samples", candidates.size())
	var stopped := 0
	var detours := 0
	var details: Array = []
	for candidate in candidates:
		var start: Vector3 = candidate["start"]
		var direction: Vector3 = candidate["direction"]
		await _settle(start)
		_direction(start + direction * 10)
		var stood := _player.is_on_floor()
		var settled := _player.global_position
		var trace: Array = []
		var supported_frames := 0
		var lowest := _player.global_position.y
		var touched := false
		Input.action_press("move_forward")
		for i in 100:
			await physics_frame
			_player.call("_physics_process", 1.0 / 60)
			lowest = minf(lowest, _player.global_position.y)
			var support := _ray(_player.global_position, _player.global_position.y + .4)
			if not support.is_empty() and absf(_player.global_position.y - float(support["position"].y)) < .7:
				supported_frames += 1
			if i % 10 == 0:
				trace.append({"at": str(_player.global_position), "supported": not support.is_empty()})
			for ci in _player.get_slide_collision_count():
				var collider: Object = _player.get_slide_collision(ci).get_collider()
				if collider is Node and collider.name == "ScanBoundary":
					touched = true
		Input.action_release("move_forward")
		var travel := (_player.global_position - start).dot(direction)
		var sideways := absf((_player.global_position - start).dot(Vector3(-direction.z, 0, direction.x)))
		# Finite holes have corners: walking around one on measured ground is
		# valid. Keep those samples and require support on every simulated frame.
		var detour := travel >= .9 and sideways > .3 and supported_frames == 100
		var ok := stood and touched and (travel < .9 or detour) and lowest >= start.y - .7
		details.append({"start": str(start), "end": str(_player.global_position), "contact": touched,
			"travel": travel, "sideways": sideways, "supported_frames": supported_frames,
			"kind": "supported detour" if detour else "stopped", "ok": ok})
		if ok:
			stopped += 1
			if detour:
				detours += 1
		else:
			print("[access] guard detail ", {"start": str(start), "settled": str(settled), "stood": stood, "end": str(_player.global_position), "contact": touched, "travel": travel, "trace": trace})
	_check(stopped == candidates.size(), "real player stays protected from scan void", {"protected": stopped, "samples": candidates.size(), "supported_detours": detours, "details": details})
