extends SceneTree
## 标定：**让脊梁正好水平**需要多少 `_lean` 补偿角。
##
## 用户 2026-11-10：「完全不要仰头,好丑」。
##
## 背景：`_carrier.rotation.x = _lean`（绕 X 正转 = 机头下压 = 前倾），
## 而载具动画自带 −7.31° 后仰。所以「脊梁水平」= 补偿角抵消掉那 −7.31°。
## 但那个 7.31 是从某个具体动画片段量出来的 —— 飞行时播的是 `Move_Ing`，
## 它的后仰量可能不一样。本探针**扫一遍补偿角，找出脊梁 = 0 的那个点**。
##
## 用法：
##   & <godot> --headless --path . --script res://scripts/_diag_lean_calibrate.gd

const GAME := "res://scenes/game.tscn"
const HEAD_NAMES := ["Bip001 Head", "Bip001_Head", "bone_head"]
const HIP_NAMES := ["Bip001 Pelvis", "Bip001_Pelvis", "bone_pelvis", "Bip001 Hips"]


func _initialize() -> void:
	_run.call_deferred()


## 取「胯 → 头」这条向量相对世界水平的仰角（度）。
## 正 = 前倾（低头），负 = 后仰（抬头）。
## ⚠️ 本喵第一版取骨格的 basis.y 算，结果全是 −90°（取错轴）。
##    正确做法照抄 `_verify_carrier_pitch.gd::_pitch_deg()`：
##    **用两个骨骼的世界坐标之差**，投到机身前方向和世界上方向之间取 atan2。
func _pitch_deg(skel: Skeleton3D, carrier: Node3D, hip: int, head: int) -> float:
	if skel == null or hip < 0 or head < 0 or carrier == null:
		return 0.0
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
	print("========== 姿态补偿角标定 ==========")
	var level := (load(GAME) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	for _i in 15:
		await process_frame

	var player := level.get_node_or_null("Player")
	var carrier := player.get_node_or_null("Arisu/CarrierForm") if player else null
	if carrier == null:
		push_error("[cal] 没有 CarrierForm")
		quit(1)
		return
	var MechStateScript := load("res://scripts/mech_state.gd") as GDScript
	MechStateScript.call("set_carrier_for_test", true)
	carrier.call("set_form", true)
	for _i in 25:
		await process_frame

	var skel := carrier.get("_skel") as Skeleton3D
	if skel == null:
		push_error("[cal] 没有骨架")
		quit(1)
		return
	var hip := _find(skel, HIP_NAMES)
	var head := _find(skel, HEAD_NAMES)
	print("胯骨 = %d，头骨 = %d" % [hip, head])

	# ── 悬停：扫补偿角，找脊梁 ≈ 0 的点 ──
	print("\n── 悬停（airborne、速度 0）──")
	carrier.set("_airborne", true)
	carrier.set("flight_speed", 0.0)
	print("  补偿角 → 脊梁俯仰 / 头俯仰")
	for deg in [-6.0, -4.0, -3.0, -2.0, -1.0, 0.0, 1.0]:
		carrier.set("_lean", deg_to_rad(deg))
		# 强制把 _lean 应用到机身上（正常是 _process 里做）
		var model = carrier.get("_model")
		var carrier_node = carrier.get("_carrier") as Node3D
		if carrier_node != null and model != null:
			carrier_node.rotation = Vector3(float(carrier.get("_lean")),
				float(model.rotation.y), 0.0)
		await process_frame
		var pit := _pitch_deg(skel, carrier.get("_carrier"), hip, head)
		print("  %5.2f° → 脊梁 %+6.2f°%s" % [deg, pit, "  ← 仍仰头" if pit < -0.5 else ""])

	# ── 全速：同样扫一遍 ──
	print("\n── 全速（速度 19 m/s，用飞行动画）──")
	carrier.set("flight_speed", 19.0)
	# 让飞行动画播起来（和真飞一样）
	carrier.call("_play", "Move_Ing", true)
	for _i in 30:
		await process_frame
	for deg in [-6.0, -4.0, -3.0, -2.0, -1.0, 0.0, 1.0]:
		carrier.set("_lean", deg_to_rad(deg))
		var model = carrier.get("_model")
		var carrier_node = carrier.get("_carrier") as Node3D
		if carrier_node != null and model != null:
			carrier_node.rotation = Vector3(float(carrier.get("_lean")),
				float(model.rotation.y), 0.0)
		await process_frame
		var pit := _pitch_deg(skel, carrier.get("_carrier"), hip, head)
		print("  %5.2f° → 脊梁 %+6.2f°%s" % [deg, pit, "  ← 仍仰头" if pit < -0.5 else ""])

	print("\n（脊梁 ≈ 0 且不小负数 ⇒ 那个补偿角就是「完全不仰头」的值）")
	quit(0)
