extends SceneTree
## 探针：遍历全部动作，看枪口（bone_Railgun_Muzzle_01）到底朝哪。
## 模型节点本身有 180° 旋转，这里统一换算到「玩家前方 = 世界 -Z」来判断。

func _initialize() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var ap: AnimationPlayer = main.get_node("Arisu/Model/AnimationPlayer")
	var skel: Skeleton3D = _find(main, "Skeleton3D")
	var body: Node3D = skel.get_parent()
	var model_root: Node3D = main.get_node("Arisu/Model")

	var muzzle := skel.find_bone("bone_Railgun_Muzzle_01")
	var rhand := skel.find_bone("Bip001 R Hand")
	var up := skel.find_bone("bone_Railgunup_00")

	# 模型根节点绕 Y 转了 180°，所以模型空间的 +Z 才是玩家的「前方 -Z」
	var model_to_player := model_root.global_transform.basis

	print("动作\t\t\t枪口世界位置\t\t前向(-Z·Z轴)\t右手距离")
	var names: PackedStringArray = ap.get_animation_library("").get_animation_list()
	for n in names:
		if String(n) == "RESET":
			continue
		var anim: Animation = ap.get_animation(n)
		var t := anim.length * 0.5
		ap.play(n)
		ap.seek(t, true)
		await process_frame
		await process_frame
		var mt: Transform3D = body.global_transform * skel.get_bone_global_pose(muzzle)
		var ht: Transform3D = body.global_transform * skel.get_bone_global_pose(rhand)
		var m_origin: Vector3 = model_to_player * mt.origin
		var h_origin: Vector3 = model_to_player * ht.origin
		# 玩家前向是 -Z：取枪口 -Z 轴（绕 Y 转 180° 后）与玩家前向的点积
		var m_fwd: Vector3 = model_to_player * (-mt.basis.z).normalized()
		var fwd_dot: float = m_fwd.dot(Vector3(0, 0, -1))
		print("%-22s %s  %+.3f  %.3f" % [
			n, str(m_origin.snappedf(0.01)), fwd_dot, m_origin.distance_to(h_origin)])
	quit(0)


func _find(n: Node, target: String) -> Node:
	if String(n.name).begins_with(target):
		return n
	for c in n.get_children():
		var r := _find(c, target)
		if r:
			return r
	return null
