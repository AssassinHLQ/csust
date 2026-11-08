extends SceneTree
## 探针：柴关电脑城的**地板**到底铺到哪儿了 —— 用户「电脑城的地板怎么没有碰撞,陷进去了」。
##
## 用法：_tools/run_probe.sh res://scripts/_probe_shop_floor.gd
##
## 量三件事：
##   ① 商店内部按 1 m 网格往下打射线，看每一格有没有地板、命中高度多少、命中的是谁；
##   ② Deck 地板矩形 vs 屋壳内沿矩形，差多少（后半截是不是露在 Deck 外面）；
##   ③ 屋壳 GLB 里的网格都有哪些、那个「看得见的地板」世界 y 是多少
##      （如果它比碰撞面高，人就会被画进地板里 = 陷进去）。
##
## ⚠️ 射线必须在物理帧里打。`SceneTree` 脚本没有 `_physics_process` 虚函数，
##    所以用 `await physics_frame`。

const GAME := "res://scenes/game.tscn"

var _frames := 0
var _game: Node3D


func _initialize() -> void:
	var ps: PackedScene = load(GAME)
	if ps == null:
		print("[shop] FAIL 载不动 %s" % GAME)
		quit(1)
		return
	_game = ps.instantiate() as Node3D
	root.add_child(_game)


func _process(_d: float) -> bool:
	_frames += 1
	if _frames == 4:
		_measure.call_deferred()
	return false


func _measure() -> void:
	await physics_frame
	await physics_frame

	var shop := _game.get_node_or_null("Shop") as Node3D
	if shop == null:
		print("[shop] FAIL 没有 Shop")
		quit(1)
		return

	var deck: Rect2 = shop.get_meta("baked_deck_rect", Rect2())
	var sh := Vector3(shop.global_position.x, 0.0, shop.global_position.z)
	print("[shop] Shop 世界位置 %s" % str(sh.snappedf(0.01)))
	print("[shop] Deck 地板矩形：x %.2f ~ %.2f、z %.2f ~ %.2f" % [
		deck.position.x, deck.end.x, deck.position.y, deck.end.y])

	# ── 屋壳的四堵墙 = 内部矩形 ──
	var body := shop.get_node_or_null("Body") as Node3D
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	if body != null:
		for c in body.get_children():
			var cs := c as CollisionShape3D
			if cs == null or not (cs.shape is BoxShape3D):
				continue
			var bs := cs.shape as BoxShape3D
			if not cs.name.begins_with("ShellWall"):
				continue
			var b: AABB = cs.global_transform * AABB(-bs.size * 0.5, bs.size)
			lo = lo.min(b.position)
			hi = hi.max(b.position + b.size)
	print("[shop] 屋壳碰撞矩形：x %.2f ~ %.2f、z %.2f ~ %.2f" % [lo.x, hi.x, lo.z, hi.z])

	# ── ① 网格射线 ──
	var space := _game.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = 1
	print("\n========== ① 商店内部往下打射线（命中高度 / 命中者）==========")
	print("       " + "".join(range(0)).rpad(0))
	var xs := []
	var x := lo.x + 0.6
	while x < hi.x - 0.3:
		xs.append(x)
		x += 2.0
	var zs := []
	var z := hi.z - 0.6
	while z > lo.z + 0.3:
		zs.append(z)
		z -= 2.0

	# 表头
	var head := "        "
	for xt in xs:
		head += "%7.1f" % xt
	print(head + "     ← x")
	var holes: Array = []
	var hit_names := {}
	for zz in zs:
		var line := "  z%7.1f " % zz
		for xx in xs:
			q.from = Vector3(xx, 6.0, zz)
			q.to = Vector3(xx, -15.0, zz)
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				line += "   ──✗"
				holes.append(Vector2(xx, zz))
			else:
				var y: float = (hit["position"] as Vector3).y
				line += " %6.2f" % y
				var nm := str(hit["collider"].name)
				hit_names[nm] = int(hit_names.get(nm, 0)) + 1
		print(line)
	print("\n  命中者统计：%s" % str(hit_names))
	print("  没有地板的格子 %d / %d" % [holes.size(), xs.size() * zs.size()])
	for h in holes:
		print("    ✗ (x %.1f, z %.1f)" % [h.x, h.y])

	# ── ② Deck 与屋壳的交集 ──
	print("\n========== ② Deck 盖住了屋壳的多少 ==========")
	var cov_x0 := maxf(deck.position.x, lo.x)
	var cov_x1 := minf(deck.end.x, hi.x)
	var cov_z0 := maxf(deck.position.y, lo.z)
	var cov_z1 := minf(deck.end.y, hi.z)
	print("  交集：x %.2f ~ %.2f（宽 %.2f）、z %.2f ~ %.2f（深 %.2f）" % [
		cov_x0, cov_x1, cov_x1 - cov_x0, cov_z0, cov_z1, cov_z1 - cov_z0])
	var miss_z := 0.0
	if lo.z < deck.position.y:
		miss_z = deck.position.y - lo.z
	print("  屋壳比 Deck 更靠里（-z）露出来的深度 = %.2f m%s" % [
		miss_z, "   ← **没有地板**" if miss_z > 0.01 else ""])
	if hi.z > deck.end.y:
		print("  屋壳比 Deck 更靠外（+z）露出来的深度 = %.2f m  ← **没有地板**" % (hi.z - deck.end.y))
	if lo.x < deck.position.x:
		print("  屋壳比 Deck 更靠西露出来的宽度 = %.2f m  ← **没有地板**" % (deck.position.x - lo.x))
	if hi.x > deck.end.x:
		print("  屋壳比 Deck 更靠东露出来的宽度 = %.2f m  ← **没有地板**" % (hi.x - deck.end.x))

	# ── ③ 屋壳 GLB 的网格：地板面在哪 ──
	print("\n========== ③ 屋壳 GLB 里的网格（找那块「看得见的地板」）==========")
	var shell := shop.get_node_or_null("Shell")
	if shell == null:
		print("  没有 Shell 节点")
	else:
		var rows := []
		_collect(shell, rows, shop)
		rows.sort_custom(func(a, b): return a[1].size.x * a[1].size.z > b[1].size.x * b[1].size.z)
		for r in rows:
			var bb: AABB = r[1]
			# 只看「平」的大面：高度很薄、水平面很大
			var flat := bb.size.y < 0.6 and (bb.size.x * bb.size.z) > 4.0
			print("  %-34s y %7.3f ~ %7.3f   x %.2f~%.2f z %.2f~%.2f%s" % [
				r[0], bb.position.y, bb.position.y + bb.size.y,
				bb.position.x, bb.position.x + bb.size.x,
				bb.position.z, bb.position.z + bb.size.z,
				"   ← 大平片" if flat else ""])
		print("  （共 %d 个网格）" % rows.size())

	quit(0)


func _collect(n: Node, rows: Array, shop: Node3D) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			rows.append([mi.name, mi.global_transform * mi.get_aabb()])
	for c in n.get_children():
		_collect(c, rows, shop)
