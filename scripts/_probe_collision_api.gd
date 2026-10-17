extends SceneTree
## 探针：Godot 4.7.1 到底有没有「自动凹包分解」（对应 UE 的 Convex Decomposition）？
## 直接问 `ClassDB`，不翻文档、不猜。
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_collision_api.gd


func _initialize() -> void:
	print("[api] 引擎版本 %s" % Engine.get_version_info()["string"])

	print("\n--- MeshInstance3D 上的碰撞生成方法 ---")
	for m in ["create_convex_collision", "create_multiple_convex_collisions",
			"create_trimesh_collision", "create_debug_tangents"]:
		print("   %-36s %s" % [m, ClassDB.class_has_method("MeshInstance3D", m)])

	print("\n--- Mesh 上的 ---")
	for m in ["create_convex_shape", "create_trimesh_shape", "create_outline"]:
		print("   %-36s %s" % [m, ClassDB.class_has_method("Mesh", m)])

	print("\n--- 名字里带 convex / decompos / hull 的类 ---")
	var hits: Array[String] = []
	for c in ClassDB.get_class_list():
		var l := String(c).to_lower()
		if l.contains("convex") or l.contains("decompos") or l.contains("hull") or l.contains("vhacd"):
			hits.append(String(c))
	print("   " + (", ".join(hits) if not hits.is_empty() else "（一个都没有）"))

	print("\n--- 和形状有关的类 ---")
	var shapes: Array[String] = []
	for c in ClassDB.get_class_list():
		if String(c).ends_with("Shape3D"):
			shapes.append(String(c))
	print("   " + ", ".join(shapes))

	print("\n--- ConcavePolygonShape3D 的属性 ---")
	for p in ClassDB.class_get_property_list("ConcavePolygonShape3D"):
		print("   %s : %s" % [p["name"], p["type"]])

	print("\n--- VHACD 模块 / 编辑器插件在不在 ---")
	print("   ClassDB.class_exists('VHACD') = %s" % ClassDB.class_exists("VHACD"))
	var dir := DirAccess.open("res://addons")
	print("   res://addons 存在 = %s" % str(dir != null))
	if dir != null:
		for d in dir.get_directories():
			print("     addons/%s" % d)

	print("\n--- MeshInstance3D 全部方法（筛 convex / collision / decompose）---")
	for m in ClassDB.class_get_method_list("MeshInstance3D", true):
		var n := String(m["name"])
		if n.contains("convex") or n.contains("collision") or n.contains("decompos"):
			var args: Array[String] = []
			for a in m["args"]:
				args.append("%s: %s" % [a["name"], a["type"]])
			print("   %s(%s)" % [n, ", ".join(args)])

	print("\n--- Mesh 全部方法（筛 convex / decompos）---")
	for m in ClassDB.class_get_method_list("Mesh", true):
		var n := String(m["name"])
		if n.contains("convex") or n.contains("decompos"):
			var args: Array[String] = []
			for a in m["args"]:
				args.append("%s: %s" % [a["name"], a["type"]])
			print("   %s(%s)" % [n, ", ".join(args)])

	print("\n--- MeshConvexDecompositionSettings 的属性 ---")
	for p in ClassDB.class_get_property_list("MeshConvexDecompositionSettings", true):
		print("   %-28s type=%s" % [p["name"], p["type"]])
	quit(0)
