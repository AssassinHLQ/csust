extends RefCounted
## Let an ascending mech clear the underside of scanned campus geometry.
## Exceptions belong to this actor only and expire as soon as its capsule clears.
var _passing: Array[PhysicsBody3D] = []

func prepare(body: CharacterBody3D, ascending: bool, delta: float) -> void:
	_restore_clear(body)
	if not ascending or body.velocity.y <= 0.0:
		return
	# Inspect only vertical motion: walking into a wall never enables passage.
	for attempt in 4:
		var hit := KinematicCollision3D.new()
		var motion := Vector3.UP * maxf(body.velocity.y * delta, 0.10)
		if not body.test_move(body.global_transform, motion, hit, body.safe_margin, true, 8):
			break
		var added := false
		for index in hit.get_collision_count():
			var collider := hit.get_collider(index) as PhysicsBody3D
			if collider == null or hit.get_normal(index).y > -0.25 or not _is_scan(collider):
				continue
			if not _passing.has(collider):
				body.add_collision_exception_with(collider)
				_passing.append(collider)
				added = true
		if not added:
			break

func _restore_clear(body: CharacterBody3D) -> void:
	if _passing.is_empty():
		return
	var capsule := body.get_node_or_null("Collision") as CollisionShape3D
	if capsule == null:
		return
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule.shape
	query.transform = capsule.global_transform
	query.margin = body.safe_margin + 0.025
	query.collision_mask = body.collision_mask
	query.exclude = [body.get_rid()]
	var touching: Array[RID] = []
	for hit in body.get_world_3d().direct_space_state.intersect_shape(query, 64):
		touching.append(hit.rid)
	for index in range(_passing.size() - 1, -1, -1):
		var collider := _passing[index]
		if not is_instance_valid(collider):
			_passing.remove_at(index)
		elif not touching.has(collider.get_rid()):
			body.remove_collision_exception_with(collider)
			_passing.remove_at(index)

func pending_count() -> int:
	return _passing.size()

func _is_scan(collider: Node) -> bool:
	var node := collider
	while node != null:
		if node.name == "CampusCollision":
			return true
		node = node.get_parent()
	return false
