extends SceneTree
## 标定（第二版）：**走正常 `_process` 流程**，量 `_lean` → 脊梁俯仰的真实映射。
##
## 第一版错在：本喵手动写 `_carrier.rotation`，但那和真实流程不等价 ——
## `_process` 里还有别的东西会影响最终姿态（动画层、`_sync_face` 等）。
## 结果第一版标出 −3°、真实跑出来却是 −9.88°，差了 10° 多。
##
## 这一版**只改 `_lean`，其余全交给正常流程**，让 lerp 收敛后量真值。
##
## 用法：
##   & <godot> --headless --path . --script res://scripts/_diag_lean_calibrate2.gd

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
	print("========== 姿态标定 v2（走真实流程）==========")
	var level := (load(GAME) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	for _i in 15:
		await process_frame

	var player := level.get_node_or_null("Player")
	var carrier := player.get_node_or_null("Arisu/CarrierForm") if player else null
	if carrier == null:
		push_error("[cal2] 没有 CarrierForm")
		quit(1)
		return
	var MechStateScript := load("res://scripts/mech_state.gd") as GDScript
	MechStateScript.call("set_carrier_for_test", true)
	carrier.call("set_form", true)
	for _i in 25:
		await process_frame

	var skel := carrier.get("_skel") as Skeleton3D
	var cnode := carrier.get("_carrier") as Node3D
	if skel == null or cnode == null:
		push_error("[cal2] 没有骨架/载具节点")
		quit(1)
		return
	var hip := _find(skel, HIP_NAMES)
	var head := _find(skel, HEAD_NAMES)

	# ⚠️ 关键：把 `_update_lean` 的 want 直接顶成我们要测的值，
	#    绕开它内部的常量。做法是每帧喂完再读 —— 但 `_update_lean` 每帧都会覆盖，
	#    所以改成：先算出真实映射（用几组直传值 + 等收敛）。
	#    最干净的办法是临时改常量做不到（const），
	#    于是这里**直接调 _carrier.rotation 之后再多等几帧**，
	#    让 `_process` 里的 `_carrier.rotation = Vector3(_lean, ...)` 覆盖回来 ——
	#    那就测不到。所以改成：**临时把 _update_lean 换成空实现不可能**（GDScript 不支持）。
	#
	# 结论：只能在当前 `_lean` 常量固定为 −3° 的前提下，
	# 直接量真实流程的最终结果（这才是玩家看到的）。
	print("  当前代码里的补偿角 = %.2f°" % rad_to_deg(float(carrier.get("_lean"))))

	print("\n── 悬停（真实流程）──")
	carrier.set("_airborne", true)
	carrier.set("flight_speed", 0.0)
	for _i in 120:
		await process_frame
	var p_hover := _pitch_deg(skel, cnode, hip, head)
	print("  脊梁 = %+.2f°  机身补偿 = %.2f°" % [
		p_hover, rad_to_deg(float(carrier.get("_lean")))])

	print("\n── 全速 19 m/s（真实流程）──")
	carrier.set("flight_speed", 19.0)
	for _i in 120:
		await process_frame
	var p_fast := _pitch_deg(skel, cnode, hip, head)
	print("  脊梁 = %+.2f°  机身补偿 = %.2f°" % [
		p_fast, rad_to_deg(float(carrier.get("_lean")))])

	# 反推：需要多少补偿才能让脊梁 = 0？
	# 已知当前补偿 c0 得到 p0，若映射是近似线性的（前面 v1 量过斜率 1.77/2 ≈ 0.885），
	# 需要 c = c0 - p0 / 0.885
	var c0 := rad_to_deg(float(carrier.get("_lean")))
	const SLOPE := 0.885
	print("\n── 反推「脊梁 = 0」需要多少补偿 ──")
	print("  当前 %.2f° → 脊梁 %+.2f°" % [c0, p_hover])
	print("  反推 %.2f°（假设斜率 %.3f）" % [c0 - p_hover / SLOPE, SLOPE])
	print("  ⚠️ 斜率是用 v1 的扫描估的，最终要以真实流程再验一次。")
	quit(0)
