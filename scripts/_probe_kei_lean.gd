extends SceneTree
## 在 Godot 里实测 Move_Ing 的「躯干相对竖直的倾角」，对比 Kei.glb 与 Kei_ext.glb。
##
## 不依赖任何朝向约定：直接量 骨盆→颈 连线与世界上方向 (+Y) 的夹角。
## 同时报告踝点高度，确认接地节奏没被破坏。
##
## 运行：
##   & $godot --headless --path <_arisu_learn> --script res://scripts/_probe_kei_lean.gd

const FILES := ["res://models/companions/Kei.glb", "res://models/companions/Kei_ext.glb"]
const ANIM := "Move_Ing"


func _initialize() -> void:
	# ⚠️ 不能在 `_init()` 里直接跑：那一刻场景树还没就绪，`root.add_child()` 与
	#    `await process_frame` 都不该在那儿。本工程其它探针统一用这个写法。
	_run.call_deferred()


func _run() -> void:
	print("=== Move_Ing 躯干倾角实测（Godot 内）===")
	for path in FILES:
		if not ResourceLoader.exists(path):
			print("!! 找不到 %s" % path)
			continue
		var scene: Node = load(path).instantiate()
		root.add_child(scene)
		await process_frame

		var player := _find_anim(scene)
		var skel := _find_skeleton(scene)
		print("")
		print(path)
		if player == null or skel == null:
			print("  !! 缺 AnimationPlayer 或 Skeleton3D")
			scene.queue_free()
			await process_frame
			continue

		var i_pel := skel.find_bone("Bip001 Pelvis")
		var i_neck := skel.find_bone("Bip001 Neck")
		var i_lf := skel.find_bone("Bip001 L Foot")
		var i_rf := skel.find_bone("Bip001 R Foot")
		print("  骨索引 pelvis=%d neck=%d Lfoot=%d Rfoot=%d" % [i_pel, i_neck, i_lf, i_rf])

		player.play(ANIM)
		var length: float = player.get_animation(ANIM).length
		var step := length / 8.0
		# ⚠️ 必须写成 `Array[float]`：无类型数组取出来是 Variant，Godot 4.7 不肯
		#    往 `float` 上推断（"Cannot infer the type of ..."）。
		var tilts: Array[float] = []
		var lows: Array[float] = []
		var line := ""
		for k in 9:
			var t: float = minf(k * step, length - 0.001)
			player.seek(t, true)
			skel.force_update_all_bone_transforms()
			var pel: Vector3 = skel.global_transform * skel.get_bone_global_pose(i_pel).origin
			var neck: Vector3 = skel.global_transform * skel.get_bone_global_pose(i_neck).origin
			var torso := (neck - pel).normalized()
			var tilt: float = rad_to_deg(acos(clampf(torso.dot(Vector3.UP), -1.0, 1.0)))
			var lf: Vector3 = skel.global_transform * skel.get_bone_global_pose(i_lf).origin
			var rf: Vector3 = skel.global_transform * skel.get_bone_global_pose(i_rf).origin
			tilts.append(tilt)
			lows.append(minf(lf.y, rf.y))
			line += "%5.1f° " % tilt
		var avg := 0.0
		for v in tilts:
			avg += v
		avg /= float(tilts.size())
		var lo: float = lows[0]
		var hi: float = lows[0]
		for v in lows:
			lo = minf(lo, v)
			hi = maxf(hi, v)
		print("  躯干倾角 9 个采样：%s" % line)
		print("  躯干倾角 平均 %.1f°  最大 %.1f°" % [avg, tilts.max()])
		print("  踝点高度范围 %.4f ~ %.4f（越低越接地）" % [lo, hi])

		scene.queue_free()
		await process_frame
	print("")
	print("=== 完毕 ===")
	quit(0)


func _find_anim(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var r := _find_anim(c)
		if r:
			return r
	return null


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D and node.find_bone("Bip001 Pelvis") >= 0:
		return node
	for c in node.get_children():
		var r := _find_skeleton(c)
		if r:
			return r
	return null
