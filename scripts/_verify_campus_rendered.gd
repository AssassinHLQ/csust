extends SceneTree
## Real-time, rendered production-campus acceptance. Launch only on a private desktop.
const OffWin := preload("res://scripts/offscreen_window.gd")
var _out := "res://_tools/_tmp/rendered_collision/gameplay"
var _renderer_samples: Dictionary = {}
var _world: Node3D
var _player: CharacterBody3D
var _campus: Node3D
var _carrier: Node
var _checks: Array = []
var _frames: Dictionary = {}
var _phase := ""
var _last_frame_us := 0
var _revived_us := 0
var _revived_position := Vector3.ZERO
var _started_us := 0
var _load_seconds := 0.0

func _initialize() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--no-capture"):
		quit(2)
		return
	_run.call_deferred()

func _check(ok: bool, label: String, detail: Variant = "") -> void:
	_checks.append({"ok": ok, "label": label, "detail": detail})
	print("[rendered] %s %s %s" % ["PASS" if ok else "FAIL", label, str(detail)])

func _sample() -> void:
	var now := Time.get_ticks_usec()
	if not _phase.is_empty() and _last_frame_us > 0:
		_frames[_phase].append(float(now - _last_frame_us) / 1000.0)
	_last_frame_us = now

func _set_phase(value: String) -> void:
	_phase = value
	_last_frame_us = Time.get_ticks_usec()
	if not value.is_empty():
		if not _frames.has(value):
			_frames[value] = []
		print("[rendered] PHASE ", value)

func _release() -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right", "sprint", "jump", "crouch"]:
		Input.action_release(action)

func _face(to: Vector3) -> void:
	var direction := to - _player.global_position
	var yaw := atan2(-direction.x, -direction.z)
	_player.set("_yaw", yaw)
	(_player.get("rig") as Node3D).rotation.y = yaw

func _ray(at: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.5, at + Vector3.DOWN * 3.0, 1)
	query.exclude = [_player.get_rid()]
	return _world.get_world_3d().direct_space_state.intersect_ray(query)

func _place(at: Vector3) -> void:
	_release()
	_player.global_position = at + Vector3.UP * .10
	_player.velocity = Vector3.ZERO
	_player.set("_blocked_last_frame", false)
	_player.set("_stuck_t", 0.0)
	await create_timer(.5).timeout

func _follow(points: Array[Vector3], label: String, sprint := true) -> void:
	await _place(points[0])
	_check(_player.is_on_floor(), label + " starts on actual ground", str(_player.global_position))
	_set_phase(label)
	Input.action_press("move_forward")
	if sprint:
		Input.action_press("sprint")
	var target := 1
	var stale := 0.0
	var last := _player.global_position
	var previous_us := Time.get_ticks_usec()
	var start_us := previous_us
	var lowest_clearance := 0.0
	while target < points.size() and stale < 2.5 and Time.get_ticks_usec() - start_us < 55000000:
		_face(points[target])
		await physics_frame
		var now := Time.get_ticks_usec()
		var dt := float(now - previous_us) / 1000000.0
		previous_us = now
		var at := _player.global_position
		var flat_delta := Vector2(at.x - last.x, at.z - last.z)
		stale = stale + dt if flat_delta.length() < .001 else 0.0
		last = at
		var a := points[target - 1]
		var b := points[target]
		var segment := Vector2(b.x - a.x, b.z - a.z)
		var fraction := clampf(Vector2(at.x - a.x, at.z - a.z).dot(segment) / maxf(segment.length_squared(), .001), 0, 1)
		lowest_clearance = minf(lowest_clearance, at.y - lerpf(a.y, b.y, fraction))
		if lowest_clearance < -1.4:
			break
		if Vector2(at.x - b.x, at.z - b.z).length() < .3:
			target += 1
	_release()
	_set_phase("")
	var contacts: Array = []
	for i in _player.get_slide_collision_count():
		var hit := _player.get_slide_collision(i)
		contacts.append({"body": str(hit.get_collider().get_path()), "normal": str(hit.get_normal())})
	_check(target == points.size(), label + " completes without falling or getting trapped",
		{"waypoint": target, "total": points.size(), "end": str(last), "seconds": (Time.get_ticks_usec() - start_us) / 1000000.0, "min_clearance_m": lowest_clearance, "contacts": contacts})

func _shot(label: String) -> void:
	_set_phase("")
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	_check(picture != null and not picture.is_empty(), label + " captures rendered GPU output")
	if picture != null and not picture.is_empty():
		picture.save_png(_out + "/" + label + ".png")
	if _campus.has_method("debug_state"):
		_renderer_samples[label] = _campus.call("debug_state")
		_renderer_samples[label]["camera_transform"] = str(root.get_camera_3d().global_transform)
		if is_instance_valid(_campus.get("splat_node")):
			_renderer_samples[label]["splat_transform"] = str(_campus.get("splat_node").global_transform)
		print("[rendered] RENDERER ", label, " ", JSON.stringify(_renderer_samples[label]))

func _test_revive(airborne: bool) -> void:
	_release()
	if airborne:
		_carrier.call("set_form", true)
		_player.global_position += Vector3.UP * 6
		_carrier.call("_take_off")
		await create_timer(.3).timeout
		_check(_carrier.call("is_flying") and not _player.is_on_floor(), "airborne revival uses actual flying mech")
	# GPU image readback can stall its frame. Settle before starting damage
	# because a SceneTreeTimer also consumes its creation frame's full delta.
	await create_timer(.3).timeout
	await process_frame
	var at := _player.global_position
	_revived_us = 0
	var started := Time.get_ticks_usec()
	_player.call("take_damage", 10000.0)
	Input.action_press("move_forward")
	Input.action_press("jump")
	_set_phase("revive_air" if airborne else "revive_ground")
	while Time.get_ticks_usec() - started < 4700000:
		await process_frame
	_check(_player.call("is_downed") and _player.get("health") == 0.0, "still downed at 4.7 real seconds airborne=%s" % airborne)
	_check(_player.global_position.distance_to(at) < .01, "held input cannot move downed player airborne=%s" % airborne, _player.global_position.distance_to(at))
	_release()
	while _player.call("is_downed") and Time.get_ticks_usec() - started < 5500000:
		await process_frame
	# SceneTreeTimer completion is quantized to process frames. Allow 50 ms
	# early tolerance while reporting the unrounded monotonic measurement.
	_check(_revived_us > 0 and float(_revived_us - started) / 1000000.0 >= 4.95 and float(_revived_us - started) / 1000000.0 < 5.5,
		"revive occurs at five seconds within frame tolerance airborne=%s" % airborne, float(_revived_us - started) / 1000000.0)
	_check(_revived_position.distance_to(at) < .01 and _player.get("health") == _player.get("max_health"),
		"revive restores full health at the downed position airborne=%s" % airborne, str(_revived_position))
	_set_phase("")

func _on_health(current: float, maximum: float) -> void:
	if current == maximum and not _player.call("is_downed"):
		_revived_us = Time.get_ticks_usec()
		_revived_position = _player.global_position

func _run() -> void:
	_started_us = Time.get_ticks_usec()
	AudioServer.set_bus_mute(0, true)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rendered-out="):
			_out = arg.trim_prefix("--rendered-out=")
	DirAccess.make_dir_recursive_absolute(_out)
	preload("res://scripts/render_env.gd").capture_override = true
	# Only window placement differs from production defaults; this settings
	# write is confined to the launcher's isolated APPDATA test profile.
	preload("res://scripts/game_settings.gd").set_value("window_mode", "windowed")
	await OffWin.apply(self, Vector2i(1600, 900))
	root.size = Vector2i(1600, 900)
	process_frame.connect(_sample)
	var loaded_us := Time.get_ticks_usec()
	_world = (load("res://scenes/next_level.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_world)
	current_scene = _world
	_player = _world.get_node("Player") as CharacterBody3D
	_campus = _world.get_node("Campus") as Node3D
	_carrier = _player.get_node("Arisu/CarrierForm")
	_player.connect("health_changed", _on_health)
	# Keep the real rendered scene, collisions, player, carrier and HUD. Stop
	# combat and automatic progression so only this route controls the test.
	for node in [_world] + _world.find_children("*", "Node", true, false):
		if node == _player or _player.is_ancestor_of(node) or node == _campus or _campus.is_ancestor_of(node):
			continue
		node.set_process(false)
		node.set_physics_process(false)
		node.set_process_input(false)
		if node is Timer:
			node.stop()
		if node is Area3D:
			node.set_deferred("monitoring", false)
	preload("res://scripts/mech_state.gd").set_carrier_for_test(true)
	await OffWin.apply(self, Vector2i(1600, 900))
	# Match default gameplay settings, including its 60 FPS cap.
	_check(DisplayServer.window_get_position() == Vector2i(-4000, -4000), "window stays off screen", str(DisplayServer.window_get_position()))
	_check(root.size == Vector2i(1600, 900), "render resolution is 1600 by 900", str(root.size))
	_check(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "mouse is never captured")
	_check(RenderingServer.get_rendering_device() != null, "real GPU rendering device exists")
	_campus.set("start_delay", 0.0)
	_campus.call("force_start")
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/campus_splattransform/manifest.json"))
	var bridge: Array[Vector3] = [Vector3(10, -.02, -57), Vector3(10, -.02, -60)]
	for p in meta["access"]["bridge_points"]:
		bridge.append(Vector3(p[0], p[1], p[2]))
	bridge.append(bridge[-1] + Vector3(0, 0, -3))
	await _follow(bridge, "hall_to_campus")
	# The production streaming system releases campus splats while the player is
	# outside its footprint. Enter before waiting; waiting in the hall would
	# immediately unload the completed scene and never satisfy is_ready().
	var wait_us := Time.get_ticks_usec()
	while not _campus.call("is_ready") and Time.get_ticks_usec() - wait_us < 150000000:
		await create_timer(1.0).timeout
		print("[rendered] loading campus seconds=", (Time.get_ticks_usec() - wait_us) / 1000000.0)
	_load_seconds = float(Time.get_ticks_usec() - loaded_us) / 1000000.0
	_check(_campus.call("is_ready"), "production campus finishes loading", _load_seconds)
	await create_timer(2.0).timeout
	await _shot("campus_arrival")
	if _renderer_samples.has("campus_arrival") and _renderer_samples["campus_arrival"].get("renderer") == "godot-gsplat-stream":
		var stream: Dictionary = _renderer_samples["campus_arrival"]
		_check(stream.get("world_transform_identity", false), "stream pack keeps original world coordinates")
		_check(int(stream.get("resident_splats", 0)) > 0, "stream renderer has resident splats", stream)
		_check(int(stream.get("io_failures", -1)) == 0, "stream pack reads without IO failures")
		_check(int(stream.get("capacity_slots", 0)) <= int(stream["budget_nodes"]) + 16, "stream allocation respects node budget")
		if not bool(stream.get("lod_enabled", true)):
			_check(int(stream["resident_splats"]) == int(stream["source_splats"]), "LOD off retains every source point", stream["resident_splats"])
			_check(int(stream["capacity_slots"]) == 1 and int(stream["wanted_nodes"]) == 1, "LOD off has no representative frontier")
	await _test_revive(false)
	await _test_revive(true)
	_set_phase("mech_descent")
	Input.action_press("crouch")
	var flight_start := Time.get_ticks_usec()
	while (not _player.is_on_floor() or _carrier.call("is_flying")) and Time.get_ticks_usec() - flight_start < 12000000:
		await physics_frame
	_release()
	_set_phase("")
	_check(_player.is_on_floor() and not _carrier.call("is_flying"), "actual mech descends and lands on scanned ground", str(_player.global_position))
	await _shot("mech_landed")
	_carrier.call("set_form", false)
	var seams: Array = [
		[Vector3(-100, 3.355106, -265.6), Vector3(-92, 3.255048, -265.6)],
		[Vector3(-4, 6.689483, -235), Vector3(4, 6.309355, -235)]]
	for i in seams.size():
		for reverse in [false, true]:
			var route: Array[Vector3] = [seams[i][0], seams[i][1]]
			if reverse:
				route.reverse()
			await _follow(route, "seam_%d_reverse_%s" % [i, reverse])
	bridge.reverse()
	await _follow(bridge, "campus_to_hall")
	await _shot("hall_return")
	_check(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "mouse remains uncaptured at completion")
	var failed := _checks.filter(func(c: Dictionary) -> bool: return not c["ok"])
	var performance := {}
	for label in _frames:
		var frames: Array = _frames[label]
		if frames.is_empty():
			continue
		frames.sort()
		var sum_ms := 0.0
		for value in frames:
			sum_ms += float(value)
		performance[label] = {"frames": frames.size(), "average_fps": frames.size() * 1000.0 / sum_ms, "p50_ms": frames[int((frames.size()-1)*.5)], "p95_ms": frames[int((frames.size()-1)*.95)], "p99_ms": frames[int((frames.size()-1)*.99)], "max_ms": frames[-1]}
	var report := {"checks": _checks, "passed": _checks.size()-failed.size(), "failed": failed.size(), "resolution": str(root.size), "window_size": str(DisplayServer.window_get_size()), "gpu": RenderingServer.get_video_adapter_name(), "fps_cap": Engine.max_fps, "load_seconds": _load_seconds, "performance": performance, "seconds": (Time.get_ticks_usec()-_started_us)/1000000.0, "limitations": "Isolated desktop, real-time default graphics, combat frozen, other applications may share GPU; not a packaged-build or boss-battle benchmark."}
	report["renderer_samples"] = _renderer_samples
	var file := FileAccess.open(_out + "/report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("[rendered] PERFORMANCE ", JSON.stringify(performance))
	print("[rendered] RESULT %d passed / %d failed" % [report["passed"], report["failed"]])
	_world.queue_free()
	await process_frame
	var selector := preload("res://addons/gdgs/runtime/render/backend/gaussian_backend_selector.gd")
	selector.release_gpu()
	await process_frame
	var manager: Variant = GaussianRenderManager.get_instance()
	_check(manager == null or not manager._gpu_state_cache.has_render_states(), "scene change releases stream render states")
	if OS.get_cmdline_user_args().has("--stream-reentry"):
		var again := (load("res://scenes/campus_venue.tscn") as PackedScene).instantiate() as Node3D
		again.set("hide_inside_aabb", AABB())
		root.add_child(again)
		var camera := Camera3D.new()
		camera.position = Vector3(-62, 8, -151)
		root.add_child(camera)
		camera.current = true
		var reentry_start := Time.get_ticks_usec()
		while not again.call("is_ready") and Time.get_ticks_usec() - reentry_start < 10000000:
			await process_frame
		await create_timer(1.5).timeout
		_check(again.call("is_ready"), "same stream pack loads again after GPU purge")
		manager = GaussianRenderManager.get_instance()
		_check(manager != null and manager._gpu_state_cache.has_render_states(), "same stream pack rebuilds GPU states after purge")
		again.queue_free()
		camera.queue_free()
		await process_frame
		selector.release_gpu()
	# Cleanup and reentry assertions are also part of the saved report.
	failed = _checks.filter(func(c: Dictionary) -> bool: return not c["ok"])
	report["checks"] = _checks
	report["passed"] = _checks.size() - failed.size()
	report["failed"] = failed.size()
	file = FileAccess.open(_out + "/report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("[rendered] FINAL RESULT %d passed / %d failed" % [report["passed"], report["failed"]])
	await create_timer(.5).timeout
	quit(0 if failed.is_empty() else 1)
