extends SceneTree
## 验：黑市七块板是固定 +1%（不再是扣 0.8%）；霍德四个技能都在、没有激光。
##   godot --path . --headless --script res://scripts/_verify_dark_market.gd
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var lvl := (load("res://scenes/parkour.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(lvl)
	for _i in 30:
		await physics_frame
	var fut := lvl.get_node_or_null("Futures")
	var quotes: Array = fut.get("quotes")

	# ① 七块 DK 的价牌都是 +1.00%
	var dk: Array = []
	for q in quotes:
		if String(q["node"].get_meta("lane", "")) == "DK":
			dk.append(q)
	print("[dark] DK 板 %d 块（期望 7）" % dk.size())
	for q in dk:
		print("[dark]   %-4s %s" % [String(q["node"].name), str(q["seq"])])

	# ② 七块各结算一次 → 保证金 10 万 × 1.01^7
	fut.set("margin", 10.0)
	fut.set("settled", {})
	fut.set("_settled_pct", {})
	fut.set("_on_plate", "")
	for pl in fut.get("plates"):
		if String(pl["name"]).begins_with("DK"):
			fut.call("_settle", pl)
	var m := float(fut.get("margin"))
	var want := 10.0 * pow(1.01, 7.0)
	print("[dark] 七块结算后保证金 = %.4f 万（期望 %.4f，%+.1f%%）" % [
		m, want, (m / 10.0 - 1.0) * 100.0])

	# ③ 霍德：四个技能 + 没有激光
	var player := (load("res://scenes/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	root.add_child(player)
	player.global_position = Vector3(-374.0, 2.0, -1.7)
	var boss := (load("res://scenes/dark_boss.tscn") as PackedScene).instantiate() as DarkBoss
	root.add_child(boss)
	for _i in 10:
		await physics_frame
	boss.global_position = player.global_position + Vector3(0.0, 7.0, 0.0)
	boss.set("_player", player)
	boss.set_physics_process(false)
	var consts: Dictionary = boss.get_script().get_script_constant_map()
	print("[dark] 技能 = %s（%d 个）" % [str(consts.get("SKILL_NAMES", [])),
		int(consts.get("SKILL_COUNT", -1))])
	print("[dark] 激光节点 = %s（期望 null）" % str(boss.get_node_or_null("LaserBeam")))

	var s0 := boss.shots_fired()
	boss.call("_skill_barrage", boss.call("_player_point"))
	for _i in 30:
		await process_frame
	print("[dark] 弹幕：%d 发（期望 2）" % (boss.shots_fired() - s0))

	var s1 := boss.shots_fired()
	boss.call("_skill_triple", boss.call("_player_point"))
	for _i in 4:
		await process_frame
	print("[dark] 三连炮：%d 发（期望 3）" % (boss.shots_fired() - s1))

	player.health = player.max_health
	boss.call("_skill_quake", boss.call("_player_point"))
	for _i in 4:
		await process_frame
	print("[dark] 震地波预警圈 = %d 个（≥1）" % boss.mark_count())
	await _wait_ms(1100)
	print("[dark] 震地波后血量 = %.0f / %.0f（期望掉血）" % [player.health, player.max_health])

	player.health = player.max_health
	player.global_position = Vector3(-374.0, 2.0, -1.7)
	boss.call("_skill_slam", boss.call("_player_point"))
	for _i in 4:
		await process_frame
	print("[dark] 砸击预警 = %d 个（期望 ≥2：圈 + 光柱）" % boss.mark_count())
	await _wait_ms(1350)
	print("[dark] 砸击后血量 = %.0f / %.0f（期望掉血）" % [player.health, player.max_health])
	quit(0)


func _wait_ms(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame
