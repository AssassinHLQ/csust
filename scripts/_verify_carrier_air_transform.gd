extends SceneTree
## 自检：**在空中变身**也能飞（不必先落地）。
##
## 用户 2026-11-10：「为什么在空中变身不能飞行,只能够从地上飞起来?」
##
## 病因（本喵查到的）：
##   `set_form(true)` 原来无条件 `_airborne = false`，而重新起飞的判定是
##     `not _airborne and grounded_grace and hold_ms <= JUMP_BUFFER_MS`
##     `grounded_grace = on_floor or (now - _air_since) <= COYOTE_MS(110ms)`
##   空中时 `on_floor=false`、`_air_since` 早已过期 ⇒ **永远起飞不了**，
##   垂直方向又被本脚本接管 ⇒ 人僵在半空。
##
## 本探针做的是**真实复现**：
##   ① 让玩家先站在地上
##   ② 用真实按键起跳，跳到空中
##   ③ **在空中**变身成机甲
##   ④ 再按上升键 —— 必须真的往上飞（高度显著增加）
##
## 用法：
##   & <godot> --headless --path . --script res://scripts/_verify_carrier_air_transform.gd

const GAME := "res://scenes/game.tscn"

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  %s" % what)
	else:
		_fail += 1
		print("  FAIL  %s" % what)


func _run() -> void:
	print("========== 空中变身飞行自检 ==========")
	var level := (load(GAME) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	for _i in 20:
		await process_frame

	var player := level.get_node_or_null("Player") as CharacterBody3D
	var carrier := player.get_node_or_null("Arisu/CarrierForm") if player else null
	if player == null or carrier == null:
		push_error("[verify] 缺 Player 或 CarrierForm")
		quit(1)
		return
	var MechStateScript := load("res://scripts/mech_state.gd") as GDScript
	MechStateScript.call("set_carrier_for_test", true)

	# ① 站稳
	for _i in 40:
		await physics_frame
	var y0 := player.global_position.y
	print("  地面高度 y = %.2f   on_floor = %s" % [y0, str(player.is_on_floor())])
	_check(player.is_on_floor(), "① 起跳前站在地上")

	# ② 真实按键起跳（普通形态），跳到空中
	Input.action_press("jump")
	for _i in 30:
		await physics_frame
	Input.action_release("jump")
	for _i in 6:
		await physics_frame
	var y_mid := player.global_position.y
	var on_floor_now := player.is_on_floor()
	print("  跳到 y = %.2f（离地 %.2f m）  on_floor = %s" % [y_mid, y_mid - y0, str(on_floor_now)])
	_check(not on_floor_now and y_mid - y0 > 0.5,
		"② 已离地（高度 %.2f m）" % (y_mid - y0))

	# ③ **在空中**变身
	carrier.call("set_form", true)
	for _i in 8:
		await physics_frame
	var airborne := bool(carrier.get("_airborne"))
	var y_after_form := player.global_position.y
	print("  空中变身：airborne=%s  高度 %.2f → %.2f" % [
		str(airborne), y_mid, y_after_form])
	_check(airborne, "③ 空中变身后 _airborne = true（不再被强制打回地面态）")
	# 变身不应该掉下去太多（重力已被接管）
	_check(y_after_form > y_mid - 1.5,
		"③ 变身瞬间没有往下掉（掉了 %.2f m）" % (y_mid - y_after_form))

	# ④ 再按上升键 —— 必须真的往上飞
	var y_before_rise := player.global_position.y
	Input.action_press("jump")
	for _i in 75:
		await physics_frame
	Input.action_release("jump")
	var y_after_rise := player.global_position.y
	var climbed := y_after_rise - y_before_rise
	print("  按上升键 1.25 s：高度 %.2f → %.2f（爬升 %.2f m）" % [
		y_before_rise, y_after_rise, climbed])
	_check(climbed > 1.0,
		"④ 空中变身后**能继续往上飞**（爬升 %.2f m > 1.0）" % climbed)

	# ⑤ 下降也要能用
	var y_before_down := player.global_position.y
	Input.action_press("crouch")
	for _i in 45:
		await physics_frame
	Input.action_release("crouch")
	var dropped := y_before_down - player.global_position.y
	print("  按下降键 0.75 s：下降 %.2f m" % dropped)
	_check(dropped > 0.5, "⑤ 空中也能下降（降了 %.2f m）" % dropped)

	print("\n========== 结果 ==========")
	print("  通过 %d，失败 %d" % [_pass, _fail])
	print("  %s" % ("★ 空中变身可飞" if _fail == 0 else "✗ 有问题"))
	quit(0 if _fail == 0 else 1)
