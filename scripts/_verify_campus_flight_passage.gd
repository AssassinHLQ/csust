extends SceneTree
const Passage := preload("res://scripts/campus_flight_passage.gd")
var _world: Node3D
var _body: CharacterBody3D
var _passage: RefCounted
var _passed := 0
var _failed := 0

func _initialize() -> void:
	if DisplayServer.get_name() != "headless" or not OS.get_cmdline_user_args().has("--no-capture"):
		quit(2)
		return
	_run.call_deferred()

func _check(ok: bool, label: String, detail: Variant = "") -> void:
	if ok: _passed += 1
	else: _failed += 1
	print("[flight-passage] ", "PASS " if ok else "FAIL ", label, " ", detail)

func _box(parent: Node3D, at: Vector3, size: Vector3, concave := false) -> StaticBody3D:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	if concave:
		var mesh := BoxMesh.new()
		mesh.size = size
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(mesh.get_faces())
		cs.shape = shape
	else:
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)
	body.position = at
	return body

func _reset(at: Vector3) -> void:
	_body.position = at
	_body.velocity = Vector3.ZERO
	await physics_frame
	_passage.prepare(_body, false, 1.0 / 60)

func _move(frames: int, velocity: Vector3, flight: bool) -> void:
	for i in frames:
		await physics_frame
		_body.velocity = velocity
		_passage.prepare(_body, flight, 1.0 / 60)
		_body.move_and_slide()

func _run() -> void:
	_world = Node3D.new()
	root.add_child(_world)
	var scan := Node3D.new()
	scan.name = "CampusCollision"
	_world.add_child(scan)
	_box(scan, Vector3.ZERO, Vector3(8, 0.2, 8), true)
	_box(scan, Vector3(10, 0, 0), Vector3(8, 0.2, 8))
	_box(_world, Vector3(0, -4.1, 0), Vector3(40, 0.2, 40))
	_box(_world, Vector3(20, 0, 0), Vector3(8, 0.2, 8))
	_box(scan, Vector3(4, 2, 0), Vector3(0.2, 4, 8))
	_body = CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	cs.name = "Collision"
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.5
	cs.shape = shape
	cs.position.y = 0.75
	_body.add_child(cs)
	_world.add_child(_body)
	_passage = Passage.new()
	await _reset(Vector3(0, -2.0, 0))
	await _move(60, Vector3.UP * 5, true)
	_check(_body.position.y > 2.5, "ascending flight clears double-sided scan underside", _body.position)
	_check(_passage.pending_count() == 0 and _body.get_collision_exceptions().is_empty(), "exceptions expire above the surface")
	await _move(100, Vector3.DOWN * 6, false)
	_check(absf(_body.position.y - 0.1) < 0.03 and _body.is_on_floor(), "descending lands on the same scanned surface", _body.position)
	await _move(240, Vector3.DOWN * 0.5, false)
	_check(absf(_body.position.y - 0.1) < 0.03, "standing on top never drops through")
	await _reset(Vector3(0, -2, 0))
	await _move(40, Vector3.UP * 5, false)
	_check(_body.position.y < -1.55, "ordinary jump does not phase through scan", _body.position)
	await _reset(Vector3(10, -2, 0))
	await _move(60, Vector3.UP * 5, true)
	_check(_body.position.y > 2.5, "bridge box underside permits upward flight", _body.position)
	await _move(100, Vector3.DOWN * 6, false)
	_check(_body.is_on_floor() and absf(_body.position.y - 0.1) < 0.03, "bridge restores solid landing")
	await _reset(Vector3(20, -2, 0))
	await _move(40, Vector3.UP * 5, true)
	_check(_body.position.y < -1.55, "non-campus ceilings keep their collision")
	await _reset(Vector3(3, 0.2, 0))
	await _move(35, Vector3(5, 0.1, 0), true)
	_check(_body.position.x < 3.62, "vertical campus wall still blocks horizontal flight", _body.position)
	await _reset(Vector3(0, -2, 0))
	await _move(10, Vector3.UP * 5, true)
	await _move(120, Vector3.DOWN * 5, false)
	_check(_body.position.y > -4.03 and _body.is_on_floor(), "cancelled ascent restores support on lower floor", _body.position)
	_check(_passage.pending_count() == 0, "cancelled ascent leaves no exception")

	# Actual production campus, including the large irregular scan chunks.
	scan.free()
	var campus := (load("res://scenes/campus_splattransform.tscn") as PackedScene).instantiate() as Node3D
	campus.name = "CampusCollision"
	_world.add_child(campus)
	await physics_frame
	for point in [Vector3(-100, 3.36, -265.6), Vector3(-92, 3.26, -265.6)]:
		var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 3, point + Vector3.DOWN * 3, 1, [_body.get_rid()])
		var hit := _world.get_world_3d().direct_space_state.intersect_ray(query)
		_check(not hit.is_empty(), "production street has real scan support", point)
		if hit.is_empty(): continue
		var surface: Vector3 = hit.position
		await _reset(surface + Vector3.DOWN * 2.2)
		await _move(75, Vector3.UP * 5, true)
		_check(_body.position.y > surface.y + 2.5, "flight escapes below production street", _body.position)
		await _move(100, Vector3.DOWN * 5, false)
		_check(_body.is_on_floor() and absf(_body.position.y - surface.y) < 0.12, "lands above production scan after crossing", _body.position)
		_check(_passage.pending_count() == 0, "production scan exceptions fully restored")
	_check(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "mouse remains uncaptured")
	print("[flight-passage] RESULT ", _passed, " passed / ", _failed, " failed")
	quit(0 if _failed == 0 else 1)
