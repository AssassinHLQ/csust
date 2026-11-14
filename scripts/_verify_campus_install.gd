extends SceneTree
## Verify production wiring and actors against scanned terrain without a flat fallback.
var _failed := 0
var _passed := 0

func _initialize() -> void:
	if DisplayServer.get_name() != "headless" or not OS.get_cmdline_user_args().has("--no-capture"):
		quit(2)
		return
	_run.call_deferred()

func _check(ok: bool, label: String, detail: Variant = "") -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
	print("[install] %s %s %s" % ["PASS" if ok else "FAIL", label, str(detail)])

func _run() -> void:
	AudioServer.set_bus_mute(0, true)
	var world := (load("res://scenes/next_level.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	for i in 8:
		await physics_frame
	var collision := world.get_node("CampusCollision") as Node3D
	_check(collision.scene_file_path == "res://scenes/campus_splattransform.tscn", "production uses refined scan")
	_check(collision.global_transform.is_equal_approx(Transform3D.IDENTITY), "world coordinates are not transformed twice")
	_check(collision.get_child_count() == 33, "31 scan tiles, outline guard and bridge installed")
	_check((world.get_node("CampusFloor/Collision") as CollisionShape3D).disabled, "flat fallback disabled")
	_check((world.get_node("CampusFloor/Collision").shape as BoxShape3D).size == Vector3(575.6, 80, 483.4), "arena footprint retained")
	_check(is_equal_approx(float(world.get_node("Player").safe_margin), .004), "campus player uses 4 mm collision margin")
	var space := world.get_world_3d().direct_space_state
	for name in ["TrexBossA", "TrexBossB", "TrexBossC"]:
		var boss := world.get_node(name) as Node3D
		var p := boss.global_position
		var query := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 2, p + Vector3.DOWN * 4, 1)
		var hit := space.intersect_ray(query)
		_check(not hit.is_empty() and absf(float(hit.get("position", Vector3.INF).y) - p.y) < .1, name + " stands on scanned ground", p)
		boss.call("_attack", world.get_node("Player"))
		var disk := boss.get_node("AttackTelegraph") as Node3D
		var at := disk.global_position
		query.from = Vector3(at.x, p.y + 3, at.z)
		query.to = Vector3(at.x, p.y - 6, at.z)
		hit = space.intersect_ray(query)
		_check(not hit.is_empty() and absf(at.y - float(hit["position"].y) - .10) < .02, name + " warning disk follows terrain", at)
	var query := PhysicsRayQueryParameters3D.create(Vector3(10, .8, -73.8), Vector3(10, .8, -76), 1)
	var cap := space.intersect_ray(query)
	_check(not cap.is_empty() and cap["collider"].name in ["CampusBridgeExtension", "ScanBoundary"], "old bridge spur cannot lead into void")
	_check(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "mouse remains uncaptured")
	print("[install] RESULT %d passed / %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
