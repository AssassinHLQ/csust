extends SceneTree
## 查「全局 LOD 距离」这条路在 4.7 里有哪些可用接口。
##
## ⚠️ `Viewport` 是抽象类，不能 `Viewport.new()`（第一次就这么写，解析报错）。
##    改用 `root`（SceneTree.root 就是根 Window，本身是 Viewport）。
##
## 用法：_tools/run_probe.sh res://scripts/_probe_lod_caps.gd

func _initialize() -> void:
	print("[lod] ── 根 Viewport 上跟 LOD 有关的属性 ──")
	var found := 0
	for p in root.get_property_list():
		var nm := String(p.get("name", ""))
		if nm.contains("lod"):
			found += 1
			print("[lod]   Viewport.%s  type=%d  hint=%s" % [
				nm, int(p.get("type", 0)), str(p.get("hint_string", ""))])
	if found == 0:
		print("[lod]   （没有）")
	print("[lod]   当前 mesh_lod_threshold = %s" % str(root.mesh_lod_threshold))

	print("[lod] ── ProjectSettings 里的 mesh_lod 项 ──")
	for p in ProjectSettings.get_property_list():
		var nm := String(p.get("name", ""))
		if nm.contains("mesh_lod"):
			print("[lod]   %s = %s（默认 %s）" % [
				nm, str(ProjectSettings.get_setting(nm)),
				str(ProjectSettings.property_get_revert(nm))])

	print("[lod] ── GeometryInstance3D ──")
	var mi := MeshInstance3D.new()
	print("[lod]   lod_bias 默认 = %s" % str(mi.lod_bias))
	print("[lod]   visibility_range_end 默认 = %s" % str(mi.visibility_range_end))
	mi.free()

	print("[lod] ── 运行时改不动？试一下赋值能否立刻回读 ──")
	var before := root.mesh_lod_threshold
	root.mesh_lod_threshold = 2.5
	print("[lod]   设 2.5 后回读 = %s（原 %s）" % [str(root.mesh_lod_threshold), str(before)])
	root.mesh_lod_threshold = before
	quit()
