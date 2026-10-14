extends SceneTree
## 对比 Arisu.glb 与 Arisu_ext.glb 里 Move_Ing 的脊柱关键帧，确认「减小前倾」真的进了导出文件。
##
## 运行：
##   & $g --headless --path <_arisu_learn> --script res://scripts/_probe_lean_godot.gd

const FILES := ["res://models/Arisu.glb", "res://models/Arisu_ext.glb"]
const ANIM := "Move_Ing"
const BONES := ["Bip001 Spine", "Bip001 Spine1", "Bip001 Neck"]


func _init() -> void:
	print("=== Move_Ing 脊柱关键帧对比 ===")
	for path in FILES:
		if not ResourceLoader.exists(path):
			print("!! 找不到 %s" % path)
			continue
		var packed: PackedScene = load(path)
		var scene: Node = packed.instantiate()
		var player := _find_player(scene)
		print("")
		print(path)
		if player == null or not player.has_animation(ANIM):
			print("  （没有 %s）" % ANIM)
			scene.free()
			continue
		var anim: Animation = player.get_animation(ANIM)
		print("  时长 %.3f s，轨道 %d" % [anim.length, anim.get_track_count()])
		for bone in BONES:
			for t in anim.get_track_count():
				var p := str(anim.track_get_path(t))
				if not p.ends_with(":" + bone):
					continue
				if anim.track_get_type(t) != Animation.TYPE_ROTATION_3D:
					continue
				var n := anim.track_get_key_count(t)
				var out := []
				for i in [0, n / 2, n - 1]:
					var q: Quaternion = anim.track_get_key_value(t, i)
					out.append("k%d 转角 %.2f°" % [i, 2.0 * rad_to_deg(acos(clampf(absf(q.w), 0.0, 1.0)))])
				print("  %-14s %d 键  %s" % [bone, n, "  |  ".join(out)])
				break
		scene.free()
	print("")
	print("=== 完毕 ===")
	quit(0)


func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var r := _find_player(c)
		if r:
			return r
	return null
