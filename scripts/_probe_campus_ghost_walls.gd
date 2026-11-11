extends SceneTree
## 量化「看不见的墙」：校园碰撞网格里有多少面**点云附近根本没有东西**。
##
##   godot --path . --headless --script res://scripts/_probe_campus_ghost_walls.gd -- --splat=on
##
## 用户 2026-11-11：「碰撞总是卡住人」。
##
## 做法：
##   ① 拿点云（`splat_node.gaussian.xyz`）采样 → 世界坐标，建 2 m 空间哈希；
##   ② 拿 `CampusCollision` 里 ConcavePolygonShape3D 的三角面 → 世界坐标，
##      算它的 AABB / 质心，和点云对账（**对账能查出网格和显示错位/镜像**）；
##   ③ 在场地平面按网格打**水平射线**（离地 1 m，模拟玩家走路），
##      统计被挡的比例；对每条被挡的，看命中点 1.5 m 内有没有点云（= 看得见的墙）：
##        有点云 → 真墙；没点云 → **鬼墙**（就是「卡住人」的元凶）。
##
## 输出：真墙/鬼墙条数、鬼墙的典型高度与位置、以及网格 vs 点云的质心差。

const LEVEL := "res://scenes/next_level.tscn"
const RAY_Y := 1.0
const NEAR := 1.5            # 命中点周围多少米内有点云就算「看得见」
const CELL := 2.0            # 空间哈希边长
const GRID := 26             # 每个方向取几个点（26×26 = 676 条射线）
const SPAN := 300.0          # 覆盖范围（米）：以校园中心为原点 ±SPAN/2


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var level := (load(LEVEL) as PackedScene).instantiate()
	root.add_child(level)
	await process_frame

	var campus: Node3D = level.get_node_or_null("Campus")
	if campus == null:
		print("[FAIL] 没有 Campus")
		quit(1)
		return
	campus.set("start_delay", 0.0)
	campus.set("low_priority", false)
	campus.set("preload_on_gate", false)
	campus.call("force_start")
	var t0 := Time.get_ticks_msec()
	while not bool(campus.call("is_ready")) and Time.get_ticks_msec() - t0 < 240000:
		await process_frame
	print("[ghost] 泼溅就绪 %d ms" % (Time.get_ticks_msec() - t0))

	# ── ① 点云采样 + 空间哈希 ──
	var node: Node3D = campus.get("splat_node")
	var g = node.get("gaussian")
	var xyz: PackedVector3Array = g.get("xyz")
	var xf: Transform3D = node.global_transform
	var stride := int(maxf(1.0, floor(float(xyz.size()) / 400000.0)))
	var buckets := {}
	var cx := 0.0
	var cz := 0.0
	var cy := 0.0
	var splat_lo := Vector3(INF, INF, INF)
	var splat_hi := Vector3(-INF, -INF, -INF)
	var n_pt := 0
	for i in range(0, xyz.size(), stride):
		var w: Vector3 = xf * xyz[i]
		cx += w.x
		cy += w.y
		cz += w.z
		splat_lo = splat_lo.min(w)
		splat_hi = splat_hi.max(w)
		n_pt += 1
		var key := Vector3i(floori(w.x / CELL), floori(w.y / CELL), floori(w.z / CELL))
		if buckets.has(key):
			(buckets[key] as Array).append(w)
		else:
			buckets[key] = [w]
	cx /= maxf(1.0, n_pt)
	cy /= maxf(1.0, n_pt)
	cz /= maxf(1.0, n_pt)
	print("[ghost] 点云采样 %d 点（步长 %d）  质心 (%.1f, %.1f, %.1f)" % [n_pt, stride, cx, cy, cz])
	print("[ghost] 点云 AABB %s ~ %s" % [str(splat_lo.snappedf(0.1)), str(splat_hi.snappedf(0.1))])

	# ── ② 碰撞三角面 ──
	var faces := PackedVector3Array()
	var mcx := 0.0
	var mcy := 0.0
	var mcz := 0.0
	var mesh_lo := Vector3(INF, INF, INF)
	var mesh_hi := Vector3(-INF, -INF, -INF)
	var n_faces := 0
	for cs in _all_shapes(level):
		var cshape := (cs as CollisionShape3D).shape
		if cshape == null:
			continue
		if not (cshape is ConcavePolygonShape3D):
			continue
		var f: PackedVector3Array = (cshape as ConcavePolygonShape3D).get_faces()
		var gt: Transform3D = (cs as CollisionShape3D).global_transform
		var k := 0
		while k + 2 < f.size():
			for j in 3:
				var w: Vector3 = gt * f[k + j]
				faces.append(w)
				mcx += w.x
				mcy += w.y
				mcz += w.z
				mesh_lo = mesh_lo.min(w)
				mesh_hi = mesh_hi.max(w)
			k += 3
			n_faces += 1
	if n_faces == 0:
		print("[FAIL] 没找到 ConcavePolygonShape3D 三角面")
		quit(1)
		return
	var nverts := maxf(1.0, float(faces.size()))
	mcx /= nverts
	mcy /= nverts
	mcz /= nverts
	print("[ghost] 碰撞三角 %d 面  顶点质心 (%.1f, %.1f, %.1f)" % [n_faces, mcx, mcy, mcz])
	print("[ghost] 碰撞 AABB %s ~ %s" % [str(mesh_lo.snappedf(0.1)), str(mesh_hi.snappedf(0.1))])
	print("[ghost] ⇒ 质心差 (%.1f, %.1f, %.1f) m（网格 vs 点云；大 = 错位/镜像）"
		% [mcx - cx, mcy - cy, mcz - cz])

	# ── ③ 水平射线找鬼墙 ──
	var space := (level as Node3D).get_world_3d().direct_space_state
	var x0 := (splat_lo.x + splat_hi.x) * 0.5 - SPAN * 0.5
	var z0 := (splat_lo.z + splat_hi.z) * 0.5 - SPAN * 0.5
	var step := SPAN / float(GRID - 1)
	var blocked := 0
	var real_wall := 0
	var ghost := 0
	var ghost_ys: Array[float] = []
	var shot := 0
	var ghost_samples: Array[String] = []
	var dirs: Array[Vector3] = [Vector3(1, 0, 0), Vector3(-1, 0, 0),
		Vector3(0, 0, 1), Vector3(0, 0, -1)]
	for iz in GRID:
		for ix in GRID:
			var px := x0 + float(ix) * step
			var pz := z0 + float(iz) * step
			for d in dirs:
				var from := Vector3(px, RAY_Y, pz)
				var q := PhysicsRayQueryParameters3D.create(from, from + d * 3.0)
				q.collision_mask = 1
				var hit := space.intersect_ray(q)
				shot += 1
				if hit.is_empty():
					continue
				# 只算【墙】—— 撞到 CampusFloor 平板不算
				var obj: Node = hit["collider"]
				if obj != null and String(obj.name) != "CampusCollision":
					continue
				blocked += 1
				var hp: Vector3 = hit["position"]
				if _has_point_near(buckets, hp, NEAR):
					real_wall += 1
				else:
					ghost += 1
					ghost_ys.append(hp.y)
					if ghost_samples.size() < 8:
						ghost_samples.append("(%6.1f, %5.1f, %6.1f)" % [hp.x, hp.y, hp.z])

	print("\n[ghost] 水平射线 %d 条（离地 %.1f m、每方向 3 m），被 CampusCollision 挡住 %d 条"
		% [shot, blocked])
	print("[ghost]   真墙 %d 条 / **鬼墙 %d 条**（命中点 %.1f m 内没有点云）" % [real_wall, ghost, NEAR])
	if ghost > 0:
		var avg := 0.0
		for y in ghost_ys:
			avg += y
		avg /= float(ghost_ys.size())
		print("[ghost]   鬼墙平均高度 y = %.2f" % avg)
		print("[ghost]   鬼墙样例：%s" % ", ".join(ghost_samples))
	print("[ghost]   鬼墙占比 %.1f%%（占全部射线）" % (100.0 * ghost / maxf(1.0, float(shot))))

	# ── ④ 决定性检验：碰撞顶点到最近点云的距离分布 ──
	# 如果网格和点云还是「套在一起」的，绝大多数顶点应当贴在点云表面（< 1 m）；
	# 如果网格是**另一套变换**烘出来的（例如烘的时候还开着 180° 翻转），
	# 那这些顶点就会整体飘在离点云好几米的地方 —— 那才是「总有看不见的墙」的根。
	print("\n[ghost] === 碰撞顶点 → 最近点云距离 ===")
	var hist := {"<=0.5": 0, "<=1": 0, "<=2": 0, "<=5": 0, ">5": 0}
	var sampled := 0
	var vs := maxi(1, int(faces.size() / 60000))   # 顶点太多，抽样
	var dsum := 0.0
	var dmax := 0.0
	var i2 := 0
	while i2 < faces.size():
		var p: Vector3 = faces[i2]
		i2 += vs
		sampled += 1
		var d := _nearest_dist(buckets, p, 6.0)
		dsum += d
		dmax = maxf(dmax, d)
		if d <= 0.5:
			hist["<=0.5"] += 1
		elif d <= 1.0:
			hist["<=1"] += 1
		elif d <= 2.0:
			hist["<=2"] += 1
		elif d <= 5.0:
			hist["<=5"] += 1
		else:
			hist[">5"] += 1
	if sampled > 0:
		print("[ghost] 抽样 %d 个顶点（每 %d 个取 1）" % [sampled, vs])
		print("[ghost] 平均距离 %.2f m，最大 %.2f m（超过 %.0f m 记作 >5）"
			% [dsum / float(sampled), dmax, 5.0])
		for k in ["<=0.5", "<=1", "<=2", "<=5", ">5"]:
			print("[ghost]   %-6s : %5d（%.1f%%）"
				% [k, int(hist[k]), 100.0 * float(hist[k]) / float(sampled)])
		var near_frac := 100.0 * float(int(hist["<=0.5"]) + int(hist["<=1"])) / float(sampled)
		print("[ghost] ⇒ 贴合率（≤1 m）%.1f%%" % near_frac)
		if near_frac >= 70.0:
			print("[ghost] ⇒ 判定：网格**贴合**点云 —— 「卡住人」不是错位，是薄墙/凸起卡胶囊")
		else:
			print("[ghost] ⇒ 判定：网格**没贴住**点云（另一套变换烘的）—— 需要重烘或整体校正")
	quit(0)


func _all_shapes(n: Node) -> Array:
	var out: Array = []
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		if x is CollisionShape3D:
			out.append(x)
		for c in x.get_children():
			stack.append(c)
	return out


## 空间哈希查：命中点周围 NEAR 米内有没有点云
func _has_point_near(buckets: Dictionary, p: Vector3, near: float) -> bool:
	return _nearest_dist(buckets, p, near) <= near


## 最近点云点到 p 的距离；超过 limit 就返回 limit（省时间）
func _nearest_dist(buckets: Dictionary, p: Vector3, limit: float) -> float:
	var r := int(ceil(limit / CELL))
	var base := Vector3i(floori(p.x / CELL), floori(p.y / CELL), floori(p.z / CELL))
	var best := limit
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var k := base + Vector3i(dx, dy, dz)
				if not buckets.has(k):
					continue
				for w in buckets[k]:
					var d: float = (w as Vector3).distance_to(p)
					if d < best:
						best = d
	return best
