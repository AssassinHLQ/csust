extends SceneTree
## 只读：列出 Yuuka.glb 每个表面的材质名 / 贴图路径 / 透明模式。
##
##   Godot --headless --script res://scripts/_probe_yuuka_mats.gd
##
## 用途：要只给「优香-恐怖」换眼睛贴图，得先知道哪一面是眼睛。

const PATH := "res://models/companions/Yuuka.glb"


func _initialize() -> void:
	var ps := load(PATH) as PackedScene
	if ps == null:
		print("[ymat] ✗ 载入失败")
		quit(1)
		return
	var inst := ps.instantiate()
	root.add_child(inst)
	var seen := {}
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(s)
			if mat == null:
				continue
			var std := mat as BaseMaterial3D
			var key := "%s|%s|%s" % [mat.resource_name, std.resource_path,
				std.albedo_texture.resource_path if std != null and std.albedo_texture != null else "<无>"]
			if seen.has(key):
				continue
			seen[key] = true
			print("网格 %-22s 面%d  材质 %-24s 贴图 %s  透明=%s" % [
				m.name, s, mat.resource_name,
				std.albedo_texture.resource_path if std != null and std.albedo_texture != null else "<无>",
				str(std.transparency) if std != null else "?"])
	print("[ymat] 共 %d 种材质表面组合" % seen.size())
	quit(0)
