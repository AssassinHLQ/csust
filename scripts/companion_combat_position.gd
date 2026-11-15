extends RefCounted
## Grounded firing positions independent of the player's flight and camera.
var _body: CharacterBody3D
var _target: WeakRef
var _index := 0
var _destination := Vector3.ZERO
var _last_safe := Vector3.ZERO
var _has_position := false
var _refresh := 0.0
var _blocked := 0.0
var _ground_check := 0.0
var _player_rid := RID()

func start(body: CharacterBody3D, target: Node3D, index: int) -> bool:
	_body = body
	body.add_to_group("campus_combat_party")
	_target = weakref(target)
	_index = index
	var player := body.get_tree().get_first_node_in_group("player") as CollisionObject3D
	if player != null: _player_rid = player.get_rid()
	_has_position = _choose_position()
	body.visible = true
	if _has_position:
		body.global_position = _destination
		_last_safe = _destination
	body.velocity = Vector3.ZERO
	_refresh = 1.0 + index * 0.2
	return _has_position

func target() -> Node3D:
	return _target.get_ref() as Node3D if _target != null else null

func tick(delta: float) -> void:
	var enemy := target()
	if not is_instance_valid(enemy):
		_hold(delta)
		return
	_refresh -= delta
	_ground_check -= delta
	if _refresh <= 0.0:
		_refresh = 1.5
		var flat := Vector2(_body.global_position.x - enemy.global_position.x,
			_body.global_position.z - enemy.global_position.z)
		var lost_sight := not _visible_from(_body.global_position, enemy)
		if not _has_position or flat.length() > 35.0 or _blocked > 1.0 \
				or lost_sight:
			if _choose_position():
				# New positions have passed support and capsule checks. A blocked
				# route must not strand the party behind buildings after a boss blink.
				if not _has_position or flat.length() > 35.0 or _blocked > 1.0 or lost_sight:
					_body.global_position = _destination
					_last_safe = _destination
					_body.velocity = Vector3.ZERO
				_has_position = true
				_body.visible = true
			_blocked = 0.0
	if not _has_position:
		_body.velocity = Vector3.ZERO
		return
	if _body.global_position.y < _last_safe.y - 1.5:
		# Rescue to verified ground, never to the player in midair.
		_body.global_position = _last_safe
		_body.velocity = Vector3.ZERO
	if _ground_check <= 0.0:
		_ground_check = 0.25
		var supported := _ground(_body.global_position, _body.global_position.y)
		if not supported.is_empty() and _body.is_on_floor():
			_last_safe = supported.position + Vector3.UP * 0.04
	var offset := _destination - _body.global_position
	offset.y = 0.0
	var motion := Vector3.ZERO
	if offset.length() > 0.45:
		motion = offset.normalized() * minf(float(_body.get("run_speed")), offset.length() / maxf(delta, 0.001))
		var ahead := _body.global_position + motion.normalized() * maxf(0.8, motion.length() * delta + 0.4)
		var support := _safe_position(ahead, _body.global_position.y)
		if support.is_empty() or absf((support.position as Vector3).y - _body.global_position.y) > 0.35:
			motion = Vector3.ZERO
			_blocked += delta
	var before := _body.global_position
	_body.velocity.x = motion.x
	_body.velocity.z = motion.z
	_body.velocity.y = -0.5 if _body.is_on_floor() else _body.velocity.y - 22.0 * delta
	_body.move_and_slide()
	if motion.length_squared() > 0.0 and _body.global_position.distance_to(before) < delta * 0.2:
		_blocked += delta
	var facing := enemy.global_position - _body.global_position
	_body.rotation.y = lerp_angle(_body.rotation.y, atan2(facing.x, facing.z), minf(9.0 * delta, 1.0))

func _hold(delta: float) -> void:
	if not _has_position:
		return
	_body.velocity.x = 0.0
	_body.velocity.z = 0.0
	_body.velocity.y = -0.5 if _body.is_on_floor() else _body.velocity.y - 22.0 * delta
	_body.move_and_slide()

func _choose_position() -> bool:
	var enemy := target()
	if enemy == null: return false
	# Prefer the present grounded firing position; reposition only when needed.
	var current := _safe_position(_body.global_position, _body.global_position.y)
	if not current.is_empty() and _visible_from(current.position, enemy) \
			and current.position.distance_to(enemy.global_position) < 30.0:
		_destination = current.position
		return true
	var base_angle := float(_index) * TAU / 4.0 + PI / 4.0
	var fallback: Dictionary = {}
	if not current.is_empty() and current.position.distance_to(enemy.global_position) < 30.0:
		fallback = current
	for radius in [18.0, 23.0, 14.0, 28.0, 8.0, 4.0]:
		for turn in [0.0, 0.3, -0.3, 0.65, -0.65, 1.1, -1.1, PI]:
			var angle: float = base_angle + float(turn)
			var point: Vector3 = enemy.global_position + Vector3(cos(angle), 0, sin(angle)) * float(radius)
			var safe := _safe_position(point, enemy.global_position.y)
			if safe.is_empty(): continue
			if fallback.is_empty(): fallback = safe
			if not _visible_from(safe.position, enemy): continue
			_destination = safe.position
			return true
	# Physics registration may lag the spawn callback by one frame. Ground is
	# still required; visibility can be reassessed once the target has registered.
	if not fallback.is_empty():
		_destination = fallback.position
		return true
	# Preserve a grounded fallback even while the boss is behind a building.
	if not current.is_empty():
		_destination = current.position
		return true
	return false

func _safe_position(point: Vector3, reference_y: float) -> Dictionary:
	var center := _ground(point, reference_y)
	if center.is_empty(): return {}
	var at: Vector3 = center.position + Vector3.UP * 0.04
	for ally in _body.get_tree().get_nodes_in_group("campus_combat_party"):
		if ally == _body or not (ally is Node3D): continue
		if absf(ally.global_position.y - at.y) < 1.5 and Vector2(ally.global_position.x - at.x, ally.global_position.z - at.z).length() < 1.2:
			return {}
	# A central hit alone can be a triangle edge or a narrow tree branch.
	for offset in [Vector3(0.65, 0, 0), Vector3(-0.65, 0, 0), Vector3(0, 0, 0.65), Vector3(0, 0, -0.65)]:
		var edge := _ground(at + offset, at.y)
		if edge.is_empty() or absf((edge.position as Vector3).y - at.y) > 0.55: return {}
	var capsule := _body.get_node("Collision") as CollisionShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule.shape
	query.transform = _body.global_transform * capsule.transform
	query.transform.origin += at - _body.global_position
	query.collision_mask = 1
	query.exclude = _excludes()
	if not _body.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): return {}
	return {"position": at}

func _ground(point: Vector3, reference_y: float) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(Vector3(point.x, reference_y + 2.5, point.z),
		Vector3(point.x, reference_y - 80.0, point.z), 1, _excludes())
	var space := _body.get_world_3d().direct_space_state
	for attempt in 5:
		var hit := space.intersect_ray(query)
		if hit.is_empty(): return {}
		if hit.collider is StaticBody3D:
			if (hit.normal as Vector3).y >= 0.7: return hit
			query.from = hit.position + Vector3.DOWN * 0.03
			continue
		query.exclude = query.exclude + [hit.rid]
	return {}

func _visible_from(at: Vector3, enemy: Node3D) -> bool:
	var height: Variant = enemy.get("height")
	var top := 1.6 if height == null else clampf(float(height), 1.2, 20.0)
	var gun := _body.get_node_or_null("Gun")
	var muzzle_height := float(gun.get("muzzle_height")) if gun != null else 1.15
	var muzzle_forward := float(gun.get("muzzle_forward")) if gun != null else 0.35
	var direction := enemy.global_position - at
	direction.y = 0.0
	var origin := at + Vector3.UP * muzzle_height + direction.normalized() * muzzle_forward
	for fraction in [0.7, 0.55, 0.4, 0.85]:
		var query := PhysicsRayQueryParameters3D.create(origin,
			enemy.global_position + Vector3.UP * (top * fraction), 1, _excludes())
		var hit := _body.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and (hit.collider == enemy or (hit.collider as Node).get_parent() == enemy):
			return true
	return false

func _excludes() -> Array[RID]:
	var out: Array[RID] = [_body.get_rid()]
	if _player_rid.is_valid(): out.append(_player_rid)
	return out

func status() -> Dictionary:
	return {"ready": _has_position, "destination": _destination, "last_safe": _last_safe,
		"target": target()}
