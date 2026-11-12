extends SceneTree
## 找出电竞房里那个「想让人钻进去」的柜子：候选网格 + 罩住它的碰撞盒。
##
## 用户 2026-11-12：「这个电竞房柜子要可以进去」。
## 柜子的**外观**来自 `esports_room.glb`（`Room` 实例里的家具网格），
## 而挡住人的是 `BakedCollision/AutoCol` 里那 769 个烘焙碰撞盒。
##
## ⚠️ `find_children()` 的 pattern 匹配的是**节点名字**，不是路径 ——
##    第一版写成 `"Room/*"` 结果一个都没匹配到（量出来的房间范围是 0.0~0.0）。
##    所以这里先取 `Room` 节点，再在它下面 `find_children("*", ...)`。
##
##   godot --path . --script res://scripts/_probe_esports_cabinet.gd -- --splat=off --story=off

const OFF := preload("res://scripts/offscreen_window.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await OFF.apply(self, Vector2i(1280, 720))
	for _i in 3:
		await process_frame
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 60:
		await process_frame
	paused = false

	var room := game.get_node_or_null("EsportsRoom") as Node3D
	if room == null:
		print("❌ 没有 EsportsRoom")
		quit(1)
		return
	room.visible = true
	var glb := room.get_node_or_null("Room")
	if glb == null:
		print("❌ 没有 EsportsRoom/Room")
		quit(1)
		return

	# 房间 GLB 总范围（当过滤基准）
	var room_box := AABB()
	var first := true
	for mi in glb.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var b: AABB = m.global_transform * m.mesh.get_aabb()
		room_box = b if first else room_box.merge(b)
		first = false
	print("\n房间 GLB 总范围  XZ x %.1f~%.1f  z %.1f~%.1f   y %.2f~%.2f"
		% [room_box.position.x, room_box.end.x, room_box.position.z, room_box.end.z,
			room_box.position.y, room_box.end.y])

	# ── ① 柜子候选：高 1.5~3.2 m、最长水平边 < 3 m、厚度方向 < 1.2 m ──
	print("\n======== 「柜子」候选（高 1.5~3.2 m，占地不大）========")
	var cands: Array = []
	var seen := {}
	for mi in glb.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var b: AABB = m.global_transform * m.mesh.get_aabb()
		if b.size.y < 1.5 or b.size.y > 3.2:
			continue
		if maxf(b.size.x, b.size.z) > 3.0:
			continue
		if minf(b.size.x, b.size.z) > 1.2:
			continue
		var key := "%s|%.1f|%.1f|%.1f" % [String(m.name), b.position.x, b.position.z, b.size.y]
		if seen.has(key):
			continue
		seen[key] = true
		cands.append({"n": String(m.name), "b": b})
	cands.sort_custom(func(a, c): return float(a["b"].size.y) > float(c["b"].size.y))
	print("  共 %d 个：" % cands.size())
	for r in cands:
		var b: AABB = r["b"]
		print("  %-34s y %.2f~%.2f  x %.2f~%.2f  z %.2f~%.2f  (%.2f×%.2f×%.2f)"
			% [String(r["n"]), b.position.y, b.end.y, b.position.x, b.end.x,
				b.position.z, b.end.z, b.size.x, b.size.y, b.size.z])

	# ── ② 与候选相交的碰撞盒 ──
	var auto := room.get_node_or_null("BakedCollision/AutoCol")
	if auto == null:
		print("\n❌ 没有 BakedCollision/AutoCol")
		quit(0)
		return
	var boxes: Array = []
	for c in auto.get_children():
		var cs := c as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		var sz: Vector3 = (cs.shape as BoxShape3D).size
		var half: Vector3 = cs.global_transform.basis.get_scale().abs() * sz * 0.5
		boxes.append({"n": String(cs.name),
			"b": AABB(cs.global_position - half, half * 2.0)})
	print("\n======== 烘焙碰撞盒共 %d 个 ========" % boxes.size())
	print("与每个候选 AABB 相交的盒子：")
	for r in cands:
		var probe: AABB = (r["b"] as AABB).grow(0.15)
		var hits: Array = []
		for e in boxes:
			if (e["b"] as AABB).intersects(probe):
				hits.append(e)
		print("  「%s」→ %d 个相交盒" % [String(r["n"]), hits.size()])
		for e in hits:
			var b: AABB = e["b"]
			print("      %-14s (%.2f×%.2f×%.2f)  x %.2f~%.2f y %.2f~%.2f z %.2f~%.2f"
				% [String(e["n"]), b.size.x, b.size.y, b.size.z,
					b.position.x, b.end.x, b.position.y, b.end.y,
					b.position.z, b.end.z])
	quit(0)
