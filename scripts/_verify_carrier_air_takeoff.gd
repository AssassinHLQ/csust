extends SceneTree
## 验证：爱丽丝机甲**高空掉落时仍能起飞**（用户 2026-11-11）。
##
## 用户原话：「爱丽丝机甲空中还是不能起飞为什么,之前修好了变身后默认飞行状态
##            还不够,要爱丽丝机甲高空掉落仍然起飞」
##
## 上一轮只修了「**空中变身**那一下直接进飞行态」——那只覆盖「在飞行态之间切换」。
## 从地面走出去/掉下平台时从没进过飞行态，而原来起飞要求
##     grounded_grace = on_floor or (now − _air_since) <= 110ms
## 高空里两项都 false ⇒ 永远起飞不了，`_apply_flight()` 也不跑 ⇒ 纯自由落体。
## 已改为「不在飞行态 + 这次按下没消费」就起飞。
##
## 本探针只验**用户关心的行为**，不纠结中间态：
##   A. 站在地面按 → 起飞并爬升（回归）
##   B. 悬在 60 m 高空、**带下落速度**、且不在飞行态 → 按上升键后
##      · 进入飞行态
##      · 高度**由下降转为上升**
##   C. 掉落中途按 → 同上
##
##   & <godot> --headless --path . --script res://scripts/_verify_carrier_air_takeoff.gd

const PlayerScene := preload("res://scenes/player.tscn")
const MechState := preload("res://scripts/mech_state.gd")

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String, detail := "") -> void:
	if ok:
		_pass += 1
		print("  [PASS] %s%s" % [what, ("  " + detail) if detail != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s%s" % [what, ("  " + detail) if detail != "" else ""])


## 按一次上升键，保持 N 帧，返回期间的高度变化
func _press_rise(frames: int, player: Player) -> float:
	var y0 := player.global_position.y
	Input.action_press("jump")
	for _i in frames:
		await process_frame
	Input.action_release("jump")
	for _i in 3:
		await process_frame
	return player.global_position.y - y0


func _run() -> void:
	print("========== 机甲高空掉落能否起飞 ==========")
	MechState.set_carrier_for_test(true)

	var world := Node3D.new()
	root.add_child(world)
	var body := StaticBody3D.new()
	body.position = Vector3(0, -0.5, 0)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	col.shape = box
	body.add_child(col)
	world.add_child(body)

	var player := PlayerScene.instantiate() as Player
	world.add_child(player)
	player.global_position = Vector3(0, 0.2, 0)
	for _i in 15:
		await process_frame
	var cf = player.get_node_or_null("Arisu/CarrierForm")
	if cf == null or not cf.call("set_form", true):
		push_error("[air] 变形失败")
		quit(1)
		return
	for _i in 20:
		await process_frame

	# ---------- A. 地面起飞（回归） ----------
	print("[A] 站在地面按上升键")
	_check(not bool(cf.get("_airborne")), "变形后站在地上")
	var dy_a: float = await _press_rise(30, player)
	_check(bool(cf.get("_airborne")), "进入飞行态")
	_check(dy_a > 1.0, "爬升了 %.2f m" % dy_a)

	# ---------- B. 60 m 高空 + 下落速度 + 不在飞行态 ----------
	print("[B] 悬在 60 m、带 −8 m/s 下落速度、不在飞行态 → 按上升键")
	# 手工退出飞行态（模拟「从平台边缘走出去」那一刻的状态）
	cf.set("_airborne", false)
	cf.set("_hold_y", -9000.0)
	if player.has_method("set_flight_lock"):
		player.call("set_flight_lock", false)
	player.global_position = Vector3(60, 60, 0)
	player.set("velocity", Vector3(0, -8, 0))
	for _i in 4:
		await process_frame
	print("     按键前：_airborne=%s  vy=%.2f  y=%.2f" % [
		str(cf.get("_airborne")), (player.get("velocity") as Vector3).y,
		player.global_position.y])
	var vy_b := (player.get("velocity") as Vector3).y
	_check(vy_b < -2.0, "（前置）确实带下落速度", "vy=%.2f" % vy_b)

	var dy_b: float = await _press_rise(45, player)
	print("     按键后：_airborne=%s  y=%.2f" % [
		str(cf.get("_airborne")), player.global_position.y])
	_check(bool(cf.get("_airborne")), "**进入飞行态**")
	_check(dy_b > 1.0, "**高度转为上升**（%+.2f m）" % dy_b)

	# ---------- C. 掉落中途按 ----------
	print("[C] 从 80 m 自由落体 0.8 s 后按上升键")
	cf.set("_airborne", false)
	cf.set("_hold_y", -9000.0)
	if player.has_method("set_flight_lock"):
		player.call("set_flight_lock", false)
	player.global_position = Vector3(60, 80, 0)
	player.set("velocity", Vector3(0, 0, 0))
	for _i in 48:
		await process_frame
	var vy_c := (player.get("velocity") as Vector3).y
	var y_c := player.global_position.y
	print("     按键前：vy=%.2f  y=%.2f（已下落 %.1f m）" % [vy_c, y_c, 80.0 - y_c])
	var dy_c: float = await _press_rise(90, player)
	print("     按键后：_airborne=%s  y=%.2f" % [
		str(cf.get("_airborne")), player.global_position.y])
	_check(bool(cf.get("_airborne")), "**进入飞行态**")
	_check(dy_c > 1.0, "**高度转为上升**（%+.2f m）" % dy_c)

	print()
	print("========== 结果 ==========")
	print("  通过 %d，失败 %d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
