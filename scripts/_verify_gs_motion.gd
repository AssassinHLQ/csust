extends SceneTree
## No-window collision acceptance. Uses the production player scene and controller.
## godot --headless --fixed-fps 60 --path . --script res://scripts/_verify_gs_motion.gd -- --no-capture --campus-splat=off --story=off
## --collision=old compares the previous mesh; --integration loads next_level.
## Results are local artifacts, not rendered gameplay FPS.

const GS := "res://scenes/campus_gs.tscn"
const OLD := "res://scenes/campus_collision_walls_final.scn"
const OUT := "res://_tools/_tmp/collision_validation"
const X0 := -287.8
const X1 := 287.8
const Z0 := -558.4
const Z1 := -75.0
const OFFSETS := [-3.0, -2.0, -1.0, -0.5, 0.0, 0.5, 1.0, 2.0, 3.0]

## Fixed acceptance routes retained from the original failed bake for repeatable comparisons.
const BASELINE_ROUTES := [
	["x=-192.0", -192.000000000, 1.999999523, -434.399993896, true],
	["x=-192.0", -192.000000000, 1.000000000, -170.399993896, true],
	["x=-96.0", -96.000000000, 3.000000000, -490.399993896, true],
	["x=-96.0", -96.000000000, 1.000000000, -322.399993896, true],
	["x=0.0", 0.000000000, 3.040002346, -370.399993896, true],
	["x=0.0", 0.000000000, 2.000000000, -234.399993896, true],
	["x=96.0", 96.000000000, 1.959997654, -226.399993896, true],
	["x=96.0", 96.000000000, 3.040002346, -242.399993896, true],
	["x=192.0", 192.000000000, 0.000000000, -114.400001526, true],
	["x=192.0", 192.000000000, 2.959997654, -262.399993896, true],
	["z=-468.0", 36.200000763, 2.000000000, -468.000000000, false],
	["z=-468.0", -75.800003052, 1.000000000, -468.000000000, false],
	["z=-372.0", 144.199996948, 1.120000839, -372.000000000, false],
	["z=-372.0", 256.200012207, 2.320007086, -372.000000000, false],
	["z=-276.0", 168.199996948, 2.120001316, -276.000000000, false],
	["z=-276.0", -91.800003052, 3.000000000, -276.000000000, false],
	["z=-180.0", 124.199996948, 0.699996948, -180.000000000, false],
	["z=-180.0", 220.199996948, 1.879999161, -180.000000000, false],
	["main_street_z=-180.0", 0.000000000, 0.000000000, -180.000000000, false],
	["main_street_z=-276.0", 0.000000000, 0.000000000, -276.000000000, false],
	["main_street_z=-372.0", 0.000000000, 0.000000000, -372.000000000, false],
	["main_street_z=-468.0", 0.000000000, 0.000000000, -468.000000000, false],
	["arena_spawn", -60.000000000, 0.000000000, -140.000000000, true],
	["arena_spawn", -60.000000000, 0.000000000, -140.000000000, false],
]

var _world: Node3D
var _collision: Node3D
var _player: CharacterBody3D
var _space: PhysicsDirectSpaceState3D
var _routes: Array[Dictionary] = []
var _checks: Array[Dictionary] = []
var _report: Dictionary = {}
var _old := false
var _integration := false
var _candidate := ""
var _tile_overrides := ""
var _report_tag := ""
var _route_tag := ""
var _player_ms: Array[float] = []

func _initialize() -> void:
	if DisplayServer.get_name() != "headless" or not OS.get_cmdline_user_args().has("--no-capture"):
		push_error("[collision] Requires --headless and -- --no-capture")
		quit(2)
		return
	_old = OS.get_cmdline_user_args().has("--collision=old")
	_integration = OS.get_cmdline_user_args().has("--integration")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--collision-scene="):
			_candidate = a.trim_prefix("--collision-scene=")
		elif a.begins_with("--tile-overrides="):
			_tile_overrides = a.trim_prefix("--tile-overrides=")
		elif a.begins_with("--report-tag="):
			_report_tag = a.trim_prefix("--report-tag=")
		elif a.begins_with("--route-tag="):
			_route_tag = a.trim_prefix("--route-tag=")
	_run.call_deferred()

func _check(ok: bool, label: String, detail: Variant = "") -> void:
	_checks.append({"ok": ok, "label": label, "detail": detail})
	print("[collision] %s %s %s" % ["PASS" if ok else "FAIL", label, str(detail)])

func _run() -> void:
	AudioServer.set_bus_mute(0, true)
	var start := Time.get_ticks_usec()
	if _integration:
		_world = (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
		if _old or not _candidate.is_empty():
			var replaced := _world.get_node("CampusCollision")
			_world.remove_child(replaced)
			replaced.free()
			var old_collision := (load(OLD if _old else _candidate) as PackedScene).instantiate()
			old_collision.name = "CampusCollision"
			_world.add_child(old_collision)
		if not _tile_overrides.is_empty():
			var campus_collision := _world.get_node("CampusCollision")
			for file in DirAccess.get_files_at(_tile_overrides):
				if not file.ends_with(".scn"):
					continue
				var original := campus_collision.get_node_or_null(file.get_basename())
				if original != null:
					original.free()
				campus_collision.add_child((load(_tile_overrides + "/" + file) as PackedScene).instantiate())
		root.add_child(_world)
		current_scene = _world
		_player = _world.get_node("Player") as CharacterBody3D
		_collision = _world.get_node("CampusCollision") as Node3D
		# Remove combat/reset interference; keep all scenery and its collisions.
		# Do not use PROCESS_MODE_DISABLED: CollisionObject3D's default disable_mode
		# removes bodies from the physics world, including the static campus mesh.
		_world.set_process(false)
		_world.set_physics_process(false)
		for child in _world.find_children("*", "Node", true, false):
			if child != _player and not _player.is_ancestor_of(child):
				child.set_process(false)
				child.set_physics_process(false)
				if child is Timer:
					(child as Timer).stop()
		for n in _world.find_children("*", "CollisionObject3D", true, false):
			if n is Area3D:
				n.set_deferred("monitoring", false)
			elif n != _player and (n as CollisionObject3D).collision_layer != 1:
				(n as CollisionObject3D).collision_layer = 0
	else:
		_world = Node3D.new()
		root.add_child(_world)
		current_scene = _world
		_collision = (load(OLD if _old else (GS if _candidate.is_empty() else _candidate)) as PackedScene).instantiate()
		_world.add_child(_collision)
	_report["load_ms"] = (Time.get_ticks_usec() - start) / 1000.0
	_report["mode"] = ("integration_old" if _old else "integration") if _integration else ("old" if _old else "gdgs")
	if not _report_tag.is_empty():
		_report["mode"] = _report_tag
	_report["route_filter"] = _route_tag
	_report["candidate"] = _candidate
	_report["tile_overrides"] = _tile_overrides
	_report["source_path"] = _collision.scene_file_path
	_report["engine"] = Engine.get_version_info()["string"]
	_report["rendering"] = "headless; no rendered FPS measured"
	_report["physics_hz"] = Engine.physics_ticks_per_second
	for i in 8:
		await physics_frame
	_space = _world.get_world_3d().direct_space_state
	var shapes := _collision.find_children("*", "CollisionShape3D", true, false)
	var triangles := 0
	for s in shapes:
		var shape := (s as CollisionShape3D).shape as ConcavePolygonShape3D
		if shape != null:
			triangles += shape.get_faces().size() / 3
	_report["shapes"] = shapes.size()
	_report["triangles"] = triangles
	_check(not shapes.is_empty(), "collision loaded", {"shapes": shapes.size(), "triangles": triangles, "load_ms": _report["load_ms"]})
	if _collision.scene_file_path == GS:
		_check(shapes.size() == 28, "all original campus chunks present", shapes.size())
	if not _candidate.is_empty():
		var manifest_path := _candidate.trim_suffix(".tscn") + "/manifest.json"
		if FileAccess.file_exists(manifest_path):
			var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
			_check(shapes.size() == manifest["tiles"].size(), "all candidate chunks present", shapes.size())
	if not _integration and not _old:
		_survey()
		_find_seams()
		for z in [-180.0, -276.0, -372.0, -468.0]:
			_routes.append({"tag": "main_street_z=" + str(z), "center": Vector3(0.0, 0.0, z), "axis": Vector3.BACK})
		for axis in [Vector3.RIGHT, Vector3.BACK]:
			_routes.append({"tag": "arena_spawn", "center": Vector3(-60.0, 0.0, -140.0), "axis": axis})
	else:
		for r in BASELINE_ROUTES:
			_routes.append({"tag": r[0], "center": Vector3(r[1], r[2], r[3]), "axis": Vector3.RIGHT if r[4] else Vector3.BACK})
		if _integration:
			_integration_survey()
	_check(_routes.size() >= 10, "street routes cover campus", _routes.size())
	if not _route_tag.is_empty():
		_routes = _routes.filter(func(r: Dictionary) -> bool: return r["tag"] == _route_tag)
	if _player == null:
		_player = (load("res://scenes/player.tscn") as PackedScene).instantiate() as CharacterBody3D
		_world.add_child(_player)
	# Prevent expensive idle carrier prewarming from contaminating measurements.
	var carrier := _player.get_node_or_null("Arisu/CarrierForm")
	if carrier != null:
		carrier.process_mode = Node.PROCESS_MODE_DISABLED
	_player.set_process_input(false)
	_player.set_process_unhandled_input(false)
	_player.set("_dev_speed_scale", 1.0)
	# One production controller invocation per engine physics tick, timed directly.
	# Performance.TIME_PHYSICS_PROCESS refreshes too slowly for accelerated tests.
	_player.set_physics_process(false)
	var control := StaticBody3D.new()
	control.name = "ValidationFlatControl"
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	cs.shape = box
	cs.position = Vector3(1000.0, -0.5, 0.0)
	control.add_child(cs)
	_world.add_child(control)
	await physics_frame
	var controls: Array[Dictionary] = []
	var control_route := {"tag": "flat_control", "center": Vector3(1000.0, 0.0, 0.0), "axis": Vector3.RIGHT}
	for sprint in [false, true]:
		for sign_ in [-1.0, 1.0]:
			controls.append(await _walk(control_route, sprint, sign_))
	_report["flat_control"] = controls
	_check(controls.all(func(t: Dictionary) -> bool: return t["ok"]), "flat control proves movement input and controller work")
	_player_ms.clear()
	var trials: Array[Dictionary] = []
	for route in _routes:
		for sprint in [false, true]:
			for sign_ in [-1.0, 1.0]:
				trials.append(await _walk(route, sprint, sign_))
	_report["walk_trials"] = trials
	var failed := trials.filter(func(t: Dictionary) -> bool: return not t["ok"])
	_check(not trials.is_empty() and failed.is_empty(), "real player walks/runs both ways without falling or sticking", {"trials": trials.size(), "failed": failed.size()})
	_report["player_update_ms"] = _stats(_player_ms)
	_report["memory_mib"] = OS.get_static_memory_usage() / 1048576.0
	_ray_benchmark()
	_check(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "mouse remains free")
	_report["checks"] = _checks
	_report["routes"] = []
	for r in _routes:
		var p: Vector3 = r["center"]
		_report["routes"].append({"tag": r["tag"], "x": p.x, "y": p.y, "z": p.z, "axis": "x" if r["axis"] == Vector3.RIGHT else "z"})
	var failures := _checks.filter(func(c: Dictionary) -> bool: return not c["ok"])
	_report["passed"] = _checks.size() - failures.size()
	_report["failed"] = failures.size()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var f := FileAccess.open(OUT + "/" + String(_report["mode"]) + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify(_report, "\t"))
	f.close()
	print("[collision] player controller update ms ", _report["player_update_ms"], " memory MiB ", _report["memory_mib"])
	print("[collision] RESULT %d passed / %d failed; %s/%s.json" % [_report["passed"], _report["failed"], OUT, _report["mode"]])
	_release()
	quit(0 if failures.is_empty() else 1)

func _ray(x: float, z: float, top := 6.0, bottom := -4.0) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, top, z), Vector3(x, bottom, z), 1)
	if is_instance_valid(_player):
		q.exclude = [_player.get_rid()]
	return _space.intersect_ray(q)

func _survey() -> void:
	var misses: Array = []
	var below_street: Array = []
	var total := 0
	for iz in range(61):
		for ix in range(73):
			var x := -288.0 + ix * 8.0
			var z := -560.0 + iz * 8.0
			var hit := _ray(x, z, 120.0, -40.0)
			total += 1
			if hit.is_empty():
				misses.append([x, z])
			elif float(hit["position"].y) < -0.4:
				below_street.append([x, hit["position"].y, z])
	_report["coverage"] = {"total": total, "missing": misses.size(), "missing_positions": misses, "below_floor": below_street.size(), "below_floor_positions": below_street}
	print("[collision] coverage %d/%d hit; below fallback top %d (GS only)" % [total - misses.size(), total, below_street.size()])

func _integration_survey() -> void:
	var counts := {"total": 0, "gdgs_or_old": 0, "fallback": 0, "other": 0, "missing": 0}
	for iz in range(61):
		for ix in range(73):
			var x := -288.0 + ix * 8.0
			var z := -560.0 + iz * 8.0
			if x < X0 or x > X1 or z < Z0 or z > Z1:
				continue
			counts["total"] += 1
			var hit := _ray(x, z, 120.0, -40.0)
			if hit.is_empty():
				counts["missing"] += 1
			elif _collision.is_ancestor_of(hit["collider"]):
				counts["gdgs_or_old"] += 1
			elif hit["collider"].name == "CampusFloor":
				counts["fallback"] += 1
			else:
				counts["other"] += 1
	_report["with_floor_coverage"] = counts
	_check(counts["missing"] == 0, "every sampled column within fallback footprint is supported", counts)

func _find_seams() -> void:
	var gaps: Array = []
	var jumps: Array = []
	var tested := 0
	var unavailable: Array = []
	for axis_index in 2:
		for k in range(1, 6):
			var seam := (-288.0 if axis_index == 0 else -564.0) + k * 96.0
			var axis := Vector3.RIGHT if axis_index == 0 else Vector3.BACK
			var candidates: Array[Dictionary] = []
			var from_ := Z0 + 8.0 if axis_index == 0 else X0 + 8.0
			var to_ := Z1 - 8.0 if axis_index == 0 else X1 - 8.0
			if axis_index == 1 and (seam < Z0 or seam > Z1):
				continue
			for j in range(int((to_ - from_) / 4.0) + 1):
				var along := from_ + j * 4.0
				var center := Vector3(seam, 0.0, along) if axis_index == 0 else Vector3(along, 0.0, seam)
				var left := _ray((center - axis * 3.0).x, (center - axis * 3.0).z)
				var right := _ray((center + axis * 3.0).x, (center + axis * 3.0).z)
				if left.is_empty() or right.is_empty():
					continue
				var yl: float = left["position"].y
				var yr: float = right["position"].y
				if absf(yl - yr) > 1.2 or yl < -0.4 or yl > 3.0 or yr < -0.4 or yr > 3.0:
					continue
				tested += 1
				var clean := true
				var previous := yl
				var roughness := 0.0
				for offset in OFFSETS:
					var p: Vector3 = center + axis * offset
					var h := _ray(p.x, p.z)
					if h.is_empty():
						gaps.append([p.x, p.z])
						clean = false
						continue
					var y: float = h["position"].y
					if absf(y - previous) > 0.38:
						jumps.append([p.x, p.z, previous, y])
						roughness += absf(y - previous)
					if absf(y - yl) > 1.2:
						clean = false
					previous = y
				if clean:
					var middle := _ray(center.x, center.z)
					center.y = float(middle["position"].y) if not middle.is_empty() else yl
					candidates.append({"center": center, "roughness": roughness, "capsule_clear": _clear_route(center, axis)})
			var tag := ("x" if axis_index == 0 else "z") + "=" + str(seam)
			if candidates.is_empty():
				unavailable.append(tag)
				continue
			candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				if a["capsule_clear"] != b["capsule_clear"]:
					return a["capsule_clear"]
				return a["roughness"] < b["roughness"])
			var picked := 0
			for candidate in candidates:
				var p: Vector3 = candidate["center"]
				if _routes.any(func(r: Dictionary) -> bool: return r["center"].distance_to(p) < 16.0):
					continue
				_routes.append({"tag": tag, "center": p, "axis": axis})
				picked += 1
				if picked >= 2:
					break
	_report["seams"] = {"candidate_crossings": tested, "gap_samples": gaps, "step_samples": jumps, "no_open_route": unavailable}
	_check(tested > 0, "seam street samples available", tested)
	_check(gaps.is_empty(), "no missing ground between level street endpoints", gaps.size())
	# These may include legitimate slopes/objects; real motion determines traversability.
	print("[collision] candidate rough surface samples ", jumps.size())

func _clear_route(center: Vector3, axis: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.5
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = capsule
	q.collision_mask = 1
	for i in range(-20, 21):
		var p := center + axis * i * 0.25
		var h := _ray(p.x, p.z)
		if h.is_empty() or absf(float(h["position"].y) - center.y) > 1.2:
			return false
		q.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, float(h["position"].y) + 0.85, p.z))
		if not _space.intersect_shape(q, 1).is_empty():
			return false
	return true

func _walk(route: Dictionary, sprint: bool, sign_: float) -> Dictionary:
	_release()
	var center: Vector3 = route["center"]
	var direction: Vector3 = route["axis"] * sign_
	var start := center - direction * 4.0
	var ground := _ray(start.x, start.z)
	if not ground.is_empty():
		start.y = float(ground["position"].y)
	_player.global_position = start + Vector3.UP * 0.12
	_player.velocity = Vector3.ZERO
	_player.set("_yaw", atan2(-direction.x, -direction.z))
	(_player.get("rig") as Node3D).rotation.y = float(_player.get("_yaw"))
	_player.set("_pitch", -0.12)
	for i in 120:
		await physics_frame
		_player.call("_physics_process", 1.0 / Engine.physics_ticks_per_second)
	var grounded_start := _player.is_on_floor()
	Input.action_press("move_forward")
	if sprint:
		Input.action_press("sprint")
	var limit := 300 if not sprint else 130
	var progress := 0.0
	var min_y := _player.global_position.y
	var floor_frames := 0
	var frames := 0
	var timings: Array[float] = []
	for i in limit:
		await physics_frame
		var started := Time.get_ticks_usec()
		_player.call("_physics_process", 1.0 / Engine.physics_ticks_per_second)
		var ms := (Time.get_ticks_usec() - started) / 1000.0
		frames += 1
		progress = (_player.global_position - start).dot(direction)
		min_y = minf(min_y, _player.global_position.y)
		if _player.is_on_floor():
			floor_frames += 1
		_player_ms.append(ms)
		timings.append(ms)
		if progress >= 8.0 or min_y < -4.0:
			break
	_release()
	var lateral := absf((_player.global_position - start).dot(Vector3(-direction.z, 0.0, direction.x)))
	var ok := grounded_start and progress >= 7.8 and min_y >= -0.4 and lateral < 0.8
	var contacts: Array = []
	for i in _player.get_slide_collision_count():
		var contact := _player.get_slide_collision(i)
		contacts.append({"body": str(contact.get_collider().get_path()), "position": str(contact.get_position()), "normal": str(contact.get_normal())})
	var result := {"tag": route["tag"], "sprint": sprint, "direction": sign_, "start": str(start), "end": str(_player.global_position), "distance": progress, "minimum_y": min_y, "grounded_start": grounded_start, "floor_frames": floor_frames, "frames": frames, "player_update_ms": _stats(timings), "contacts": contacts, "ok": ok}
	if not ok:
		print("[collision] WALK FAIL ", result)
	return result

func _ray_benchmark() -> void:
	var samples: Array[float] = []
	for repeat in 5:
		var t := Time.get_ticks_usec()
		for i in 2000:
			_ray(-280.0 + (i * 37 % 560), -550.0 + (i * 53 % 470), 120.0, -40.0)
		samples.append((Time.get_ticks_usec() - t) / 2000.0)
	_report["ray_us"] = _stats(samples)
	print("[collision] ray microseconds per query ", _report["ray_us"])

func _stats(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {}
	var sorted := values.duplicate()
	sorted.sort()
	return {"samples": sorted.size(), "p50": sorted[int((sorted.size() - 1) * 0.50)], "p95": sorted[int((sorted.size() - 1) * 0.95)], "p99": sorted[int((sorted.size() - 1) * 0.99)], "max": sorted[-1]}

func _release() -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right", "sprint", "jump", "crouch"]:
		Input.action_release(action)
