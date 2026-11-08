extends SceneTree
## 验「巡航者模式 + 能量条」（用户 2026-11-08 那一整套）。
##
## 需求拆条（原话见 `carrier_form.gd` 那段的注释）：
##   T = 巡航者模式（武器关闭 + 飞得更快）
##   飞行累计（含巡航）每 3 km 攒 1 条，最多 5 条
##   R = 启用 1 条，5 秒；攻速倍率 = 1 + 已启用条数（1条×2 / 2条×3 / …）
##   时间**独立**：第一条到点，从 ×4 掉回 ×3
##   启用期间照样能飞、能攒条
##
##   & D:\GAME\godot\Godot_v4.7.1-stable_win64_console.exe --headless --path . \
##       --script res://scripts/_verify_carrier_power.gd

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
	stage.name = "PowerStage"
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
	var cf := player.get_node_or_null("Arisu/CarrierForm") as CarrierForm
	var wpn := player.get_node_or_null("Weapon") as Weapon
	if cf == null or wpn == null:
		push_error("[Power] 缺 CarrierForm / Weapon")
		quit(1)
		return
	_check(cf.set_form(true), "变形成机甲")
	cf.call("_take_off")
	await process_frame
	player.global_position.y = 40.0
	cf.set("_hold_y", 40.0)

	print("")
	print("========== 1. 攒条：飞 3 km 一条 ==========")
	# 直接把进度顶到差一点，再飞一小段跨过去 —— 免得真飞 3 km 等半天
	cf.set("fly_distance_m", 2990.0)
	cf.set("energy_bars", 0)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	var got := 0
	for i in 240:
		if int(cf.get("energy_bars")) > got:
			got = int(cf.get("energy_bars"))
			break
		await physics_frame
	print("       飞行 %.1f m 后 energy_bars = %d" % [float(cf.get("fly_distance_m")), int(cf.get("energy_bars"))])
	_check(got >= 1, "跨过 3000 m 时攒到 1 条（实际 %d）" % int(cf.get("energy_bars")))

	print("")
	print("========== 2. 上限 5 条 ==========")
	cf.set("energy_bars", 5)
	cf.set("fly_distance_m", 2999.0)
	for i in 30:
		await physics_frame
	_check(int(cf.get("energy_bars")) == 5, "满了以后不再涨（还是 %d）" % int(cf.get("energy_bars")))
	_check(float(cf.get("fly_distance_m")) <= 3000.0, "满条后进度不再溢出（%.1f m）" % float(cf.get("fly_distance_m")))
	Input.action_release("move_forward")
	Input.action_release("sprint")

	print("")
	print("========== 3. R 启用一条：攻速 ×2，累加 ==========")
	cf.set("energy_bars", 5)
	cf.set("_bar_timers", [] as Array[float])
	cf.call("_update_power", 0.0)
	_check(absf(float(cf.get("rate_scale")) - 1.0) < 0.001, "没启用时攻速 ×1.0")
	_check(bool(cf.call("use_energy_bar")), "第 1 次按 R 成功启用")
	cf.call("_update_power", 0.0)
	print("       启用 1 条：剩 %d 条，攻速 ×%.1f" % [int(cf.get("energy_bars")), float(cf.get("rate_scale"))])
	_check(int(cf.get("energy_bars")) == 4, "存条 5 → 4")
	_check(absf(float(cf.get("rate_scale")) - 2.0) < 0.001, "攻速变成 ×2")
	cf.call("use_energy_bar")
	cf.call("use_energy_bar")
	cf.call("_update_power", 0.0)
	print("       再启用 2 条：存 %d 条，攻速 ×%.1f" % [int(cf.get("energy_bars")), float(cf.get("rate_scale"))])
	_check(absf(float(cf.get("rate_scale")) - 4.0) < 0.001, "3 条在计时 → 攻速 ×4")

	print("")
	print("========== 4. 时间独立：掉一条只降一档 ==========")
	var timers: Array = cf.get("_bar_timers")
	_check(timers.size() == 3, "确实有 3 条在各自计时")
	# 把第一条掐成 0.01 s，其他两条保持 5 s
	timers[0] = 0.01
	cf.set("_bar_timers", timers)
	cf.call("_update_power", 0.05)
	print("       第一条到期后：%d 条在计时，攻速 ×%.1f" % [
		(cf.get("_bar_timers") as Array).size(), float(cf.get("rate_scale"))])
	_check((cf.get("_bar_timers") as Array).size() == 2, "只剩 2 条（另外两条不受影响）")
	_check(absf(float(cf.get("rate_scale")) - 3.0) < 0.001, "攻速从 ×4 掉到 ×3（不是清零）")

	print("")
	print("========== 5. 攻速真的作用到开火上 ==========")
	wpn.current_ammo = wpn.magazine_size
	wpn.set("_cooldown", 0.0)
	wpn.call("set_rate_scale", 1.0)
	wpn.shoot()
	var cd1 := float(wpn.get("_cooldown"))
	wpn.set("_cooldown", 0.0)
	wpn.call("set_rate_scale", 4.0)
	wpn.shoot()
	var cd4 := float(wpn.get("_cooldown"))
	print("       间隔：×1 = %.4f s   ×4 = %.4f s（基础 %.2f）" % [cd1, cd4, float(wpn.beam_fire_interval)])
	_check(cd1 > cd4 * 3.5, "×4 的冷却明显更短（%.4f vs %.4f）" % [cd1, cd4])

	print("")
	print("========== 6. 巡航者模式：关武器 + 飞更快 ==========")
	cf.call("set_cruise", true)
	await process_frame
	_check(bool(cf.get("cruise")), "巡航者模式已开")
	_check(bool(wpn.get("disabled")), "武器被关闭")
	wpn.set("_cooldown", 0.0)
	_check(not wpn.shoot(), "巡航者模式下扣扳机打不出子弹")
	_check(absf(float(player.get("_fly_scale")) - 1.6) < 0.001, "玩家的飞行速度倍率 = 1.6")
	# 巡航期间照样攒条
	cf.set("energy_bars", 0)
	cf.set("fly_distance_m", 2995.0)
	Input.action_press("move_forward")
	for i in 60:
		await physics_frame
	print("       巡航中飞行进度 %.1f m，存条 %d" % [
		float(cf.get("fly_distance_m")), int(cf.get("energy_bars"))])
	_check(int(cf.get("energy_bars")) >= 1, "巡航期间照样能攒条")
	Input.action_release("move_forward")

	print("")
	print("========== 7. 变回本体要把巡航清干净 ==========")
	cf.set_form(false)
	await process_frame
	_check(not bool(cf.get("cruise")), "巡航者模式被关掉")
	_check(absf(float(player.get("_fly_scale")) - 1.0) < 0.001, "玩家飞行倍率回到 1.0")
	_check(not bool(wpn.get("disabled")), "武器重新可用（本体能开枪）")

	MechState.set_carrier_for_test(false)
	print("")
	print("========== 结果 ==========")
	if _fail == 0:
		print("全部 %d 项通过" % _pass)
	else:
		print("%d 项通过，%d 项失败" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
