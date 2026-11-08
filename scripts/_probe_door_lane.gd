extends SceneTree
## 查：门洞那条通道上到底有什么盒子挡着。
## 门洞中心应在世界 (52.0, ~2.0, 21.42)，门洞宽 2.4（x: 50.8~53.2）、高 2.4（y: 0.31~2.71）。
##
##   & godot --script res://scripts/_probe_door_lane.gd -- --splat=off --story=off

func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	await _wait(3)
	var room: Node3D = load("res://scenes/esports_room.tscn").instantiate()
	root.add_child(room)
	room.global_position = Vector3(52, 0.01, 13)
	await _wait(30)

	var body := room.get_node_or_null("AutoCol") as StaticBody3D
	if body == null:
		print("[lane] 没有 AutoCol")
		quit(1)
		return

	# 门洞通道：x ∈ [50.8, 53.2]，y ∈ [0.4, 2.6]，z ∈ [18, 23]
	var n := 0
	var total := 0
	print("[lane] ---- 挡在门洞通道里的盒子（x 50.8~53.2, y 0.4~2.6, z 18~23）----")
	for c in body.get_children():
		var cs := c as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		total += 1
		var bs := cs.shape as BoxShape3D
		var p := cs.global_position
		var s := bs.size
		var x0 := p.x - s.x * 0.5
		var x1 := p.x + s.x * 0.5
		var y0 := p.y - s.y * 0.5
		var y1 := p.y + s.y * 0.5
		var z0 := p.z - s.z * 0.5
		var z1 := p.z + s.z * 0.5
		# 和门洞 AABB 相交？
		if x1 < 50.8 or x0 > 53.2:
			continue
		if y1 < 0.4 or y0 > 2.6:
			continue
		if z1 < 18.0 or z0 > 23.0:
			continue
		n += 1
		print("[lane]  BOX pos(%7.2f,%6.2f,%7.2f) size(%5.2f,%5.2f,%5.2f)  x[%.2f,%.2f] y[%.2f,%.2f] z[%.2f,%.2f]"
			% [p.x, p.y, p.z, s.x, s.y, s.z, x0, x1, y0, y1, z0, z1])
	print("[lane] 共 %d 个（总数 %d）" % [n, total])

	# 沿门洞正中打一条射线，看命中的是谁
	var space := room.get_world_3d().direct_space_state
	var from := Vector3(52.0, 1.7, 23.0)
	var to := Vector3(52.0, 1.7, 10.0)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		print("[lane] 射线 23 -> 10 未命中（门洞完全畅通）")
	else:
		print("[lane] 射线 23 -> 10 命中 @ %s" % str((hit["position"] as Vector3).snappedf(0.01)))
	quit(0)
