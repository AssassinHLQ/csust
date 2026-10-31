extends SceneTree
## 逐栋检查：门洞能不能走进去、墙挡不挡、室内隔墙在不在。
##   _tools/run_probe.sh res://scripts/_check_bldg.gd
func _initialize(): _run.call_deferred()
func _run():
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	await process_frame
	await process_frame
	await physics_frame
	var space: PhysicsDirectSpaceState3D = level.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = 1
	var ok_door := 0
	var ok_wall := 0
	var total := 0
	for b in level.get_node("CampusDeconstruct").get_children():
		if not (b is StaticBody3D):
			continue
		total += 1
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for c in b.get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
				var cs := c as CollisionShape3D
				var sz: Vector3 = (cs.shape as BoxShape3D).size
				lo = lo.min(cs.position - sz * 0.5)
				hi = hi.max(cs.position + sz * 0.5)
		var w := hi.x - lo.x
		var front: float = b.position.z + hi.z
		var cx: float = b.position.x
		var door_x := cx - w * 0.25
		q.from = Vector3(door_x, 1.2, front + 2.0)
		q.to = Vector3(door_x, 1.2, front - 2.0)
		var d := space.intersect_ray(q)
		q.from = Vector3(cx + w * 0.25, 1.2, front + 2.0)
		q.to = Vector3(cx + w * 0.25, 1.2, front - 2.0)
		var wl := space.intersect_ray(q)
		if d.is_empty(): ok_door += 1
		if not wl.is_empty(): ok_wall += 1
		print("[chk] %-20s 门 %s  墙 %s" % [b.name,
			"通 ✔" if d.is_empty() else "堵 ✘", "挡住 ✔" if not wl.is_empty() else "穿 ✘"])
	print("[chk] 合计 %d 栋：门通 %d，墙挡 %d" % [total, ok_door, ok_wall])
	level.free()
	quit(0)
