extends SceneTree
## 校园碰撞到底还在不在？玩家能不能撞到楼？
##
## 用户报：「终于看见学校了，但是碰撞怎么不见了」。
## 本喵 2026-11-11 把校园点云抬到和墙碰撞网格同一高度（y −0.87~58.98），
## 如果碰撞真的没了，先要分清是「节点没挂上 / layer 不对 / 形状被禁用」
## 还是「玩家的碰撞层和它对不上」。
##
##   & <godot> --headless --path . --script res://scripts/_probe_campus_physics.gd
##
## 判据：从校园路面上一点向 16 个水平方向打射线，看能打到几面墙；
## 再往下打一条，看地面板在不在。

const LEVEL := "res://scenes/next_level.tscn"
## 校园主路上的一点（避开三只霸王龙：(-95,-96)/(-120,-115)/(-135,-140)）
const SPOT := Vector3(-20.0, 1.0, -210.0)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var level := (load(LEVEL) as PackedScene).instantiate()
	root.add_child(level)
	for _i in 10:
		await physics_frame

	var player := level.get_node_or_null("Player") as CharacterBody3D
	print("[phys] 玩家 layer=%d mask=%d" % [player.collision_layer, player.collision_mask])

	# ── 碰撞体清单 ──
	for name_ in ["CampusCollision", "CampusFloor"]:
		var n := level.get_node_or_null(name_)
		if n == null:
			print("[phys] 缺 %s" % name_)
			continue
		var stack: Array = [n]
		var bodies := 0
		var shapes := 0
		var disabled := 0
		var layers := {}
		while not stack.is_empty():
			var cur: Node = stack.pop_back()
			if cur is CollisionObject3D:
				var co := cur as CollisionObject3D
				bodies += 1
				layers["%d/%d" % [co.collision_layer, co.collision_mask]] = true
			var cs := cur as CollisionShape3D
			if cs != null:
				shapes += 1
				if cs.disabled:
					disabled += 1
			for c in cur.get_children():
				stack.append(c)
		print("[phys] %s：碰撞体 %d，形状 %d（禁用 %d），layer/mask=%s"
			% [name_, bodies, shapes, disabled, str(layers.keys())])

	# ── 射线：16 个水平方向 + 向下 ──
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var hits := 0
	var nearest := 1e9
	var names := {}
	for i in 16:
		var a := TAU * float(i) / 16.0
		var dir := Vector3(cos(a), 0.0, sin(a))
		var q := PhysicsRayQueryParameters3D.create(SPOT, SPOT + dir * 120.0)
		q.collide_with_areas = false
		var hit: Dictionary = space.intersect_ray(q)
		if not hit.is_empty():
			hits += 1
			var d := SPOT.distance_to(hit["position"])
			nearest = minf(nearest, d)
			var col: Object = hit.get("collider")
			var nm := (col as Node).name if col is Node else str(col)
			names[nm] = true
	print("[phys] 水平 16 向命中 %d 条；最近 %.2f m；撞到的对象 %s"
		% [hits, nearest, str(names.keys())])

	var qd := PhysicsRayQueryParameters3D.create(SPOT + Vector3(0, 3, 0), SPOT - Vector3(0, 20, 0))
	qd.collide_with_areas = false
	var hd: Dictionary = space.intersect_ray(qd)
	if hd.is_empty():
		print("[phys] ✗ 向下 20 m 什么也没打到（地面板缺失！）")
	else:
		var c: Object = hd.get("collider")
		print("[phys] 向下命中 y=%.2f 对象「%s」"
			% [float(hd["position"].y), (c as Node).name if c is Node else str(c)])

	# ── 真让玩家撞一次：站在路面上向前冲 2 秒，看位移 ──
	player.global_position = SPOT
	await physics_frame
	var start := player.global_position
	for _i in 120:
		player.velocity = Vector3(0, 0, -6.0)
		player.move_and_slide()
		await physics_frame
	var delta := player.global_position - start
	print("[phys] 强制前冲 2 s（-Z 6 m/s）位移 = %s（自由走应约 -12 m；被墙挡住会更小）"
		% str(delta.round()))
	print("[phys] 完")
	quit(0)
