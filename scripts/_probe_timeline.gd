extends SceneTree
## 探针：扫 Normal_Attack_Ing 整条时间线，找枪口真正朝前的时刻。
## 参考系：模型节点已绕 Y 转 180°，玩家前方 = 世界 +Z（模型根节点局部 -Z）。

func _initialize() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var ap: AnimationPlayer = main.get_node("Arisu/Model/AnimationPlayer")
	var skel: Skeleton3D = _find(main, "Skeleton3D")
	var body: Node3D = skel.get_parent()   # Skeleton3D 的父节点，带模型整体的变换

	var muzzle := skel.find_bone("bone_Railgun_Muzzle_03")
	var rhand := skel.find_bone("Bip001 R Hand")

	# 用 Skeleton3D 自己的全局变换换算，不手动再加旋转
	var skel_xf := skel.global_transform

	print("=== Normal_Attack_Ing 时间线扫描（枪口相对角色的前向/右手距离）===")
	print("参考：角色前方 = 世界 +Z；fwd 越接近 +1 越朝前")
	var anim: Animation = ap.get_animation("Normal_Attack_Ing")
	ap.play("Normal_Attack_Ing")
	var steps := 30
	for i in steps + 1:
		var t := anim.length * float(i) / float(steps)
		ap.seek(t, true)
		await process_frame
		var mt: Transform3D = skel_xf * skel.get_bone_global_pose(muzzle)
		var ht: Transform3D = skel_xf * skel.get_bone_global_pose(rhand)
		var fwd: Vector3 = mt.basis.z.normalized()   # 枪口骨 +Z 朝枪管方向
		var fwd_alt: Vector3 = -mt.basis.y.normalized()
		print("  t=%5.2f  fwdZ=%+.3f fwd-Y=%+.3f  muzzle=%s  手距=%.3f" % [
			t, fwd.z, fwd_alt.z, str(mt.origin.snappedf(0.01)),
			mt.origin.distance_to(ht.origin)])
	quit(0)


func _find(n: Node, target: String) -> Node:
	if String(n.name).begins_with(target):
		return n
	for c in n.get_children():
		var r := _find(c, target)
		if r:
			return r
	return null
