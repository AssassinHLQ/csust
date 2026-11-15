extends SceneTree
## Headless physics checks; --campus uses the isolated desktop runner for integration.
const Arena := preload("res://scripts/arena_lock.gd")
const OffWin := preload("res://scripts/offscreen_window.gd")
const Settings := preload("res://scripts/game_settings.gd")
const CAP_MASK := 1 << (Arena.CEILING_LAYER - 1)
var _passed := 0
var _failed := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String, detail: Variant = "") -> void:
	if ok: _passed += 1
	else: _failed += 1
	print("[arena-ceiling] ", "PASS " if ok else "FAIL ", label, " ", detail)

func _box(parent: Node3D, at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	body.position = at

func _ray(world: Node3D, from: Vector3, to: Vector3, mask: int) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	return world.get_world_3d().direct_space_state.intersect_ray(query)

func _move(player: CharacterBody3D, at: Vector3, motion: Vector3) -> void:
	player.global_position = at
	await physics_frame
	await physics_frame
	player.move_and_collide(motion)

func _run() -> void:
	AudioServer.set_bus_mute(0, true)
	if OS.get_cmdline_user_args().has("--campus"):
		await _campus()
	else:
		await _unit()
	_check(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "probe never captures mouse")
	print("[arena-ceiling] RESULT ", _passed, " passed / ", _failed, " failed")
	quit(0 if _failed == 0 else 1)

func _unit() -> void:
	var world := Node3D.new()
	root.add_child(world)
	_box(world, Vector3(0, -4.5, 0), Vector3(200, 1, 200))
	_box(world, Vector3(0, -0.5, 0), Vector3(25, 1, 25))
	_box(world, Vector3(40, 9.5, 0), Vector3(4, 1, 4))
	var player := CharacterBody3D.new()
	player.collision_layer = 2
	player.collision_mask = 1
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.5
	capsule.radius = 0.3
	collision.shape = capsule
	collision.position.y = 0.75
	player.add_child(collision)
	world.add_child(player)
	player.position.y = 2.0
	var lock := Arena.new()
	world.add_child(lock)
	await physics_frame
	await physics_frame
	lock._build_walls(AABB(Vector3(-40, -20, -30), Vector3(80, 100, 60)))
	lock._bind_ceiling_player(player)
	_check(lock.status().walls.size() == 4, "four-wall status contract is preserved")
	_check(not lock.status().ceiling_active, "ceiling starts disabled")
	lock._rise()
	await create_timer(4.3).timeout
	_check(lock.status().ceiling_active, "ceiling activates with arena rise")
	_check(player.get_collision_mask_value(Arena.CEILING_LAYER), "player collides with dedicated ceiling layer")
	for wall in lock._walls:
		var box := (wall.get_node("Body").get_child(0) as CollisionShape3D).shape as BoxShape3D
		var top := wall.global_position.y + box.size.y * 0.5
		_check(absf(top - 100.0) < 0.01, "side wall meets world Y100 ceiling", [wall.name, top])
		_check(wall.global_position.y - box.size.y * 0.5 <= -1.0, "roof samples never lift wall off street", wall.name)
	var cap := lock.get_node("Ceiling/Body/Collision") as CollisionShape3D
	var cap_box := cap.shape as BoxShape3D
	_check(absf(cap.global_position.y - cap_box.size.y * 0.5 - 100.0) < 0.01, "ceiling underside is exactly Y100")
	_check(cap_box.size.x >= 82.0 and cap_box.size.z >= 62.0, "ceiling overlaps every side and corner")
	_check(is_equal_approx(float(lock._ceiling_mat.get_shader_parameter("opacity")), 1.0), "red ceiling finishes fading in")
	var ground := _ray(world, Vector3(0, 300, 0), Vector3(0, -100, 0), 1)
	_check(not ground.is_empty() and absf(ground.position.y) < 0.01, "terrain rays ignore ceiling and retain real ground", ground.get("position"))
	_check(lock._ground_of(0, 0) != null and absf(float(lock._ground_of(0, 0))) < 0.01, "Boss spawn ground query remains correct")
	for at in [Vector3(0, 90, 0), Vector3(-38, 90, -28), Vector3(38, 90, 28)]:
		await _move(player, at, Vector3.UP * 40.0)
		_check(player.global_position.y <= 98.51 and player.global_position.y > 98.0, "ascending capsule stops under ceiling", player.global_position)
	for motion in [Vector3(80, 0, 0), Vector3(-80, 0, 0), Vector3(0, 0, 60), Vector3(0, 0, -60)]:
		await _move(player, Vector3(0, 98, 0), motion)
		_check(absf(player.position.x) < 39.0 and absf(player.position.z) < 29.0, "high-altitude flight cannot escape side wall", player.position)
	player.position = Vector3(0, 160, 0)
	player.velocity = Vector3(12, 20, 0)
	lock._confine_below_ceiling(player)
	_check(player.position.y + 1.5 < 100.0 and is_zero_approx(player.velocity.y) and is_equal_approx(player.velocity.x, 12.0), "already airborne player returns inside with ascent cancelled")
	player.set_collision_mask_value(5, true)
	lock._lower_walls()
	await physics_frame
	await physics_frame
	_check(not lock.status().ceiling_active, "victory disables ceiling collision immediately")
	_check(not player.get_collision_mask_value(Arena.CEILING_LAYER) and player.get_collision_mask_value(5), "release restores ceiling bit and preserves other mask changes")
	await _move(player, Vector3(0, 95, 0), Vector3.UP * 20.0)
	_check(player.position.y > 110.0, "flight passes above Y100 after victory", player.position)
	await create_timer(3.3).timeout
	_check(not lock._ceiling.visible, "red ceiling hides after release fade")
	player.set_collision_mask_value(Arena.CEILING_LAYER, true)
	lock._bind_ceiling_player(player)
	lock._fade_ceiling(1.0, 0.0)
	lock._lower_walls()
	_check(player.get_collision_mask_value(Arena.CEILING_LAYER), "cleanup preserves preexisting ceiling mask bit")
	player.set_collision_mask_value(Arena.CEILING_LAYER, false)
	lock._bind_ceiling_player(player)
	lock.queue_free()
	await process_frame
	await process_frame
	_check(not player.get_collision_mask_value(Arena.CEILING_LAYER), "scene removal restores player mask")
	world.queue_free()
	await process_frame
	await process_frame

func _campus() -> void:
	if not OS.get_cmdline_user_args().has("--no-capture"):
		_check(false, "campus probe requires no-capture")
		return
	await OffWin.apply(self, Vector2i(1280, 720))
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
	var street := player.global_position
	player.set_physics_process(false)
	world.set("_final_started", true)
	world.call("_begin_final_phase")
	var lock: Node3D
	var boss: Node3D
	var deadline := Time.get_ticks_msec() + 20000
	while boss == null and Time.get_ticks_msec() < deadline:
		lock = world.get_node_or_null("ArenaLock")
		if lock != null: boss = lock.get("_boss") as Node3D
		await process_frame
	_check(boss != null and lock != null, "production Boss appears below active cap")
	if boss == null or lock == null:
		world.queue_free()
		await process_frame
		return
	boss.call("debug_set_chase", false)
	boss.call("debug_set_blink_cd", 999.0)
	_check(bool(lock.call("status").ceiling_active), "actual arena ceiling is active")
	_check(boss.global_position.y < 20.0, "ceiling does not move Boss spawn into sky", boss.position)
	# Move the player's own mask-1 capsule out of the downward terrain ray.
	player.position.y = 90.0
	await physics_frame
	await physics_frame
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(street.x, 300, street.z), Vector3(street.x, -100, street.z), 1)
	query.exclude = [player.get_rid()]
	var terrain: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
	# ArenaLock's existing query sees actors too; sample beside the airborne capsule.
	player.position.x += 3.0
	await physics_frame
	await physics_frame
	var g: Variant = lock.call("_ground_of", street.x, street.z)
	_check(g != null and not terrain.is_empty() and absf(float(g) - terrain.position.y) < 0.02 and float(g) < 20.0,
		"actual scanned street query ignores cap", [g, terrain.get("position")])
	for offset in [Vector3.ZERO, Vector3(15, 0, 12)]:
		await _move(player, Vector3(street.x, 90, street.z) + offset, Vector3.UP * 50.0)
		_check(player.position.y <= 98.51 and player.position.y > 98.0, "production player cannot fly through cap", player.position)
	var flight_passage := preload("res://scripts/campus_flight_passage.gd").new()
	player.velocity = Vector3.UP * 40.0
	flight_passage.prepare(player, true, 1.0 / 60.0)
	_check(flight_passage.pending_count() == 0, "upward scan passage cannot exempt arena cap")
	lock.call("_lower_walls")
	await physics_frame
	await physics_frame
	_check(not bool(lock.call("status").ceiling_active), "actual arena releases cap collision")
	await _move(player, Vector3(street.x, 95, street.z), Vector3.UP * 25.0)
	_check(player.position.y > 115.0, "production player can leave above cap after release", player.position)
	_check(OffWin.is_safe()[0], "private probe leaves foreground and mouse alone")
	world.queue_free()
	await process_frame
	await process_frame
