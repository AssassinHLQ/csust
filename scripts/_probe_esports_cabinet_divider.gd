extends SceneTree
## 验收：电竞房柜子**中间竖分隔板**有没有碰撞（用户 2026-11-13 报「角色直接穿进去分隔板」）。
##
## 背景：`_open_cabinet()` 把柜内下三层实心盒挖空时，中缝分隔板那一路也被挖掉，
## 分隔板只剩视觉网格。本探针先量分隔板真实位置/厚度（网格顶点 x 聚类），
## 再真物理横推：左格朝 +X、右格朝 -X，应当被挡住；左格正面仍应能走进。
##
##   _tools/run_probe.sh res://scripts/_probe_esports_cabinet_divider.gd -- --splat=off --story=off

const CABINET_MESH := "M_Scene_-_Root"
const PUSH_FRAMES := 90

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for _i in 3:
		await process_frame
	print("═══ 电竞房柜子 · 中缝分隔板碰撞验收 ═══\n")
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

	# ── ① 量分隔板：柜网格顶点里「贯穿大部分柜高」的竖直 x 平面 ──
	var cab := AABB()
	var verts := PackedVector3Array()
	var glb := room.get_node_or_null("Room")
	for mi in glb.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m == null or m.mesh == null or String(m.name) != CABINET_MESH:
			continue
		cab = m.global_transform * m.mesh.get_aabb()
		for s in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(s)
			var vs := arr[Mesh.ARRAY_VERTEX] as PackedVector3Array
			for v in vs:
				verts.append(m.global_transform * v)
	_check(verts.size() > 0, "量到柜子网格顶点 %d 个" % verts.size())
	if verts.is_empty():
		_summary()
		quit(1)
		return
	print("柜子世界 x %.3f~%.3f  y %.3f~%.3f  z %.3f~%.3f"
		% [cab.position.x, cab.end.x, cab.position.y, cab.end.y, cab.position.z, cab.end.z])

	var bins := {}
	for v in verts:
		if v.x < cab.position.x + 0.15 or v.x > cab.end.x - 0.15:
			continue
		var k := snappedf(v.x, 0.002)
		if not bins.has(k):
			bins[k] = {"n": 0, "y0": INF, "y1": -INF, "z0": INF, "z1": -INF}
		var b: Dictionary = bins[k]
		b["n"] = int(b["n"]) + 1
		b["y0"] = minf(float(b["y0"]), v.y)
		b["y1"] = maxf(float(b["y1"]), v.y)
		b["z0"] = minf(float(b["z0"]), v.z)
		b["z1"] = maxf(float(b["z1"]), v.z)
	var planes: Array = []
	for k in bins:
		var b: Dictionary = bins[k]
		if int(b["n"]) >= 8 and float(b["y1"]) - float(b["y0"]) > cab.size.y * 0.6:
			planes.append({"x": float(k), "n": int(b["n"]),
				"y0": float(b["y0"]), "y1": float(b["y1"]),
				"z0": float(b["z0"]), "z1": float(b["z1"])})
	planes.sort_custom(func(a, b): return float(a["x"]) < float(b["x"]))
	print("贯穿柜高的竖直 x 平面（候选分隔板面）：")
	for p in planes:
		print("  x=%.3f  顶点 %d  y %.2f~%.2f  z %.2f~%.2f"
			% [p["x"], p["n"], p["y0"], p["y1"], p["z0"], p["z1"]])
	_check(planes.size() >= 2, "量到分隔板两个面（%d 个候选平面）" % planes.size())
	if planes.size() < 2:
		_summary()
		quit(1)
		return
	var div_x := (float(planes[0]["x"]) + float(planes[planes.size() - 1]["x"])) * 0.5
	var div_t := float(planes[planes.size() - 1]["x"]) - float(planes[0]["x"])
	print("分隔板中心 x=%.3f  厚 %.3f m（柜中心 x=%.3f）\n"
		% [div_x, div_t, cab.get_center().x])

	# ── ② 真物理：左格朝 +X 横推、右格朝 -X 横推，应被分隔板挡住 ──
	var cz := cab.get_center().z
	var left_cx := (cab.position.x + div_x) * 0.5
	var right_cx := (div_x + cab.end.x) * 0.5
	for side in [["左格→+X", left_cx, 3.0, div_x], ["右格→-X", right_cx, -3.0, div_x]]:
		var tag: String = side[0]
		var sx: float = side[1]
		var vx: float = side[2]
		player.global_position = Vector3(sx, 0.9, cz)
		player.velocity = Vector3.ZERO
		await _wait(12)
		var crossed := 0
		for _f in PUSH_FRAMES:
			player.velocity = Vector3(vx, player.velocity.y, 0)
			player.move_and_slide()
			await physics_frame
			var px := player.global_position.x
			if (vx > 0 and px > div_x + 0.05) or (vx < 0 and px < div_x - 0.05):
				crossed += 1
		print("② %-10s 推进后 x=%.3f（分隔板 x=%.3f）  穿过帧数 %d"
			% [tag, player.global_position.x, div_x, crossed])
		_check(crossed == 0, "%s 被分隔板挡住" % tag)

	# ──  左格正面仍应能走进（分隔板不该堵死入口）──
	var z_lo := cab.position.z
	var z_hi := cab.end.z
	player.global_position = Vector3(left_cx, 0.9, z_lo - 1.5)
	player.velocity = Vector3.ZERO
	await _wait(12)
	var inside := 0
	for _f in PUSH_FRAMES:
		player.velocity = Vector3(0, player.velocity.y, 3.0)
		player.move_and_slide()
		await physics_frame
		var p := player.global_position
		if p.z > z_lo + 0.05 and p.z < z_hi - 0.05 and p.x < div_x - 0.05:
			inside += 1
	print("② %-10s 推进后 z=%.3f（柜内 z %.2f~%.2f）  左格内帧数 %d"
		% ["左格正面进", player.global_position.z, z_lo, z_hi, inside])
	_check(inside >= 5, "左格正面仍能走进柜子")

	_summary()
	quit(0 if _fail == 0 else 1)


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % what)
	else:
		_fail += 1
		print("  ✗ %s" % what)


func _summary() -> void:
	print("\n═══ 通过 %d / 失败 %d ═══" % [_pass, _fail])