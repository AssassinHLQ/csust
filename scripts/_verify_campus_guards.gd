extends SceneTree
## All installed guards must be local ledges, not walls through lower floors or flight space.
var _passed := 0
var _failed := 0

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
	print("[guards] %s %s %s" % ["PASS" if ok else "FAIL", label, detail])

func _run() -> void:
	AudioServer.set_bus_mute(0, true)
	var world := Node3D.new()
	root.add_child(world)
	var boundary := (load("res://scenes/campus_splattransform/ScanBoundary.scn") as PackedScene).instantiate() as StaticBody3D
	var shape := (boundary.get_node("Collision") as CollisionShape3D).shape as ConcavePolygonShape3D
	var faces := shape.get_faces()
	var max_span := 0.0
	var horizontal := 0
	for i in range(0, faces.size(), 3):
		max_span = maxf(max_span, maxf(faces[i].y, maxf(faces[i + 1].y, faces[i + 2].y)) - minf(faces[i].y, minf(faces[i + 1].y, faces[i + 2].y)))
		if absf((faces[i + 1] - faces[i]).cross(faces[i + 2] - faces[i]).normalized().y) > .01:
			horizontal += 1
	_check(max_span <= 1.601, "all guard triangles have local height <= 1.6 m", max_span)
	_check(horizontal == 0, "guards do not create horizontal ceilings or replace scanned ground")
	# Exercise real capsule sweeps against a complete installed guard quad.
	# Other campus geometry is deliberately absent so each measured constraint
	# belongs to this guard rather than a building or a neighbouring floor.
	var selected := -1
	for i in range(0, faces.size(), 6):
		if faces[i + 2].y - faces[i].y > 1.59 and faces[i].distance_to(faces[i + 1]) > .4:
			selected = i
			break
	_check(selected >= 0, "installed geometry contains full height edge guard")
	if selected >= 0:
		var quad := faces.slice(selected, selected + 6)
		var local_shape := ConcavePolygonShape3D.new()
		local_shape.backface_collision = true
		local_shape.set_faces(quad)
		(boundary.get_node("Collision") as CollisionShape3D).shape = local_shape
		world.add_child(boundary)
		var body := CharacterBody3D.new()
		body.collision_layer = 2
		body.collision_mask = 1
		var collision := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = .3
		capsule.height = 1.5
		collision.shape = capsule
		collision.position.y = .75
		body.add_child(collision)
		world.add_child(body)
		await physics_frame
		await physics_frame
		var center := (quad[0] + quad[1]) * .5
		var edge := quad[1] - quad[0]
		var normal := Vector3(-edge.z, 0, edge.x).normalized()
		var surface_y := center.y + .5
		for sign_ in [-1.0, 1.0]:
			var at := Transform3D.IDENTITY
			at.origin = Vector3(center.x, surface_y, center.z) + normal * sign_ * .8
			var motion: Vector3 = normal * float(sign_) * -1.6
			_check(body.test_move(at, motion), "walking capsule stops at scan edge sign=%s" % sign_)
			at.origin.y = surface_y + 2.5
			_check(not body.test_move(at, motion), "flying capsule passes above guard sign=%s" % sign_)
			at.origin.y = surface_y - 2.5
			_check(not body.test_move(at, motion), "lower floor is not fenced by upper ledge sign=%s" % sign_)
	else:
		boundary.free()
	_check(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "mouse remains uncaptured")
	world.free()
	print("[guards] RESULT %d passed / %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
