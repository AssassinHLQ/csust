extends SceneTree
## Actual player: five game seconds, same position, no movement or fire while down.
var _passed := 0
var _failed := 0

func _initialize() -> void:
	if DisplayServer.get_name() != "headless" or not OS.get_cmdline_user_args().has("--no-capture"):
		quit(2)
		return
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
	print("[revive] %s %s" % ["PASS" if ok else "FAIL", label])

func _run() -> void:
	AudioServer.set_bus_mute(0, true)
	root.size = Vector2i(1600, 900)
	preload("res://scripts/ui_skin.gd").ui_font().get_string_size("COST 0123456789", HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	await process_frame
	await process_frame
	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, .2, 40)
	cs.shape = box
	ground.add_child(cs)
	world.add_child(ground)
	ground.position.y = -.1
	var player := (load("res://scenes/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	world.add_child(player)
	player.set_process_input(false)
	player.call("set_respawn_point", Vector3(100, 100, 100))
	var carrier := player.get_node("Arisu/CarrierForm")
	Engine.time_scale = 4.0
	for airborne in [false, true]:
		player.global_position = Vector3(3, 12 if airborne else .02, -4)
		player.velocity = Vector3.ZERO
		player.call("set_flight_lock", airborne)
		var at := player.global_transform
		player.call("take_damage", 10000.0)
		_check(player.call("is_downed") and player.get("health") == 0.0, "downed starts immediately airborne=%s" % airborne)
		Input.action_press("move_forward")
		Input.action_press("jump")
		player.call("heal", 1000.0)
		player.call("take_damage", 100.0)
		_check(player.get("health") == 0.0, "healing and repeat damage cannot cancel downed state")
		_check(not player.get("weapon").call("shoot"), "direct weapon firing is blocked while downed")
		var key := InputEventKey.new()
		key.keycode = KEY_G
		key.pressed = true
		var form_before: bool = carrier.call("is_on")
		carrier.call("_input", key)
		_check(carrier.call("is_on") == form_before, "carrier toggle is blocked while downed")
		await create_timer(4.7, false).timeout
		_check(player.call("is_downed") and player.get("health") == 0.0, "cannot revive before five seconds")
		_check(player.global_transform.is_equal_approx(at), "held movement leaves downed transform unchanged")
		paused = true
		await create_timer(.15, true, false, true).timeout
		_check(player.call("is_downed"), "pause freezes the revive countdown")
		paused = false
		Input.action_release("move_forward")
		Input.action_release("jump")
		# Stop gravity for the completion frame so this measures the revive placement.
		player.set_physics_process(false)
		await create_timer(.4, false).timeout
		_check(not player.call("is_downed") and player.get("health") == player.get("max_health"), "five seconds restores full health")
		_check(player.global_transform.is_equal_approx(at), "revive preserves world position and orientation")
		player.set_physics_process(true)
		Input.action_press("move_forward")
		await create_timer(.4, false).timeout
		Input.action_release("move_forward")
		_check(player.global_position.distance_to(at.origin) > .2, "movement resumes after revival")
	_check(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "mouse remains uncaptured")
	world.free()
	Engine.time_scale = 1.0
	print("[revive] RESULT %d passed / %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
