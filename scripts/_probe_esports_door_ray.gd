extends SceneTree
## 探针：电竞房的**门到底能不能进** —— 用射线逐点扫，不读代码猜。
##
## 背景：用户 2026-11-11 又提了一次「为什么这两个地方门还是进不去」，
## 编辑器截图里两个门洞上方都有像门楣的薄板。这个问题从 2026-11-09 起反复出现，
## 之前几次探针都说"能过"，但实测过不去 —— 说明**探针的假设本身有问题**。
##
## 这次不假设任何东西：
##   ① 先把房间世界包围盒、门在世界哪一侧量出来；
##   ② 在门洞里铺一张**网格**（横向 × 纵向），每格从门外 3 m 往里打射线，
##      记录第一个击中点的距离和**是哪块碰撞/网格**；
##   ③ 再把玩家胶囊（radius 0.30 / height 1.50）整个挪到门口做 shape cast，
##      看它卡在哪一格。
##
## 用法：& <godot_console.exe> --headless --path . --script res://scripts/_probe_esports_door_ray.gd -- --splat=off --no-capture

const ROOM := "EsportsRoom"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 150:
		await process_frame
	paused = false
	for _f in 30:
		await process_frame

	var room := game.get_node_or_null(ROOM) as Node3D
	if room == null:
		print("[错误] 没有 %s" % ROOM)
		quit(1)
		return
	# 电竞房平时 visible=false，射线需要它参与（CollisionShape 不看 visible，
	# 但为了保险起见还是打开）
	room.visible = true
	await process_frame
	for _f in 10:
		await process_frame

	print("═══ 电竞房门可达性实测 ═══\n")

	# ① 世界包围盒
	var bb := AABB()
	var first := true
	var n_mesh := 0
	for mi in room.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var a: AABB = m.global_transform * m.mesh.get_aabb()
		bb = a if first else bb.merge(a)
		first = false
		n_mesh += 1
	print("① 房间世界包围盒（%d 网格）" % n_mesh)
	print("   x %.2f ~ %.2f   y %.2f ~ %.2f   z %.2f ~ %.2f"
		% [bb.position.x, bb.end.x, bb.position.y, bb.end.y, bb.position.z, bb.end.z])
	print("   根节点世界位置 %s" % str(room.global_position.round()))

	# ② 碰撞体统计
	var n_shape := 0
	var n_body := 0
	for b in room.find_children("*", "StaticBody3D", true, false):
		n_body += 1
		for c in b.get_children():
			if c is CollisionShape3D:
				n_shape += 1
	print("② 碰撞：%d 个 StaticBody3D / %d 个 CollisionShape3D" % [n_body, n_shape])

	var space := room.get_world_3d().direct_space_state

	# ③ 找门：在房间四面墙外的中间高度打射线，看哪一面是通的
	#    门在模型局部 +Z（旧记录），翻转后映射到世界 -Z
	var cy := (bb.position.y + bb.end.y) * 0.5
	var cx := (bb.position.x + bb.end.x) * 0.5
	var cz := (bb.position.z + bb.end.z) * 0.5
	print("\n③ 四面中点水平射线（y=%.2f，从外 6 m 处朝房间打）" % cy)
	var dirs := {
		"-Z": Vector3(0, 0, 1), "+Z": Vector3(0, 0, -1),
		"-X": Vector3(1, 0, 0), "+X": Vector3(-1, 0, 0),
	}
	for k in dirs:
		var d: Vector3 = dirs[k]
		var start: Vector3 = Vector3(cx, cy, cz) - d * 8.0
		var q := PhysicsRayQueryParameters3D.create(start, start + d * 16.0)
		q.collide_with_areas = false
		var h := space.intersect_ray(q)
		if h.is_empty():
			print("   %-3s 整条穿透（没打到任何东西）" % k)
		else:
			var dist: float = start.distance_to(h["position"])
			print("   %-3s 打到 %s，距起点 %.2f m（离房间中心 %.2f m）"
				% [k, str(h["collider"].get_parent().name if h["collider"].get_parent() else "?"),
					dist, (h["position"] as Vector3).distance_to(Vector3(cx, cy, cz))])

	# ④ 门洞网格扫描：沿每条边每 0.1 m 打一条射线，找出「通的区间」
	#    门高度范围：y 从地面 +0.1 到 +2.2
	print("\n④ 四面按 0.10 m 网格扫，找可通行的横向区间（y 取 0.3 / 1.0 / 1.8 三档）")
	var y_tests := [bb.position.y + 0.30, bb.position.y + 1.00, bb.position.y + 1.80]
	for k in dirs:
		var d2: Vector3 = dirs[k]
		# 这条边的横向轴
		var horiz: Vector3 = Vector3(1, 0, 0) if absf(d2.z) > 0.5 else Vector3(0, 0, 1)
		var c0: Vector3 = Vector3(cx, 0, cz)
		# 边的长度取包围盒对应半宽 ×2
		var half: float = (bb.size.x if absf(horiz.x) > 0.5 else bb.size.z) * 0.5
		for yy in y_tests:
			var open: Array[float] = []
			var t := -half
			while t <= half:
				var base: Vector3 = c0 + horiz * t
				base.y = yy
				var start2: Vector3 = base - d2 * 6.0
				var q2 := PhysicsRayQueryParameters3D.create(start2, start2 + d2 * 12.0)
				q2.collide_with_areas = false
				var h2 := space.intersect_ray(q2)
				# 「通」= 射线穿过房间中心区域都没被挡（或打到的最远点在房间内侧）
				if h2.is_empty():
					open.append(t)
				else:
					var p: Vector3 = h2["position"]
					# 打到点是否已经到了房间内部（越过中心就算通）
					var passed := (p - c0).dot(d2) > 0.0
					if passed:
						open.append(t)
				t += 0.10
			if not open.is_empty():
				var lo: float = open[0]
				var hi: float = open[open.size() - 1]
				print("   %-3s y=%.2f  可通区间 横向 %.2f ~ %.2f（宽 %.2f m，%d 个采样点）"
					% [k, yy, lo, hi, hi - lo, open.size()])
			else:
				print("   %-3s y=%.2f  全被挡" % [k, yy])

	print("\n完成")
	quit(0)
