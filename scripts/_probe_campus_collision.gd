extends SceneTree
## 量 `CampusCollision`（墙碰撞网格）的**世界坐标**范围 —— 这是「主路 45 个落点
## 全踩 −0.02」实测过的真值，用来给点云对位。
##
## 为什么不能靠点云自己算：点云盒是轴对齐的，576×484 m 的扫描带上倾角后
## 上下差 60 m，盒子的 min/max 根本看不出「地面」在哪一高度。
## 碰撞网格是照点云烘的、且被实测校准过，它的 y 才是路面。
##
##   _probe_campus_collision.gd（不需要解码点云，秒出）

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	await process_frame

	for name_ in ["CampusCollision", "CampusFloor"]:
		var n := level.get_node_or_null(name_) as Node3D
		if n == null:
			print("[col] 缺 %s" % name_)
			continue
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		var verts := 0
		var boxes := 0
		var stack: Array = [n]
		while not stack.is_empty():
			var cur: Node = stack.pop_back()
			var cs := cur as CollisionShape3D
			if cs != null and cs.shape != null:
				var sh := cs.shape
				if sh is ConcavePolygonShape3D:
					var faces: PackedVector3Array = (sh as ConcavePolygonShape3D).get_faces()
					verts += faces.size()
					for v in faces:
						var w: Vector3 = cs.global_transform * v
						lo = lo.min(w)
						hi = hi.max(w)
				elif sh is BoxShape3D:
					boxes += 1
					var raw: Vector3 = (sh as BoxShape3D).size
					var b: AABB = cs.global_transform * AABB(-raw * 0.5, raw)
					lo = lo.min(b.position)
					hi = hi.max(b.end)
			for c in cur.get_children():
				stack.append(c)
		if verts == 0 and boxes == 0:
			print("[col] %s：没找到碰撞形状" % name_)
			continue
		print("[col] %s：顶点 %d / 盒 %d  世界范围 x %.2f~%.2f  y %.2f~%.2f  z %.2f~%.2f"
			% [name_, verts, boxes, lo.x, hi.x, lo.y, hi.y, lo.z, hi.z])

	# 点云的 y 分布（不解码点云，只读 manifest 里已有的统计不行 —— 所以退一步：
	# 直接把 3 个霸王龙的落点打印出来，它们是按「站在校园地面」摆的）
	for bn in ["TrexBossA", "TrexBossB", "TrexBossC"]:
		var b := level.get_node_or_null(bn) as Node3D
		if b != null:
			print("[col] %s 摆位 = %s" % [bn, str(b.global_position)])
	print("[col] 完")
	quit(0)
