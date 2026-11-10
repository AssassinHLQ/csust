extends SceneTree
## 标定 v4：用**真实飞行**驱动（不手工设 `_airborne`），扫 `lean_comp_deg`。
##
## v3 的失败：八个补偿角量出**完全一样**的脊梁（+3.17° / +2.96°），
## 说明 `_update_lean()` 根本没生效。怀疑两点：
##   ① `_process` 里 `if _oneshot_left > 0.0 and _oneshot_full: return` 提前退出
##   ② 手工设 `_airborne` 会被 `_physics_process` 覆盖回去
##
## v4 改法：**照真人操作**——调 `set_form(true)` 后真的让它飞起来
## （调 `player.gd` 的垂直输入），等稳定后量脊梁。
##
## 用法：
##   & <godot> --headless --path . --script res://scripts/_diag_lean_calibrate4.gd

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
	print("========== 姿态标定 v4（真实飞行驱动）==========")
	var level := (load(GAME) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	for _i in 20:
		await process_frame

	var player := level.get_node_or_null("Player")
	var carrier := player.get_node_or_null("Arisu/CarrierForm") if player else null
	if carrier == null:
		push_error("[cal4] 没有 CarrierForm")
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

	# 让它真的飞起来 —— 必须**模拟真实按键**：
	# `_tick_flight()` 读的是 `Input.is_action_pressed("jump")` / `rise_key`，
	# 直接设 `_vert_want` 或 `_airborne` 都没用（v3/v4 前几版就是这么白测的）。
	Input.action_press("jump")
	for _i in 90:
		await physics_frame
	print("  起升后：airborne=%s  高度=%.2f  _lean=%.2f°" % [
		str(carrier.get("_airborne")), (player as Node3D).global_position.y,
		rad_to_deg(float(carrier.get("_lean")))])
	# 松手（保持 airborne，不再继续爬升）
	Input.action_release("jump")
	for _i in 20:
		await physics_frame

	print("\n  补偿角 → 悬停脊梁 / 全速脊梁（正=前倾，负=仰头）")
	var rows := []
	for deg in [7.3]:
		carrier.set("lean_comp_deg", deg)
		# 悬停（不加速）
		carrier.set("_vert_want", 0.0)
		for _i in 90:
			await physics_frame
		for _i in 30:
			await process_frame
		var p_hover := _pitch_deg(skel, cnode, hip, head)
		# 全速：给一个水平速度
		(player as CharacterBody3D).velocity.x = 19.0
		for _i in 60:
			await physics_frame
		for _i in 20:
			await process_frame
		var p_fast := _pitch_deg(skel, cnode, hip, head)
		var lean_now := rad_to_deg(float(carrier.get("_lean")))
		rows.append([deg, p_hover, p_fast, lean_now])
		print("  %6.1f° → %+6.2f° / %+6.2f°   (_lean=%.2f°)" % [deg, p_hover, p_fast, lean_now])

	# 挑「两态都不仰头、且最接近 0」
	var best := 0.0
	var best_err := 999.0
	for r in rows:
		var ph: float = r[1]
		var pf: float = r[2]
		if ph > -0.3 and pf > -0.3:
			var e := absf(ph) + absf(pf)
			if e < best_err:
				best_err = e
				best = r[0]
	print("\n★ 最佳 = %.1f°（偏差和 %.2f°）" % [best, best_err])
	quit(0)
