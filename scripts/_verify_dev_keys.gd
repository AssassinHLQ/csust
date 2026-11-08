extends SceneTree
## 验开发者快捷键 + 巡航者加速（用户 2026-11-08）。
##
##   F3 → 开发者模式开关（帧率面板归 `game.gd`，本自检只管开关本身）
##   F4 → 下一场景（**只在开发者模式打开后生效**）
##   F5 → 秒杀 `bosses` 分组里的敌人
##   F6 → 角色速度 ×3 / 恢复
##   巡航者倍率 1.6 → 2.6（用户：「巡航者太慢了」）
##
##   & D:\GAME\godot\Godot_v4.7.1-stable_win64_console.exe --headless --path . \
##       --script res://scripts/_verify_dev_keys.gd

const PlayerScene := preload("res://scenes/player.tscn")
const MechState := preload("res://scripts/mech_state.gd")
const CarrierForm := preload("res://scripts/carrier_form.gd")
const DevMode := preload("res://scripts/dev_mode.gd")

var _pass := 0
var _fail := 0


## 假的 Boss：只记「吃了多少伤害」。
class FakeBoss extends StaticBody3D:
	var dmg := 0.0
	func take_damage(amount: float, _p := Vector3.ZERO, _d := Vector3.ZERO) -> void:
		dmg += amount


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
	DevMode.set_on(false)

	var stage := Node3D.new()
	stage.name = "DevStage"
	root.add_child(stage)
	var floor_body := StaticBody3D.new()
	var fm := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	fm.mesh = plane
	floor_body.add_child(fm)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 0.4, 400)
	col.shape = box
	col.position.y = -0.2
	floor_body.add_child(col)
	stage.add_child(floor_body)

	var player := PlayerScene.instantiate() as Player
	stage.add_child(player)
	await process_frame
	await process_frame

	print("")
	print("========== 1. 开发者模式默认关，F4/F5/F6 不该生效 ==========")
	_check(not DevMode.is_on(), "默认是关的")
	_check(not bool(player.call("_dev_key", KEY_F4)), "F4 在关着时不被吃掉")
	_check(not bool(player.call("_dev_key", KEY_F5)), "F5 在关着时不被吃掉")
	_check(not bool(player.call("_dev_key", KEY_F6)), "F6 在关着时不被吃掉")

	print("")
	print("========== 2. F3 开开发者模式 ==========")
	_check(bool(player.call("_dev_key", KEY_F3)), "F3 被吃掉（面板归 game.gd，这里只切开关）")
	_check(DevMode.is_on(), "开发者模式已开")
	_check(float(player.get("_dev_speed_scale")) == 1.0, "刚开时倍速还是 1.0（要按 F6 才变）")

	print("")
	print("========== 3. F6 三倍速，真的作用到移动上 ==========")
	# 先量一遍正常速度
	player.global_position = Vector3(0, 0.6, 0)
	Input.action_press("move_forward")
	for i in 60:
		await physics_frame
	var v1 := Vector2(player.velocity.x, player.velocity.z).length()
	_check(bool(player.call("_dev_key", KEY_F6)), "F6 被吃掉")
	_check(absf(float(player.get("_dev_speed_scale")) - 3.0) < 0.001, "倍速变成 ×3")
	for i in 90:
		await physics_frame
	var v3 := Vector2(player.velocity.x, player.velocity.z).length()
	print("       移动速度：×1 = %.2f m/s   ×3 = %.2f m/s" % [v1, v3])
	_check(v3 > v1 * 2.5, "三倍速真的更快（%.2f → %.2f）" % [v1, v3])
	# 再按一次恢复
	player.call("_dev_key", KEY_F6)
	_check(absf(float(player.get("_dev_speed_scale")) - 1.0) < 0.001, "再按 F6 恢复 ×1")
	Input.action_release("move_forward")

	print("")
	print("========== 4. F5 秒杀 bosses 分组 ==========")
	var b1 := FakeBoss.new()
	var b2 := FakeBoss.new()
	b1.add_to_group("bosses")
	b2.add_to_group("bosses")
	stage.add_child(b1)
	stage.add_child(b2)
	_check(bool(player.call("_dev_key", KEY_F5)), "F5 被吃掉")
	print("       两个假 Boss 各吃了 %.0f 伤害" % b1.dmg)
	_check(b1.dmg >= 1.0e9 and b2.dmg >= 1.0e9, "场上敌人都被结算了致命伤害")

	print("")
	print("========== 5. 巡航者倍率 1.6 → 2.6 ==========")
	var cf := player.get_node_or_null("Arisu/CarrierForm") as CarrierForm
	if cf == null:
		_check(false, "拿得到 CarrierForm")
		_done()
		return
	_check(cf.set_form(true), "变形成机甲")
	cf.call("_take_off")
	await process_frame
	player.global_position.y = 40.0
	cf.set("_hold_y", 40.0)
	Input.action_press("move_forward")
	# 先量普通飞行速度
	for i in 90:
		await physics_frame
	var fly_normal := Vector2(player.velocity.x, player.velocity.z).length()
	cf.call("set_cruise", true)
	_check(absf(float(player.get("_fly_scale")) - 2.6) < 0.001,
		"巡航倍率 = 2.6（实际 %.2f）" % float(player.get("_fly_scale")))
	for i in 120:
		await physics_frame
	var fly_cruise := Vector2(player.velocity.x, player.velocity.z).length()
	print("       飞行速度：普通 %.2f m/s   巡航 %.2f m/s（×%.2f）" % [
		fly_normal, fly_cruise, fly_cruise / maxf(fly_normal, 0.01)])
	_check(fly_cruise > fly_normal * 2.0, "巡航明显更快（%.2f → %.2f）" % [fly_normal, fly_cruise])
	Input.action_release("move_forward")

	DevMode.set_on(false)
	MechState.set_carrier_for_test(false)
	_done()


func _done() -> void:
	print("")
	print("========== 结果 ==========")
	if _fail == 0:
		print("全部 %d 项通过" % _pass)
	else:
		print("%d 项通过，%d 项失败" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
