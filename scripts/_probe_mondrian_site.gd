extends SceneTree
## 探针：给蒙德里安大楼选地基 —— 量出商店正对面的空地，并检查有没有障碍物。
##   godot --path . --headless --script res://scripts/_probe_mondrian_site.gd -- --splat=off
##
## 商店（`shop.gd`）：世界中心 x=27.30、z=-15.50；墙体 x 20.70~33.90、z -18.30~-12.70；
## 门在南墙（+Z 侧）：z = -12.70，门中心 x = 27.30。
## 商店地板一直铺到 x = 40.00、z -20.00 ~ +20.00。
## 平台（`Floor`）是 40 × 40，中心 (0,-0.5,0) → 覆盖 x -20~20、z -20~20。

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 90:
		await process_frame

	var space := (root.get_world_3d() as World3D).direct_space_state

	# ── 1. 商店的实测数值（不照抄注释，现场量）──
	var shop := game.get_node_or_null("Shop") as Node3D
	if shop == null:
		print("[错误] 场景里没有 Shop")
		quit(1)
		return
	print("Shop 世界原点 %s" % str(shop.global_position.snapped(Vector3.ONE * 0.01)))
	var bb := AABB()
	var first := true
	for mi in shop.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var a: AABB = m.global_transform * m.mesh.get_aabb()
		bb = a if first else bb.merge(a)
		first = false
	print("Shop 网格包围盒 x %.2f~%.2f  y %.2f~%.2f  z %.2f~%.2f" % [
		bb.position.x, bb.end.x, bb.position.y, bb.end.y, bb.position.z, bb.end.z])

	# ── 2. 商店正对面（南侧 z > -12.70）探一片地：看地上有没有东西 ──
	# 候选地块：x 20 ~ 40、z -12.70 ~ +18（商店门外的整片南侧空地）
	print("\n—— 商店门外南侧空地：从上往下打射线，看地表高度与有没有障碍 ——")
	const GRID := 4.0
	var z := -10.0
	while z <= 18.0:
		var line := ""
		var x := 20.5
		while x <= 39.5:
			var from := Vector3(x, 12.0, z)
			var q := PhysicsRayQueryParameters3D.create(from, Vector3(x, -6.0, z))
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				line += "?"
			else:
				var hy: float = hit["position"].y
				var nm := (hit["collider"] as Node).name
				if hy > 0.1:
					line += "#"          # 空中有东西（障碍/建筑）
				else:
					line += "."          # 平地
				if hy > 0.1:
					line = line.substr(0, line.length() - 1) + "#"
			x += GRID
		print("z=%+6.1f  %s" % [z, line])
		z += GRID
	print("（x 从 20.5 到 39.5，每格 %.0f m；. = 地面 y≈0， # = 空中有东西， ? = 打空）" % GRID)

	# ── 3. 逐点报出「高度 > 0.1 的命中」到底是哪个节点 ──
	print("\n—— 南侧空地上的障碍明细 ——")
	var seen := {}
	var zz := -10.0
	while zz <= 18.0:
		var xx := 20.5
		while xx <= 39.5:
			var q2 := PhysicsRayQueryParameters3D.create(
				Vector3(xx, 12.0, zz), Vector3(xx, -6.0, zz))
			var h2 := space.intersect_ray(q2)
			if not h2.is_empty() and (h2["position"] as Vector3).y > 0.1:
				var nm2 := str((h2["collider"] as Node).name)
				if not seen.has(nm2):
					seen[nm2] = 0
				seen[nm2] = int(seen[nm2]) + 1
			xx += GRID
		zz += GRID
	if seen.is_empty():
		print("（没有障碍：商店正对面整片是空平地）")
	else:
		for k in seen:
			print("  %-20s 命中 %d 个格点" % [k, int(seen[k])])

	# ── 4. 平台/地板的实际覆盖范围（射线打不到就说明掉虚空）──
	print("\n—— 地板覆盖率抽查 ——")
	for p in [Vector2(28, -8), Vector2(28, 0), Vector2(28, 10), Vector2(28, 19),
			Vector2(28, 21), Vector2(21, 20.5), Vector2(0, 0), Vector2(10, 10)]:
		var q3 := PhysicsRayQueryParameters3D.create(
			Vector3(p.x, 8.0, p.y), Vector3(p.x, -8.0, p.y))
		var h3 := space.intersect_ray(q3)
		if h3.is_empty():
			print("  (%.0f, %.0f) 打空 —— 没有地板（虚空）" % [p.x, p.y])
		else:
			print("  (%.0f, %.0f) 打中 %-12s y = %+.3f" % [
				p.x, p.y, (h3["collider"] as Node).name, (h3["position"] as Vector3).y])
	quit(0)
