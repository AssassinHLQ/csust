extends SceneTree
## 验收：电竞房柜子里的**水平板**（底板/层板/顶板）有没有碰撞（用户 2026-11-13 报
## 「右边的上下板子怎么没有碰撞」）。
##
## 先量：柜区顶点按 y 聚类找水平面、聚成板（独立盒状板每面只有 4 个顶点，门槛 4）。
## 再真物理：两列各从半空落体应被底板托住；各起跳一次头应被层板/顶板挡住。
##
##   _tools/run_probe.sh res://scripts/_probe_esports_cabinet_shelves.gd -- --splat=off --story=off

const CABINET_MESH := "M_Scene_-_Root"

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for _i in 3:
		await process_frame
	print("═══ 电竞房柜子 · 水平层板测量 ═══\n")
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _f in 150:
		await process_frame
	paused = false
	for _f in 30:
		await process_frame
	var room := game.get_node_or_null("EsportsRoom") as Node3D
	var player := game.get("_player") as CharacterBody3D
	if room == null or player == null:
		print("!! 缺房间或玩家")
		quit(1)
		return
	room.visible = true
	for _f in 5:
		await process_frame

	var cab := AABB()
	var glb := room.get_node_or_null("Room")
	for mi in glb.find_children("*", "MeshInstance3D", true, false):
		var m0 := mi as MeshInstance3D
		if m0 != null and m0.mesh != null and String(m0.name) == CABINET_MESH:
			cab = m0.global_transform * m0.mesh.get_aabb()
	var meshes: Array = []
	var src_planes: Array = []
	for mi in room.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m == null or m.mesh == null:
			continue
		var b: AABB = m.global_transform * m.mesh.get_aabb()
		meshes.append({"m": m, "b": b})
	print("柜子世界 x %.3f~%.3f  y %.3f~%.3f  z %.3f~%.3f"
		% [cab.position.x, cab.end.x, cab.position.y, cab.end.y, cab.position.z, cab.end.z])

	# 柜区里每个网格的水平面（层板可能在别的材质桶里）
	for e in meshes:
		var m: MeshInstance3D = e["m"]
		var b: AABB = e["b"]
		if b.position.x > cab.end.x or b.end.x < cab.position.x:
			continue
		if b.position.z > cab.end.z or b.end.z < cab.position.z:
			continue
		if b.position.y > cab.end.y or b.end.y < cab.position.y:
			continue
		var verts := PackedVector3Array()
		for s in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(s)
			var vs := arr[Mesh.ARRAY_VERTEX] as PackedVector3Array
			for v in vs:
				var w: Vector3 = m.global_transform * v
				# 只留柜区内的顶点：层板可能和别的家具混在同一材质桶里
				if w.x < cab.position.x - 0.02 or w.x > cab.end.x + 0.02:
					continue
				if w.z < cab.position.z - 0.02 or w.z > cab.end.z + 0.02:
					continue
				if w.y < cab.position.y - 0.02 or w.y > cab.end.y + 0.02:
					continue
				verts.append(w)
		if verts.is_empty():
			continue
		var bins := {}
		for v in verts:
			var k := snappedf(v.y, 0.002)
			if not bins.has(k):
				bins[k] = {"n": 0, "x0": INF, "x1": -INF, "z0": INF, "z1": -INF}
			var bb: Dictionary = bins[k]
			bb["n"] = int(bb["n"]) + 1
			bb["x0"] = minf(float(bb["x0"]), v.x)
			bb["x1"] = maxf(float(bb["x1"]), v.x)
			bb["z0"] = minf(float(bb["z0"]), v.z)
			bb["z1"] = maxf(float(bb["z1"]), v.z)
		var planes: Array = []
		for k in bins:
			var bb: Dictionary = bins[k]
			# 独立盒状层板每个水平面只有 4 个顶点，门槛不能高于 4
			if int(bb["n"]) >= 4 and float(bb["x1"]) - float(bb["x0"]) > 0.25 \
					and float(bb["z1"]) - float(bb["z0"]) > 0.25:
				planes.append({"y": float(k), "n": int(bb["n"]),
					"x0": float(bb["x0"]), "x1": float(bb["x1"]),
					"z0": float(bb["z0"]), "z1": float(bb["z1"])})
		if planes.is_empty():
			continue
		planes.sort_custom(func(a, b2): return float(a["y"]) < float(b2["y"]))
		if src_planes.is_empty():
			src_planes = planes
		print("\n网格 %s（父 %s，顶点 %d，AABB y %.3f~%.3f）水平面：" % [String(m.name), String(m.get_parent().name), verts.size(), b.position.y, b.end.y])
		for p in planes:
			print("  y=%.3f  顶点 %3d  x %.3f~%.3f  z %.3f~%.3f"
				% [p["y"], p["n"], p["x0"], p["x1"], p["z0"], p["z1"]])

	# 玩家碰撞体
	print("\n玩家碰撞体：")
	for c in player.find_children("*", "CollisionShape3D", true, false):
		var cs := c as CollisionShape3D
		var sh := cs.shape
		var desc := "?"
		if sh is CapsuleShape3D:
			desc = "胶囊 radius=%.3f height=%.3f" % [(sh as CapsuleShape3D).radius, (sh as CapsuleShape3D).height]
		elif sh is BoxShape3D:
			desc = "盒 size=%s" % str((sh as BoxShape3D).size)
		elif sh is CylinderShape3D:
			desc = "圆柱 radius=%.3f height=%.3f" % [(sh as CylinderShape3D).radius, (sh as CylinderShape3D).height]
		print("  %s  %s  disabled=%s  global_y=%.3f" % [String(cs.name), desc, str(cs.disabled), cs.global_position.y])

	# 柜内现存碰撞盒
	print("\n柜内现存（未禁用）碰撞盒：")
	var auto_col := room.get_node_or_null("BakedCollision/AutoCol") as Node3D
	for c in auto_col.get_children():
		var cs := c as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D) or cs.disabled:
			continue
		var half: Vector3 = cs.global_basis.get_scale().abs() * (cs.shape as BoxShape3D).size * 0.5
		var cb := AABB(cs.global_position - half, half * 2.0)
		if cb.get_center().x < cab.position.x - 0.3 or cb.get_center().x > cab.end.x + 0.3:
			continue
		if cb.get_center().z < cab.position.z - 0.3 or cb.get_center().z > cab.end.z + 0.3:
			continue
		print("  %-14s x %.3f~%.3f  y %.3f~%.3f  z %.3f~%.3f"
			% [String(cs.name), cb.position.x, cb.end.x, cb.position.y, cb.end.y, cb.position.z, cb.end.z])

	# ── 真物理验收：底板托住、层板/顶板顶头 ──
	var boards: Array = []
	for p in src_planes:
		if boards.is_empty() or float(p["y"]) - float(boards[boards.size() - 1]["y1"]) > 0.08:
			boards.append({"y0": float(p["y"]), "y1": float(p["y"])})
		else:
			boards[boards.size() - 1]["y1"] = float(p["y"])
	_check(boards.size() == 3, "量到 3 块板（底/层/顶，实际 %d）" % boards.size())
	if boards.size() < 3:
		_summary()
		quit(1)
		return
	# 玩家节点原点在**脚底**（胶囊向上偏半高），所以落体停位=板顶、起跳顶点=板底-胶囊全高
	var cap_h := 1.5
	for c in player.find_children("*", "CollisionShape3D", true, false):
		var sh := (c as CollisionShape3D).shape
		if sh is CapsuleShape3D:
			cap_h = (sh as CapsuleShape3D).height
	var left_cx := cab.position.x + cab.size.x * 0.25
	var right_cx := cab.position.x + cab.size.x * 0.75
	var cz := cab.get_center().z
	print("")
	for side in [["左列", left_cx], ["右列", right_cx]]:
		player.global_position = Vector3(float(side[1]), 1.4, cz)
		player.velocity = Vector3.ZERO
		for _f in 90:
			await physics_frame
		var rest: float = player.global_position.y
		var want: float = float(boards[0]["y1"])
		print("② %-8s 落体停 y=%.3f（期望底板顶 %.3f）" % [side[0], rest, want])
		_check(absf(rest - want) < 0.03, "%s 被底板托住" % side[0])
	for side in [["右列", right_cx, 1], ["左列", left_cx, 2]]:
		player.global_position = Vector3(float(side[1]), float(boards[0]["y1"]), cz)
		player.velocity = Vector3.ZERO
		for _f in 10:
			await physics_frame
		player.velocity = Vector3(0, 7.1, 0)
		var apex := 0.0
		for _f in 70:
			await physics_frame
			apex = maxf(apex, player.global_position.y)
		var want2: float = float(boards[int(side[2])]["y0"]) - cap_h
		print("② %-8s 起跳顶点 y=%.3f（期望板底-胶囊高 %.3f）" % [side[0], apex, want2])
		_check(absf(apex - want2) < 0.06, "%s 头被板挡住" % side[0])
	_summary()
	quit(0 if _fail == 0 else 1)


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % what)
	else:
		_fail += 1
		print("  ✗ %s" % what)


func _summary() -> void:
	print("\n═══ 通过 %d / 失败 %d ═══" % [_pass, _fail])