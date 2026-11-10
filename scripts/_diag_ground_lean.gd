extends SceneTree
## 标定：机甲**站在地上**时，机身补偿角取多少脊梁才端正（≈0°）。
##
## 用户 2026-11-10：「只有地上,爱丽丝机甲才仰头,空中之前改好了」
##
## 空中已经标定好（`lean_comp_deg = 7.3` ⇒ 脊梁 +0.35°）。
## 地上因为播的是另一个动画（`Idle`），同一个 7.3 落出 **+10.96°**（前倾过头），
## 所以要单独扫一个值。
##
## 用法：
##   & <godot> --headless --path . --script res://scripts/_diag_ground_lean.gd

const GAME := "res://scenes/game.tscn"
const HIP_NAMES := ["Bip001 Pelvis", "Bip001_Pelvis", "bone_hip"]
const HEAD_NAMES := ["Bip001 Head", "Bip001_Head", "bone_head"]


func _initialize() -> void:
	_run.call_deferred()


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
	print("========== 地面机身补偿角标定 ==========")
	var level := (load(GAME) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	for _i in 20:
		await process_frame

	var player := level.get_node_or_null("Player") as CharacterBody3D
	var cf := player.get_node_or_null("Arisu/CarrierForm") if player else null
	if player == null or cf == null:
		push_error("[cal] 缺 Player / CarrierForm")
		quit(1)
		return

	player.global_position = Vector3(0.0, 0.6, 0.0)
	player.set("velocity", Vector3.ZERO)
	for _i in 60:
		await physics_frame

	var MechStateScript := load("res://scripts/mech_state.gd") as GDScript
	MechStateScript.call("set_carrier_for_test", true)
	cf.call("set_form", true)
	for _i in 100:
		await physics_frame

	var skel := cf.get("_skel") as Skeleton3D
	var cnode := cf.get("_carrier") as Node3D
	var hip := _bone(skel, HIP_NAMES)
	var head := _bone(skel, HEAD_NAMES)
	print("  骨架就位：胯 %d 头 %d   airborne = %s" % [hip, head, str(cf.get("_airborne"))])

	print("\n  补偿角 → 地面脊梁俯仰（正 = 前倾，负 = 仰头）")
	var best := 0.0
	var best_err := 999.0
	for deg in [-12.0, -10.0, -8.0, -6.0, -5.0, -4.0, -2.0, 0.0, 3.0, 7.3]:
		cf.set("lean_comp_ground_deg", deg)
		for _i in 70:
			await physics_frame
		var p := _pitch_deg(skel, cnode, hip, head)
		var tag := ""
		if absf(p) < best_err:
			best_err = absf(p)
			best = deg
			tag = "  ← 目前最正"
		print("  %6.1f° → 脊梁 %+7.2f°%s" % [deg, p, tag])

	print("\n★ 最端正的地面补偿角 = %.1f°（脊梁偏差 %.2f°）" % [best, best_err])
	print("  把它写进 carrier_form.gd::lean_comp_ground_deg")
	quit(0)
