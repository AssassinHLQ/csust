extends SceneTree
## 量机甲「机身俯仰」：各条动画在载具骨架上演出来，脊梁是前倾还是后仰、多少度。
##
## 背景（用户 2026-11-08：「飞行姿势为什么这么奇怪，仰头，应该平视前方」）：
## `carrier_form.gd` 里 `_lean` 每帧都算、但**从来没有被应用到任何一根骨上**
## —— 也就是说「前倾」这个特性从来就没生效，飞行时看到的是**动画自带的姿势**。
##
## 判据（不靠眼睛）：
##   d = 头骨世界坐标 − 胯骨世界坐标      （脊梁轴，从下往上）
##   fwd = 载具节点的 +Z 世界方向          （模型正面，见 `facing_yaw_deg` 那段）
##   pitch = atan2(d·fwd, d·up)
##     > 0 = 头在胯的**前方**（前倾）
##     < 0 = 头在胯的**后方**（后仰 / 仰头）
##
##   & D:\GAME\godot\Godot_v4.7.1-stable_win64_console.exe --headless --path . \
##       --script res://scripts/_diag_carrier_pose.gd

const PlayerScene := preload("res://scenes/player.tscn")
const MechState := preload("res://scripts/mech_state.gd")
const CarrierForm := preload("res://scripts/carrier_form.gd")

## 参考骨：胯 / 头。BA 骨架用 Bip001 前缀，另留几个别名兜底。
const HIP_NAMES := ["Bip001 Pelvis", "Bip001_Pelvis", "Bip001 Pelvis1", "bone_hip"]
const HEAD_NAMES := ["Bip001 Head", "Bip001_Head", "bone_head"]


func _initialize() -> void:
	_run()


func _run() -> void:
	MechState.set_carrier_for_test(true)
	var stage := Node3D.new()
	stage.name = "PoseStage"
	root.add_child(stage)
	var player := PlayerScene.instantiate() as Player
	stage.add_child(player)
	await process_frame
	await process_frame

	var cf := player.get_node_or_null("Arisu/CarrierForm") as CarrierForm
	if cf == null:
		push_error("[Pose] 没有 CarrierForm")
		quit(1)
		return
	if not cf.set_form(true):
		push_error("[Pose] 变形失败")
		quit(1)
		return
	await process_frame

	var skel := cf.get("_skel") as Skeleton3D
	var ap := cf.get("_ap") as AnimationPlayer
	var carrier := cf.get("_carrier") as Node3D
	if skel == null or ap == null or carrier == null:
		push_error("[Pose] 拿不到骨架 / 动画器 / 载具节点")
		quit(1)
		return

	# 接管一切：本探针只关心「播这条动画时是什么姿势」
	cf.set_process(false)
	cf.set_physics_process(false)
	player.set_physics_process(false)
	player.call("set_flight_lock", true)

	var hip := _find_bone(skel, HIP_NAMES)
	var head := _find_bone(skel, HEAD_NAMES)
	print("")
	print("骨架 %d 根骨 ｜ 胯骨 index=%d ｜ 头骨 index=%d" % [
		skel.get_bone_count(), hip, head])
	if hip < 0 or head < 0:
		push_error("[Pose] 找不到胯/头骨，改名字再试")
		quit(1)
		return

	print("")
	print("========== 各动画的机身俯仰（正=前倾，负=仰头）==========")
	var clips: Array[String] = []
	for c in ap.get_animation_list():
		clips.append(String(c))
	clips.sort()
	for clip in clips:
		var anim := ap.get_animation(clip)
		if anim == null:
			continue
		ap.play(clip)
		var mid := anim.length * 0.5
		ap.seek(mid, true)
		for i in 6:
			await process_frame
		var pitch := _pitch_deg(skel, carrier, hip, head)
		var tag := ""
		if clip == "Move_Ing":
			tag = "   <== 飞行时播的就是这条"
		elif clip == "Idle":
			tag = "   <== 载具自带待机"
		elif clip == "Normal_Idle":
			tag = "   <== 地面待机"
		print("  %-22s 中点 t=%.2fs  pitch %+7.2f°%s" % [clip, mid, pitch, tag])

	# 再看 Move_Ing 整条片子里的极值（可能是某一帧特别仰）
	if ap.has_animation("Move_Ing"):
		var anim := ap.get_animation("Move_Ing")
		var lo := 999.0
		var hi := -999.0
		var lo_t := 0.0
		var hi_t := 0.0
		var steps := 24
		for k in steps:
			var t := anim.length * float(k) / float(steps)
			ap.play("Move_Ing")
			ap.seek(t, true)
			for i in 3:
				await process_frame
			var pitch := _pitch_deg(skel, carrier, hip, head)
			if pitch < lo:
				lo = pitch
				lo_t = t
			if pitch > hi:
				hi = pitch
				hi_t = t
		print("")
		print("========== Move_Ing 全片扫描（%d 个采样点）==========" % steps)
		print("  最仰 %.2f° @ t=%.2fs ｜ 最前倾 %.2f° @ t=%.2fs" % [lo, lo_t, hi, hi_t])

	print("")
	print("[Pose] 完")
	quit(0)


## 脊梁轴相对「正前方 / 正上方」的夹角（度）。正 = 前倾，负 = 后仰。
func _pitch_deg(skel: Skeleton3D, carrier: Node3D, hip: int, head: int) -> float:
	var xf := skel.global_transform
	var p_hip := (xf * skel.get_bone_global_pose(hip)).origin
	var p_head := (xf * skel.get_bone_global_pose(head)).origin
	var d := p_head - p_hip
	if d.length_squared() < 1e-6:
		return 0.0
	# 载具节点的 +Z 就是模型正面（`_sync_face()` 用的就是 yaw，脸 = (sin, cos)）
	var fwd := carrier.global_transform.basis.z.normalized()
	fwd.y = 0.0
	if fwd.length_squared() < 1e-6:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	return rad_to_deg(atan2(d.dot(fwd), d.dot(Vector3.UP)))


func _find_bone(skel: Skeleton3D, names: Array) -> int:
	for n in names:
		var i := skel.find_bone(String(n))
		if i >= 0:
			return i
	return -1
