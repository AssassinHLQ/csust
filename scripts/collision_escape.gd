extends RefCounted
## Recover only from a real corner, using swept motion onto supported ground.

static func recover(body: CharacterBody3D, intent: Vector3) -> bool:
	var normals: Array[Vector3] = []
	var away := Vector3.ZERO
	for i in body.get_slide_collision_count():
		var normal := body.get_slide_collision(i).get_normal()
		if absf(normal.y) > .65:
			continue
		normal.y = 0.0
		normal = normal.normalized()
		normals.append(normal)
		away += normal
	var corner := false
	for a in normals:
		for b in normals:
			if a.dot(b) < -.15:
				corner = true
	# Holding movement against one wall is normal blocking, not a trap.
	if not corner:
		return false
	if away.length_squared() < .01:
		away = -intent
		away.y = 0.0
	if away.length_squared() < .01:
		return false
	var reverse := Vector3(-intent.x, 0, -intent.z).normalized()
	for direction in [away.normalized(), reverse, Vector3(-away.z, 0, away.x).normalized(), Vector3(away.z, 0, -away.x).normalized()]:
		var motion: Vector3 = direction * .35
		if body.test_move(body.global_transform, motion, null, body.safe_margin):
			continue
		var target := body.global_position + motion
		var query := PhysicsRayQueryParameters3D.create(target + Vector3.UP * .15,
			target + Vector3.DOWN * .4, body.collision_mask)
		query.exclude = [body.get_rid()]
		var support := body.get_world_3d().direct_space_state.intersect_ray(query)
		if support.is_empty() or (support["normal"] as Vector3).y < cos(body.floor_max_angle):
			continue
		var previous := body.global_position
		body.move_and_collide(motion, false, body.safe_margin)
		if body.global_position.distance_squared_to(previous) > .0001:
			return true
	return false
