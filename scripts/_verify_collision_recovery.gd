extends SceneTree
## Real-player regression: held input at walls must not cause teleport loops.
var _world: Node3D
var _player: CharacterBody3D
var _passed := 0
var _failed := 0

func _initialize() -> void:
	if DisplayServer.get_name() != "headless" or not OS.get_cmdline_user_args().has("--no-capture"):
		quit(2)
		return
	_run.call_deferred()

func _box(size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	_world.add_child(body)
	body.position = at
	return body

func _check(ok: bool, label: String, detail: Variant = "") -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
	print("[recovery] %s %s %s" % ["PASS" if ok else "FAIL", label, detail])

func _tick(frames: int) -> void:
	for i in frames:
		await physics_frame
		_player.call("_physics_process", 1.0 / 60)

func _reset(at: Vector3) -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right", "sprint", "jump"]:
		Input.action_release(action)
	_player.position = at + Vector3.UP * .05
	_player.velocity = Vector3.ZERO
	_player.set("_yaw", 0.0)
	(_player.get("rig") as Node3D).rotation.y = 0.0
	_player.set("_stuck_t", 0.0)
	_player.set("_unstick_cool", 0.0)
	_player.set("_blocked_last_frame", false)
	await _tick(60)

func _run() -> void:
	AudioServer.set_bus_mute(0, true)
	_world = Node3D.new()
	root.add_child(_world)
	_box(Vector3(30, .2, 30), Vector3(0, -.1, 0))
	_box(Vector3(10, 3, .05), Vector3(0, 1.5, -2))
	var side := _box(Vector3(.05, 3, 10), Vector3(2, 1.5, 0))
	_player = (load("res://scenes/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	_player.safe_margin = .004
	_world.add_child(_player)
	_player.set_physics_process(false)
	_player.set_process_input(false)
	_player.set_process_unhandled_input(false)
	_player.get_node("Arisu/CarrierForm").process_mode = Node.PROCESS_MODE_DISABLED
	await _reset(Vector3.ZERO)
	Input.action_press("move_forward")
	await _tick(100)
	var contact := _player.global_position
	var max_shift := 0.0
	for i in 180:
		await _tick(1)
		max_shift = maxf(max_shift, _player.global_position.distance_to(contact))
	_check(max_shift < .04, "holding against one wall has no backward teleport loop", max_shift)
	_check(_player.global_position.z > -1.72, "thin wall cannot be crossed by recovery", _player.global_position)
	Input.action_release("move_forward")
	Input.action_press("move_back")
	await _tick(100)
	_check(_player.global_position.z - contact.z > 3.0, "reverse input leaves wall without jumping", _player.global_position)
	await _reset(Vector3(1, 0, -1))
	Input.action_press("move_forward")
	Input.action_press("move_right")
	await _tick(100)
	contact = _player.global_position
	max_shift = 0.0
	for i in 180:
		await _tick(1)
		max_shift = maxf(max_shift, _player.global_position.distance_to(contact))
	_check(max_shift < .06, "ordinary right-angle corner does not oscillate", max_shift)
	Input.action_release("move_forward")
	Input.action_release("move_right")
	Input.action_press("move_back")
	Input.action_press("move_left")
	await _tick(100)
	_check(_player.global_position.distance_to(contact) > 3.0, "diagonal reverse leaves corner without jumping", _player.global_position)
	_check(_player.global_position.y > -.1 and _player.is_on_floor(), "recovery stays on supported ground")
	_check(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "mouse remains uncaptured")
	side.free()
	print("[recovery] RESULT %d passed / %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
