extends SceneTree
## 量画室609 每面墙的**内表面**在哪，给「跨进门槛才加载」定判据。
##
##   godot --path . --headless --script res://scripts/_probe_wall_inner.gd
##
## 为什么需要：现在的判据是「墙盒外框内收 0.05 m」，但墙有 0.30 m 厚，
## 于是判据边界正好落在墙里 —— 玩家站在**墙内那一侧**（还没进屋）就已经
## 被判成「在屋里」了。用户实测 x=5.74 距判据边界只剩 0.36 m，站在那里
## 泼溅就加载了（他要的是跨进门才加载）。
##
## 打印：每面墙的 法向轴 / 外表面 / 内表面 / 厚度，以及内表面围成的矩形。

const SCENE := "res://scenes/game.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load(SCENE) as PackedScene
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame

	var col: Node = scene.get_node_or_null("Room609/RoomCollision")
	if col == null:
		print("[inner] !! 找不到 RoomCollision")
		quit(1)
		return

	# 先求所有墙的外框
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var walls: Array = []
	for c in col.get_children():
		var cs := c as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		var s: Vector3 = (cs.shape as BoxShape3D).size
		if s.y <= 2.0:
			continue
		var b: AABB = cs.global_transform * AABB(-s * 0.5, s)
		walls.append({"name": cs.name, "box": b, "size": s})
		lo = lo.min(b.position)
		hi = hi.max(b.position + b.size)

	print("[inner] 墙外框 x %.2f~%.2f  z %.2f~%.2f  y %.2f~%.2f" % [
		lo.x, hi.x, lo.z, hi.z, lo.y, hi.y])
	print("[inner] ── 每面墙 ──")

	# 每面墙：判断它贴在哪一侧，求出「指向房间内部」的那个面
	var cx := (lo.x + hi.x) * 0.5
	var cz := (lo.z + hi.z) * 0.5
	var inner_lo := Vector3(INF, INF, INF)
	var inner_hi := Vector3(-INF, -INF, -INF)
	for w in walls:
		var b: AABB = w["box"]
		var s: Vector3 = w["size"]
		# 墙是薄的：厚度方向 = 尺寸最小的水平轴
		var thin_x := s.x < s.z
		var axis := "x" if thin_x else "z"
		var thick := s.x if thin_x else s.z
		var center := (b.position + b.size * 0.5)
		# 外表面 = 离房间中心更远的那一面
		var outer_face := 0.0
		var inner_face := 0.0
		if thin_x:
			var dist_lo := absf(b.position.x - cx)
			var dist_hi := absf(b.position.x + b.size.x - cx)
			if dist_hi > dist_lo:
				outer_face = b.position.x + b.size.x
				inner_face = b.position.x
			else:
				outer_face = b.position.x
				inner_face = b.position.x + b.size.x
		else:
			var dist_lo := absf(b.position.z - cz)
			var dist_hi := absf(b.position.z + b.size.z - cz)
			if dist_hi > dist_lo:
				outer_face = b.position.z + b.size.z
				inner_face = b.position.z
			else:
				outer_face = b.position.z
				inner_face = b.position.z + b.size.z
		print("[inner]   %-12s 轴 %s  外表面 %.2f  内表面 %.2f  厚 %.2f" % [
			w["name"], axis, outer_face, inner_face, thick])
		inner_lo = inner_lo.min(b.position)
		inner_hi = inner_hi.max(b.position + b.size)

	# 内表面矩形：取所有墙盒的并集，然后各方向收掉墙厚
	# 更简单可靠：外框各方向减去对应墙的厚度
	var thick_x := 0.0
	var thick_z := 0.0
	for w in walls:
		var s: Vector3 = w["size"]
		if s.x < s.z:
			thick_x = maxf(thick_x, s.x)
		else:
			thick_z = maxf(thick_z, s.z)
	print("[inner] 墙厚：x 向 %.2f，z 向 %.2f" % [thick_x, thick_z])
	print("[inner] ── 内表面矩形（= 真正能站人的范围）──")
	print("[inner]   x %.2f ~ %.2f" % [lo.x + thick_x, hi.x - thick_x])
	print("[inner]   z %.2f ~ %.2f" % [lo.z + thick_z, hi.z - thick_z])

	print("[inner] ── 玩家实测位置 (5.74, 0.00, 1.81) 判定 ──")
	print("[inner]   旧判据（外框内收 0.05）: x %.2f~%.2f → %s" % [
		lo.x + 0.05, hi.x - 0.05,
		"在屋里（会加载）" if 5.74 <= hi.x - 0.05 and 5.74 >= lo.x + 0.05 else "在屋外"])
	print("[inner]   新判据（内表面）      : x %.2f~%.2f → %s" % [
		lo.x + thick_x, hi.x - thick_x,
		"在屋里（会加载）" if 5.74 <= hi.x - thick_x and 5.74 >= lo.x + thick_x else "在屋外（不加载）"])
	print("[inner] 完成")
	quit(0)
