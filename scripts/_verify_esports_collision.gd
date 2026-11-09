extends SceneTree
## 验证电竞房碰撞 v3（离线烘的「一件物体一个盒子」）。
##
##   godot --path . --headless --script res://scripts/_verify_esports_collision.gd
##
## 查四件事：
##   ① 形状数量 & 是不是真的「一件一个」
##   ② 墙 / 地面 / 天花板 挡得住
##   ③ 门洞通得过
##   ④ 可走性（胸口高度铺网格，看有多少点没被占）
##
## ⚠️ 2026-11-09：碰撞节点从「运行时建在 EsportsRoom 下」改成
##    「场景里实例化的 BakedCollision/AutoCol」，所以这里改成递归找。

const GAME := "res://scenes/game.tscn"
## 小件（体积 < 0.05 m³，像书 / 摆件）在碰撞里应该**各自独立**，
## 这是使用者要的：「书本桌子本来是两个不同的碰撞」
const SMALL_VOL := 0.05


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := (load(GAME) as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	for _i in 20:
		await process_frame

	var room := game.get_node_or_null("EsportsRoom") as Node3D
	if room == null:
		print("[ecol] !! 没有 EsportsRoom")
		quit(1)
		return

	# ① 找碰撞体
	var body := room.find_child("AutoCol", true, false) as StaticBody3D
	if body == null:
		print("[ecol] !! 找不到 AutoCol（烘好的碰撞没接上？）")
		quit(1)
		return
	var shapes: Array[CollisionShape3D] = []
	for c in body.get_children():
		if c is CollisionShape3D:
			shapes.append(c as CollisionShape3D)
	print("[ecol] AutoCol 形状 %d 个" % shapes.size())

	# ①b 「一件一个」的证据：统计形状尺寸分布，数小件
	var n_small := 0
	var n_mid := 0
	var n_big := 0
	var smallest := 1e9
	for cs in shapes:
		var sh := cs.shape as BoxShape3D
		if sh == null:
			continue
		var s := sh.size
		var v := s.x * s.y * s.z
		smallest = minf(smallest, v)
		if v < SMALL_VOL:
			n_small += 1
		elif v < 1.0:
			n_mid += 1
		else:
			n_big += 1
	print("[ecol] 尺寸分布：小件(<%.2f m³) %d 个、中件 %d 个、大件 %d 个；最小 %.4f m³"
		% [SMALL_VOL, n_small, n_mid, n_big, smallest])
	if n_small >= 100:
		print("[ecol] [PASS] 小件确实各自独立（≥100 个）—— 不再是「一坨」")
	else:
		print("[ecol] [FAIL] 小件只有 %d 个，可能又糊成一坨了" % n_small)

	var space := room.get_world_3d().direct_space_state
	var low := room.get_node_or_null("Room") as Node3D
	var box := AABB()
	var first := true
	if low != null:
		for m in low.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			if mi.mesh == null:
				continue
			var a: AABB = mi.global_transform * mi.mesh.get_aabb()
			box = a if first else box.merge(a)
			first = false
	var c := box.position + box.size * 0.5
	print("[ecol] 房间世界 AABB pos=%s size=%s" % [
		str(box.position.snappedf(0.01)), str(box.size.snappedf(0.01))])

	# ② 墙 / 地 / 天花板
	var fails := 0
	var g := space.intersect_ray(PhysicsRayQueryParameters3D.create(
		Vector3(c.x, c.y + 1.2, c.z), Vector3(c.x, box.position.y - 1.5, c.z), 1))
	if g.is_empty():
		print("[ecol] [FAIL] 地面射线空（会掉下去）")
		fails += 1
	else:
		print("[ecol] [PASS] 地面命中 y=%.2f" % (g.get("position") as Vector3).y)
	var up := space.intersect_ray(PhysicsRayQueryParameters3D.create(
		Vector3(c.x, c.y + 1.2, c.z), Vector3(c.x, box.position.y + box.size.y + 2.0, c.z), 1))
	print("[ecol] %s 天花板" % ("[PASS]" if not up.is_empty() else "[FAIL]"))

	# ③ 实墙（⚠️ 2026-11-09 更正：门在**世界 −X** 那侧）
	#
	# 房间节点在 `game.tscn` 里带旋转，把**局部 +Z 映射到世界 −X**；
	# 而门洞正是开在局部 +Z 那面墙上的（见 `_bake_esports_parts.gd::NO_COLLIDE`）。
	# 所以「西(−X)」是**门**，不该要求它挡人 —— 原来把它列进「必须挡住」，
	# 门一封死这条就 PASS、门一开就对不上了（本喵修门洞时被它误报过一次）。
	# 现在换成正对着局部 −Z（世界 +X）那面实墙。
	var probes := {
		"东(+X)": Vector3(1, 0, 0),
		"南(−Z)": Vector3(0, 0, -1),
		"北(+Z)": Vector3(0, 0, 1),
	}
	for k in probes:
		var d: Vector3 = probes[k]
		var reach := maxf(box.size.x, box.size.z) + 3.0
		var h := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			Vector3(c.x, c.y, c.z), Vector3(c.x, c.y, c.z) + d * reach, 1))
		print("[ecol] %s %s" % ["[PASS]" if not h.is_empty() else "[FAIL]", k])

	# ④ 门洞（+Z 那侧，扫 0.4 m）
	var open_n := 0
	var total_n := 0
	var x := box.position.x + 0.4
	while x <= box.position.x + box.size.x - 0.4:
		total_n += 1
		var dh := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			Vector3(x, box.position.y + 1.2, box.position.z + box.size.z + 2.0),
			Vector3(x, box.position.y + 1.2, box.position.z + box.size.z - 3.0), 1))
		if dh.is_empty():
			open_n += 1
		x += 0.4
	print("[ecol] [%s] 门洞可通行 %d/%d 个采样点" % [
		"PASS" if open_n >= 2 else "FAIL", open_n, total_n])

	# ⑤ 可走性
	var free_n := 0
	var hit_n := 0
	x = box.position.x
	while x <= box.position.x + box.size.x:
		var z := box.position.z
		while z <= box.position.z + box.size.z:
			var q := PhysicsPointQueryParameters3D.new()
			q.position = Vector3(x, box.position.y + 0.9, z)
			q.collision_mask = 1
			if space.intersect_point(q).is_empty():
				free_n += 1
			else:
				hit_n += 1
			z += 0.5
		x += 0.5
	var total := free_n + hit_n
	print("[ecol] 可走性：可走 %d / %d = %.0f%%" % [
		free_n, total, 100.0 * float(free_n) / maxf(float(total), 1.0)])

	print("[ecol] 完成（硬失败 %d 项）" % fails)
	quit(0)
