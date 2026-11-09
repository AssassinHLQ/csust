extends SceneTree
## 验「机甲飞行的水平手感」。
##
## 用户 2026-11-08 两条反馈，根子是同一个：
##   「打得到霸王龙，但是人飞不过去」
##   「我不能同时加速前进与下降」
##
## 修法是 `player.gd` 里加了 `_flight_lock` 专属的三件套：
##   · `crouching` 在飞行时恒为 false（`Ctrl` 只当「下降」，不再压成蹲速）
##   · 目标速度换成 `SPEED_FLY = 11` / `SPEED_FLY_BOOST = 19`
##   · 加速度 `ACCEL_FLY = 26`、摩擦 `FRICTION_FLY = 12`
##
## 这条自检把「手感」量成数字：巡航速度、加力速度、蹲键不再拖慢、
## 以及「Shift + Ctrl 同时按」时水平速度**不掉**。
##
##   & D:\GAME\godot\Godot_v4.7.1-stable_win64_console.exe --headless --path . \
##       --script res://scripts/_probe_carrier_handling.gd -- --no-capture

const PlayerScene := preload("res://scenes/player.tscn")
const MechState := preload("res://scripts/mech_state.gd")
const CarrierForm := preload("res://scripts/carrier_form.gd")

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
	stage.name = "HandlingStage"
	root.add_child(stage)

	# 一块地板（起飞后我们会把人抬到空中，地板只用来验「地面手感没被改坏」）
	var floor_body := StaticBody3D.new()
	var fm := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	fm.mesh = plane
	floor_body.add_child(fm)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 0.4, 80)
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
		push_error("[Handling] 没有 CarrierForm")
		quit(1)
		return
	_check(cf.set_form(true), "变形成功")
	_check(player.is_flight_locked() == false, "变形但还没起飞时没接管垂直方向")

	# ── 起飞并抬到 40 m 高空（离地板远一点，避免落地判定干扰）──
	cf.call("_take_off")
	await process_frame
	player.global_position.y = 40.0
	cf.set("_hold_y", 40.0)
	player.set("velocity", Vector3.ZERO)
	await process_frame
	_check(bool(cf.call("is_flying")), "已经进入飞行态")
	_check(player.is_flight_locked(), "飞行中垂直方向由机甲接管")

	print("")
	print("========== 1. 巡航 / 加力 ==========")
	Input.action_press("move_forward")
	var v_cruise := await _settle_speed(player, cf, 90)
	print("       巡航水平速度 %.2f m/s" % v_cruise)
	_check(v_cruise >= 10.0, "飞行巡航够快（%.2f ≥ 10.0 m/s）" % v_cruise)

	Input.action_press("sprint")
	var v_boost := await _settle_speed(player, cf, 90)
	print("       加力水平速度 %.2f m/s" % v_boost)
	_check(v_boost >= 17.0, "Shift 加力够快（%.2f ≥ 17.0 m/s）" % v_boost)
	_check(player.sprinting, "飞行时按 Shift 真的进入 sprint 状态")

	# 第二关的三只龙离出生点 137 / 168 / 197 m —— 加力下要几秒？
	var far := 137.4
	var secs := far / maxf(v_boost, 0.01)
	print("       飞完 137.4 m 需要 %.1f 秒（加力）" % secs)
	_check(secs <= 9.0, "飞到第一只霸王龙不超过 9 秒（%.1f s）" % secs)

	print("")
	print("========== 2. 同时加速 + 下降 ==========")
	# 这是用户那条「我不能同时加速前进与下降」的原样复现
	Input.action_press("crouch")
	var v_both := await _settle_speed(player, cf, 60)
	var vy: float = player.velocity.y
	print("       Shift + Ctrl 同时按：水平 %.2f m/s，垂直 %.2f m/s" % [v_both, vy])
	_check(not player.crouching, "飞行时 Ctrl 不再被当成「蹲」（crouching = false）")
	_check(player.sprinting, "飞行时按住 Ctrl 也不掐掉冲刺")
	_check(v_both >= 17.0, "边加速边下降时水平速度不掉（%.2f ≥ 17.0 m/s）" % v_both)
	_check(vy <= -3.0, "Ctrl 真的在下降（vy = %.2f m/s）" % vy)
	_check(int(cf.get("_vert_want")) == -1, "机甲的垂直意图是「下降」")
	Input.action_release("crouch")

	# ── 松开冲刺，退回巡航 ──
	Input.action_release("sprint")
	var v_back := await _settle_speed(player, cf, 90)
	print("       松开 Shift 后 %.2f m/s" % v_back)
	_check(v_back >= 10.0 and v_back <= 13.0, "松开 Shift 回到巡航速（%.2f）" % v_back)

	Input.action_release("move_forward")
	var v_stop := await _settle_speed(player, cf, 90)
	print("       松开方向键后 %.2f m/s" % v_stop)
	_check(v_stop < 1.0, "松开方向键会停下来（%.2f m/s）" % v_stop)

	print("")
	print("========== 3. 机甲形态**在地面**也要用飞行速度 ==========")
	# 用户 2026-11-09：「在地上怎么飞这么慢，不应该也是飞吗，为什么不和天上一个速度」
	# 病根：落地时 `_apply_flight()` 末会调 `_land()` → `set_flight_lock(false)`，
	# 于是速度从 SPEED_FLY 11 掉回 SPEED_WALK 2.4（慢 4.6 倍）。
	# 修法：`player.gd` 的速度判据改成 `_flight_lock or _carrier_on`。
	# ── 先真的落地：清掉飞行锁，**保持机甲形态** ──
	cf.call("_land")
	player.global_position = Vector3(0, 0.6, 0)
	player.set("velocity", Vector3.ZERO)
	for i in 30:
		await physics_frame
	_check(not player.is_flight_locked(), "落地后飞行锁已清（垂直方向交还 player）")
	_check(player.is_carrier_form(), "但**仍然是机甲形态**（carrier_form 为真）")

	Input.action_press("move_forward")
	for i in 90:
		await physics_frame
	var v_ground := Vector2(player.velocity.x, player.velocity.z).length()
	print("       机甲**站在地上**走：%.2f m/s" % v_ground)
	_check(v_ground >= 10.0,
		"地上也是飞行巡航速，不再是步兵 2.4（%.2f ≥ 10.0 m/s）" % v_ground)

	Input.action_press("sprint")
	for i in 90:
		await physics_frame
	var v_ground_boost := Vector2(player.velocity.x, player.velocity.z).length()
	print("       机甲站在地上按 Shift：%.2f m/s" % v_ground_boost)
	_check(v_ground_boost >= 17.0,
		"地上加力也到飞行档（%.2f ≥ 17.0 m/s）" % v_ground_boost)
	Input.action_release("sprint")

	# 机甲形态下 Ctrl 不该被当成蹲（它落地了也不蹲）
	Input.action_press("crouch")
	for i in 45:
		await physics_frame
	print("       机甲站在地上按 Ctrl：crouching=%s 速度 %.2f m/s" % [
		str(player.crouching), Vector2(player.velocity.x, player.velocity.z).length()])
	_check(not player.crouching, "机甲形态下 Ctrl 不触发「蹲」")
	Input.action_release("crouch")
	Input.action_release("move_forward")

	print("")
	print("========== 4. 变回本体后地面手感没被改坏 ==========")
	# 变回本体、落地，按 Ctrl 仍然应该走蹲速
	cf.set_form(false)
	await process_frame
	player.global_position = Vector3(0, 0.6, 0)
	player.set("velocity", Vector3.ZERO)
	for i in 20:
		await physics_frame
	_check(not player.is_flight_locked(), "变回本体后垂直方向交还给 player")
	_check(not player.is_carrier_form(), "变回本体后 carrier_form 也清掉了")
	Input.action_press("move_forward")
	Input.action_press("crouch")
	for i in 60:
		await physics_frame
	var v_crouch := Vector2(player.velocity.x, player.velocity.z).length()
	print("       地面上蹲行速度 %.2f m/s" % v_crouch)
	_check(player.crouching, "地面上 Ctrl 仍然是「蹲」")
	_check(v_crouch <= 2.0, "地面蹲行速度仍是 SPEED_CROUCH 那一档（%.2f ≤ 2.0）" % v_crouch)
	Input.action_release("crouch")
	Input.action_release("move_forward")

	MechState.set_carrier_for_test(false)
	print("")
	print("========== 结果 ==========")
	if _fail == 0:
		print("全部 %d 项通过" % _pass)
	else:
		print("%d 项通过，%d 项失败" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


## 跑若干帧，返回稳定的水平速度。
func _settle_speed(player: Player, cf: CarrierForm, frames: int) -> float:
	for i in frames:
		await physics_frame
	# 把机甲抬在空中别掉下去（`_apply_flight` 会把它往 −HOVER_SINK 拉）
	cf.set("_hold_y", player.global_position.y)
	return Vector2(player.velocity.x, player.velocity.z).length()
