extends SceneTree
## 量：这块「场地」到底有多大、上面那些建筑离边缘多近（2026-11-11）。
##
## 用户（附两张俯视图）：
##   「边界扩大蒙德里安都快挨到边上了,场地长方形加宽」
##
## 「场地」是哪个平台必须先量清楚 —— 主平台 `Floor` 是 40×40（方形），
## 但东侧还有 `LotEast`（24×40，长条）和 `ShopDeck`，用户的截图看着像长条的。
## 猜错就白改，所以这里把所有「大块地面」和各建筑的世界包围盒都打出来，
## 再算「建筑边缘离脚下平台边缘还有几米」。
##
## 用法：
##   bash _tools/run_probe.sh res://scripts/_probe_ground_edges.gd -- --splat=off

const GAME := "res://scenes/game.tscn"
## 只关心"像地面"的东西：水平投影足够大
const MIN_AREA := 40.0


func _initialize() -> void:
	_run.call_deferred()


## 一个节点的世界 AABB（把子树里所有 mesh 并起来）
func _aabb_of(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or m.mesh.get_aabb().size == Vector3.ZERO:
			continue
		var bb: AABB = m.global_transform * m.get_aabb()
		if first:
			out = bb
			first = false
		else:
			out = out.merge(bb)
	if first and n is Node3D:
		out = AABB((n as Node3D).global_position, Vector3.ZERO)
	return out


func _run() -> void:
	print("========== 场地尺寸 / 建筑离边缘多远 ==========")
	var game := (load(GAME) as PackedScene).instantiate()
	root.add_child(game)
	for _i in 20:
		await process_frame

	# ── 1. 所有"像地面"的块（水平投影 > MIN_AREA）──
	print("\n── ① 大块地面 ──")
	var grounds: Array = []
	for mi in game.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var bb: AABB = m.global_transform * m.get_aabb()
		var area := bb.size.x * bb.size.z
		# 「地面」= 水平投影大、且竖直方向很薄
		if area < MIN_AREA or bb.size.y > 2.0:
			continue
		grounds.append({"name": String(m.get_path()), "bb": bb, "area": area})
	grounds.sort_custom(func(a, b): return float(a["area"]) > float(b["area"]))
	for g in grounds:
		var bb: AABB = g["bb"]
		print("  %-46s x[%7.2f %7.2f] z[%7.2f %7.2f] 顶面 y=%6.2f  %.0f×%.0f m" % [
			String(g["name"]).substr(String(g["name"]).find("/") + 1),
			bb.position.x, bb.end.x, bb.position.z, bb.end.z, bb.end.y,
			bb.size.x, bb.size.z])

	# ── 2. 各建筑的世界 AABB ──
	print("\n── ② 建筑 ──")
	var names := ["MondrianHouse", "GameDevRoom", "EsportsRoom", "Shop", "MeshHut"]
	for nm in names:
		var n := game.get_node_or_null(nm)
		if n == null:
			print("  %-16s （不存在）" % nm)
			continue
		var bb := _aabb_of(n)
		print("  %-16s x[%7.2f %7.2f] z[%7.2f %7.2f]  y[%6.2f %6.2f]  %.1f×%.1f m" % [
			nm, bb.position.x, bb.end.x, bb.position.z, bb.end.z,
			bb.position.y, bb.end.y, bb.size.x, bb.size.z])

	# ── 3. 每个建筑离**脚下那块地面**的边还有几米 ──
	print("\n── ③ 建筑边缘 → 脚下地面的边缘（米，越小越挤）──")
	for nm in names:
		var n := game.get_node_or_null(nm)
		if n == null:
			continue
		var bb := _aabb_of(n)
		var c := bb.get_center()
		# 找脚下这块地：水平投影包含建筑中心、顶面高度接近建筑底面
		var best: Dictionary = {}
		for g in grounds:
			var gb: AABB = g["bb"]
			if c.x < gb.position.x or c.x > gb.end.x:
				continue
			if c.z < gb.position.z or c.z > gb.end.z:
				continue
			if absf(gb.end.y - bb.position.y) > 1.5:
				continue
			if best.is_empty() or float(g["area"]) > float(best["area"]):
				best = g
		if best.is_empty():
			print("  %-16s 脚底下没找到匹配的地面（可能悬空/落在别的块上）" % nm)
			continue
		var gb2: AABB = best["bb"]
		print("  %-16s 地面 %-30s 西 %5.2f  东 %5.2f  北 %5.2f  南 %5.2f" % [
			nm, String(best["name"]).get_file(),
			bb.position.x - gb2.position.x, gb2.end.x - bb.end.x,
			bb.position.z - gb2.position.z, gb2.end.z - bb.end.z])

	quit(0)
