extends SceneTree
## 只读探针：量爱丽丝的**枪骨**和脊背位置 —— 给「走路时把枪背到身后」定槽位。
##   godot --headless --path . --script res://scripts/_probe_gun_slot.gd

const GAME := "res://scenes/game.tscn"

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := (load(GAME) as PackedScene).instantiate()
	root.add_child(game)
	for _i in 30:
		await process_frame
	var player := game.get_node_or_null("Player") as Node3D
	if player == null:
		print("[gun] 没有玩家")
		quit(1)
		return
	var skel: Skeleton3D = null
	var meshes: Array = []
	var stack: Array[Node] = [player]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Skeleton3D and skel == null:
			skel = n as Skeleton3D
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			meshes.append(n)
		for c in n.get_children():
			stack.append(c)
	if skel == null:
		print("[gun] 没有骨架")
		quit(1)
		return

	for want in ["Bip001_Weapon", "Bip001 Spine", "Bip001 Spine1", "Bip001 Neck",
			"Bip001 Head", "Bip001 L Clavicle", "Bip001 R Clavicle"]:
		var i := skel.find_bone(want)
		if i < 0:
			print("[gun] %-20s 无" % want)
			continue
		var p := skel.get_bone_global_pose(i)
		print("[gun] %-20s 骨架空间 origin %s（世界 %s）scale %s"
			% [want, str(p.origin.snappedf(0.01)),
				str((skel.global_transform * p).origin.snappedf(0.01)),
				str(p.basis.get_scale().snappedf(0.01))])
	# 枪的骨头姿态现在是素材给的（Idle）——记下来当参考
	var wi := skel.find_bone("Bip001_Weapon")
	if wi >= 0:
		var wp := skel.get_bone_global_pose(wi)
		print("[gun] 枪骨父 = %d（−1 = 根级）" % skel.get_bone_parent(wi))
		print("[gun] 枪骨基线 %s" % str(wp))
		print("[gun] 枪骨 euler %s" % str(wp.basis.get_euler().snappedf(0.001)))

	# 哪些网格是枪（名字里带 railgun / weapon）
	var inv := skel.global_transform.affine_inverse()
	for m in meshes:
		var mi := m as MeshInstance3D
		var nm := String(mi.name).to_lower()
		if not (nm.contains("railgun") or nm.contains("weapon")):
			continue
		var a: AABB = (inv * mi.global_transform) * mi.mesh.get_aabb()
		print("[gun] 网格 %-34s 骨架空间 AABB 中心 %s 尺寸 %s"
			% [mi.name, str(a.get_center().snappedf(0.01)), str(a.size.snappedf(0.01))])
	quit(0)
