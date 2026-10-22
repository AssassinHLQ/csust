extends SceneTree
## 只读探针：检查一个角色 .glb 的骨架 / 手骨 / 光环 / 动画 / 身高。
##   godot --headless --path . --script res://scripts/_probe_model_info.gd -- res://models/npc/serika/serika.glb
## 不带参数时默认查芹香。

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var path := "res://models/npc/serika/serika.glb"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("res://"):
			path = a
	if not ResourceLoader.exists(path):
		print("[mdl] 没有 %s（先 --editor --quit 导一次）" % path)
		quit(1)
		return
	var ps := load(path) as PackedScene
	if ps == null:
		print("[mdl] %s 不是场景" % path)
		quit(1)
		return
	var root := ps.instantiate()
	get_root().add_child(root)
	await process_frame

	var skel: Skeleton3D = null
	var stack: Array[Node] = [root]
	var meshes: Array[MeshInstance3D] = []
	var anims: Array[String] = []
	var aabb := AABB()
	var first := true
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Skeleton3D and skel == null:
			skel = n as Skeleton3D
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			meshes.append(mi)
			if mi.mesh != null:
				var a: AABB = mi.global_transform * mi.mesh.get_aabb()
				if first:
					aabb = a
					first = false
				else:
					aabb = aabb.merge(a)
		if n is AnimationPlayer:
			for nm in (n as AnimationPlayer).get_animation_list():
				anims.append(String(nm))
		for c in n.get_children():
			stack.append(c)

	print("[mdl] %s（%.1f MB）" % [path, FileAccess.get_file_as_bytes(path).size() / 1048576.0])
	print("[mdl] 网格 %d 个，包围盒 %s m，底 y=%.2f 顶 y=%.2f"
		% [meshes.size(), str(aabb.size.snappedf(0.01)), aabb.position.y, aabb.end.y])
	if skel != null:
		print("[mdl] 骨架 %d 骨" % skel.get_bone_count())
		for want in ["hand.l", "hand.r", "Bip001 eye_L", "Bip001 eye_R", "Hips", "Head"]:
			var idx := skel.find_bone(want)
			if idx >= 0:
				var wp := skel.global_transform * skel.get_bone_global_pose(idx).origin
				print("[mdl]   %-14s 世界 %s" % [want, str(wp.snappedf(0.01))])
			else:
				print("[mdl]   %-14s 无" % want)
		# 手/脚/头的骨头名（各家的 rig 命名都不一样，量一遍才敢写代码）
		var hands := []
		var feet := []
		for b in skel.get_bone_count():
			var nm := skel.get_bone_name(b)
			var low := nm.to_lower()
			if low.contains("hand"):
				var wp2 := skel.global_transform * skel.get_bone_global_pose(b).origin
				hands.append("%s=y%.2f" % [nm, wp2.y])
			elif low.contains("foot") or low.contains("toe"):
				feet.append(nm)
			if low.contains("head"):
				var wp3 := skel.global_transform * skel.get_bone_global_pose(b).origin
				print("[mdl]   头骨 %s 世界 y=%.2f" % [nm, wp3.y])
		print("[mdl] 手骨：%s" % ("无" if hands.is_empty() else ", ".join(hands)))
		print("[mdl] 脚骨：%s" % ("无" if feet.is_empty() else ", ".join(feet)))
		print("[mdl] 全部骨头：%s" % str(skel.get_bone_names()))
	else:
		print("[mdl] 没有 Skeleton3D")
	print("[mdl] 动画 %d 条：%s" % [anims.size(), ", ".join(anims)])
	var halo := []
	for mi in meshes:
		var nm := String(mi.name).to_lower()
		if nm.contains("halo") or nm.contains("光环"):
			halo.append(String(mi.name))
	print("[mdl] 光环网格：%s" % ("无" if halo.is_empty() else ", ".join(halo)))
	root.queue_free()
	quit(0)
