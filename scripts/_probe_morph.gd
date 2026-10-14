extends SceneTree
## 一次性验证：口型（blend shape）在动画播放时是否真的被驱动。
## 用法：godot --headless --path <工程> --script res://scripts/_probe_morph.gd

var _main: Node


func _initialize() -> void:
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	await process_frame
	await process_frame
	await _run()
	quit(0)


func _run() -> void:
	var ap: AnimationPlayer = _main.get_node("Arisu/Model/AnimationPlayer")
	var mouth: MeshInstance3D = _find(_main, "Mouth_401")
	var skel: Skeleton3D = _find(_main, "Skeleton3D")
	if mouth == null or skel == null:
		print("!! 找不到 Mouth_401 或 Skeleton3D")
		return

	print("=== 口型形变验证：Mouth_401 / Normal_Callsign ===")
	print("Mouth_401 节点路径: ", _main.get_path_to(mouth))
	ap.play("Normal_Callsign")
	var samples := 8
	for i in samples:
		var t := 1.5 * float(i) / float(samples - 1)
		ap.seek(t, true)
		await process_frame
		print("  t=%.3fs  morph_0=%.4f" % [t, mouth.get_blend_shape_value(0)])

	print("\n=== 骨骼验证：Bip001 Head 姿态随动作变化 ===")
	var head := skel.find_bone("Bip001 Head")
	print("  Bip001 Head 索引: ", head)
	for anim_name in ["Normal_Idle", "Vital_Death"]:
		ap.play(anim_name)
		ap.seek(0.4, true)
		await process_frame
		print("  %-12s @0.4s origin=%s" % [anim_name, str(skel.get_bone_global_pose(head).origin.snappedf(0.001))])


func _find(n: Node, target: String) -> Node:
	if String(n.name) == target or String(n.name).begins_with(target):
		return n
	for c in n.get_children():
		var r := _find(c, target)
		if r:
			return r
	return null
