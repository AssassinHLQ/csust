extends SceneTree
## 量「脸到底朝哪」——不再用脊梁（胯→头）当替身。
##
## 为什么重做：本喵上轮用脊梁俯仰（+1.91°）断言「已经平视」，但用户仍说仰视。
## **脊梁平 ≠ 脸平**：脖子/头可以被动画抬起来，而脊梁一动不动。
##
## 做法（自标定，不靠猜哪根轴是脸）：
##   ① 在地面待机 `Normal_Idle` 下，把头骨**世界基的三根轴**分别和模型正面
##      （载具节点的 +Z）以及世界上方做点积 —— 对齐度最高的那根就是「脸朝前」。
##   ② 拿同一根轴去量飞行姿态 `Move_Ing` 的**仰角**：
##        + = 脸朝上（仰视）  − = 脸朝下（俯视）  0 = 平视
##
##   & D:\GAME\godot\Godot_v4.7.1-stable_win64_console.exe --headless --path . \
##       --script res://scripts/_diag_carrier_head.gd

const PlayerScene := preload("res://scenes/player.tscn")
const MechState := preload("res://scripts/mech_state.gd")
const CarrierForm := preload("res://scripts/carrier_form.gd")

const HEAD := ["Bip001 Head", "Bip001_Head"]
const NECK := ["Bip001 Neck", "Bip001_Neck"]


func _initialize() -> void:
	_run()


func _run() -> void:
	MechState.set_carrier_for_test(true)
	var stage := Node3D.new()
	root.add_child(stage)
	var player := PlayerScene.instantiate() as Player
	stage.add_child(player)
	await process_frame
	await process_frame
	var cf := player.get_node_or_null("Arisu/CarrierForm") as CarrierForm
	if cf == null or not cf.set_form(true):
		push_error("[Head] 变形失败")
		quit(1)
		return
	await process_frame
	var skel := cf.get("_skel") as Skeleton3D
	var ap := cf.get("_ap") as AnimationPlayer
	var carrier := cf.get("_carrier") as Node3D
	if skel == null or ap == null or carrier == null:
		push_error("[Head] 拿不到骨架/动画器/节点")
		quit(1)
		return
	cf.set_process(false)
	cf.set_physics_process(false)
	player.set_physics_process(false)
	player.call("set_flight_lock", true)

	var hi := _bone(skel, HEAD)
	var ni := _bone(skel, NECK)
	var pi := _bone(skel, ["Bip001 Pelvis", "bone_hip"])
	print("")
	print("头骨 index=%d  颈骨 index=%d  胯骨 index=%d" % [hi, ni, pi])
	if hi < 0:
		push_error("[Head] 找不到头骨")
		quit(1)
		return

	# ── ① 标定：地面待机下，头骨哪根轴对得上「模型正面」 ──
	var face_axis := -1
	await _play(ap, "Normal_Idle", 0.5)
	var fwd := _flat_fwd(carrier)
	print("")
	print("========== ① 标定（地面待机 Normal_Idle）==========")
	var axes := ["local X", "local Y", "local Z"]
	var best := 0.0
	for a in 3:
		var d := (_axis_world(skel, hi, a) as Vector3).dot(fwd)
		print("   %s 与模型正面的点积 = %+.3f" % [axes[a], d])
		if absf(d) > best:
			best = absf(d)
			face_axis = a
	if face_axis < 0:
		push_error("[Head] 标定失败")
		quit(1)
		return
	print("   ⇒ 脸朝前 = 头骨的 **%s**（点积绝对值最大 %.3f）" % [axes[face_axis], best])

	# ── ② 各动画下「脸」的仰角 ──
	print("")
	print("========== ② 各动画下三根轴的仰角（正=朝上 / 负=朝下）==========")
	print("   判据：哪根轴在 `Idle` / `Walk` 下接近 0（＝正常平视），那根才是「脸」")
	for clip in ["Normal_Idle", "Idle", "Move_Ing", "Walk", "Normal_Attack_Ing"]:
		if not ap.has_animation(clip):
			continue
		await _play(ap, clip, 0.5)
		var tag := "   <== 飞行时播的" if clip == "Move_Ing" else ""
		print("  %-20s%s" % [clip, tag])
		for a in 3:
			var dir := _axis_world(skel, hi, a) as Vector3
			var face := dir.dot(fwd)
			var up := dir.y
			var elev := rad_to_deg(atan2(up, absf(face)))
			print("      local %s：前向分量 %+.3f   仰角 %+7.2f°" % [["X", "Y", "Z"][a], face, elev])

	print("")
	print("[Head] 完")
	quit(0)


func _play(ap: AnimationPlayer, clip: String, frac: float) -> void:
	var anim := ap.get_animation(clip)
	ap.play(clip)
	ap.seek(anim.length * frac, true)
	for i in 8:
		await process_frame


## 头骨第 `a` 根局部轴在世界空间的方向（0=X 1=Y 2=Z）
func _axis_world(skel: Skeleton3D, bi: int, a: int) -> Vector3:
	var xf := skel.global_transform * skel.get_bone_global_pose(bi)
	match a:
		0:
			return xf.basis.x.normalized()
		1:
			return xf.basis.y.normalized()
		_:
			return xf.basis.z.normalized()


## 模型正面（去掉俯仰，只取水平）
func _flat_fwd(carrier: Node3D) -> Vector3:
	var f := carrier.global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 1e-6 else Vector3.FORWARD


func _bone(skel: Skeleton3D, names: Array) -> int:
	for n in names:
		var i := skel.find_bone(String(n))
		if i >= 0:
			return i
	return -1
