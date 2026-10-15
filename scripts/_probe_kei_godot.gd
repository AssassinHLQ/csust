extends SceneTree
## 对比 Kei.glb 与 Kei_ext.glb 里 Move_Ing 的骨骼轨道，确认「跑步前倾变小」真的进了导出文件。
##
## 运行：
##   & $godot --headless --path <_arisu_learn> --script res://scripts/_probe_kei_godot.gd

const FILES := ["res://models/companions/Kei.glb", "res://models/companions/Kei_ext.glb"]
const ANIM := "Move_Ing"
const BONES := ["Bip001", "Bip001 Pelvis", "Bip001 Spine", "Bip001 Spine1",
	"Bip001 Neck", "Bip001 L Thigh", "Bip001 R Thigh", "Bip001 L Calf"]


func _init() -> void:
	print("=== Move_Ing 骨骼轨道对比（Kei）===")
	for path in FILES:
		if not ResourceLoader.exists(path):
			print("!! 找不到 %s" % path)
			continue
		var packed: PackedScene = load(path)
		var scene: Node = packed.instantiate()
		print("")
		print(path)
		var players := []
		_collect_players(scene, players)
		print("  场景内 AnimationPlayer 数 = %d" % players.size())
		for pl in players:
			if not pl.has_animation(ANIM):
				continue
			var anim: Animation = pl.get_animation(ANIM)
			print("  [%s] 时长 %.3f s，轨道 %d" % [pl.name, anim.length, anim.get_track_count()])
			for bone in BONES:
				for t in anim.get_track_count():
					var p := str(anim.track_get_path(t))
					if not p.ends_with(":" + bone):
						continue
					if anim.track_get_type(t) == Animation.TYPE_ROTATION_3D:
						var n := anim.track_get_key_count(t)
						var out := []
						for i in [0, n / 2, n - 1]:
							var q: Quaternion = anim.track_get_key_value(t, i)
							out.append("k%d %5.2f°" % [i, 2.0 * rad_to_deg(acos(clampf(absf(q.w), 0.0, 1.0)))])
						print("    转 %-18s %3d 键  %s" % [bone, n, "  ".join(out)])
					elif anim.track_get_type(t) == Animation.TYPE_POSITION_3D:
						var n2 := anim.track_get_key_count(t)
						var lo := Vector3(1e9, 1e9, 1e9)
						var hi := Vector3(-1e9, -1e9, -1e9)
						for i in n2:
							var v: Vector3 = anim.track_get_key_value(t, i)
							lo = lo.min(v)
							hi = hi.max(v)
						print("    位移 %-18s %3d 键  范围 %s ~ %s" % [
							bone, n2, _v(lo), _v(hi)])
		scene.free()
	print("")
	print("=== 完毕 ===")
	quit(0)


func _v(v: Vector3) -> String:
	return "(%.4f, %.4f, %.4f)" % [v.x, v.y, v.z]


func _collect_players(node: Node, out: Array) -> void:
	if node is AnimationPlayer:
		out.append(node)
	for c in node.get_children():
		_collect_players(c, out)
