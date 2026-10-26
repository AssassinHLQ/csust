extends SceneTree
## 探针：给「往后挪、贴近地块边缘」的蒙德里安大楼重新选点。
##   godot --path . --headless --script res://scripts/_probe_mondrian_spot.gd -- --splat=off
##
## 用户 2026-10-26：「房子靠后到接近边缘，不要挡店铺」。
## 原来摆在 (27.30, 0, −2.00)：北墙 z = −8.00，离商店门（z = −12.70）只有 4.70 m ——
## 出门就是一面 16 m 宽的大墙，把店铺整个挡在后面。
##
## 这次要量三件事：
##   ① 商店门、商店地板（Deck）、主平台（Floor）的**实际边界**（不照抄注释）；
##   ② 往南（+Z）一直推到地块边缘那段路的**地面高度与障碍**：楼房的地基必须全落在
##      实地上，不能有一条边悬空（`mondrian_house.gd` 的一层地面**没有碰撞**，
##      玩家踩的是 Deck / 平台，脚下缺一块就是掉下去）；
##   ③ footprint（外墙外表面围出的 16 × 12 m 矩形）四角 + 四边中点是否落在
##      **Deck ∪ 主平台** 之内，再在室内几个空点上打射线确认地面就在 y = 0。
##
## ⚠️ ③ 为什么不直接「在 footprint 上打射线」：楼已经站在那儿了，射线打中的是
##    楼自己的墙、楼梯和家具，量到的是「有东西」而不是「有地板」。所以改成
##    量两块地板的实际范围 + 判包含关系，另挑几个空点验 y = 0。

func _initialize() -> void:
	_run.call_deferred()


## 大楼外壳的两个半尺寸（只用来算 footprint，`mondrian_house.gd` 的真实尺寸）
const HALF_W := 8.00
const HALF_D := 6.00
const EAVE := 0.50


func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 90:
		await process_frame

	var space := (root.get_world_3d() as World3D).direct_space_state
	var shop := game.get_node_or_null("Shop") as Node3D
	if shop == null:
		print("[错误] 场景里没有 Shop")
		quit(1)
		return
	var house := game.get_node_or_null("MondrianHouse") as Node3D

	# ── ① 商店门在哪（读实物，不读注释）──
	print("—— 商店 ——")
	print("Shop 世界原点 %s" % str(shop.global_position.snapped(Vector3.ONE * 0.01)))
	var door := shop.find_child("DoorHead", true, false) as MeshInstance3D
	if door != null:
		print("门头 DoorHead 世界中心 %s" % str(door.global_position.snapped(Vector3.ONE * 0.01)))
	var deck_rect: Rect2 = shop.get("deck_rect")
	print("Deck 地板：x %.2f ~ %.2f、z %.2f ~ %.2f"
		% [deck_rect.position.x, deck_rect.end.x, deck_rect.position.y, deck_rect.end.y])

	# ── ② 从 z = −10 一路扫到 z = +21：地面高度 + 障碍 ──
	print("\n—— 商店南侧到地块南沿：地表扫描（x 18 ~ 40，每格 1.5 m）——")
	print("   行 = z，列 = x（18 起）；. 平地(y≤0.1)  o 高台(0.1<y≤3)  # 建筑(y>3)  ? 打空")
	var z := -10.0
	while z <= 21.0:
		var line := ""
		var x := 18.0
		while x <= 40.0:
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
				Vector3(x, 14.0, z), Vector3(x, -8.0, z)))
			if hit.is_empty():
				line += "?"
			else:
				var hy: float = (hit["position"] as Vector3).y
				line += "." if hy <= 0.1 else ("o" if hy <= 3.0 else "#")
			x += 1.5
		print("z=%+6.1f  %s" % [z, line])
		z += 1.5

	# ── ③ 障碍明细 ──
	print("\n—— 南侧 x 18~40 / z +2~+21 的立体障碍明细 ——")
	var seen := {}
	z = 2.0
	while z <= 21.0:
		var x2 := 18.0
		while x2 <= 40.0:
			var h2 := space.intersect_ray(PhysicsRayQueryParameters3D.create(
				Vector3(x2, 14.0, z), Vector3(x2, -8.0, z)))
			if not h2.is_empty():
				var nm := str((h2["collider"] as Node).get_parent().name)
				var hy2: float = (h2["position"] as Vector3).y
				if hy2 > 0.15:
					var k := "%s (y=%.2f)" % [nm, hy2]
					seen[k] = int(seen.get(k, 0)) + 1
			x2 += 1.5
		z += 1.5
	if seen.is_empty():
		print("（没有任何高于 0.15 m 的东西：整片是空平地）")
	else:
		for k in seen:
			print("  %-28s 命中 %d 点" % [k, int(seen[k])])

	# ── ④ 地基判定：大楼 footprint 是否完全落在 Deck ∪ 主平台 之内 ──
	#
	# ⚠️ 不能用「在 footprint 上打射线」来验：楼自己已经站在那儿了，射线打中的是
	#    楼自己的墙/楼梯/家具。所以这里改成**量两块地板的实际范围**再判包含关系 ——
	#    `mondrian_house.gd` 的一层地面只有视觉没有碰撞，玩家真正踩的就是这两块。
	if house == null:
		print("[错误] 场景里没有 MondrianHouse")
		quit(1)
		return
	var hp := house.global_position
	var deck: Rect2 = shop.get("deck_rect")
	var floor_shape := game.get_node_or_null("Floor/Collision") as CollisionShape3D
	var plat := Rect2()
	if floor_shape != null:
		var fb := floor_shape.shape as BoxShape3D
		var fp := floor_shape.global_position
		plat = Rect2(Vector2(fp.x - fb.size.x * 0.5, fp.z - fb.size.z * 0.5),
			Vector2(fb.size.x, fb.size.z))
	print("\n—— 地基两块地板（实测）——")
	print("主平台 Floor/Collision：x %.2f ~ %.2f、z %.2f ~ %.2f"
		% [plat.position.x, plat.end.x, plat.position.y, plat.end.y])
	print("商店 Deck：x %.2f ~ %.2f、z %.2f ~ %.2f"
		% [deck.position.x, deck.end.x, deck.position.y, deck.end.y])

	# footprint = 外墙外表面（HALF_W × HALF_D）
	print("\n—— 大楼 footprint 是否处处有地板 ——")
	var fw := hp.x - HALF_W
	var fe := hp.x + HALF_W
	var fn := hp.z - HALF_D
	var fs := hp.z + HALF_D
	var corners := [
		["西北角", Vector2(fw, fn)], ["东北角", Vector2(fe, fn)],
		["西南角", Vector2(fw, fs)], ["东南角", Vector2(fe, fs)],
	]
	var bad := 0
	for c in corners:
		var p: Vector2 = c[1]
		var in_plat := p.x >= plat.position.x and p.x <= plat.end.x \
			and p.y >= plat.position.y and p.y <= plat.end.y
		var in_deck := p.x >= deck.position.x and p.x <= deck.end.x \
			and p.y >= deck.position.y and p.y <= deck.end.y
		var ok := in_plat or in_deck
		if not ok:
			bad += 1
		print("  %s (%.2f, %.2f)：%s（主平台 %s / Deck %s）"
			% [c[0], p.x, p.y, "有地" if ok else "**悬空**",
				"内" if in_plat else "外", "内" if in_deck else "外"])
	# 四条边中点也过一遍（角在、边中点不在是可能的：两块地板中间有 1 cm 缝）
	for e in [["北边中", Vector2(hp.x, fn)], ["南边中", Vector2(hp.x, fs)],
			["西边中", Vector2(fw, hp.z)], ["东边中", Vector2(fe, hp.z)]]:
		var p2: Vector2 = e[1]
		var ok2 := (p2.x >= plat.position.x and p2.x <= plat.end.x
				and p2.y >= plat.position.y and p2.y <= plat.end.y) \
			or (p2.x >= deck.position.x and p2.x <= deck.end.x
				and p2.y >= deck.position.y and p2.y <= deck.end.y)
		if not ok2:
			bad += 1
		print("  %s (%.2f, %.2f)：%s" % [e[0], p2.x, p2.y, "有地" if ok2 else "**悬空**"])
	print("  → %s（%d 个采样点悬空）" % ["footprint 全在地板上" if bad == 0 else "**有悬空**", bad])

	# 室内几个空点：从 y = 0.30 往下打，应当打到 y = 0.000 的地板
	print("\n—— 室内地面抽点（避开家具/楼梯）——")
	for p3 in [Vector2(24.0, 10.5), Vector2(30.0, 10.5), Vector2(33.0, 10.5),
			Vector2(24.0, 15.0), Vector2(33.0, 15.0)]:
		var h4 := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			Vector3(p3.x, 0.30, p3.y), Vector3(p3.x, -8.0, p3.y)))
		if h4.is_empty():
			print("  (%.1f, %.1f) **打空 —— 脚下没地板**" % [p3.x, p3.y])
		else:
			print("  (%.1f, %.1f) 打到 %-10s y = %+.3f" % [p3.x, p3.y,
				(h4["collider"] as Node).get_parent().name, (h4["position"] as Vector3).y])

	# ── ⑤ 和商店门的关系 ──
	print("\n—— 现状 ——")
	print("MondrianHouse 现在 (%.2f, %.2f, %.2f)：北墙 z = %.2f，南墙 z = %.2f，"
		% [hp.x, hp.y, hp.z, hp.z - HALF_D, hp.z + HALF_D]
		+ "屋檐外沿 z = %.2f" % (hp.z + HALF_D + EAVE))
	print("商店门世界坐标 z = %.2f  → 两门相距 %.2f m（横向偏移 %.2f m）"
		% [shop.global_position.z + 2.84, (hp.z - HALF_D) - (shop.global_position.z + 2.84),
			absf(hp.x - shop.global_position.x)])
	quit(0)
