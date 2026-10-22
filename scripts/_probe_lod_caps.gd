extends SceneTree
## 只读探针：查这台 Godot 4.7.1 **本体**到底带了哪些 LOD 能力（不查文档，问引擎）。
##   godot --headless --path . --script res://scripts/_probe_lod_caps.gd

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# ① 项目设置里所有带 lod 的项 + 默认值
	var keys := PackedStringArray()
	for k in ProjectSettings.get_property_list():
		var name := String(k.get("name", ""))
		if name.to_lower().contains("lod"):
			keys.append(name)
	keys.sort()
	print("[lod] ProjectSettings 里含 lod 的项 %d 个：" % keys.size())
	for k in keys:
		print("[lod]   %-52s = %s" % [k, str(ProjectSettings.get_setting(k))])

	# ② 关键属性/方法存不存在
	var checks := [
		["Viewport", "mesh_lod_threshold", "prop"],
		["GeometryInstance3D", "lod_bias", "prop"],
		["GeometryInstance3D", "visibility_range_begin", "prop"],
		["GeometryInstance3D", "visibility_range_end", "prop"],
		["GeometryInstance3D", "visibility_range_fade_mode", "prop"],
		["ImporterMesh", "generate_lods", "method"],
		["ImporterMesh", "get_mesh", "method"],
		["Mesh", "get_lod_count", "method"],
		["MeshInstance3D", "get_lod_bias", "method"],
	]
	for c in checks:
		var cls := String(c[0])
		var what := String(c[1])
		var ok := false
		if String(c[2]) == "prop":
			for p in ClassDB.class_get_property_list(cls):
				if String(p.get("name", "")) == what:
					ok = true
					break
		else:
			ok = ClassDB.class_has_method(cls, what)
		print("[lod] %-24s %-26s %s" % [cls, what, "有" if ok else "没有"])

	# ③ 现在这棵具体的树里，有多少网格能吃到 LOD
	print("[lod] Mesh 类可用方法里含 lod 的：%s"
		% str(ClassDB.class_get_method_list("Mesh").filter(
			func(m: Dictionary) -> bool: return String(m.get("name", "")).contains("lod")
		).map(func(m: Dictionary) -> String: return String(m.get("name")))))
	print("[lod] ArrayMesh 里含 lod 的方法：%s"
		% str(ClassDB.class_get_method_list("ArrayMesh").filter(
			func(m: Dictionary) -> bool: return String(m.get("name", "")).contains("lod")
		).map(func(m: Dictionary) -> String: return String(m.get("name")))))
	quit(0)
