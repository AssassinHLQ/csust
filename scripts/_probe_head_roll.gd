extends SceneTree
## 探针：把「跑起来头往左偏」和「待机只有右眼睑在动」两件事**量化**。
##
## 判据（都不依赖骨骼局部轴的朝向，省得又踩欧拉分解的坑）：
## * **侧倾 roll**：`right = normalize(eye_R − eye_L)`，`roll = asin(right.y)`。
##   右耳抬高 → roll > 0。角色脸朝 +Z，所以「头往左偏」= 右耳抬高 = roll > 0。
## * **俯仰 pitch**：`up = normalize(head − neck)`，`pitch = asin(−up.z)`（前倾为正）。
## * **眼睑**：`Bip001 eye_R_1 / eye_L_1` 的姿势四元数 y 分量（相对静止）。
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_head_roll.gd

const MODEL := "res://models/Arisu_ext.glb"
const CLIPS := ["Normal_Idle", "Cafe_Walk", "Move_Ing"]
const SAMPLES := 24


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var inst: Node3D = (load(MODEL) as PackedScene).instantiate()
	root.add_child(inst)
	await process_frame
	var sk := _find_skel(inst)
	var ap := _find_anim(inst)
	if sk == null or ap == null:
		print("!! 缺骨架或 AnimationPlayer")
		quit(1)
		return

	var fix := "--fix" in OS.get_cmdline_user_args()
	if fix:
		var r1 := PoseFix.fix_run_lean(sk, ap)
		var r2 := PoseFix.fix_head_roll(sk, ap)
		var r3 := PoseFix.fix_eyelid_sync(sk, ap)
		print("[roll] PoseFix：前倾 %d 帧、侧倾 %d 帧、眼睑 %d 帧" % [
			int(r1["total"]), int(r2["total"]), int(r3["keys"])])
	if "--calib" in OS.get_cmdline_user_args():
		# 标定：骨架空间的 ±X/±Y/±Z 到底哪个是「绕前进轴滚」（改 roll 不改 pitch）
		#
		# ⚠️ 必须先把播放切成 MANUAL：不然 `AnimationPlayer` 每帧都会把姿势重新写回去，
		#    这里 `set_bone_pose_rotation()` 的结果下一个 `await process_frame` 就没了 ——
		#    第一版六个轴测出来 Δ 全是 +1.0 / +2.6，一模一样，就是被覆盖了（踩过）。
		ap.playback_process_mode = AnimationPlayer.ANIMATION_PROCESS_MANUAL
		ap.play("Move_Ing")
		ap.seek(0.3, true)
		sk.force_update_all_bone_transforms()
		var hi := sk.find_bone("Bip001 Head")
		var base := sk.get_bone_pose_rotation(hi)
		var r0 := _roll(sk)
		var p0 := _pitch(sk)
		print("[calib] 原始 roll=%+.2f  pitch=%+.2f" % [r0, p0])
		# 世界「前进轴」换算到骨架空间：模型脸朝世界 +Z，而骨架节点带 −90° X 旋转
		var fwd_skel := (sk.global_transform.basis.inverse() * Vector3(0, 0, 1)).normalized()
		print("[calib] 世界前进轴在骨架空间里 = %s" % str(fwd_skel.snappedf(0.001)))
		var axes2: Array[Vector3] = [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), fwd_skel]
		for axis in axes2:
			for s in [-1.0, 1.0]:
				var d := _delta_like(sk, hi, axis, 10.0 * s)
				sk.set_bone_pose_rotation(hi, (d * base).normalized())
				sk.force_update_all_bone_transforms()
				await process_frame
				var r1 := _roll(sk)
				var p1 := _pitch(sk)
				print("[calib] 绕 %s %+.0f° → Δroll %+6.2f  Δpitch %+6.2f" % [
					str(axis), 10.0 * s, r1 - r0, p1 - p0])
		sk.set_bone_pose_rotation(hi, base)
		quit(0)
		return

	var eL := sk.find_bone("Bip001 eye_L")
	var eR := sk.find_bone("Bip001 eye_R")
	var head := sk.find_bone("Bip001 Head")
	var neck := sk.find_bone("Bip001 Neck")
	var lidL := sk.find_bone("Bip001 eye_L_1")
	var lidR := sk.find_bone("Bip001 eye_R_1")
	var lidL2 := sk.find_bone("Bip001 eye_L_2")
	var lidR2 := sk.find_bone("Bip001 eye_R_2")
	print("[roll] 骨：eye_L=%d eye_R=%d head=%d neck=%d lidL=%d lidR=%d lidL2=%d lidR2=%d" % [
		eL, eR, head, neck, lidL, lidR, lidL2, lidR2])

	for clip in CLIPS:
		if not ap.has_animation(clip):
			continue
		var a := ap.get_animation(clip)
		ap.play(clip)
		ap.speed_scale = 1.0
		var rolls: Array[float] = []
		var pitches: Array[float] = []
		var lid_ly: Array[float] = []
		var lid_ry: Array[float] = []
		var lid_l2y: Array[float] = []
		var lid_r2y: Array[float] = []
		for i in SAMPLES:
			var t := a.length * float(i) / float(SAMPLES)
			ap.seek(t, true)
			sk.force_update_all_bone_transforms()
			await process_frame
			sk.force_update_all_bone_transforms()
			# ⚠️ 必须换到**世界空间**：glb 的根节点带一个 −90° X 旋转（Y-up ↔ Z-up），
			#    直接在骨架空间里跟「世界上」比对，会量出 −36° / −77° 这种鬼数字（踩过）。
			var xf := sk.global_transform
			var pl: Vector3 = xf * sk.get_bone_global_pose(eL).origin
			var pr: Vector3 = xf * sk.get_bone_global_pose(eR).origin
			var right := (pr - pl).normalized()
			rolls.append(rad_to_deg(asin(clampf(right.y, -1.0, 1.0))))
			var ph: Vector3 = xf * sk.get_bone_global_pose(head).origin
			var pn: Vector3 = xf * sk.get_bone_global_pose(neck).origin
			var up := (ph - pn).normalized()
			pitches.append(rad_to_deg(asin(clampf(-up.z, -1.0, 1.0))))
			lid_ly.append(absf(sk.get_bone_pose_rotation(lidL).y))
			lid_ry.append(absf(sk.get_bone_pose_rotation(lidR).y))
			lid_l2y.append(absf(sk.get_bone_pose_rotation(lidL2).y))
			lid_r2y.append(absf(sk.get_bone_pose_rotation(lidR2).y))
		print("\n===== %s（%.2f s，%d 采样）=====" % [clip, a.length, SAMPLES])
		_stat("侧倾 roll（右耳抬高为正）", rolls)
		_stat("俯仰 pitch（前倾为正）", pitches)
		_stat("左眼睑 eye_L_1 |q.y|", lid_ly)
		_stat("右眼睑 eye_R_1 |q.y|", lid_ry)
		_stat("左眼睑 eye_L_2 |q.y|", lid_l2y)
		_stat("右眼睑 eye_R_2 |q.y|", lid_r2y)
	quit(0)


func _roll(sk: Skeleton3D) -> float:
	var xf := sk.global_transform
	var pl: Vector3 = xf * sk.get_bone_global_pose(sk.find_bone("Bip001 eye_L")).origin
	var pr: Vector3 = xf * sk.get_bone_global_pose(sk.find_bone("Bip001 eye_R")).origin
	return rad_to_deg(asin(clampf((pr - pl).normalized().y, -1.0, 1.0)))


func _pitch(sk: Skeleton3D) -> float:
	var xf := sk.global_transform
	var ph: Vector3 = xf * sk.get_bone_global_pose(sk.find_bone("Bip001 Head")).origin
	var pn: Vector3 = xf * sk.get_bone_global_pose(sk.find_bone("Bip001 Neck")).origin
	return rad_to_deg(asin(clampf(-(ph - pn).normalized().z, -1.0, 1.0)))


## 和 `PoseFix._axis_delta` 同一套夹法：用**父骨**的 global rest 基
func _delta_like(sk: Skeleton3D, idx: int, axis: Vector3, deg: float) -> Quaternion:
	var g := Basis.IDENTITY
	var parent := sk.get_bone_parent(idx)
	if parent >= 0:
		g = sk.get_bone_global_rest(parent).basis.orthonormalized()
	var gq := g.get_rotation_quaternion()
	return (gq.inverse() * Quaternion(axis, deg_to_rad(deg)) * gq).normalized()


func _stat(label: String, vals: Array[float]) -> void:
	var lo := 999.0
	var hi := -999.0
	var sum := 0.0
	for v in vals:
		lo = minf(lo, v)
		hi = maxf(hi, v)
		sum += v
	print("   %-26s 均值 %+7.2f   范围 [%+7.2f, %+7.2f]" % [label, sum / float(vals.size()), lo, hi])


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var r := _find_skel(c)
		if r != null:
			return r
	return null


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var r := _find_anim(c)
		if r != null:
			return r
	return null
