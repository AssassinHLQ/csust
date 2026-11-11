extends SceneTree
## 求 `CampusCollision` 相对点云的**整体偏移**（以及是否左右镜像），用来挪节点。
##
##   godot --path . --headless --script res://scripts/_probe_campus_collision_fit.gd -- --splat=on
##
## 用户 2026-11-11：「碰撞总是卡住人」，并选择「先量出整体偏移，只挪节点对上去」。
##
## ── 为什么不用「顶点到最近点云的距离」直接判 ──
## 那份网格是 Poisson 重建 + 只留竖直面的产物，里面本来就有**航拍看不见的面**
## （楼内侧、树底下、被遮挡的立面），它们天然离点云很远。实测顶点 48% 距点云 >5 m，
## 但这**不能**证明「变换错了」，只能说明网格里有很多推断面。所以不能拿它定偏移。
##
## ── 改用俯视占用图互相关 ──
## 楼在俯视图里是「有东西」的格子。把点云和网格各自栅格化成俯视占用图
## （8 m 一格，只算离地 2 m 以上的东西），然后在 ±40 m、8 m 步长上平移，
## 两种镜像（不翻 / 沿 X 翻）都试，取重合度最高的：
##   score = Σ min(a, b) / Σ max(a, b)      （占用的 Jaccard 式重合度）
## 得到的 (dx, dz, mirror) 就是要把 CampusCollision 挪多少、要不要翻。
##
## 输出可以直接照着改 `scenes/next_level.tscn` 里 CampusCollision 的 transform。

const LEVEL := "res://scenes/next_level.tscn"
const CELL := 8.0          # 俯视栅格边长
const SHIFT_MAX := 40.0    # 搜索半径
const SHIFT_STEP := 8.0    # 搜索步长
const MIN_H := 2.0         # 只统计离地 2 m 以上的东西（楼/树冠）


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var level := (load(LEVEL) as PackedScene).instantiate()
	root.add_child(level)
	await process_frame

	var campus: Node3D = level.get_node_or_null("Campus")
	if campus == null:
		print("[fit] 没有 Campus")
		quit(1)
		return
	campus.set("start_delay", 0.0)
	campus.set("low_priority", false)
	campus.set("preload_on_gate", false)
	campus.call("force_start")
	var t0 := Time.get_ticks_msec()
	while not bool(campus.call("is_ready")) and Time.get_ticks_msec() - t0 < 240000:
		await process_frame
	print("[fit] 泼溅就绪 %d ms" % (Time.get_ticks_msec() - t0))

	# ── 点云占用图 ──
	var node: Node3D = campus.get("splat_node")
	var g = node.get("gaussian")
	var xyz: PackedVector3Array = g.get("xyz")
	var xf: Transform3D = node.global_transform
	var stride := int(maxf(1.0, floor(float(xyz.size()) / 400000.0)))
	var cloud := {}
	for i in range(0, xyz.size(), stride):
		var w: Vector3 = xf * xyz[i]
		if w.y < MIN_H:
			continue
		var k := Vector2i(floori(w.x / CELL), floori(w.z / CELL))
		cloud[k] = int(cloud.get(k, 0)) + 1
	print("[fit] 点云占用格 %d 个（%.0f m 格，只算 y ≥ %.0f）" % [cloud.size(), CELL, MIN_H])

	# ── 网格占用图 ──
	var mesh := {}
	var nv := 0
	for cs in _all_shapes(level):
		var sc := (cs as CollisionShape3D).shape
		if sc == null or not (sc is ConcavePolygonShape3D):
			continue
		var f: PackedVector3Array = (sc as ConcavePolygonShape3D).get_faces()
		var gt: Transform3D = (cs as CollisionShape3D).global_transform
		var j := 0
		while j < f.size():
			var w: Vector3 = gt * f[j]
			j += 3            # 每个三角取 1 个顶点就够（都是竖直面的角点）
			if w.y < MIN_H:
				continue
			var k := Vector2i(floori(w.x / CELL), floori(w.z / CELL))
			mesh[k] = int(mesh.get(k, 0)) + 1
			nv += 1
	print("[fit] 网格占用格 %d 个（抽样顶点 %d）" % [mesh.size(), nv])
	if cloud.is_empty() or mesh.is_empty():
		print("[fit] 有一边是空的，没法拟合")
		quit(1)
		return
	# 调试：两边各打印几个格子，确认坐标系/步长一致
	var ck := cloud.keys()
	var mk2 := mesh.keys()
	print("[fit] 点云格样例 %s %s %s" % [str(ck[0]), str(ck[mini(1, ck.size() - 1)]), str(ck[ck.size() - 1])])
	print("[fit] 网格格样例 %s %s %s" % [str(mk2[0]), str(mk2[mini(1, mk2.size() - 1)]), str(mk2[mk2.size() - 1])])
	var overlap0 := 0
	for k in cloud.keys():
		if mesh.has(k):
			overlap0 += 1
	print("[fit] 零偏移下直接重合的格子数 = %d" % overlap0)

	# ── 互相关搜索 ──
	var steps := int(round(SHIFT_MAX * 2.0 / SHIFT_STEP))
	var best := {"score": -1.0, "dx": 0.0, "dz": 0.0, "mirror": false}
	var rows: Array = []
	for mirror in [false, true]:
		for sx in range(-steps, steps + 1):
			for sz in range(-steps, steps + 1):
				var dx := float(sx) * SHIFT_STEP
				var dz := float(sz) * SHIFT_STEP
				var score := _score(mesh, cloud, dx, dz, mirror)
				rows.append({"score": score, "dx": dx, "dz": dz, "mirror": mirror})
				if score > float(best["score"]):
					best = {"score": score, "dx": dx, "dz": dz, "mirror": mirror}
	rows.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
	print("\n[fit] === 前 6 名（重合度越高越对） ===")
	for i in mini(6, rows.size()):
		var r: Dictionary = rows[i]
		print("[fit]   #%d  score=%.3f  dx=%+.0f dz=%+.0f  镜像=%s"
			% [i + 1, float(r["score"]), float(r["dx"]), float(r["dz"]),
				"是（沿 X 翻）" if bool(r["mirror"]) else "否"])

	# 基准：完全不挪
	var base := _score(mesh, cloud, 0.0, 0.0, false)
	print("[fit]   基准（不挪、不翻）= %.3f" % base)
	print("\n[fit] === 结论 ===")
	var s_best := float(best["score"])
	if s_best - base < 0.02:
		print("[fit] 最佳偏移(%.0f, %.0f) 只比「不挪」好 %.3f —— 也就是**网格已经是套准的**，"
			% [float(best["dx"]), float(best["dz"]), s_best - base])
		print("[fit]       挪节点不会解决问题；「卡住人」来自网格里的推断面/薄墙。")
	else:
		print("[fit] 建议：把 CampusCollision 平移 dx=%+.0f  dz=%+.0f%s，重合度 %.3f → %.3f"
			% [float(best["dx"]), float(best["dz"]),
				"（并沿 X 镜像）" if bool(best["mirror"]) else "", base, s_best])
		print("[fit]       照着改 `scenes/next_level.tscn` 里 CampusCollision 的 transform 即可。")
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


## 把网格格子平移（可选沿 X 镜像）后和点云格子求**占用集合的 Jaccard 重合度**。
##
## ⚠️ 不能拿「每格点数」直接比：点云一格上千点、网格一格只有几个顶点，
##    min/max 会被量级吞掉、所有候选都算出 0.000（本喵第一版就踩了这个）。
##    楼在俯视图里只关心「这格有没有东西」，所以两边都按**二值占用**算。
##
## 映射关系（以「点云格」为基准反推「网格格」）：
##   不镜像：mesh( kx − sx , kz − sz )
##   镜像  ：mesh( sx − kx , kz − sz )      —— 镜像后 x 变号，再平移 sx
func _score(mesh: Dictionary, cloud: Dictionary, dx: float, dz: float, mirror: bool) -> float:
	var sx := int(round(dx / CELL))
	var sz := int(round(dz / CELL))
	var matched := {}
	for k in cloud.keys():
		# ⚠️ `Vector2i` 的第二个分量叫 `.y`，不是 `.z` —— 写成 `.z` 会抛
		#    「Invalid access to property or key 'z'」，函数直接中断、返回 null，
		#    外面当 0.0 处理，于是**所有候选都算出 0.000**（本喵连踩两版才发现）。
		var kk: Vector2i = k
		var mx := (sx - kk.x) if mirror else (kk.x - sx)
		var mk := Vector2i(mx, kk.y - sz)
		if mesh.has(mk):
			matched[mk] = true
	var inter := matched.size()
	var union := cloud.size() + mesh.size() - inter
	if union <= 0:
		return 0.0
	return float(inter) / float(union)
