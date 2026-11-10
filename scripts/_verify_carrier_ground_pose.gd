extends SceneTree
## 自检：**机甲站在地上**时脊梁是端正的（不仰头）。
##
## 用户 2026-11-10：「只有地上,爱丽丝机甲才仰头,空中之前改好了」
##
## 病因：`carrier_form.gd` 里两处都被 `_airborne` 挡住
##   · `_update_lean()`   只有空中才补偿机身 ⇒ 地上补偿 = 0
##   · `_fix_head_face()` 只有空中才掰头
## 而机甲自带的 `Idle` 动画有 **−6.60° 后仰** ⇒ 站在地上就是仰头姿势。
##
## 本探针**只测地面**（不按起飞键），拿 `_verify_carrier_pitch.gd` 同一套几何量法
## （胯→头向量投到前向/上向）。
##
## 用法：
##   & <godot> --headless --path . --script res://scripts/_verify_carrier_ground_pose.gd

const GAME := "res://scenes/game.tscn"
const HIP_NAMES := ["Bip001 Pelvis", "Bip001_Pelvis", "bone_hip"]
const HEAD_NAMES := ["Bip001 Head", "Bip001_Head", "bone_head"]

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


func _bone(sk: Skeleton3D, names: Array) -> int:
	for n in names:
		var i := sk.find_bone(String(n))
		if i >= 0:
			return i
	return -1


func _pitch_deg(sk: Skeleton3D, carrier: Node3D, hip: int, head: int) -> float:
	var xf := sk.global_transform
	var p_hip := (xf * sk.get_bone_global_pose(hip)).origin
	var p_head := (xf * sk.get_bone_global_pose(head)).origin
	var d := p_head - p_hip
	if d.length_squared() < 1e-6:
		return 0.0
	var fwd := carrier.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 1e-6:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	return rad_to_deg(atan2(d.dot(fwd), d.dot(Vector3.UP)))


func _run() -> void:
	print("========== 机甲地面姿态自检 ==========")
	var level := (load(GAME) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	for _i in 20:
		await process_frame

	var player := level.get_node_or_null("Player") as CharacterBody3D
	var cf := player.get_node_or_null("Arisu/CarrierForm") if player else null
	if player == null or cf == null:
		push_error("[verify] 缺 Player 或 CarrierForm")
		quit(1)
		return

	# 站到地面
	player.global_position = Vector3(0.0, 0.6, 0.0)
	player.set("velocity", Vector3.ZERO)
	for _i in 60:
		await physics_frame
	_check(player.is_on_floor(), "① 先站在地上")

	# 变形（**不按起飞键**，全程留在地面）
	var MechStateScript := load("res://scripts/mech_state.gd") as GDScript
	MechStateScript.call("set_carrier_for_test", true)
	var ok := bool(cf.call("set_form", true))
	_check(ok, "② 变身成机甲")
	for _i in 120:
		await physics_frame

	var airborne := bool(cf.get("_airborne"))
	print("  变身并稳定后：airborne = %s（应为 false，全程没起飞）" % str(airborne))
	_check(not airborne, "③ 全程都在地面上（airborne = false）")

	var skel := cf.get("_skel") as Skeleton3D
	var cnode := cf.get("_carrier") as Node3D
	if skel == null or cnode == null:
		_check(false, "拿得到骨架与载具节点")
		_finish()
		return
	var hip := _bone(skel, HIP_NAMES)
	var head := _bone(skel, HEAD_NAMES)
	_check(hip >= 0 and head >= 0, "④ 拿得到胯/头骨（%d / %d）" % [hip, head])

	var lean := rad_to_deg(float(cf.get("_lean")))
	var pitch := _pitch_deg(skel, cnode, hip, head)
	print("  地面机身补偿 = %+.2f°" % lean)
	print("  地面脊梁俯仰 = %+.2f°（正 = 前倾，负 = 仰头）" % pitch)

	# 核心断言：地上也不许仰头
	_check(pitch > -3.0, "⑤ 站在地上**没有仰头**（%+.2f° > -3.0）" % pitch)
	_check(absf(pitch) < 6.0, "⑥ 站在地上基本端正（|%+.2f°| < 6）" % pitch)
	# 补偿必须真的生效（这是修好的直接证据）。
	# ⚠️ 判据是「等于配置的地面值」，不是「绝对值够大」——
	#    标定出来的正确地面值是 −2.0°（|−2| < 3，本喵第一版写成 >3.0 就误报了）。
	#    而且地面值与空中值**刻意不同**：两者播不同动画（`Idle` vs `Move_Ing`）。
	var want_ground := float(cf.get("lean_comp_ground_deg"))
	_check(absf(lean - want_ground) < 0.5,
		"⑦ 地面补偿已生效（实测 %+.2f°，配置 %+.2f°）" % [lean, want_ground])
	_check(absf(want_ground - float(cf.get("lean_comp_deg"))) > 0.5,
		"⑧ 地面值与空中值**分开标定**（%.2f° vs %.2f°）" % [
			want_ground, float(cf.get("lean_comp_deg"))])

	_finish()


func _finish() -> void:
	print("\n========== 结果 ==========")
	print("  通过 %d，失败 %d" % [_pass, _fail])
	print("  %s" % ("★ 机甲在地面也端正" if _fail == 0 else "✗ 有问题"))
	quit(0 if _fail == 0 else 1)
