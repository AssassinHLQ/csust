extends SceneTree
## 探针：**跑 + 开火叠加时，到底哪些骨被开火动画改掉了**。
##
## 用户的判断：「应该是跑步开火两个动画叠加导致的」。对 —— 那就把它量化：
## 在同一个冻结相位上，逐根骨比较 `Move_Ing`（只跑）与 `Normal_Attack_Ing`（站桩开火）
## 的**局部旋转差**，再标出这根骨**有没有被运行时的过滤规则覆盖**：
##
##   LOWER_KEYWORDS = thigh/calf/foot/toe/leg/pelvis/hip/root/skirt   （两层都滤）
##   TRUNK_KEYWORDS = spine/chest/neck/head                          （只移动层滤）
##
## 没被覆盖又差得多的骨，就是「跑打时身上多出来的那点姿态」——后倾就从它们身上找。
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_fire_vs_run_bones.gd

const MODEL := "res://models/Arisu_ext.glb"
const RUN_CLIP := "Move_Ing"
const FIRE_CLIP := "Normal_Attack_Ing"
const RUN_T := 0.30
const FIRE_T := 0.40
const SHOW := 18


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var inst: Node3D = (load(MODEL) as PackedScene).instantiate()
	root.add_child(inst)
	await process_frame
	var sk := _find_skel(inst)
	var ap := _find_anim(inst)
	if sk == null or ap == null:
		print("!! 缺 Skeleton3D / AnimationPlayer")
		quit(1)
		return
	if not ap.has_animation(RUN_CLIP) or not ap.has_animation(FIRE_CLIP):
		print("!! 缺动画 %s / %s" % [RUN_CLIP, FIRE_CLIP])
		quit(1)
		return

	var run: Array = await _snapshot(sk, ap, RUN_CLIP, RUN_T)
	var fire: Array = await _snapshot(sk, ap, FIRE_CLIP, FIRE_T)

	print("[cmp] 逐骨局部旋转差（%s@%.2fs vs %s@%.2fs）" % [RUN_CLIP, RUN_T, FIRE_CLIP, FIRE_T])
	var rows: Array = []
	for i in sk.get_bone_count():
		var a: Quaternion = run[i]
		var b: Quaternion = fire[i]
		var deg := rad_to_deg(a.angle_to(b))
		if deg < 0.5:
			continue
		var bn := String(sk.get_bone_name(i))
		rows.append({"name": bn, "deg": deg, "low": _hit(bn, AnimDriver.LOWER_KEYWORDS),
			"trunk": _hit(bn, AnimDriver.TRUNK_KEYWORDS)})
	rows.sort_custom(func(x, y): return float(x["deg"]) > float(y["deg"]))

	print("%-26s %8s  %-8s %s" % ["骨", "差(°)", "已被滤", "说明"])
	var uncovered := 0
	for k in mini(SHOW, rows.size()):
		var r: Dictionary = rows[k]
		var covered := bool(r["low"]) or bool(r["trunk"])
		var tag := "两层都滤" if bool(r["low"]) else ("移动层滤" if bool(r["trunk"]) else "**没滤**")
		if not covered:
			uncovered += 1
		print("%-26s %8.2f  %-8s %s" % [String(r["name"]), float(r["deg"]), tag,
			"" if covered else "← 跑打时会带上这段姿态"])
	print("\n[cmp] 差 > 0.5° 的骨 %d 根，其中**没被过滤**的 %d 根" % [rows.size(), uncovered])
	quit(0)


func _hit(bone: String, kws: Array) -> bool:
	var low := bone.to_lower()
	for k in kws:
		if low.contains(String(k)):
			return true
	return false


func _snapshot(sk: Skeleton3D, ap: AnimationPlayer, clip: String, t: float) -> Array:
	ap.play(clip)
	ap.seek(t, true)
	await process_frame
	await process_frame
	var out: Array = []
	for i in sk.get_bone_count():
		out.append(sk.get_bone_pose_rotation(i))
	return out


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
