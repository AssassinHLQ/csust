extends SceneTree
## 探针：把 **霍德** 的骨架扒开看 —— 骨骼名 / 父子关系 / 静止位姿 / 哪些网格挂在骨骼上。
## 要做「待机 + 攻击」的程序化动画，必须先知道能扭哪几根骨头（这份 FBX 没有动画剪辑）。
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_hod_bones.gd

const PATH := "res://models/boss_hod/HOD_Original.fbx"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var node := (load(PATH) as PackedScene).instantiate()
	root.add_child(node)
	var skels := node.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		print("BONES 没有 Skeleton3D")
		quit(1)
		return
	for sk in skels:
		var s := sk as Skeleton3D
		print("BONES Skeleton3D「%s」共 %d 根骨头" % [s.name, s.get_bone_count()])
		for i in s.get_bone_count():
			var p := s.get_bone_parent(i)
			var rest := s.get_bone_rest(i)
			print("  %3d  %-32s parent=%-4d  rest_origin=(%.3f, %.3f, %.3f)  len=%.3f" % [
				i, String(s.get_bone_name(i)), p,
				rest.origin.x, rest.origin.y, rest.origin.z, rest.basis.get_scale().length()])
	print("BONES ── 挂骨骼的网格（BoneAttachment3D）──")
	for ba in node.find_children("*", "BoneAttachment3D", true, false):
		var a := ba as BoneAttachment3D
		print("  %-24s bone=%s  path=%s" % [String(a.name), a.bone_name,
			str(a.get_parent().name)])
	print("BONES ── 各网格用到的材质 ──")
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var mats: Array[String] = []
		for s in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(s)
			var nm := "?"
			if mat is StandardMaterial3D:
				nm = (mat as StandardMaterial3D).resource_name
			mats.append(nm)
		print("  %-40s skel=%s  surfaces=%s" % [
			str(node.get_path_to(m)), str(m.skeleton), str(mats)])
	quit(0)
