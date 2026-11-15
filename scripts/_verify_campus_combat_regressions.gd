extends SceneTree
const Guard := preload("res://scripts/boss_terrain_guard.gd")
const Positions := preload("res://scripts/companion_combat_position.gd")
class TestBoss extends "res://scripts/yuuka_horror_boss.gd":
	func _ready() -> void: pass
	func _physics_process(_delta: float) -> void: pass
class TestTrex extends "res://scripts/trex_yuuka_boss.gd":
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass
class TestPlayer extends Player:
	func _ready() -> void: pass
	func _physics_process(_delta: float) -> void: pass
var passed := 0
var failed := 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failed += 1
	print("[campus-combat] ", "PASS " if ok else "FAIL ", label)
func box(parent: Node3D, at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)
	body.position = at
	return body
func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	box(world, Vector3(0, -0.5, 0), Vector3(400, 1, 400))
	var building := box(world, Vector3(0, 9, 0), Vector3(14, 18, 14))
	var boss := TestBoss.new()
	world.add_child(boss)
	boss.position = Vector3(9.5, .05, 0)
	var player := TestPlayer.new()
	var rig := Node3D.new()
	rig.name = "CameraRig"
	var spring := SpringArm3D.new()
	spring.name = "SpringArm3D"
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	spring.add_child(camera)
	rig.add_child(spring)
	player.add_child(rig)
	var arisu := Node3D.new()
	arisu.name = "Arisu"
	var model := Node3D.new()
	model.name = "Model"
	var animation := Node.new()
	animation.name = "AnimDriver"
	model.add_child(animation)
	arisu.add_child(model)
	player.add_child(arisu)
	var player_shape := CollisionShape3D.new()
	player_shape.name = "Collision"
	player.add_child(player_shape)
	var weapon := Node.new()
	weapon.name = "Weapon"
	player.add_child(weapon)
	world.add_child(player)
	player.add_to_group("player")
	await physics_frame
	await physics_frame
	check(not Guard.is_clear(boss, Vector3(0, .05, 0)), "body volume rejects building interior")
	check(not Guard.can_move(boss, Vector3(-20, .05, 0), Vector3(20, .05, 0)), "swept volume rejects tunneling across a building")
	check(Guard.can_move(boss, Vector3(20, .05, 0), Vector3(21, .05, 0)), "open street remains walkable")
	boss._settle_on_ground(1.0)
	var safe := boss.position
	boss.position = Vector3(0, .05, 0)
	boss._settle_on_ground(1.0)
	check(boss.position.is_equal_approx(safe), "embedded boss returns to verified open ground")
	var landing := boss._blink_landing_for(Vector3.ZERO, Vector3.BACK)
	check(not is_nan(landing.y) and Guard.is_clear(boss, landing), "blink selects a clear alternative around building")
	boss._has_grounded_position = false
	boss.position = Vector3(0, .05, 0)
	boss._settle_on_ground(1.0)
	check(Guard.is_clear(boss, boss.position), "initial embedded spawn searches open supported ground")
	boss._last_grounded_position = Vector3(90, .05, 90)
	boss.position = Vector3(0, .05, 0)
	boss._settle_on_ground(1.0)
	check(Guard.is_clear(boss, boss.position) and boss.position.length() < 40.0, "recovery searches locally instead of returning to distant old battle position")
	var trex := TestTrex.new()
	world.add_child(trex)
	trex.position = Vector3(-80, .05, 0)
	trex._home = Vector3(-150, .05, 0)
	player.position = Vector3(-80, .05, 150)
	var distance := trex.position.distance_to(player.position)
	trex._tick_chase(0.1)
	check(trex._walking and trex.position.distance_to(player.position) < distance, "trex pursues beyond notice range and original leash")
	player.position = trex.position + Vector3(0, 80, 40)
	distance = Vector2(trex.position.x-player.position.x, trex.position.z-player.position.z).length()
	trex._tick_chase(0.1)
	check(trex._walking and Vector2(trex.position.x-player.position.x, trex.position.z-player.position.z).length() < distance, "airborne player remains pursuit target on the ground")
	var companion := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	cs.name = "Collision"
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.5
	capsule.radius = .3
	cs.shape = capsule
	cs.position.y = .75
	companion.add_child(cs)
	world.add_child(companion)
	companion.position = Vector3(45, 45, 0)
	boss.position = Vector3(35, 40, 0)
	var positions := Positions.new()
	check(positions.start(companion, boss, 0) and companion.position.y < .1, "party finds scanned floor far below airborne reference")
	companion.position = Vector3(600, 40, 600)
	boss.position = Vector3(600, 40, 600)
	positions = Positions.new()
	check(not positions.start(companion, boss, 0) and companion.visible, "failed search never makes companion invisible")
	Music.reserve("finalboss", world)
	var music := Music._load_stream("finalboss") as AudioStreamOggVorbis
	check(music != null and absf(music.get_length() - 112.5) < .01 and music.loop, "loaded audio cache contains trimmed looping source")
	Music._player.seek(112.2)
	await create_timer(.7).timeout
	check(Music._player.playing and Music._player.get_playback_position() < 1.0, "actual playback wraps past trimmed endpoint without stopping")
	check(Music.current() == "finalboss" and not Music.play("mondrian"), "battle music rejects room override")
	Music.stop()
	check(Music.is_playing(), "room stop cannot silence battle music")
	Music.release(world)
	check(Music.play("mondrian"), "room music resumes after battle releases ownership")
	Music.stop()
	# Dummy audio mixes asynchronously; allow stopped playback to be released.
	Music._player.stream = null
	await create_timer(0.25).timeout
	building.queue_free()
	world.queue_free()
	await process_frame
	await process_frame
	print("[campus-combat] RESULT ", passed, " passed / ", failed, " failed")
	quit(0 if failed == 0 else 1)
