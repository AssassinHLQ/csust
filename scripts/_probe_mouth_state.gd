extends SceneTree
## 口型动画到底同时驱动几块嘴？逐动画逐时刻打印 14 块 Mouth 的 morph_0。
##
## 运行：
##   & $godot --headless --path <_arisu_learn> --script res://scripts/_probe_mouth_state.gd

const FILE := "res://models/companions/Kei_ext.glb"
const ANIMS := ["Normal_Idle", "Normal_Callsign", "Normal_Attack_Ing", "Cafe_Walk"]


func _init() -> void:
	_run()


func _run() -> void:
	var scene: Node = load(FILE).instantiate()
	root.add_child(scene)
	await process_frame
	var player := _anim(scene)
	var mouths := []
	for m in _all(scene, "MeshInstance3D"):
		var mi := m as MeshInstance3D
		if mi.name.begins_with("Mouth") and mi.mesh != null and mi.mesh.get_blend_shape_count() > 0:
			mouths.append(mi)
	print("=== 口型形变同时驱动统计（%s）===" % FILE.get_file())
	print("带形态键的 Mouth 网格 %d 个" % mouths.size())
	print("")
	print("%-22s %6s | %s" % ["动画", "时刻", "各块 morph_0（只列 >0.01 的）"])
	for an in ANIMS:
		if not player.has_animation(an):
			print("  （没有 %s）" % an)
			continue
		player.play(an)
		var length: float = player.get_animation(an).length
		for frac in [0.0, 0.25, 0.5, 0.75]:
			var t: float = minf(frac * length, length - 0.001)
			player.seek(t, true)
			var open := []
			for mi in mouths:
				var v: float = mi.get_blend_shape_value(0)
				if v > 0.01:
					open.append("%s=%.2f" % [mi.name.replace("Mouth_", ""), v])
			print("%-22s %6.2f | 张嘴 %d 块  %s" % [
				an, t, open.size(), ", ".join(open) if open.size() > 0 else "(全闭)"])
		print("")
	scene.queue_free()
	await process_frame
	print("=== 完毕 ===")
	quit(0)


func _anim(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var r := _anim(c)
		if r:
			return r
	return null


func _all(node: Node, cls: String) -> Array:
	var out := []
	if node.is_class(cls):
		out.append(node)
	for c in node.get_children():
		out.append_array(_all(c, cls))
	return out
