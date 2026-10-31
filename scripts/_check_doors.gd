extends SceneTree
## 检查推门：玩家走近 → 门转开；走远 → 关回。
##   _tools/run_probe.sh res://scripts/_check_doors.gd
func _initialize(): _run.call_deferred()
func _run():
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	await process_frame
	await process_frame
	var player := level.get_node_or_null("Player") as Node3D
	var doors := get_nodes_in_group("push_door")
	print("[door] 推门 %d 扇" % doors.size())
	var space: PhysicsDirectSpaceState3D = level.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = 1
	var ok := 0
	var walk := 0
	for d in doors:
		var hinge := d as Node3D
		player.global_position = hinge.global_position + Vector3(0, 0.05, 1.2)
		for i in 45:
			await physics_frame
		var open_ang := rad_to_deg(hinge.rotation.y)
		player.global_position = hinge.global_position + Vector3(0, 0.05, 12.0)
		for i in 60:
			await physics_frame
		var closed_ang := rad_to_deg(hinge.rotation.y)
		# 门开着时，从门外 2 m 往屋里打一条射线，应该能穿过去
		player.global_position = hinge.global_position + Vector3(0, 0.05, 1.2)
		for i in 40:
			await physics_frame
		var pb: Basis = (hinge.get_parent() as Node3D).global_basis
		var n: Vector3 = pb.z.normalized()
		var c: Vector3 = hinge.global_position + pb.x.normalized() * 0.7 + Vector3(0, 1.2, 0)
		var saved_layer: int = (player as CollisionObject3D).collision_layer
		player.collision_layer = 0
		q.from = c - n * 2.0
		q.to = c + n * 1.6
		var hit := space.intersect_ray(q)
		player.collision_layer = saved_layer
		var passable := hit.is_empty()
		if not passable:
			print("[door]   %s 被挡在 %s（碰撞体 %s）" % [String(hinge.name), str(hit["position"]),
				str(hit["collider"].name) if hit.has("collider") else "?"])
		if passable:
			walk += 1
		var good := absf(open_ang) > 60.0 and absf(closed_ang) < 10.0 and passable
		if good:
			ok += 1
		print("[door] %-14s 开 %.0f°  关 %.0f°  %s" % [String(hinge.name), open_ang, closed_ang,
			"✔" if good else "✘"])
	print("[door] %d / %d 开关正常，%d / %d 门开着时能走进去" % [ok, doors.size(), walk, doors.size()])
	level.free()
	quit(0)
