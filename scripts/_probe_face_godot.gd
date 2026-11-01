extends SceneTree
## 看清「脸」在 Godot 侧到底长什么样：口型网格是否全部可见、贴图、透明模式、形态键。
##
## 运行：
##   & $godot --headless --path <_arisu_learn> --script res://scripts/_probe_face_godot.gd

const FILES := ["res://models/companions/Kei_ext.glb", "res://models/Arisu_ext.glb"]


func _init() -> void:
	_run()


func _run() -> void:
	for path in FILES:
		if not ResourceLoader.exists(path):
			print("!! 找不到 %s" % path)
			continue
		var scene: Node = load(path).instantiate()
		root.add_child(scene)
		await process_frame
		print("")
		print("======== %s ========" % path)
		var mouths := []
		var others := []
		for m in _all(scene, "MeshInstance3D"):
			var mi := m as MeshInstance3D
			if mi.name.begins_with("Mouth"):
				mouths.append(mi)
			else:
				others.append(mi)
		print("  MeshInstance3D 共 %d（Mouth* %d）" % [mouths.size() + others.size(), mouths.size()])
		print("  非 Mouth 网格：")
		for mi in others:
			print("    %-26s 可见=%-5s 尺寸 %s 蒙皮=%s" % [
				mi.name, str(mi.visible), _v(mi.get_aabb().size),
				str(mi.skin != null)])
		print("  Mouth* 网格：")
		var visible_count := 0
		for mi in mouths:
			var mesh: Mesh = mi.mesh
			var bs := 0
			var bs_val := ""
			if mesh != null:
				bs = mesh.get_blend_shape_count()
				if bs > 0:
					bs_val = "  morph0=%.2f" % mi.get_blend_shape_value(0)
			var tex := "(无)"
			var alpha := "-"
			var mat: Material = mi.get_active_material(0)
			if mat is BaseMaterial3D:
				var bm := mat as BaseMaterial3D
				if bm.albedo_texture != null:
					tex = bm.albedo_texture.resource_path.get_file()
					if tex == "":
						tex = bm.albedo_texture.resource_name
				alpha = str(bm.transparency)
			elif mat != null:
				alpha = mat.get_class()
			if mi.visible:
				visible_count += 1
			print("    %-22s 可见=%-5s 尺寸 %-22s 形态键=%d%s  贴图=%s 透明=%s  父=%s" % [
				mi.name, str(mi.visible), _v(mi.get_aabb().size), bs, bs_val, tex, alpha,
				mi.get_parent().name if mi.get_parent() else "-"])
		print("  >>> Mouth* 中 visible=true 的有 %d / %d" % [visible_count, mouths.size()])
		print("  --- 名字含 eye / brow 的骨骼 ---")
		var sk := _skel(scene)
		if sk != null:
			var names := []
			for i in sk.get_bone_count():
				var bn := sk.get_bone_name(i)
				var low := bn.to_lower()
				if low.contains("eye") or low.contains("brow") or low.contains("mouth") \
						or low.contains("lip") or low.contains("cheek"):
					names.append(bn)
			print("    共 %d 根：%s" % [names.size(), ", ".join(names)])
		scene.queue_free()
		await process_frame
	print("")
	print("=== 完毕 ===")
	quit(0)


func _v(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]


func _skel(node: Node) -> Skeleton3D:
	for s in _all(node, "Skeleton3D"):
		var sk := s as Skeleton3D
		if sk.get_bone_count() > 50:
			return sk
	return null


func _all(node: Node, cls: String) -> Array:
	var out := []
	if node.is_class(cls):
		out.append(node)
	for c in node.get_children():
		out.append_array(_all(c, cls))
	return out
