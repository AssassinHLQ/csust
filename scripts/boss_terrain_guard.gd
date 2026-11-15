extends RefCounted
## Static bosses require volume checks in addition to ground rays.
static func _query(body: PhysicsBody3D, at: Vector3, stature_override := -1.0) -> PhysicsShapeQueryParameters3D:
	var stature := stature_override if stature_override > 0.0 else float(body.get("height"))
	var radius := clampf(stature * 0.14, 0.6, 2.3)
	var key := "terrain_guard_capsule_%d" % roundi(stature * 100.0)
	var capsule := body.get_meta(key) as CapsuleShape3D if body.has_meta(key) else null
	var capsule_height := maxf(stature * 0.82, radius * 2.0)
	if capsule == null:
		capsule = CapsuleShape3D.new()
		body.set_meta(key, capsule)
	if not is_equal_approx(capsule.radius, radius) or not is_equal_approx(capsule.height, capsule_height):
		capsule.radius = radius
		capsule.height = capsule_height
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform.origin = at + Vector3.UP * (capsule.height * 0.5 + 0.65)
	query.collision_mask = 1
	query.exclude = [body.get_rid()]
	# Actors crossing one another are not buildings and must not trigger recovery.
	for group in ["bosses", "player"]:
		for actor in body.get_tree().get_nodes_in_group(group):
			if actor is PhysicsBody3D and actor != body:
				query.exclude = query.exclude + [actor.get_rid()]
	return query

static func is_clear(body: PhysicsBody3D, at: Vector3, stature_override := -1.0) -> bool:
	return body.get_world_3d().direct_space_state.intersect_shape(_query(body, at, stature_override), 1).is_empty()

static func can_move(body: PhysicsBody3D, from: Vector3, to: Vector3) -> bool:
	var query := _query(body, from)
	query.motion = to - from
	var space := body.get_world_3d().direct_space_state
	var fractions := space.cast_motion(query)
	return fractions[0] >= 0.999 and is_clear(body, to)
