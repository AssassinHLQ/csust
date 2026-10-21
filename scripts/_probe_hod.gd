extends SceneTree
## 探针：量一下 **霍德（HOD）** 那只 FBX —— 材质名（`texture_map` 的 key 必须一字不差）、
## 包围盒、骨骼数、面数。换 Boss 之前先把这些数字拿到手。
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_hod.gd

const PATH := "res://models/boss_hod/HOD_Original.fbx"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ps := load(PATH) as PackedScene
	if ps == null:
		print("HOD 加载失败：", PATH)
		quit(1)
		return
	var node := ps.instantiate()
	root.add_child(node)
	var box := AABB()
	var first := true
	var tris := 0
	var names: Array[String] = []
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var b: AABB = m.global_transform * m.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
		for s in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(s)
			var nm := ""
			if mat is StandardMaterial3D:
				nm = (mat as StandardMaterial3D).resource_name
			if not names.has(nm):
				names.append(nm)
		if m.mesh is ArrayMesh:
			for s in (m.mesh as ArrayMesh).get_surface_count():
				var arr := (m.mesh as ArrayMesh).surface_get_arrays(s)
				if arr.size() > Mesh.ARRAY_INDEX and arr[Mesh.ARRAY_INDEX] != null:
					tris += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	var bones := node.find_children("*", "BoneAttachment3D", true, false).size()
	var skels := node.find_children("*", "Skeleton3D", true, false)
	var bone_n := 0
	for s in skels:
		bone_n += (s as Skeleton3D).get_bone_count()
	print("HOD 包围盒 size = %s  position = %s" % [
		str(box.size.snappedf(0.01)), str(box.position.snappedf(0.01))])
	print("HOD 面数 ≈ %d，Skeleton3D %d 个 / 骨骼 %d 根，BoneAttachment %d 个" % [
		tris, skels.size(), bone_n, bones])
	print("HOD 材质名（texture_map 的 key）：%s" % str(names))
	for ap in node.find_children("*", "AnimationPlayer", true, false):
		var pl := ap as AnimationPlayer
		var clips: Array[String] = []
		for a in pl.get_animation_list():
			var an := pl.get_animation(a)
			clips.append("%s(%.1fs)" % [String(a), an.length if an != null else -1.0])
		print("HOD AnimationPlayer「%s」动画 %d 条：%s" % [pl.name, clips.size(), str(clips)])
	quit(0)
