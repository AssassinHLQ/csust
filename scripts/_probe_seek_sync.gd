extends SceneTree
## 探针（短）：`AnimationPlayer.seek(t, true)` + `Skeleton3D.force_update_all_bone_transforms()`
## 之后，**同一帧**读出来的骨全局姿势到底是不是新的？
##
## 为什么要问：`PoseFix.fix_head_roll()` 想「量完再修」，而 `_ready()` 里不能 `await`。
## 如果 seek 后必须等一帧才生效，那就得换方案（延后一帧再标定）。
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_seek_sync.gd

const MODEL := "res://models/Arisu_ext.glb"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var inst: Node3D = (load(MODEL) as PackedScene).instantiate()
	root.add_child(inst)
	await process_frame
	var sk := _find(inst, "Skeleton3D") as Skeleton3D
	var ap := _find(inst, "AnimationPlayer") as AnimationPlayer
	if sk == null or ap == null:
		print("!! 缺骨架或 AnimationPlayer")
		quit(1)
		return
	var eL := sk.find_bone("Bip001 eye_L")
	var eR := sk.find_bone("Bip001 eye_R")
	print("骨：eye_L=%d eye_R=%d head=%d" % [eL, eR, sk.find_bone("Bip001 Head")])
	if eL < 0 or eR < 0:
		print("!! 没有眼骨，退出")
		quit(1)
		return

	var clip := "Move_Ing"
	var a := ap.get_animation(clip)
	# ⚠️ 先记下**静止**姿势（没有动画驱动时）的 roll，作为「没生效」的对照
	ap.stop()
	sk.force_update_all_bone_transforms()
	var r_rest := _roll(sk, eL, eR)
	print("\n静止 roll = %+.3f°" % r_rest)

	# ① 播放 + 同一帧 seek，**不等帧**就读
	ap.playback_process_mode = AnimationPlayer.ANIMATION_PROCESS_MANUAL
	ap.play(clip)
	var r_no_wait: Array[float] = []
	for i in 8:
		var t := a.length * float(i) / 8.0
		ap.seek(t, true)
		sk.force_update_all_bone_transforms()
		r_no_wait.append(_roll(sk, eL, eR))
	print("① seek 后**同一帧**读：%s" % _fmt(r_no_wait))

	# ② 播放 + seek + 等一帧再读（`_probe_head_roll.gd` 用的就是这种）
	var r_wait: Array[float] = []
	for i in 8:
		var t := a.length * float(i) / 8.0
		ap.seek(t, true)
		sk.force_update_all_bone_transforms()
		await process_frame
		sk.force_update_all_bone_transforms()
		r_wait.append(_roll(sk, eL, eR))
	print("② seek 后**等一帧**读：%s" % _fmt(r_wait))

	var same := true
	for i in 8:
		if absf(r_no_wait[i] - r_wait[i]) > 0.01:
			same = false
	print("\n两种读法一致（差值 < 0.01°）：%s" % ("✔ 可以在 `_ready()` 里同步标定" if same
		else "✘ 必须等一帧"))
	ap.stop()
	quit(0)


func _roll(sk: Skeleton3D, eL: int, eR: int) -> float:
	var xf := sk.global_transform
	var pl: Vector3 = xf * sk.get_bone_global_pose(eL).origin
	var pr: Vector3 = xf * sk.get_bone_global_pose(eR).origin
	return rad_to_deg(asin(clampf((pr - pl).normalized().y, -1.0, 1.0)))


func _fmt(v: Array[float]) -> String:
	var parts: Array[String] = []
	for x in v:
		parts.append("%+.2f" % x)
	return "[%s]" % ", ".join(parts)


func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r != null:
			return r
	return null
