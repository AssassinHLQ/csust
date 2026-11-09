extends SceneTree
## 量电脑城（Shop）里每个网格的世界 AABB，判断哪些需要碰撞。
##
##   godot --path . --headless --script res://scripts/_probe_shop_meshes.gd
##
## 背景：`shop.gd:185` 写着「2026-11-07 用户：芹香的桌子也不要了，放个人就行了——
##       柜台整套撤掉，只留人」，所以**程序化柜台已经没了**。
##       但新屋壳 GLB（Sketchfab「Shop」）自带柜台/货架/玻璃隔断，
##       那些是网格、**没有碰撞**，人可以直接穿过去。
##
## 这个探针把 GLB 里 7 个 mesh 的名字、面数、世界 AABB 全列出来，
## 再按「薄且高 = 墙 / 扁且低 = 台面 / 透明 = 玻璃」分类，给出建议。

const SCENE := "res://scenes/shop_baked.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var shop := (load(SCENE) as PackedScene).instantiate()
	root.add_child(shop)
	current_scene = shop
	await process_frame
	await process_frame
	await process_frame

	print("[shopmesh] Shop 世界位置 = %s" % str((shop as Node3D).global_position))

	# 现有碰撞
	print("[shopmesh] ── 现有碰撞盒 ──")
	for n in shop.find_children("*", "CollisionShape3D", true, false):
		var cs := n as CollisionShape3D
		if cs.shape is BoxShape3D:
			var s: Vector3 = (cs.shape as BoxShape3D).size
			var b: AABB = cs.global_transform * AABB(-s * 0.5, s)
			print("[shopmesh]   %-24s 世界 x %7.2f~%7.2f  y %6.2f~%6.2f  z %7.2f~%7.2f" % [
				cs.name,
				b.position.x, b.position.x + b.size.x,
				b.position.y, b.position.y + b.size.y,
				b.position.z, b.position.z + b.size.z])

	# GLB 里每个 mesh
	print("[shopmesh] ── GLB 网格（Shell 下）──")
	var shell := shop.get_node_or_null("Shell")
	if shell == null:
		print("[shopmesh] !! 没有 Shell 节点")
		quit(1)
		return

	for m in shell.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var b: AABB = mi.global_transform * mi.mesh.get_aabb()
		var tris := 0
		if mi.mesh is ArrayMesh:
			var am := mi.mesh as ArrayMesh
			for si in am.get_surface_count():
				var arr := am.surface_get_arrays(si)
				if arr.size() > Mesh.ARRAY_INDEX:
					tris += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		# 材质是不是透明（玻璃）
		var alpha := 1.0
		var mat := mi.get_active_material(0)
		if mat is StandardMaterial3D:
			alpha = (mat as StandardMaterial3D).albedo_color.a
			if (mat as StandardMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				alpha = minf(alpha, 0.5)
		print("[shopmesh]   %-32s 面 %6d  透明 %.2f" % [mi.name, tris, alpha])
		print("[shopmesh]        x %7.2f~%7.2f  y %6.2f~%6.2f  z %7.2f~%7.2f  尺寸 %.2f×%.2f×%.2f" % [
			b.position.x, b.position.x + b.size.x,
			b.position.y, b.position.y + b.size.y,
			b.position.z, b.position.z + b.size.z,
			b.size.x, b.size.y, b.size.z])

	print("[shopmesh] 完成")
	quit(0)
