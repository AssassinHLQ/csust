extends SceneTree
## 量「校园围墙 / 竞技场」的真实包围盒与地面高度 —— 给「封锁 + 最终 Boss」用。
##
##   godot --headless --path . --script res://scripts/_probe_arena_bounds.gd \
##         -- --no-capture --campus-splat=off
##
## 为什么要量而不是写死：
##   · 校园泼溅 `Campus` 的变换被改过好几次（翻转那次 y 44.8 → 40.28），
##     硬编码 y 迟早又对不上；
##   · 真正「用户建的围墙」是 `CampusCollision` 那份烘焙网格
##     （`campus_collision_walls_final.scn`）的**外轮廓**，
##     新墙要长在同一个footprint 上，所以必须从它的 AABB 取。
##
## 输出：
##   1. 各节点的世界 AABB（x/z 范围、地面 y）
##   2. 网格点向下射线 → 地面高度表（看校园是不是平的）
##   3. 三只霸王龙脚下的地面高度（它们 y 写的是 0，验证一下）

const LEVEL := "res://scenes/next_level.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ps := load(LEVEL) as PackedScene
	if ps == null:
		push_error("[bounds] 载入失败")
		quit(1)
		return
	var lvl := ps.instantiate() as Node3D
	root.add_child(lvl)
	# 等物理服务器注册完（射线要它）
	for _i in 12:
		await physics_frame
	for _i in 8:
		await process_frame

	print("\n═══ 1. 节点 AABB（世界）═══")
	for nm in ["Plaza", "ParapetS", "ParapetW", "ParapetE", "CampusFloor",
			"CampusCollision", "Campus", "Hall", "CampusBridge"]:
		var n := lvl.get_node_or_null(nm)
		if n == null:
			print("  %-16s （没有这个节点）" % nm)
			continue
		var box := _node_aabb(n)
		if box.size == Vector3.ZERO:
			print("  %-16s （量不出 AABB）" % nm)
			continue
		var lo := box.position
		var hi := box.position + box.size
		print("  %-16s x %8.2f ~ %8.2f ｜ y %8.2f ~ %8.2f ｜ z %8.2f ~ %8.2f  （%s）" % [
			nm, lo.x, hi.x, lo.y, hi.y, lo.z, hi.z,
			str(box.size.snappedf(0.01))])

	print("\n═══ 2. 向下射线：地面高度 ═══")
	var probes := [
		["出生点", Vector3(-2, 0, 5.2)],
		["广场中心", Vector3(0, 0, 0)],
		["校园北缘", Vector3(0, 0, -80)],
		["校园中心", Vector3(0, 0, -316.7)],
		["校园西", Vector3(-250, 0, -316.7)],
		["校园东", Vector3(250, 0, -316.7)],
		["校园南", Vector3(0, 0, -550)],
		["N1(K=0)", Vector3(0, 0, -200)],
		["N2(K=1)", Vector3(120, 0, -200)],
		["N3(K=2)", Vector3(-120, 0, -200)],
	]
	for p in probes:
		var got := _ground(lvl, p[1] as Vector3)
		print("  %-12s xz(%8.2f,%8.2f) → 地面 y = %s" % [
			p[0], (p[1] as Vector3).x, (p[1] as Vector3).z,
			("—" if got == null else "%.3f" % float(got))])

	print("\n═══ 3. 三只霸王龙 ═══")
	for nm in ["TrexBossA", "TrexBossB", "TrexBossC"]:
		var b := lvl.get_node_or_null(nm) as Node3D
		if b == null:
			continue
		var g := _ground(lvl, b.global_position)
		print("  %-10s 位置 %s  脚底地面 y = %s  名字「%s」" % [
			nm, str(b.global_position.snappedf(0.01)),
			("—" if g == null else "%.3f" % float(g)), String(b.get("display_name"))])

	# 建议的墙矩形：从 CampusCollision 的 x/z 取
	var cc := lvl.get_node_or_null("CampusCollision")
	if cc != null:
		var box := _node_aabb(cc)
		var lo := box.position
		var sz := box.size
		print("\n═══ 4. 建议墙矩形（CampusCollision footprint）═══")
		print("  center x %.2f  z %.2f   半宽 %.2f  半深 %.2f" % [
			lo.x + sz.x * 0.5, lo.z + sz.z * 0.5, sz.x * 0.5, sz.z * 0.5])
		print("  周长约 %.0f m" % (2.0 * (sz.x + sz.z)))

	quit(0)


## 把一个节点（含子孙）的所有可见网格 / 碰撞形状并成世界 AABB。
func _node_aabb(n: Node) -> AABB:
	var out := AABB()
	var seen := false
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			if mi.mesh != null:
				var b: AABB = mi.global_transform * mi.get_aabb()
				out = b if not seen else out.merge(b)
				seen = true
		elif c is CollisionShape3D:
			var cs := c as CollisionShape3D
			if cs.shape is BoxShape3D:
				var bs := (cs.shape as BoxShape3D).size
				var b2: AABB = cs.global_transform * AABB(-bs * 0.5, bs)
				out = b2 if not seen else out.merge(b2)
				seen = true
		for ch in c.get_children():
			stack.append(ch)
	return out


## 从 (xz, 400) 往下打到 -400，返回第一个命中点的 y（没有命中返回 null）。
func _ground(lvl: Node3D, xz: Vector3) -> Variant:
	var space := lvl.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(xz.x, 400.0, xz.z), Vector3(xz.x, -400.0, xz.z))
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return null
	return (hit["position"] as Vector3).y
