extends SceneTree
## 探针：对比 Arisu.glb 与 Arisu_ext.glb
##   1. 结构：节点链 / 骨骼数 / 动作数
##   2. 动作时长逐条对比（确认 `CYCLE_SPEED` 表是否还有效）
##   3. 「跑动前倾」在 Godot 里实测的角度（验证 §5.4 的数据级修正进了导出文件）
##
## ⚠️ 必须把实例加进树：AnimationPlayer.seek() 只对树内的节点生效，
##    否则骨骼姿势不更新，量出来全是垃圾（本喵第一版就踩了这个）。
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_ext_glb.gd

const FILES := ["res://models/Arisu.glb", "res://models/Arisu_ext.glb"]
const DRIVER_CLIPS := ["Normal_Idle", "Cafe_Walk", "Move_Ing", "Normal_Attack_Ing", "Normal_Reload"]
const SAMPLE := 24


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var info := {}
	for path in FILES:
		info[path] = await _inspect(path)

	print("\n================ 1. 结构 ================")
	for path in FILES:
		var d: Dictionary = info[path]
		print("%s" % path)
		print("  骨骼数 = %d   动作数 = %d   AnimationPlayer = %s" % [
			d["bones"], d["clip_count"], d["ap_path"]])

	print("\n================ 2. 动作时长逐条对比 ================")
	var clips0: Dictionary = info[FILES[0]]["clips"]
	var clips1: Dictionary = info[FILES[1]]["clips"]
	var diff := 0
	var same := 0
	for n in clips0.keys():
		if not clips1.has(n):
			print("  只在 Arisu.glb：%s" % n)
			continue
		var a: float = clips0[n]
		var b: float = clips1[n]
		if absf(a - b) > 0.0005:
			print("  时长不同：%-20s %.4f → %.4f（差 %+.1f 帧 @60fps）" % [
				n, a, b, (b - a) * 60.0])
			diff += 1
		else:
			same += 1
	var extra: Array = []
	for n in clips1.keys():
		if not clips0.has(n):
			extra.append(n)
	print("  时长完全一致 = %d 条；不同 = %d 条；Arisu_ext 独有 = %s" % [same, diff, str(extra)])

	print("\n  --- 驱动器实际引用的 5 条（缺一条就会退化）---")
	for n in DRIVER_CLIPS:
		var in0: bool = clips0.has(n)
		var in1: bool = clips1.has(n)
		var l0: float = clips0.get(n, -1.0)
		var l1: float = clips1.get(n, -1.0)
		print("    %-20s Arisu=%-8s Arisu_ext=%-8s  时长 %.4f → %.4f" % [
			n, str(in0), str(in1), l0, l1])

	print("\n================ 3. Move_Ing 前倾（Godot 实测）================")
	print("  %-16s %-24s %-24s" % ["模型", "躯干(骨盆→颈) 均值/峰值", "胸腔(Spine1→颈) 均值/峰值"])
	for path in FILES:
		var s: Dictionary = info[path]["lean"]
		print("  %-16s %+6.1f° / %+6.1f°        %+6.1f° / %+6.1f°" % [
			path.get_file(), s["trunk_mean"], s["trunk_peak"], s["chest_mean"], s["chest_peak"]])

	print("\n================ 4. 其它动作的胸腔前倾基线 ================")
	for clip in ["Normal_Idle", "Cafe_Walk"]:
		var line := "  %-12s" % clip
		for path in FILES:
			var s: Dictionary = info[path]["baseline"].get(clip, {})
			line += "   %s %+.1f°" % [path.get_file(), s.get("chest_mean", 0.0)]
		print(line)

	quit(0)


func _inspect(path: String) -> Dictionary:
	var scene: Node = (load(path) as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var ap := _find(scene, "AnimationPlayer") as AnimationPlayer
	var skel := _find(scene, "Skeleton3D") as Skeleton3D
	var clips := {}
	for n in ap.get_animation_list():
		clips[String(n)] = ap.get_animation(n).length
	var lean := await _measure_lean(ap, skel, "Move_Ing")
	var baseline := {
		"Normal_Idle": await _measure_lean(ap, skel, "Normal_Idle"),
		"Cafe_Walk": await _measure_lean(ap, skel, "Cafe_Walk"),
	}
	var result := {
		"bones": skel.get_bone_count(),
		"clip_count": clips.size(),
		"clips": clips,
		"ap_path": String(scene.get_path_to(ap)),
		"lean": lean,
		"baseline": baseline,
	}
	scene.queue_free()
	await process_frame
	return result


## 播动作、逐帧 seek 取样，量「躯干前倾」与「胸腔前倾」。
## 模型脸朝世界 +Z（§1.4），所以前倾 = 该方向 +Z 分量 / 竖直分量 的 atan。
func _measure_lean(ap: AnimationPlayer, skel: Skeleton3D, clip: String) -> Dictionary:
	if not ap.has_animation(clip):
		return {"trunk_mean": 0.0, "trunk_peak": 0.0, "chest_mean": 0.0, "chest_peak": 0.0}
	ap.play(clip)
	var pel := skel.find_bone("Bip001 Pelvis")
	var s1 := skel.find_bone("Bip001 Spine1")
	var neck := skel.find_bone("Bip001 Neck")
	var length := ap.get_animation(clip).length
	var trunk := PackedFloat32Array()
	var chest := PackedFloat32Array()
	for i in SAMPLE:
		ap.seek(length * float(i) / float(SAMPLE), true)
		await process_frame
		var xf := skel.global_transform
		var p: Vector3 = xf * skel.get_bone_global_pose(pel).origin
		var n: Vector3 = xf * skel.get_bone_global_pose(neck).origin
		var c: Vector3 = xf * skel.get_bone_global_pose(s1).origin
		trunk.append(_tilt(p, n))
		chest.append(_tilt(c, n))
	return {
		"trunk_mean": _mean(trunk), "trunk_peak": _peak(trunk),
		"chest_mean": _mean(chest), "chest_peak": _peak(chest),
	}


## 从 a 到 b 的方向相对竖直的偏角，向 +Z（脸的方向）为正
func _tilt(a: Vector3, b: Vector3) -> float:
	var d := b - a
	var flat := Vector2(d.z, d.y)
	if flat.length() < 0.0001:
		return 0.0
	return rad_to_deg(atan2(flat.x, flat.y))


func _mean(v: PackedFloat32Array) -> float:
	if v.is_empty():
		return 0.0
	var s := 0.0
	for x in v:
		s += x
	return s / v.size()


func _peak(v: PackedFloat32Array) -> float:
	var m := -999.0
	for x in v:
		m = maxf(m, x)
	return m


func _find(node: Node, cls: String) -> Node:
	if node.is_class(cls):
		return node
	for c in node.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null
