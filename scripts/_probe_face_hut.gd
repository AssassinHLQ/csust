extends SceneTree
## 探针：① 芹香脸上的表情怎么换（网格 / 形态键清单）
##       ② 小屋 MeshHut 和天使24（Shop）各多高
##       ③ 芹香的脚到底离地多少
##   godot --path . --script res://scripts/_probe_face_hut.gd -- --splat=off
func _initialize() -> void:
	_run.call_deferred()


func _aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var all: Array = []
	if n is VisualInstance3D:
		all.append(n)
	all.append_array(n.find_children("*", "VisualInstance3D", true, false))
	for x in all:
		var a := AABB()
		var ok := false
		if x is MeshInstance3D and (x as MeshInstance3D).mesh != null:
			a = (x as MeshInstance3D).global_transform * (x as MeshInstance3D).mesh.get_aabb()
			ok = true
		elif x is CSGShape3D:
			var cs := x as CSGShape3D
			if cs.is_inside_tree():
				await process_frame
			a = cs.global_transform * cs.get_aabb()
			ok = true
		if ok:
			if first:
				out = a
				first = false
			else:
				out = out.merge(a)
	return out


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 60:
		await process_frame
	paused = false

	print("── ① 芹香的脸 ──")
	var clerk := game.get_node_or_null("Shop/ClerkSerika") as Node3D
	if clerk != null:
		for mi in clerk.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var mesh := m.mesh
			if mesh == null:
				continue
			var bs: int = mesh.get_blend_shape_count()
			var surf: int = mesh.get_surface_count()
			var note := ""
			if m.name.to_lower().contains("face") or m.name.to_lower().contains("head") \
					or m.name.to_lower().contains("eye") or m.name.to_lower().contains("mouth"):
				note = "  ← 疑似脸部"
			print("  %-28s surf=%d 形态键=%d%s" % [m.name, surf, bs, note])
			if bs > 0:
				var names := []
				for i in bs:
					names.append(mesh.get_blend_shape_name(i))
				print("      形态键：%s" % str(names))
			# 每个 surface 的材质名（BA 模型常用换贴图做表情）
			for s in surf:
				var mat := m.get_active_material(s)
				print("      surf%d 材质：%s" % [s, mat.resource_name if mat else "null"])

	print("── ② 高度 ──")
	for nm in ["MeshHut", "Shop", "RoomProxy"]:
		var n := game.get_node_or_null(nm) as Node3D
		if n == null:
			print("  %s：没有" % nm)
			continue
		var a := await _aabb(n)
		print("  %-10s y %.2f ~ %.2f（高 %.2f m）  x %.1f~%.1f  z %.1f~%.1f" % [
			nm, a.position.y, a.position.y + a.size.y, a.size.y,
			a.position.x, a.position.x + a.size.x,
			a.position.z, a.position.z + a.size.z])

	print("── ③ 芹香的脚 ──")
	if clerk != null:
		var a2 := await _aabb(clerk)
		print("  世界 AABB y %.3f ~ %.3f（地面 y=0）→ 脚离地 %.3f m" % [
			a2.position.y, a2.position.y + a2.size.y, a2.position.y])
		print("  节点位置 %s" % str(clerk.global_position.snappedf(0.001)))
	quit(0)
