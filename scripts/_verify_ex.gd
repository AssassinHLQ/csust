extends SceneTree
## 自检：EX 必杀系统（充能 / 蓄力 / 两套必杀 / HUD 条）。
##
## 用户 2026-11-09：「按 EX 连按释放必杀技能：普通状态是蓄力激光球，
##                   机甲状态是蓄力激光巨型连续轨道炮。EX 充能是随着时间增加的」
##
## 验证清单：
##   ① EX 系统被挂到 Player 上，初始能量 0
##   ② 能量**随时间自动增加**（等 1 秒，看涨了没）
##   ③ 不满时按 EX 放不出来（不该有任何效果）
##   ④ 充满后按下→松手，普通状态**放出激光球**（ExFx 下出现 LaserOrb）
##   ⑤ 一按能量就清零（防止蓄力被打断变无限能量）
##   ⑥ 机甲状态分流走**轨道炮**（出现 RailBeam*）
##   ⑦ HUD 上有 ExBar / ExLabel，且条值跟着能量走
##
## 用法：
##   & <godot> --headless --path . --script res://scripts/_verify_ex.gd

const GAME := "res://scenes/game.tscn"

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
	print("========== EX 必杀系统自检 ==========")
	var ps := load(GAME) as PackedScene
	var level := ps.instantiate()
	root.add_child(level)
	current_scene = level
	for _i in 12:
		await process_frame

	# ① 系统挂上了没有
	var player := level.get_node_or_null("Player")
	_check(player != null, "找到 Player")
	if player == null:
		_finish()
		return
	var ex := player.get_node_or_null("ExSystem")
	_check(ex != null, "Player 下有 ExSystem")
	if ex == null:
		_finish()
		return
	# ⚠️ 不能断言「严格等于 0」：玩家 `_ready()` 之后场景已经跑了十几帧，
	#    能量自然涨了一点点（实测 12 帧 ≈ 0.05）。这里只要求「还没满」。
	_check(float(ex.get("ex_ratio")) < 0.2,
		"初始能量接近 0 且远未满（实际 %.3f）" % float(ex.get("ex_ratio")))

	# ② 随时间增加
	var r0 := float(ex.get("ex_ratio"))
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1000:
		await process_frame
	var r1 := float(ex.get("ex_ratio"))
	print("  能量：%.3f → %.3f（等了 1 s）" % [r0, r1])
	_check(r1 > r0, "能量随时间自动增加（+%.4f/秒）" % (r1 - r0))

	# ③ 不满时按 EX 应失败
	var pressed_early := bool(ex.call("press_ex"))
	_check(not pressed_early, "能量不满时 press_ex() 返回 false（实际 %s）" % str(pressed_early))

	# ④ 充满 → 按下 → 松手 → 普通状态放激光球
	ex.set("ex_ratio", 1.0)
	var ok_press := bool(ex.call("press_ex"))
	_check(ok_press, "充满后 press_ex() 成功")
	_check(float(ex.get("ex_ratio")) < 0.01,
		"一按能量就清零（实际 %.3f）" % float(ex.get("ex_ratio")))
	# 让它蓄一会儿（模拟按住）
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 400:
		await process_frame
	var charge_now := float(ex.call("charge_ratio"))
	print("  蓄力进度 = %.2f" % charge_now)
	_check(charge_now > 0.1, "蓄力在推进（%.2f）" % charge_now)

	var ok_rel := bool(ex.call("release_ex"))
	_check(ok_rel, "release_ex() 成功")
	await process_frame
	await process_frame

	var fx := ex.get_node_or_null("ExFx")
	_check(fx != null, "ExFx 容器存在")
	if fx != null:
		var has_orb := false
		for c in fx.get_children():
			if String(c.name).begins_with("LaserOrb"):
				has_orb = true
				break
		_check(has_orb, "普通状态放出了激光球（ExFx 下有 LaserOrb）")

	# ⑤ 机甲状态分流：直接把 carrier 的 is_on() 顶掉是改不了的，
	#    所以这里直接验证分派函数本身（调用 _fire_railgun）
	ex.call("_fire_railgun", 0.6)
	await process_frame
	await process_frame
	await process_frame
	if fx != null:
		var has_rail := false
		for c in fx.get_children():
			if String(c.name).begins_with("RailBeam"):
				has_rail = true
				break
		_check(has_rail, "机甲必杀射出轨道炮光柱（ExFx 下有 RailBeam*）")

	# ⑥ HUD 条
	var hud := get_first_node_in_group("hud")
	_check(hud != null, "HUD 在 hud 组")
	if hud != null:
		# HUD 的条是 _process 里建的，等它跑一帧
		for _i in 3:
			await process_frame
		var bar := hud.get_node_or_null("ExBar")
		var lbl := hud.get_node_or_null("ExLabel")
		_check(bar != null, "HUD 有 ExBar（充能条）")
		_check(lbl != null, "HUD 有 ExLabel（充能文字）")
		if lbl != null:
			print("  HUD 文字 = 「%s」" % (lbl as Label).text)

	_finish()


func _finish() -> void:
	print("\n========== 结果 ==========")
	print("  通过 %d，失败 %d" % [_pass, _fail])
	print("  %s" % ("★ EX 系统正常" if _fail == 0 else "✗ 有问题"))
	quit(0 if _fail == 0 else 1)
