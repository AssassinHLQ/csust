extends SceneTree
const OffWin := preload("res://scripts/offscreen_window.gd")
const Settings := preload("res://scripts/game_settings.gd")
var _passed := 0
var _failed := 0
var _world: Node3D

func _initialize() -> void:
	if not OS.get_cmdline_user_args().has("--no-capture"):
		quit(2)
		return
	_run.call_deferred()

func _check(ok: bool, label: String, detail: Variant = "") -> void:
	if ok: _passed += 1
	else: _failed += 1
	print("[boss-mobility] ", "PASS " if ok else "FAIL ", label, " ", detail)

func _run() -> void:
	await OffWin.apply(self, Vector2i(1280, 720))
	preload("res://scripts/render_env.gd").capture_override = true
	Settings.set_value("window_mode", "windowed")
	Settings.set_value("boss_attack", false)
	Settings.set_value("companion_attack", true)
	_world = (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(_world)
	current_scene = _world
	var player := _world.get_node("Player") as CharacterBody3D
	player.position = Vector3(-100, 3.66, -265.6)
	player.velocity = Vector3.ZERO
	player.set("max_health", 1.0e9)
	player.set("health", 1.0e9)
	await create_timer(3).timeout
	await OffWin.apply(self, Vector2i(1280, 720))
	_check(player.is_on_floor(), "real player begins on scanned campus street", player.position)
	var surface := player.position
	var carrier := player.get_node("Arisu/CarrierForm")
	preload("res://scripts/mech_state.gd").set_carrier_for_test(true)
	_check(carrier.call("set_form", true), "actual mech form activates")
	await create_timer(1.0).timeout
	player.position = surface + Vector3.DOWN * 2.2
	player.velocity = Vector3.ZERO
	Input.action_press("jump")
	await create_timer(2.0).timeout
	Input.action_release("jump")
	_check(player.position.y > surface.y + 1.0, "real mech ascends through scanned street from below", player.position)
	Input.action_press("crouch")
	await create_timer(3.0).timeout
	Input.action_release("crouch")
	_check(player.is_on_floor() and absf(player.position.y - surface.y) < 0.15, "real mech lands on top of same street", player.position)
	await create_timer(1.0).timeout
	_check(player.is_on_floor() and player.position.y >= surface.y - 0.1, "restored collision keeps standing mech above scan")
	_check(player.get_collision_exceptions().is_empty(), "real player has no scan exceptions after landing")
	_world.set("_final_started", true)
	_world.call("_begin_final_phase")
	var boss: Node3D
	var deadline := Time.get_ticks_msec() + 20000
	while boss == null and Time.get_ticks_msec() < deadline:
		for node in get_nodes_in_group("bosses"):
			if node.get_script().resource_path == "res://scripts/yuuka_horror_boss.gd":
				boss = node
				boss.set("max_health", 1.0e9)
				boss.set("health", 1.0e9)
		await process_frame
	_check(boss != null, "production finale spawns boss")
	var party: Array = _world.get("_party")
	_check(party.size() == 4, "four production companions join when boss appears")
	await create_timer(4.0).timeout
	var positions: Array[Vector3] = []
	var shots_before := 0
	for companion in party:
		var status: Dictionary = companion.call("combat_status")
		_check(status.ready and companion.is_on_floor(), "production companion finds stable scanned firing position", companion.position)
		positions.append(companion.position)
		shots_before += int(companion.get_node("Gun").get("_shots"))
	_check(shots_before > 0, "party fires from independent grounded positions", shots_before)
	player.position += Vector3(45, 45, 0)
	player.velocity = Vector3.ZERO
	Input.action_press("jump")
	await create_timer(3.0).timeout
	Input.action_release("jump")
	var shots_after := 0
	for index in party.size():
		var companion: CharacterBody3D = party[index]
		_check(companion.is_on_floor() and companion.position.y > -5, "flying player leaves party safely grounded", companion.position)
		var status: Dictionary = companion.call("combat_status")
		_check(companion.position.distance_to(player.position) > 30.0 \
				and (status.destination as Vector3).distance_to(boss.position) < 40.0,
			"party stays in boss firing range instead of chasing flying player", index)
		shots_after += int(companion.get_node("Gun").get("_shots"))
	_check(shots_after > shots_before, "party continues shooting while player flies", [shots_before, shots_after])
	var stream := preload("res://scripts/music.gd")._load_stream("finalboss") as AudioStreamOggVorbis
	_check(stream != null and absf(stream.get_length() - 116.2666) < 0.03 and stream.loop and stream.loop_offset == 0.0,
		"production boss music uses trimmed duration and loops from start", stream.get_length() if stream else 0)
	_check(OffWin.is_safe()[0], "offscreen window and uncaptured mouse")
	_world.queue_free()
	await process_frame
	await process_frame
	print("[boss-mobility] RESULT ", _passed, " passed / ", _failed, " failed")
	quit(0 if _failed == 0 else 1)
