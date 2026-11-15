extends SceneTree
## Headless regression for terrain-based blink landings and airborne recovery.
class TestBoss extends "res://scripts/yuuka_horror_boss.gd":
	func _ready() -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func _blast_fx(_at: Vector3, _play_sound := true) -> void: pass

class TestPlayer extends CharacterBody3D:
	var _facing_yaw := 0.0

var _passed := 0
var _failed := 0

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, label: String, detail: Variant = "") -> void:
	if ok: _passed += 1
	else: _failed += 1
	print("[boss-grounding] ", "PASS " if ok else "FAIL ", label, " ", detail)

func _box(parent: Node3D, at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	body.position = at
	return body

func _run() -> void:
	AudioServer.set_bus_mute(0, true)
	var world := Node3D.new()
	root.add_child(world)
	_box(world, Vector3(0, -0.5, 0), Vector3(160, 1, 160))
	_box(world, Vector3(0, 19.5, 0), Vector3(20, 1, 20))
	var player := TestPlayer.new()
	world.add_child(player)
	player.add_to_group("player")
	var boss := TestBoss.new()
	world.add_child(boss)
	boss._player = player
	boss.position = Vector3(30, 0.05, 0)
	await physics_frame
	await physics_frame
	_check(absf(boss._sample_ground(0, 0)) < 0.01, "walking samples street below overhead roof", boss._sample_ground(0, 0))
	player.position = Vector3(40, 45, 0)
	boss._do_blink(player)
	_check(absf(boss.position.y - 0.05) < 0.01, "blink to flying player lands on terrain", boss.position)
	boss.position = Vector3(30, 0.05, 0)
	player.position = Vector3(0, 60, 0)
	boss._do_blink(player)
	_check(absf(boss.position.y - 0.05) < 0.01, "roof above battle floor cannot raise blink destination", boss.position)
	boss.position = Vector3(30, 0.05, 0)
	var before := boss.position
	player.position = Vector3(300, 80, 300)
	boss._do_blink(player)
	_check(boss.position.is_equal_approx(before), "missing terrain cancels blink instead of creating aerial floor", boss.position)
	boss.position = Vector3(30, 0.05, 0)
	player.position = Vector3(30, 60, 0)
	boss.debug_force_blink()
	var blinks := boss._blinks
	boss._tick_blink(0.016)
	_check(boss._blinks == blinks, "vertical distance alone does not trigger blink")
	boss.position = Vector3(30, 0.05, 0)
	player.position = Vector3(300, 80, 300)
	boss.debug_force_blink()
	boss._tick_blink(0.016)
	_check(boss._blinks == blinks and boss._blink_cd <= 1.0, "cancelled blink neither counts nor spends full cooldown")
	boss.position = Vector3(30, 0.05, 0)
	boss._settle_on_ground(1.0 / 60.0)
	var supported := boss.position
	boss.position.y = 45.0
	boss._settle_on_ground(1.0 / 60.0)
	_check(boss.position.y < 45.0 and boss.position.y > 40.0, "airborne root begins falling without instant snap", boss.position)
	for frame in 180: boss._settle_on_ground(1.0 / 60.0)
	_check(absf(boss.position.y - 0.05) < 0.01, "airborne root returns to supported floor within three seconds", boss.position)
	boss.position = Vector3(300, 45, 300)
	boss._settle_on_ground(1.0 / 60.0)
	_check(boss.position.is_equal_approx(supported), "unsupported root recovers to last verified ground", boss.position)
	var other_boss := _box(world, Vector3(30, 0.5, 0), Vector3(3, 1, 3))
	other_boss.add_to_group("bosses")
	await physics_frame
	await physics_frame
	_check(absf(boss._sample_ground(30, 0)) < 0.01, "other boss collision cannot become terrain", boss._sample_ground(30, 0))
	other_boss.queue_free()
	boss.position = Vector3(79.99, 0.05, 0)
	_check(not boss._walk_step(Vector3.RIGHT, 1.0), "walking rejects unsupported scan edge")
	boss.position = Vector3(30, 0.05, 0)
	player.position = Vector3(77, 45, 0)
	player._facing_yaw = -PI / 2.0
	var moved := boss._do_blink(player)
	_check(moved and absf(boss.position.y - 0.05) < 0.01 and boss.position.x < 79.25, "blink tries nearby ground when exact behind point is outside scan", boss.position)
	await create_timer(1.5).timeout
	world.queue_free()
	await process_frame
	await process_frame
	_check(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "headless regression never captures mouse")
	print("[boss-grounding] RESULT ", _passed, " passed / ", _failed, " failed")
	quit(0 if _failed == 0 else 1)
