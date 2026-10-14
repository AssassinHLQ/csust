extends SceneTree
## 侦察：这个 Godot 版本到底认不认高斯泼溅（原生类 / 导入器 / 项目设置）。
## 用法：godot --path <工程> --headless --script res://scripts/_probe_splat.gd

func _initialize() -> void:
	var v := Engine.get_version_info()
	print("Godot %s.%s.%s (%s)  build=%s" % [
		v["major"], v["minor"], v["patch"], v["status"], v["build"]])
	print("mono = %s" % str(ClassDB.class_exists("CSharpScript")))
	print("")

	var all := ClassDB.get_class_list()
	print("ClassDB 总类数 = %d" % all.size())

	var hits := 0
	print("--- 名字里带 splat / gauss / radiance / nerf 的类 ---")
	for c in all:
		var l := String(c).to_lower()
		if l.contains("splat") or l.contains("gauss") or l.contains("radiance") or l.contains("nerf"):
			print("  %s" % c)
			hits += 1
	if hits == 0:
		print("  （无）")

	print("\n--- 名字里带 Import 的类（看有没有 ply/splat 导入器）---")
	for c in all:
		var l := String(c).to_lower()
		if l.contains("import"):
			print("  %s" % c)

	print("\n--- 名字里带 Ply 的类 ---")
	hits = 0
	for c in all:
		if String(c).to_lower().contains("ply"):
			print("  %s" % c)
			hits += 1
	if hits == 0:
		print("  （无）")

	print("\n--- 项目设置里带 splat/gauss 的键 ---")
	hits = 0
	for p in ProjectSettings.get_property_list():
		var n := String(p.get("name", ""))
		var l := n.to_lower()
		if l.contains("splat") or l.contains("gauss"):
			print("  %s" % n)
			hits += 1
	if hits == 0:
		print("  （无）")

	print("\n--- 已有的导入器插件（EditorImportPlugin 子类实例太麻烦，先看资源格式）---")
	print("  load(\"res://models/Arisu.glb\") = %s" % str(load("res://models/Arisu.glb") != null))

	print("\n--- Node3D 家族里能当「网格」用的（抽查）---")
	for c in ["MeshInstance3D", "MultiMeshInstance3D", "GPUParticles3D", "QuadMesh", "PointMesh"]:
		print("  %-22s 存在 = %s" % [c, str(ClassDB.class_exists(c))])

	quit(0)
