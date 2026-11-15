extends SceneTree
class CombatCompanion extends "res://scripts/companion.gd":
	func _ready() -> void:
		collision_layer = 2
		collision_mask = 1

class CombatGun extends "res://scripts/companion_gun.gd":
	func _spawn_tracer(_from: Vector3, _to: Vector3) -> void: pass
	func _muzzle_flash(_color: Color, _size: float) -> void: pass
	func _impact_spark(_at: Vector3, _color: Color, _size: float) -> void: pass
	func _play_attack() -> void: pass

class Enemy extends StaticBody3D:
	var height := 10.0
	var _dead := false
	var damage := 0.0
	func take_damage(amount: float, _at: Vector3, _direction: Vector3) -> void: damage += amount

var _passed := 0
var _failed := 0

func _initialize() -> void: _run.call_deferred()
func _check(ok: bool, label: String, detail: Variant = "") -> void:
	if ok: _passed += 1
	else: _failed += 1
	print("[combat-position] ", "PASS " if ok else "FAIL ", label, " ", detail)

func _shape(body: PhysicsBody3D, size: Vector3, at: Vector3) -> void:
	var cs := CollisionShape3D.new()
	cs.name = "Collision"
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = at
	body.add_child(cs)

func _ticks(count: int) -> void:
	for frame in count: await physics_frame

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	_shape(ground, Vector3(48, 0.2, 48), Vector3(0, -0.1, 0))
	world.add_child(ground)
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	world.add_child(player)
	var enemy := Enemy.new()
	_shape(enemy, Vector3(2, 10, 2), Vector3(0, 5, 0))
	enemy.add_to_group("bosses")
	world.add_child(enemy)
	await _ticks(2)
	var party: Array[CombatCompanion] = []
	for index in 4:
		var companion := CombatCompanion.new()
		_shape(companion, Vector3(0.6, 1.5, 0.6), Vector3(0, 0.75, 0))
		var gun := CombatGun.new()
		gun.name = "Gun"
		companion.add_child(gun)
		world.add_child(companion)
		companion.global_position = Vector3(40, 30, 0)
		companion.start_combat(enemy, index)
		party.append(companion)
		_check(companion.combat_status().ready, "companion finds a supported firing position", index)
	await _ticks(120)
	var positions: Array[Vector3] = []
	for companion in party:
		positions.append(companion.global_position)
		_check(companion.is_on_floor() and absf(companion.position.y) < 0.06, "companion grounded instead of copying player altitude", companion.position)
	_check(enemy.damage > 0.0, "independent positions face enemy and deal real ray-confirmed damage", enemy.damage)
	player.global_position = Vector3(200, 80, -200)
	await _ticks(180)
	for index in party.size():
		_check(party[index].position.distance_to(positions[index]) < 0.1, "flying player never pulls companion off its firing position", index)
	for first in party.size():
		for second in range(first + 1, party.size()):
			_check(party[first].position.distance_to(party[second].position) > 2.0, "party uses separate firing positions")
	var displaced := party[0]
	displaced.position = Vector3(25, 0, 0)
	await _ticks(150)
	_check(displaced.is_on_floor() and displaced.position.y > -0.1, "ledge fall rescues to last verified ground", displaced.position)
	_check(displaced.position.distance_to(player.position) > 100, "fall rescue never follows airborne player")
	var damage_before := enemy.damage
	await _ticks(120)
	_check(enemy.damage > damage_before, "party keeps attacking while player flies elsewhere")
	world.queue_free()
	await process_frame
	_check(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "mouse remains uncaptured")
	print("[combat-position] RESULT ", _passed, " passed / ", _failed, " failed")
	quit(0 if _failed == 0 else 1)
