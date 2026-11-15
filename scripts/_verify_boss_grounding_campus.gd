extends SceneTree
## Run with tools/run_godot_private_desktop.py; never opens on the input desktop.
const OffWin := preload("res://scripts/offscreen_window.gd")
const Settings := preload("res://scripts/game_settings.gd")
var _passed := 0
var _failed := 0

func _initialize() -> void:
	if not OS.get_cmdline_user_args().has("--no-capture"):
		quit(2)
		return
	_run.call_deferred()

func _check(ok: bool, label: String, detail: Variant = "") -> void:
	if ok: _passed += 1
	else: _failed += 1
	print("[boss-grounding-campus] ", "PASS " if ok else "FAIL ", label, " ", detail)

func _run() -> void:
	await OffWin.apply(self, Vector2i(1280, 720))
	AudioServer.set_bus_mute(0, true)
	preload("res://scripts/render_env.gd").capture_override = true
	Settings.set_value("window_mode", "windowed")
	Settings.set_value("boss_attack", false)
	Settings.set_value("companion_fire", false)
	var world := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(world)
	current_scene = world
	var player := world.get_node("Player") as CharacterBody3D
	player.position = Vector3(-100, 3.66, -265.6)
	player.velocity = Vector3.ZERO
	player.set("max_health", 1.0e9)
	player.set("health", 1.0e9)
	await create_timer(3.0).timeout
	await OffWin.apply(self, Vector2i(1280, 720))
	_check(player.is_on_floor(), "actual player starts on scanned street", player.position)
	var street := player.global_position
	player.set_physics_process(false)
	world.set("_final_started", true)
	world.call("_begin_final_phase")
	var boss: Node3D
	var deadline := Time.get_ticks_msec() + 20000
	while boss == null and Time.get_ticks_msec() < deadline:
		for node in get_nodes_in_group("bosses"):
			if node.get_script().resource_path == "res://scripts/yuuka_horror_boss.gd":
				boss = node
		await process_frame
	_check(boss != null, "production final Boss appears")
	if boss == null:
		quit(1)
		return
	boss.call("debug_set_chase", false)
	boss.call("debug_set_blink_cd", 999.0)
	boss.set("max_health", 1.0e9)
	boss.set("health", 1.0e9)
	boss.global_position = street
	await create_timer(0.2).timeout
	for height in [15.0, 45.0, 90.0, 160.0]:
		player.global_position = street + Vector3(0, height, 7)
		player.set("_facing_yaw", 0.0)
		var moved := bool(boss.call("_do_blink", player))
		_check(moved, "airborne player still permits a supported blink", height)
		var ground := float(boss.call("_sample_ground", boss.position.x, boss.position.z))
		_check(not is_nan(ground) and absf(boss.position.y - ground - 0.05) < 0.02,
			"blink stays on scanned terrain at every flight altitude", [height, boss.position])
		await create_timer(0.2).timeout
	var before := boss.global_position
	player.global_position = Vector3(2000, 100, 2000)
	_check(not bool(boss.call("_do_blink", player)) and boss.global_position.is_equal_approx(before),
		"scan boundary rejects unsupported blink")
	player.global_position = street + Vector3(0, 50, 0)
	boss.set("_busy", true)
	boss.global_position = street + Vector3.UP * 35.0
	await create_timer(0.15).timeout
	_check(boss.position.y < street.y + 35.0 and boss.position.y > street.y + 30.0,
		"production physics lowers an airborne root during skill lock", boss.position)
	await create_timer(2.5).timeout
	_check(absf(boss.position.y - street.y) < 0.1, "airborne root lands back on campus street", boss.position)
	boss.set("_busy", false)
	var visual := boss.get("model") as Node3D
	var rest_y := visual.position.y
	boss.call("debug_cast", "leapslam")
	await create_timer(0.5).timeout
	_check(visual.position.y > rest_y + 1.0 and absf(boss.position.y - street.y) < 0.1,
		"legitimate leap visual remains intact over grounded root")
	await create_timer(2.0).timeout
	_check(absf(visual.position.y - rest_y) < 0.01, "leap visual returns to rest height")
	await boss.call("debug_cast", "clones")
	var clones: Array = boss.get("_clones")
	_check(clones.size() == 10, "airborne player still receives ten grounded clone summons", clones.size())
	var airborne := 0
	for clone in clones:
		if clone.global_position.y > street.y + 8.0: airborne += 1
	_check(airborne == 0, "clone summons never inherit aircraft altitude", airborne)
	boss.call("debug_reset")
	boss.global_position = Vector3(-42, 4.09, -140)
	player.global_position = Vector3(-82, 4.69, -140)
	boss.call("debug_set_chase", true)
	var distance := boss.position.distance_to(player.position)
	await create_timer(3.5).timeout
	_check(boss.position.distance_to(player.position) < distance - 1.5,
		"scan fragments cannot pin normal ground pursuit", boss.position)
	boss.call("debug_set_chase", false)
	boss.global_position = Vector3(-42, 4.09, -140)
	player.global_position = Vector3(-76, 4.69, -140)
	var blinked := bool(boss.call("_do_blink", player))
	var behind := boss.global_position - player.global_position
	_check(blinked and behind.length() < 12.0 and Vector3.BACK.dot(behind.normalized()) < -0.2,
		"supported blink still prefers behind the player", boss.position)
	_check(OffWin.is_safe()[0], "private scene probe leaves input desktop and mouse alone")
	world.queue_free()
	await process_frame
	await process_frame
	print("[boss-grounding-campus] RESULT ", _passed, " passed / ", _failed, " failed")
	quit(0 if _failed == 0 else 1)
