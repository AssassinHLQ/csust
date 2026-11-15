extends "res://scripts/_profile_campus_full.gd"
## Rendered combat diagnosis. Launch on an inactive desktop; never launch directly.
var _world: Node3D
var _player: CharacterBody3D
var _campus: Node3D
var _boss: Node3D
var _camera: Camera3D
var _battle_results: Dictionary = {}
var _battle_seconds := 6.0
var _shots := false
var _look_away := false
var _walking := false
var _walk_target := 1
var _walk_points: Array[Vector3] = [Vector3(-100, 3.36, -265.6), Vector3(-92, 3.26, -265.6)]

func _initialize() -> void:
	_out = "res://_tools/_tmp/boss_performance/baseline"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--battle-seconds="): _battle_seconds = float(arg.trim_prefix("--battle-seconds="))
		if arg == "--battle-shots": _shots = true
	super._initialize()
	ProjectSettings.set_setting("gsplat/rendering/static_frame_cache", true)

func _run() -> void:
	seed(73151)
	DirAccess.make_dir_recursive_absolute(_out)
	preload("res://scripts/render_env.gd").capture_override = true
	preload("res://scripts/game_settings.gd").set_value("window_mode", "windowed")
	preload("res://scripts/game_settings.gd").set_value("boss_attack", true)
	await OffWin.apply(self, Vector2i(1600, 900))
	_world = (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(_world)
	current_scene = _world
	_player = _world.get_node("Player")
	_campus = _world.get_node("Campus")
	_campus.set("hide_inside_aabb", AABB())
	_player.global_position = _walk_points[0] + Vector3.UP * .3
	_player.velocity = Vector3.ZERO
	_player.set("max_health", 1.0e9)
	_player.set("health", 1.0e9)
	_campus.call("force_start")
	_camera = Camera3D.new()
	_camera.fov = 62
	_camera.far = 3000
	root.add_child(_camera)
	_camera.current = true
	var deadline := Time.get_ticks_msec() + 60000
	while not _campus.call("is_ready") and Time.get_ticks_msec() < deadline:
		_aim()
		await process_frame
	_check(bool(_campus.call("is_ready")), "full campus loads")
	await create_timer(2.0).timeout
	await OffWin.apply(self, Vector2i(1600, 900))
	_check(_player.is_on_floor() and _player.position.y > -5.0, "player starts on verified scanned street")
	# Real players defeat loaded dinosaurs. Killing unbooted targets schedules
	# their delayed model creation in the middle of the final boss sample.
	for node in get_nodes_in_group("bosses"):
		if _world.is_ancestor_of(node): node.call("_boot")
	await create_timer(1.0).timeout
	# Keep the production 60 FPS cap for end-to-end frame pacing.
	for node in get_nodes_in_group("bosses"):
		if _world.is_ancestor_of(node): node.call("take_damage", 1.0e9)
	var spawn_start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - spawn_start < 20000:
		var lock := _world.get_node_or_null("ArenaLock")
		if lock != null: _boss = lock.get_node_or_null("YuukaHorror")
		if _boss != null: break
		_aim()
		await process_frame
	_check(_boss != null, "production finale spawns boss and party")
	if _boss == null:
		quit(1)
		return
	_boss.set("max_health", 1.0e9)
	_boss.set("health", 1.0e9)
	_boss.set("_t_skill", 10000.0)
	await _sample_battle("phase1_firing", _battle_seconds)
	for kind in ["rapid", "shock", "meteor", "beam"]:
		_boss.call("debug_cast", kind)
		await _sample_battle("phase1_" + kind, 4.0)
	_boss.call("debug_reset")
	await create_timer(1.0).timeout
	_boss.call("debug_cast", "clones")
	await _sample_battle("clone_spawn", _battle_seconds)
	_check(int(_battle_results.clone_spawn.peak_clone_count) == 10, "all ten clones spawn before companions defeat them")
	var clones: Array = _boss.get("_clones")
	for clone in clones:
		if is_instance_valid(clone): (clone.get("model") as Node3D).visible = false
	await _sample_battle("clones_render_hidden", 4.0)
	for clone in clones:
		if is_instance_valid(clone): (clone.get("model") as Node3D).visible = true
	await _sample_battle("clones_render_restored", 4.0)
	_boss.call("debug_cast", "pigs")
	await _sample_battle("pigs_and_clones", _battle_seconds)
	_boss.call("debug_reset")
	await create_timer(1.0).timeout
	_boss.call("take_damage", 1.0e12)
	await _sample_battle("phase2_revive", 4.0)
	_boss.call("debug_finish_revive")
	_check(int(_boss.call("status").phase) == 2, "boss enters second phase")
	for kind in ["clones", "pigs", "rapid", "meteor", "shock", "beam"]:
		if kind == "clones": _boss.set("_clone_cd", 0.0)
		_boss.call("debug_cast", kind)
		await _sample_battle("phase2_" + kind, 4.0)
	_walking = true
	_boss.set("_t_skill", 0.0)
	await _sample_battle("phase2_walk_and_fight", 20.0)
	_walking = false
	_release_movement()
	var before_turn: Dictionary = _campus.call("debug_state")
	_look_away = true
	await _sample_battle("look_at_sky", 1.0)
	_look_away = false
	await _sample_battle("return_to_fight", 2.0)
	var state: Dictionary = _campus.call("debug_state")
	_check(not bool(state.lod_enabled) and int(state.resident_splats) == int(state.source_splats), "every source point remains resident with LOD off")
	_check(int(state.loads_completed) == int(before_turn.loads_completed) and int(state.evictions) == 0, "sky turn never reloads the full campus payload")
	for label in _battle_results:
		_check(int(_battle_results[label].min_resident_splats) == int(state.source_splats), label + " keeps all source points resident")
		_check(float(_battle_results[label].min_player_y) > -5.0, label + " player never falls out of scanned terrain")
	_check(bool(OffWin.is_safe()[0]), "offscreen window and uncaptured mouse")
	var warmup := root.get_node_or_null("BattleAssetWarmup")
	_check(warmup != null and int(warmup.call("status").held) == 6, "summoned resources remain warm for repeated casts")
	_world.queue_free()
	_camera.queue_free()
	await process_frame
	preload("res://addons/gdgs/runtime/render/backend/gaussian_backend_selector.gd").release_gpu()
	await create_timer(1.5).timeout
	_check(root.get_node_or_null("BattleAssetWarmup") == null, "leaving arena releases warmup resources")
	var failed := _checks.filter(func(c: Dictionary) -> bool: return not c.ok)
	var report := {"passed": _checks.size() - failed.size(), "failed": failed.size(), "checks": _checks,
		"resolution": str(root.size), "fps_cap": Engine.max_fps, "gpu": RenderingServer.get_video_adapter_name(),
		"campus": state, "samples": _battle_results,
		"scope": "Production finale, four active companions, live attacks and collision; scripted casts and camera, raised test health, 60 FPS cap, private desktop. Shader timestamps enabled. TIME_PROCESS monitors are periodic and may include preceding loading/readbacks, not contemporaneous per-frame CPU timing. Optional screenshots occur outside samples. Not manual gameplay or packaged executable."}
	FileAccess.open(_out + "/report.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("[boss-profile] RESULT ", report.passed, " passed / ", report.failed, " failed")
	quit(0 if failed.is_empty() else 1)

func _aim() -> void:
	if _camera == null: return
	var at := _player.global_position
	_camera.position = at + Vector3(0, 7, 13)
	var target := at + Vector3(0, 7, -25)
	if is_instance_valid(_boss): target = _boss.global_position + Vector3.UP * 7
	if _look_away: target = _camera.position + Vector3(0, 1, -.1)
	_camera.look_at(target)
	var direction := target - at
	_player.set("_yaw", atan2(-direction.x, -direction.z))
	_player.set("_pitch", -.12)

func _sample_battle(label: String, seconds: float) -> void:
	print("[boss-profile] PHASE ", label)
	while _pending: await process_frame
	_stages.clear()
	_seen.clear()
	var frames: Array = []
	var cpu: Array = []
	var physics: Array = []
	var calls: Array = []
	var primitives: Array = []
	var start := Time.get_ticks_usec()
	var previous := start
	var player_health: float = _player.get("health")
	var peak_clone_count := 0
	var min_resident_splats := 9223372036854775807
	var min_player_y := INF
	var spikes: Array = []
	var pipelines_before := _pipeline_counts()
	var weapon := _player.get_node("Weapon")
	weapon.call("trigger_down")
	while Time.get_ticks_usec() - start < int(seconds * 1.0e6):
		if _walking: _walk()
		_aim()
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - previous) / 1000.0)
		previous = now
		if frames.back() > 40.0 and spikes.size() < 12:
			spikes.append({"ms": frames.back(), "second": (now - start) / 1.0e6,
				"pipelines": _pipeline_counts(), "orbs": int(_boss.call("status").orbs)})
		peak_clone_count = maxi(peak_clone_count, (_boss.get("_clones") as Array).size())
		min_resident_splats = mini(min_resident_splats, int(_campus.call("debug_state").resident_splats))
		min_player_y = minf(min_player_y, _player.global_position.y)
		cpu.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		_read_timestamps()
	weapon.call("trigger_up")
	await process_frame
	var result := {"frames": _statistics(frames), "cpu_ms": _statistics(cpu), "physics_ms": _statistics(physics),
		"draw_calls": _statistics(calls), "primitives": _statistics(primitives), "gpu_ms": _stage_statistics(),
		"boss": _boss.call("status"), "peak_clone_count": peak_clone_count, "damage_received": player_health - float(_player.get("health")),
		"min_resident_splats": min_resident_splats, "player_position": str(_player.global_position), "camera_position": str(_camera.global_position)}
	result["min_player_y"] = min_player_y
	result["pipelines_before"] = pipelines_before
	result["pipelines_after"] = _pipeline_counts()
	result["spikes_over_40ms"] = spikes
	_battle_results[label] = result
	print("[boss-profile] SAMPLE ", label, " ", JSON.stringify(result))
	if _shots:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(_out + "/" + label + ".png")

func _statistics(values: Array) -> Dictionary:
	var result := super._statistics(values)
	if not values.is_empty(): result["max"] = values.max()
	return result

func _pipeline_counts() -> Dictionary:
	return {"mesh": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH),
		"surface": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE),
		"draw": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW),
		"specialization": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION)}

func _walk() -> void:
	var offset := _walk_points[_walk_target] - _player.global_position
	offset.y = 0.0
	if offset.length() < .5:
		_walk_target = 1 - _walk_target
		offset = _walk_points[_walk_target] - _player.global_position
		offset.y = 0.0
	var rig: Node3D = _player.get_node("CameraRig")
	var local := rig.global_basis.inverse() * offset.normalized()
	_release_movement()
	if local.x > .01: Input.action_press("move_right", local.x)
	if local.x < -.01: Input.action_press("move_left", -local.x)
	if local.z > .01: Input.action_press("move_back", local.z)
	if local.z < -.01: Input.action_press("move_forward", -local.z)

func _release_movement() -> void:
	for action in ["move_left", "move_right", "move_forward", "move_back"]: Input.action_release(action)
