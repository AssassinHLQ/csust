extends SceneTree
## 探针：先看 `hand.l` 的**父链**（这套 Maya rig 有 c_/ik/fk 三层，手骨不一定挂在 arm.l 下面），
## 再对真正的上臂骨试局部旋转，用手骨世界高度判定。
##
## 用法：godot --path <工程> --script res://scripts/_probe_sora_axis.gd -- --no-capture

const MODEL := "res://models/npc/sora/sora.glb"
const AXES := [["+X", Vector3(1, 0, 0)], ["-X", Vector3(-1, 0, 0)],
	["+Y", Vector3(0, 1, 0)], ["-Y", Vector3(0, -1, 0)],
	["+Z", Vector3(0, 0, 1)], ["-Z", Vector3(0, 0, -1)]]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(600, 400)
	var ps := load(MODEL) as PackedScene
	var model := ps.instantiate() as Node3D
	root.add_child(model)
	for _i in 5:
		await process_frame
	var skel := _best(model)
	var hand := _find(skel, "hand.l")
	print("── hand.l (%d) 的父链 ──" % hand)
	var i := hand
	var depth := 0
	while i >= 0 and depth < 20:
		print("  %2d  %s" % [depth, skel.get_bone_name(i)])
		i = skel.get_bone_parent(i)
		depth += 1
	print("── arm_fk.l = %d, arm.l = %d, forearm_fk.l = %d ──" % [
		_find(skel, "arm_fk.l"), _find(skel, "arm.l"), _find(skel, "forearm_fk.l")])

	# 对手臂链条上每一根骨试 +Z 局部旋转，看手骨掉不掉
	for bone_name in ["arm_fk.l", "arm.l", "forearm_fk.l", "shoulder.l"]:
		var b := _find(skel, bone_name)
		if b < 0:
			print("  %s 不存在" % bone_name)
			continue
		var y0 := _bone_y(skel, hand)
		var q := skel.get_bone_pose_rotation(b)
		skel.set_bone_pose_rotation(b, q * Quaternion(Vector3(0, 0, 1), deg_to_rad(45.0)))
		for _i in 3:
			await process_frame
		var y1 := _bone_y(skel, hand)
		print("  转 %-12s 局部Z 45° → 手骨 y %+.3f→%+.3f (Δ%+.3f)" % [
			bone_name, y0, y1, y1 - y0])
		skel.set_bone_pose_rotation(b, q)
		for _i in 2:
			await process_frame
	quit(0)


func _bone_y(skel: Skeleton3D, idx: int) -> float:
	if idx < 0:
		return 0.0
	return (skel.global_transform * skel.get_bone_global_pose(idx).origin).y


func _find(skel: Skeleton3D, want: String) -> int:
	for i in skel.get_bone_count():
		if skel.get_bone_name(i) == want:
			return i
	return -1


func _best(node: Node) -> Skeleton3D:
	var best: Skeleton3D = null
	for n in _all(node, "Skeleton3D"):
		var s := n as Skeleton3D
		if best == null or s.get_bone_count() > best.get_bone_count():
			best = s
	return best


func _all(node: Node, cls: String) -> Array:
	var out: Array = []
	if node == null:
		return out
	if node.is_class(cls):
		out.append(node)
	for c in node.get_children():
		out.append_array(_all(c, cls))
	return out
