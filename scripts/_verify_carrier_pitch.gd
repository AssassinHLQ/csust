extends SceneTree
## 验「飞行时机身俯仰」：悬停要平视，加速要稍微前倾，**任何情况都不许后仰**。
##
## 背景（用户 2026-11-08：「飞行姿势为什么这么奇怪，仰头，应该平视前方」）：
##   · `_diag_carrier_pose.gd` 量出飞行时播的 `Move_Ing` 自带 **−7.31°** 后仰；
##   · 而负责补偿的 `_lean` 是**死代码**（只写不读），所以补偿从来没生效。
## 现在 `_update_lean()` + `_sync_face()` 把它接上了（用节点俯仰，不是骨姿势
## —— 骨姿势会被同一帧的 `AnimationPlayer` 覆盖）。
##
## 判据：脊梁（胯→头）相对「正前方 / 正上方」的夹角
##   正 = 头在胯的前方（前倾）   负 = 头在胯的后方（后仰 / 仰头）
##
##   & D:\GAME\godot\Godot_v4.7.1-stable_win64_console.exe --headless --path . \
##       --script res://scripts/_verify_carrier_pitch.gd

const PlayerScene := preload("res://scenes/player.tscn")
const MechState := preload("res://scripts/mech_state.gd")
const CarrierForm := preload("res://scripts/carrier_form.gd")

const HIP_NAMES := ["Bip001 Pelvis", "Bip001_Pelvis", "bone_hip"]
const HEAD_NAMES := ["Bip001 Head", "Bip001_Head", "bone_head"]

## 悬停时允许的俯仰区间（度）。上界给宽一点：宁可略前倾，也绝不能后仰。
const HOVER_MIN := -3.0
const HOVER_MAX := 18.0
## 前进时的允许区间。
##
## ⚠️ 2026-11-10 放宽下限 2.0 → 0.0：用户明确要求「**完全不要仰头**」。
##    原来的 2.0 是"必须明显前倾"，但实测标定（`_diag_lean_calibrate4`）证明
##    补偿 7.3° 时脊梁正好 +0.55° —— 水平略前倾，视觉上最端正。
##    硬要求 2° 会逼着把补偿调大，反而容易过头。
##    现在的口径：**只要不是仰（> −0.3°）就算过**，上界仍防止俯冲。
const CRUISE_MIN := 0.0
const CRUISE_MAX := 30.0

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run()


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  %s" % what)
	else:
		_fail += 1
		print("  FAIL  %s" % what)


func _run() -> void:
	MechState.set_carrier_for_test(true)

	var stage := Node3D.new()
	stage.name = "PitchStage"
	root.add_child(stage)
	var floor_body := StaticBody3D.new()
	var fm := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120, 120)
	fm.mesh = plane
	floor_body.add_child(fm)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120, 0.4, 120)
	col.shape = box
	col.position.y = -0.2
	floor_body.add_child(col)
	stage.add_child(floor_body)

	var player := PlayerScene.instantiate() as Player
	stage.add_child(player)
	await process_frame
	await process_frame

	var cf := player.get_node_or_null("Arisu/CarrierForm") as CarrierForm
	if cf == null:
		push_error("[Pitch] 没有 CarrierForm")
		quit(1)
		return
	_check(cf.set_form(true), "变形成功")
	await process_frame

	var skel := cf.get("_skel") as Skeleton3D
	var carrier := cf.get("_carrier") as Node3D
	var hip := _bone(skel, HIP_NAMES)
	var head := _bone(skel, HEAD_NAMES)
	_check(skel != null and hip >= 0 and head >= 0, "拿得到骨架与胯/头骨")
	if skel == null or hip < 0 or head < 0:
		_done()
		return

	# 起飞、抬到 40 m 高空（远离地板，免得触发落地）
	cf.call("_take_off")
	await process_frame
	player.global_position.y = 40.0
	cf.set("_hold_y", 40.0)
	player.set("velocity", Vector3.ZERO)

	print("")
	print("========== 1. 悬停：应该平视前方 ==========")
	for i in 90:
		player.set("velocity", Vector3.ZERO)
		await physics_frame
	var p_hover := _pitch_deg(skel, carrier, hip, head)
	var lean_hover := rad_to_deg(float(cf.get("_lean")))
	print("       脊梁俯仰 %+.2f°（机身补偿 %+.2f°）" % [p_hover, lean_hover])
	# ⚠️ 脊梁平**不等于**脸平（2026-11-08 用户第二次说「还是仰视」才发现：
	#    `Move_Ing` 把脸抬了 46°，而脊梁一动不动）。所以这里必须单独量「脸」。
	var f_hover := _face_deg(skel, carrier, head)
	print("       脸的仰角 %+.2f°（正 = 仰视）" % f_hover)
	_check(absf(f_hover) <= 12.0, "悬停时脸是平视的（|%+.2f°| ≤ 12°）" % f_hover)
	_check(p_hover >= HOVER_MIN, "悬停没有后仰（%+.2f° ≥ %+.1f°）" % [p_hover, HOVER_MIN])
	_check(p_hover <= HOVER_MAX, "悬停没有过分低头（%+.2f° ≤ %+.1f°）" % [p_hover, HOVER_MAX])
	_check(absf(p_hover) <= 8.0, "悬停基本平视（|%+.2f°| ≤ 8°）" % p_hover)

	print("")
	print("========== 2. 加力前进：应该稍微前倾 ==========")
	Input.action_press("move_forward")
	Input.action_press("sprint")
	for i in 120:
		await physics_frame
	var hs := Vector2(player.velocity.x, player.velocity.z).length()
	var p_cruise := _pitch_deg(skel, carrier, hip, head)
	var lean_cruise := rad_to_deg(float(cf.get("_lean")))
	print("       水平速度 %.2f m/s ｜ 脊梁俯仰 %+.2f°（机身补偿 %+.2f°）" % [
		hs, p_cruise, lean_cruise])
	_check(hs > 8.0, "确实在前进（%.2f m/s > 8）" % hs)
	_check(p_cruise >= CRUISE_MIN, "前进时**没有仰头**（%+.2f° ≥ %+.1f°）" % [p_cruise, CRUISE_MIN])
	_check(p_cruise <= CRUISE_MAX, "前倾没有夸张到俯冲（%+.2f° ≤ %+.1f°）" % [p_cruise, CRUISE_MAX])

	print("")
	print("========== 3. 地面：也要端正（不仰头）==========")
	Input.action_release("move_forward")
	Input.action_release("sprint")
	cf.call("_land")
	player.global_position = Vector3(0, 0.6, 0)
	player.set("velocity", Vector3.ZERO)
	for i in 60:
		await physics_frame
	var lean_ground := rad_to_deg(float(cf.get("_lean")))
	var p_ground := _pitch_deg(skel, carrier, hip, head)
	print("       地面机身补偿 %+.2f°（地面专用值 %.2f°）" % [
		lean_ground, float(cf.get("lean_comp_ground_deg"))])
	print("       地面脊梁俯仰 %+.2f°" % p_ground)
	# ⚠️ 2026-11-10 改：原来这里断言 `|_lean| < 1.0`（"落地后补偿回到 0"）——
	#    那**正是 bug 本身**：地上不补偿 ⇒ 机甲 Idle 自带的 −6.6° 后仰露出来 ⇒
	#    用户看到的「站在地上仰头」。现在判据改成**真正的脊梁角**：
	#    地上空中都要端正（≈水平，允许略前倾）。
	#    地上用单独的标定值（−2.0°），因为地上播 `Idle`、空中播 `Move_Ing`。
	_check(p_ground > -3.0, "落地后**没有仰头**（%+.2f° > -3.0）" % p_ground)
	_check(absf(p_ground) < 6.0, "落地后基本端正（|%+.2f°| < 6）" % p_ground)
	_check(absf(lean_ground - float(cf.get("lean_comp_ground_deg"))) < 0.5,
		"地面补偿用的是**地面专用值**（实测 %+.2f°）" % lean_ground)

	_done()


## 「脸」的仰角（度，正 = 仰视）。
##
## 头骨的 **local Y** 就是脸朝前 —— 这是 `_diag_carrier_head.gd` 在地上待机姿态下
## 自标定出来的（local Y 与模型正面的点积 +1.000、仰角 +1.4°，而 local X 仰角 88°、
## local Z 仰角 −83°，只有 Y 讲得通）。
func _face_deg(skel: Skeleton3D, carrier: Node3D, head: int) -> float:
	var xf := skel.global_transform * skel.get_bone_global_pose(head)
	var dir := xf.basis.y.normalized()
	# 模型正面要去掉俯仰：载具节点本身会被 `_lean` 压下去，
	# 拿带俯仰的 basis.z 当水平参照会把机身俯仰算进「脸」里。
	var fwd := carrier.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 1e-6:
		return 0.0
	fwd = fwd.normalized()
	return rad_to_deg(atan2(dir.y, absf(dir.dot(fwd))))


func _pitch_deg(skel: Skeleton3D, carrier: Node3D, hip: int, head: int) -> float:
	var xf := skel.global_transform
	var p_hip := (xf * skel.get_bone_global_pose(hip)).origin
	var p_head := (xf * skel.get_bone_global_pose(head)).origin
	var d := p_head - p_hip
	if d.length_squared() < 1e-6:
		return 0.0
	var fwd := carrier.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 1e-6:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	return rad_to_deg(atan2(d.dot(fwd), d.dot(Vector3.UP)))


func _bone(skel: Skeleton3D, names: Array) -> int:
	if skel == null:
		return -1
	for n in names:
		var i := skel.find_bone(String(n))
		if i >= 0:
			return i
	return -1


func _done() -> void:
	MechState.set_carrier_for_test(false)
	print("")
	print("========== 结果 ==========")
	if _fail == 0:
		print("全部 %d 项通过" % _pass)
	else:
		print("%d 项通过，%d 项失败" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
