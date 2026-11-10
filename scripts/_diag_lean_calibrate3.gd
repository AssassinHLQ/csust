extends SceneTree
## 标定 v3：**走真实 `_process` 流程**扫 `lean_comp_deg`，量脊梁俯仰。
##
## 为什么有 v1/v2/v3：
##   v1 手动写 `_carrier.rotation` ⇒ 绕过了真实流程，量出 −3°→+0.72°（**假数据**）
##   v2 想绕开 const 但绕不动，只打印了当前值
##   v3 把补偿角改成 `var lean_comp_deg`，探针可以直接改、真实流程量真值
##
## 用法：
##   & <godot> --headless --path . --script res://scripts/_diag_lean_calibrate3.gd

const GAME := "res://scenes/game.tscn"
const HEAD_NAMES := ["Bip001 Head", "Bip001_Head", "bone_head"]
const HIP_NAMES := ["Bip001 Pelvis", "Bip001_Pelvis", "bone_pelvis", "Bip001 Hips"]


func _initialize() -> void:
	_run.call_deferred()


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


func _find(skel: Skeleton3D, names: Array) -> int:
	for n in names:
		var i := skel.find_bone(String(n))
		if i >= 0:
			return i
	return -1


func _run() -> void:
	print("========== 姿态标定 v3（真实流程扫参）==========")
	var level := (load(GAME) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	for _i in 15:
		await process_frame

	var player := level.get_node_or_null("Player")
	var carrier := player.get_node_or_null("Arisu/CarrierForm") if player else null
	if carrier == null:
		push_error("[cal3] 没有 CarrierForm")
		quit(1)
		return
	var MechStateScript := load("res://scripts/mech_state.gd") as GDScript
	MechStateScript.call("set_carrier_for_test", true)
	carrier.call("set_form", true)
	for _i in 25:
		await process_frame

	var skel := carrier.get("_skel") as Skeleton3D
	var cnode := carrier.get("_carrier") as Node3D
	var hip := _find(skel, HIP_NAMES)
	var head := _find(skel, HEAD_NAMES)

	print("  补偿角 → 悬停脊梁 / 全速脊梁（正=前倾，负=仰头）")
	var best_deg := 0.0
	var best_err := 999.0
	for deg in [-14.0, -12.0, -10.0, -8.0, -6.0, -4.0, -2.0, 0.0]:
		carrier.set("lean_comp_deg", deg)
		# 悬停收敛
		carrier.set("_airborne", true)
		carrier.set("flight_speed", 0.0)
		for _i in 100:
			await process_frame
		var p_hover := _pitch_deg(skel, cnode, hip, head)
		# 全速收敛
		carrier.set("flight_speed", 19.0)
		for _i in 100:
			await process_frame
		var p_fast := _pitch_deg(skel, cnode, hip, head)
		var tag := ""
		# 「完全不要仰头」= 两个都比 −0.3° 大（不留仰头），且尽量接近 0
		if p_hover > -0.3 and p_fast > -0.3:
			var err := absf(p_hover) + absf(p_fast)
			if err < best_err:
				best_err = err
				best_deg = deg
			tag = "  ← 合格"
		print("  %6.1f° → %+6.2f° / %+6.2f°%s" % [deg, p_hover, p_fast, tag])

	print("\n★ 最佳补偿角 = %.1f°（两态偏差和 %.2f°）" % [best_deg, best_err])
	print("  把 carrier_form.gd 的 lean_comp_deg 设成这个值。")
	quit(0)
