extends SceneTree
## 验证霸王龙优香攻击预警与实际伤害，玩家离开扇形应可躲避。

var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(24)
	var player := game.get_node("Player") as Player
	var boss := game.get_node("Boss") as Node
	_check(boss.has_method("_attack"), "霸王龙节点使用主动攻击脚本")
	# 飞猪这一轮也换成会攻击的了（pig_boss.gd）。这里只确认两只走的是**同一套基类**；
	# 它们的参数差异（圈/冷却/伤害都不一样）在 _verify_boss_pig.gd §6 里验。
	_check((game.get_node("BossPig") as Boss) is BossAttacker,
		"飞猪也走 BossAttacker 基类（不再是纯木桩）")
	_check(player.max_health == 100.0 and player.health == player.max_health, "玩家初始化为100点生命")

	# 关掉自动攻击：本套件手动 call _attack()，否则 _process 会自己插一脚，
	# 断言就变成看运气了。
	boss.set_process(false)
	player.set_physics_process(false)     # 冻住摩擦，击退才量得准

	var attackable := boss as Boss
	var reach := float(boss.get("attack_reach"))
	var radius := float(boss.get("attack_radius"))

	# ① 站在预警圈圆心 —— 必中。
	player.global_position = attackable.global_position + attackable.facing() * reach
	player.health = player.max_health
	player.velocity = Vector3.ZERO
	boss.set("windup_time", 0.12)
	boss.set("_attack_cooldown", 0.0)
	boss.call("_attack", player)
	_check((boss.get_node("AttackTelegraph") as MeshInstance3D).visible, "攻击蓄力阶段显示预警圈")
	await create_timer(0.3).timeout
	_check(player.health < player.max_health, "站在预警圈内受到攻击伤害")
	_check(player.velocity.length() > 0.1, "命中时产生击退")
	_check(not (boss.get_node("AttackTelegraph") as MeshInstance3D).visible, "攻击结算后隐藏预警圈")

	# ② 站在圈外一点点，但仍在 attack_range(18 m) 内 —— 必须不掉血。
	#    这条是本轮修的核心：以前判定用的是 attack_range，于是「圈在骗人」。
	player.health = player.max_health
	player.velocity = Vector3.ZERO
	player.global_position = attackable.global_position \
		+ attackable.facing() * (reach + radius + 1.5)
	boss.set("_attack_cooldown", 0.0)
	boss.call("_attack", player)
	await create_timer(0.3).timeout
	_check(is_equal_approx(player.health, player.max_health),
		"站在预警圈外（但在 18 m 发现范围内）不掉血")

	# ③ 背后更远，同样应躲开。
	player.health = player.max_health
	player.velocity = Vector3.ZERO
	player.global_position = attackable.global_position - attackable.facing() * reach
	boss.set("_attack_cooldown", 0.0)
	boss.call("_attack", player)
	await create_timer(0.3).timeout
	_check(is_equal_approx(player.health, player.max_health), "站在霸王龙背后躲开攻击")
	print("[verify_trex_attack] %d FAIL" % _fail)
	quit(1 if _fail > 0 else 0)


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _check(ok: bool, label: String) -> void:
	print("  [%s] %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_fail += 1
