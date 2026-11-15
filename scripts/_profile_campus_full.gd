extends SceneTree
## GPU stage attribution in the production scene. Use the private desktop launcher.
const OffWin := preload("res://scripts/offscreen_window.gd")
const Manager := preload("res://addons/gdgs/runtime/render/compute/gaussian_render_manager.gd")
var _out := "res://_tools/_tmp/gsplat_stream/profile_full"
var _tile := 0
var _seconds := 4.0
var _stages: Dictionary = {}
var _seen: Dictionary = {}
var _pending := false
var _read_done := false
var _counts: Array = []
var _compare := false
var _checks: Array = []

func _initialize() -> void:
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--no-capture"):
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--profile-out="): _out = arg.trim_prefix("--profile-out=")
		if arg.begins_with("--profile-tile="): _tile = int(arg.trim_prefix("--profile-tile="))
		if arg.begins_with("--profile-seconds="): _seconds = float(arg.trim_prefix("--profile-seconds="))
		if arg == "--profile-compare": _compare = true
	ProjectSettings.set_setting("gsplat/rendering/profile_gpu_timestamps", true)
	ProjectSettings.set_setting("gsplat/rendering/static_frame_cache", false)
	ProjectSettings.set_setting("gsplat/rendering/force_tile_size", _tile)
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	preload("res://scripts/render_env.gd").capture_override = true
	preload("res://scripts/game_settings.gd").set_value("window_mode", "windowed")
	await OffWin.apply(self, Vector2i(1600, 900))
	var world := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(world)
	current_scene = world
	var campus := world.get_node("Campus")
	campus.set("hide_inside_aabb", AABB())
	for node in [world] + world.find_children("*", "Node", true, false):
		if node == campus or campus.is_ancestor_of(node): continue
		node.set_process(false)
		node.set_physics_process(false)
		node.set_process_input(false)
		if node is Timer: node.stop()
		if node is Area3D: node.set_deferred("monitoring", false)
	var old_camera := root.get_camera_3d()
	var camera := Camera3D.new()
	camera.fov = old_camera.fov
	camera.near = old_camera.near
	camera.far = old_camera.far
	root.add_child(camera)
	camera.current = true
	camera.position = Vector3(-62.47, 6.90, -151.27)
	camera.rotation = Vector3(-.04, -.01312, 0)
	campus.call("force_start")
	var deadline := Time.get_ticks_msec() + 60000
	while not campus.call("is_ready") and Time.get_ticks_msec() < deadline:
		await process_frame
	if not campus.call("is_ready"):
		push_error("[profile-full] campus did not become ready")
		quit(1)
		return
	await create_timer(4.0).timeout
	await OffWin.apply(self, Vector2i(1600, 900))
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var results := {}
	var views := [Vector3(-62.47, 6.90, -151.27), Vector3(-100, 5.15, -265.6), Vector3(-4, 8.49, -235)]
	var variants: Array = [_tile]
	if _compare: variants = [8, 16, 8, 16]
	for sample_index in range(views.size() * variants.size()):
		var index := sample_index % views.size()
		var round_index := sample_index / views.size()
		if index == 0 and _compare:
			ProjectSettings.set_setting("gsplat/rendering/force_tile_size", variants[round_index])
			RenderingServer.call_on_render_thread(func(): Manager.get_instance()._gpu_state_cache.mark_all_render_states_needs_gpu_rebuild())
			await create_timer(2.0).timeout
		camera.position = views[index]
		camera.rotation.y = -.01312 if index == 0 else -PI / 2
		await create_timer(1.0).timeout
		while _pending: await process_frame
		_stages.clear()
		_seen.clear()
		var frames: Array = []
		var start := Time.get_ticks_usec()
		var previous := start
		while Time.get_ticks_usec() - start < int(_seconds * 1000000):
			await process_frame
			var now := Time.get_ticks_usec()
			frames.append((now - previous) / 1000.0)
			previous = now
			_read_timestamps()
		await process_frame
		await _read_counts()
		var label := "%d_%d" % [round_index, index] if _compare else str(index)
		_check(not frames.is_empty() and _stages.has("sort"), label + " has frame and GPU samples")
		_check(not _counts.is_empty(), label + " has GPU counters")
		for count in _counts:
			_check(int(count.sort) < int(count.sort_capacity), label + " sort capacity does not truncate points")
			_check(int(count.culled) < int(count.culled_capacity), label + " visible capacity does not truncate points")
			var expected_tile := int(variants[round_index])
			if expected_tile == 0: expected_tile = 16
			_check(int(count.tile) == expected_tile, label + " uses requested or automatic full-detail tile size")
		results[label] = {"tile_override": variants[round_index], "frames": _statistics(frames), "gpu_ms": _stage_statistics(), "counts": _counts.duplicate(true)}
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(_out + "/view_%s.png" % label)
	var campus_state: Dictionary = campus.call("debug_state")
	_check(not bool(campus_state.get("lod_enabled", true)), "LOD remains off")
	_check(int(campus_state.resident_splats) == int(campus_state.source_splats), "every source point stays resident")
	_check(bool(campus_state.world_transform_identity), "original world coordinates remain unchanged")
	_check(bool(OffWin.is_safe()[0]), "test window stays off screen without mouse capture")
	var failed := _checks.filter(func(check: Dictionary) -> bool: return not check.ok)
	var report := {"tile_override": _tile, "resolution": str(root.size), "gpu": RenderingServer.get_video_adapter_name(),
		"campus": campus_state, "views": results, "checks": _checks, "failed": failed.size(), "passed": _checks.size() - failed.size(),
		"safe_window": OffWin.is_safe(), "scope": "Uncapped fixed camera, full production scene meshes, combat/logic frozen, no static-frame cache; stage diagnosis, not gameplay certification."}
	FileAccess.open(_out + "/report.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("[profile-full] ", JSON.stringify(report))
	world.queue_free()
	camera.queue_free()
	await process_frame
	preload("res://addons/gdgs/runtime/render/backend/gaussian_backend_selector.gd").release_gpu()
	quit(0 if failed.is_empty() else 1)

func _check(ok: bool, label: String) -> void:
	_checks.append({"ok": ok, "label": label})
	if not ok: push_error("[profile-full] " + label)

func _read_timestamps() -> void:
	if _pending: return
	_pending = true
	RenderingServer.call_on_render_thread(func():
		var rd := RenderingServer.get_rendering_device()
		var frame := rd.get_captured_timestamps_frame()
		if not _seen.has(frame):
			var stamps := {}
			for i in rd.get_captured_timestamps_count():
				stamps[rd.get_captured_timestamp_name(i)] = rd.get_captured_timestamp_gpu_time(i)
			if stamps.has("gdgs/start") and stamps.has("gdgs/render"):
				_seen[frame] = true
				var previous: int = stamps["gdgs/start"]
				for stage in ["setup", "projection", "sort", "boundaries", "render"]:
					var stamp: int = stamps["gdgs/" + stage]
					if not _stages.has(stage): _stages[stage] = []
					_stages[stage].append((stamp - previous) * 1e-6)
					previous = stamp
		_pending = false)

func _read_counts() -> void:
	_counts.clear()
	_read_done = false
	RenderingServer.call_on_render_thread(func():
		for state in Manager.get_instance()._gpu_state_cache._render_states.values():
			var rd: RenderingDevice = state.context.device
			_counts.append({"tile": state.render_tile_size,
				"sort": rd.buffer_get_data(state.descriptors.histogram.rid, 0, 4).decode_u32(0),
				"sort_capacity": state.sort_elements_max,
				"culled": rd.buffer_get_data(state.descriptors.culled_counter.rid, 0, 4).decode_u32(0),
				"culled_capacity": state.culled_entries_max})
		_read_done = true)
	while not _read_done: await process_frame

func _stage_statistics() -> Dictionary:
	var result := {}
	for stage in _stages: result[stage] = _statistics(_stages[stage])
	return result

func _statistics(values: Array) -> Dictionary:
	if values.is_empty(): return {}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value in sorted: total += float(value)
	return {"mean": total / sorted.size(), "p50": sorted[sorted.size() / 2],
		"p95": sorted[int((sorted.size() - 1) * .95)], "samples": sorted.size(), "fps": sorted.size() * 1000.0 / maxf(total, .001)}
