extends SceneTree
## 查这个 Godot 4.7.1 里有哪些「少画面数」的家伙什（只看引擎实际有什么，不猜）。
##   _tools/run_probe.sh res://scripts/_probe_godot_features.gd


func _initialize() -> void:
	for cls in ["OccluderInstance3D", "MultiMeshInstance3D", "MultiMesh",
			"ImporterMesh", "MeshInstance3D", "GeometryInstance3D"]:
		print("[feat] 类 %-22s 存在=%s" % [cls, str(ClassDB.class_exists(cls))])

	print("[feat] ── LOD / 可见距离 / 剔除相关属性 ──")
	for cls in ["MeshInstance3D", "GeometryInstance3D"]:
		for p in ClassDB.class_get_property_list(cls):
			var n := String(p["name"])
			if n.contains("lod") or n.contains("visibility") or n.contains("occlu") \
					or n.contains("cull") or n.contains("cast_shadow"):
				print("[feat]   %-18s %s" % [cls, n])

	print("[feat] ── 类名带 virtual/cluster/impostor 的 ──")
	var hits := 0
	for c in ClassDB.get_class_list():
		var s := String(c).to_lower()
		if s.contains("virtual") or s.contains("cluster") or s.contains("impostor"):
			print("[feat]   %s" % c)
			hits += 1
	print("[feat]   命中 %d 个" % hits)

	print("[feat] ── 渲染相关项目设置（有没有画质护栏/剔除开关）──")
	for p in ProjectSettings.get_property_list():
		var n := String(p["name"])
		if n.begins_with("rendering/") and (n.contains("occlusion") or n.contains("lod") \
				or n.contains("mesh") or n.contains("shadow") or n.contains("driver")):
			print("[feat]   %s = %s" % [n, str(ProjectSettings.get_setting(n))])
	quit(0)