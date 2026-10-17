extends SceneTree
## 验「7 名同伴会帮着开火打靶子 / Boss」。
##
## ⚠️ 为什么每条都要「先把同伴排队 + 冻住跟随」再测：
##    同伴平时一直在走位和转身（`companion.gd` 的 `_physics_process`）。
##    不冻住的话，「有没有开火」就混进了「有没有走到位 / 转过身」，
##    断言会变成看运气而不是看功能。这里只测**枪**本身。
##
## 用法：godot --path <工程> --script res://scripts/_verify_companion_attack.gd -- --splat=off

var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(30)

	var player: Player = game.get_node("Player")
	var target: Target = game.get_node("Target1")
	var trex: Boss = game.get_node("Boss")
	var pig: Boss = game.get_node("BossPig")

	# 两位 Boss 现在都会主动打玩家（§7.5）。这里必须关掉——
	# 否则「玩家没被同伴误伤」那条会被 Boss 的伤害污染成假红。
	(trex as Node).set_process(false)
	(pig as Node).set_process(false)

	var companions: Array[Companion] = []
	var guns: Array[CompanionGun] = []
	for child in game.get_children():
		if child is Companion:
			companions.append(child as Companion)
			var gun := (child as Companion).get_node_or_null("Gun") as CompanionGun
			if gun != null:
				guns.append(gun)

	print("========== 1. 每名同伴都挂了枪 ==========")
	print("  同伴 %d 名，挂枪 %d 名" % [companions.size(), guns.size()])
	_check(companions.size() == 7, "场上 7 名同伴（实测 %d）" % companions.size())
	_check(guns.size() == companions.size(),
		"每名同伴都挂了 CompanionGun（实测 %d 把）" % guns.size())
	_check(not guns.is_empty() and guns[0].enabled, "枪默认开启（enabled = true）")
	if guns.is_empty() or companions.is_empty():
		print("\n没枪可测，后面没法验")
		_quit()
		return

	# 靶子血量临时拉高：7 名同伴一轮齐射就能把 100 血的靶子打死，
	# 一死就进 4 秒重生，反而测不到「被打掉血」。
	target.max_health = 5000.0
	target.health = 5000.0

	print("\n========== 2. 面朝靶子时会开火、并打掉血 ==========")
	_line_up(companions, target.global_position + Vector3(0, 0, 4.0), PI)
	await _wait_seconds(0.5)
	var shots0 := _total_shots(guns)
	var hp0 := target.health
	await _wait_seconds(3.5)
	var shots1 := _total_shots(guns)
	print("  3.5 s 内开火 %d 次   Target1 血量 %.0f → %.0f" % [
		shots1 - shots0, hp0, target.health])
	_check(shots1 > shots0, "同伴确实开了火（%d 次）" % (shots1 - shots0))
	_check(target.health < hp0, "靶子被打掉血（%.0f → %.0f）" % [hp0, target.health])
	_check(is_equal_approx(player.health, player.max_health),
		"玩家没被误伤（HP %.0f / %.0f）" % [player.health, player.max_health])

	print("\n========== 3. 目标在背后时不开火 ==========")
	# 位置不动，只把同伴转 180°：靶子落到背后，就不该再开火。
	# 这条守的是 `companion_gun.gd` 文件头第 3 条（不为开火乱转身）。
	#
	# ⚠️ 第四、第五位 Boss（霍德 / 佩洛洛斯拉）摆在场地的 **+Z 那半边**，
	#    正好落在这排同伴「背对靶子」时的**正前方** —— 它们会合法开火，
	#    于是这条断言变成假红（实测多出 7 发）。所以先临时把 Boss 全体
	#    移出 `bosses` 组（§5 之前再放回去），让这一节只剩「有没有靶子在前面」。
	var all_bosses: Array[Boss] = []
	for ch in game.get_children():
		if ch is Boss:
			all_bosses.append(ch as Boss)
	for b in all_bosses:
		b.remove_from_group("bosses")
	# ⚠️ 光摘组不够：`companion_gun.gd` 的 `_collect_targets()` **只跑一次**并把
	#    结果缓存进 `_targets`（第 78 行），摘组之后它照样对着缓存里的 Boss 打。
	#    实测：不重扫的话这条会多出 7 发。所以这里手动重扫一次。
	for g in guns:
		g.call("_collect_targets")
	await _wait(2)
	_line_up(companions, target.global_position + Vector3(0, 0, 4.0), 0.0)
	await _wait_seconds(0.5)
	var shots2 := _total_shots(guns)
	await _wait_seconds(3.0)
	var shots3 := _total_shots(guns)
	_check(shots3 == shots2, "靶子在背后时完全停火（%d → %d）" % [shots2, shots3])

	print("\n========== 4. 不隔墙打 ==========")
	# 守 `companion_gun.gd` 文件头第 2 条：扣血以**射线真正命中的目标**为准，
	# 中间插一堵墙就该彻底停火。
	_line_up(companions, target.global_position + Vector3(0, 0, 4.0), PI)
	var wall := _make_wall(game, target.global_position + Vector3(0, 1.0, 2.0))
	await _wait_seconds(1.0)
	var shots4 := _total_shots(guns)
	await _wait_seconds(3.0)
	var shots5 := _total_shots(guns)
	_check(shots5 == shots4, "同伴与靶子之间有墙时不开火（%d → %d）" % [shots4, shots5])
	wall.queue_free()
	await _wait(2)

	print("\n========== 5. 也会去打 Boss ==========")
	# 把 §3 临时摘掉的 `bosses` 组放回去，否则同伴找不到 Boss 可打
	for b in all_bosses:
		b.add_to_group("bosses")
	for g in guns:
		g.call("_collect_targets")     # 同上：缓存不重扫就看不见放回去的 Boss
	await _wait(2)
	_line_up(companions, trex.global_position - Vector3(6.0, 0, 0), PI * 0.5)
	await _wait_seconds(0.5)
	var trex_hp0 := trex.health
	await _wait_seconds(4.0)
	print("  霸王龙血量 %.0f → %.0f" % [trex_hp0, trex.health])
	_check(trex.health < trex_hp0, "同伴会打霸王龙（%.0f → %.0f）" % [trex_hp0, trex.health])

	print("\n========== 6. 关掉 enabled 就完全停火 ==========")
	for g in guns:
		g.enabled = false
	await _wait_seconds(0.5)
	var shots6 := _total_shots(guns)
	await _wait_seconds(2.5)
	var shots7 := _total_shots(guns)
	_check(shots7 == shots6, "enabled = false 后不再开火（%d → %d）" % [shots6, shots7])

	print("\n================ 结果 ================")
	_quit()


## 把同伴排成一行、统一朝向，并**冻住跟随逻辑**：这样测的只有枪（见文件头）。
## 横向间隔取 0.5 m 是算过的：7 人共 3 m 宽，距目标 4 m 时最边上那位偏
## atan(1.5 / 4) ≈ 21°，仍在 `aim_half_angle_degrees`(25°) 之内 ——
## 间隔再大就会出现「边上那两位打不到」的假红。
func _line_up(companions: Array[Companion], center: Vector3, face_yaw: float) -> void:
	for i in companions.size():
		var c: Companion = companions[i]
		c.set_physics_process(false)
		c.velocity = Vector3.ZERO
		c.global_position = Vector3(center.x + (float(i) - 3.0) * 0.5, 0.05, center.z)
		c.rotation.y = face_yaw


## 临时在同伴与目标之间立一堵墙（世界层 1，和场景里的墙同一层）
func _make_wall(game: Node, at: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 5.0, 0.4)
	cs.shape = box
	wall.add_child(cs)
	game.add_child(wall)
	wall.global_position = at
	return wall


func _total_shots(guns: Array[CompanionGun]) -> int:
	var n := 0
	for g in guns:
		n += g.shot_count()
	return n


func _check(cond: bool, label: String) -> void:
	print("  [%s] %s" % ["PASS" if cond else "FAIL", label])
	if not cond:
		_fail += 1


func _quit() -> void:
	print("失败 %d 项" % _fail)
	quit(1 if _fail > 0 else 0)


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame


## 按真实时间等（帧率不可控，「等 N 帧」等不出确定的秒数）
func _wait_seconds(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await process_frame
