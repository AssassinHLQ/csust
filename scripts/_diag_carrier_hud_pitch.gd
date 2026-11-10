extends SceneTree
## 诊断：① 变回本体后机甲 HUD 还在吗？② 飞行姿态角到底多少度？
##
## 用户 2026-11-10：
##   「变回普通爱丽丝为什么还有机甲爱丽丝的hud」
##   「机甲爱丽丝快速飞行为什么还是仰头」
##
## 本探针只量两件事，不下结论：
##   · HUD：变形前/后 `_power_layer.visible` 的变化
##   · 姿态：不同速度下 `_lean` 的稳态值（换算成度），和头骨的仰角
##
## 用法：
##   & <godot> --headless --path . --script res://scripts/_diag_carrier_hud_pitch.gd

const GAME := "res://scenes/game.tscn"

var _pass := 0
var _fail := 0


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  %s" % what)
	else:
		_fail += 1
		print("  FAIL  %s" % what)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("========== 机甲 HUD / 姿态诊断 ==========")
	var level := (load(GAME) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	for _i in 15:
		await process_frame

	var player := level.get_node_or_null("Player")
	var carrier := player.get_node_or_null("Arisu/CarrierForm") if player else null
	if carrier == null:
		push_error("[diag] 没有 CarrierForm")
		quit(1)
		return

	# 解锁 + 变形
	var MechStateScript := load("res://scripts/mech_state.gd") as GDScript
	MechStateScript.call("set_carrier_for_test", true)
	carrier.call("set_form", true)
	for _i in 20:
		await process_frame

	var hud = carrier.get("_power_layer")
	print("\n── 变形后 ──")
	print("  _power_layer 存在 = %s" % str(hud != null))
	if hud != null:
		print("  HUD visible = %s" % str(hud.visible))
		print("  HUD 文字 = 「%s」" % str(carrier.get("_power_label").text
			if carrier.get("_power_label") else ""))

	# 造点能量，让 HUD 有内容（截图里就是 5/5 满条那条）
	carrier.set("energy_bars", 5)
	carrier.set("fly_distance_m", 500.0)
	carrier.call("_update_power_hud")
	await process_frame
	if hud != null:
		print("  刷能量后 visible = %s 文字 = 「%s」" % [str(hud.visible),
			str(carrier.get("_power_label").text if carrier.get("_power_label") else "")])

	# 变回本体
	print("\n── 变回本体 ──")
	carrier.call("set_form", false)
	for _i in 20:
		await process_frame
	var hud2 = carrier.get("_power_layer")
	var still_visible: bool = hud2 != null and bool(hud2.visible)
	print("  _power_layer visible = %s" % str(hud2.visible if hud2 else "null"))
	if hud2 != null and carrier.get("_power_label") != null:
		print("  HUD 文字 = 「%s」" % str(carrier.get("_power_label").text))
	_check(not still_visible, "变回本体后机甲 HUD 已隐藏（实际 visible=%s）" % str(still_visible))

	# ── 姿态角 ──
	print("\n── 飞行姿态（_lean 换算成度）──")
	print("  常量：FLY_PITCH_LEVEL_DEG=%.2f  PER_SPEED=%.2f  EXTRA_MAX=%.2f" % [
		float(carrier.get("FLY_PITCH_LEVEL_DEG")) if carrier.get("FLY_PITCH_LEVEL_DEG") != null else 8.81,
		0.40, 9.0])
	carrier.call("set_form", true)
	for _i in 10:
		await process_frame
	# 模拟不同速度下的稳态 _lean
	for spd in [0.0, 5.0, 11.0, 19.0, 30.0]:
		carrier.set("flight_speed", spd)
		carrier.set("_airborne", true)
		# 让 lerp 收敛
		for _i in 90:
			carrier.call("_update_lean", 1.0 / 60.0)
		var lean_rad := float(carrier.get("_lean"))
		var lean_deg := rad_to_deg(lean_rad)
		# ⚠️ 这个数是**机身补偿角**，不是最终脊梁角：
		#    `_carrier.rotation.x = _lean`（绕 X 正转 = 机头下压 = 前倾），
		#    而动画自带 −7.31° 后仰，两者叠加后才是玩家看到的脊梁角度。
		#    所以这里**不能**用「> 12° 就是仰头」来判断 ——
		#    真正的姿态判定在 `_verify_carrier_pitch.gd`（它量的是脊梁骨）。
		#    本行只打印补偿值，不做判断。
		print("  速度 %5.1f m/s → 机身补偿 = %6.2f°（脊梁 = 补偿 − 7.31°）" % [spd, lean_deg])

	print("\n========== 结果 ==========")
	print("  通过 %d，失败 %d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
