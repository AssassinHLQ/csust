extends SceneTree
## Regression for cheap candidate rejection and frame-local aim reuse.
class TargetStub extends Node3D:
	var height := 10.0
	var _dead := false
	var damage := 0.0
	func take_damage(amount: float, _at := Vector3.ZERO, _direction := Vector3.ZERO) -> void:
		damage += amount

class GunProbe extends "res://scripts/companion_gun.gd":
	var ray_calls := 0
	var blocked := false
	var victim: Node3D
	var origin := Vector3.ZERO
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func muzzle_position() -> Vector3: return origin
	func _face_dir() -> Vector3: return Vector3.FORWARD
	func _ray(_from: Vector3, to: Vector3) -> Dictionary:
		ray_calls += 1
		return {} if blocked else {"collider": victim, "position": to}
	func _spawn_tracer(_from: Vector3, _to: Vector3) -> void: pass
	func _muzzle_flash(_color: Color, _size: float) -> void: pass
	func _impact_spark(_at: Vector3, _color: Color, _size: float) -> void: pass
	func _play_attack() -> void: pass

var _failed := 0
var _passed := 0

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, label: String) -> void:
	if ok: _passed += 1
	else:
		_failed += 1
		push_error("[companion-targeting] " + label)

func _run() -> void:
	var gun := GunProbe.new()
	var target := TargetStub.new()
	root.add_child(gun)
	root.add_child(target)
	target.position = Vector3(0, 0, -20)
	gun.victim = target
	var first := gun._aim_point(target)
	_check(gun.ray_calls == 1, "first candidate uses real visibility query")
	_check(gun._aim_point(target) == first and gun.ray_calls == 1, "same-frame repeated aim reuses point")
	gun._has_line_of_sight(target)
	_check(gun.ray_calls == 2, "line of sight still has a fresh authoritative query")
	target.position.x = 1.0
	gun._aim_point(target)
	_check(gun.ray_calls == 3, "same-frame target movement invalidates aim")
	gun.origin.x = 1.0
	gun._aim_point(target)
	_check(gun.ray_calls == 4, "same-frame muzzle movement invalidates aim")
	target.height = 12.0
	gun._aim_point(target)
	_check(gun.ray_calls == 5, "height change invalidates aim")
	gun.blocked = true
	gun._fire(target)
	_check(gun.ray_calls == 6 and target.damage == 0.0, "new obstruction blocks damage despite cached aim point")
	gun.blocked = false
	gun._fire(target)
	_check(gun.ray_calls == 7 and target.damage == gun.attack_damage, "clear shot still applies one hit")
	var previous_frame := Engine.get_process_frames()
	while Engine.get_process_frames() == previous_frame:
		await process_frame
	gun._aim_point(target)
	_check(gun.ray_calls == 8, "new process frame invalidates aim")
	gun._targets.assign([target])
	target.position = Vector3(0, 0, -1000)
	var count := gun.ray_calls
	_check(gun._pick_target() == null and gun.ray_calls == count, "far candidate does not query campus triangles")
	gun.skill = gun.Skill.SNIPE
	_check(gun._pick_skill_target(70) == null and gun.ray_calls == count, "far skill candidate does not query campus triangles")
	target.position = Vector3(0, 0, 20)
	_check(gun._pick_target() == null and gun.ray_calls == count, "candidate behind shooter does not query campus triangles")
	target.position = Vector3(0, 0, -20)
	_check(gun._pick_target() == target, "near visible target remains eligible")
	print("[companion-targeting] RESULT %d passed / %d failed" % [_passed, _failed])
	target.free()
	gun.free()
	quit(0 if _failed == 0 else 1)
