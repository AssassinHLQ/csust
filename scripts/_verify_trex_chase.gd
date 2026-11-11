extends SceneTree
## 验「霸王龙追人」：会朝玩家跑、会转身、会停下来打、会贴地、会被拴绳拉回，
## 而且腿是**真的在摆**（不是滑步）。
##
## 背景（2026-11-11 用户：「霸王龙要能跑动，追人那种」）：
## GLB 里没有走路动作，腿是程序化摆的（`trex_yuuka_boss.gd::_tick_legs()`）。
##
##   bash _tools/run_probe.sh res://scripts/_verify_trex_chase.gd -- --no-capture --splat=off

const LEVEL := "res://scenes/next_level.tscn"
const BOSS := "TrexBossA"
## 追击是 12 m/s，跑 1 s 就该挪 12 m
const RUN_FRAMES := 90

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
	var GameSettingsScript := load("res://scripts/game_settings.gd")
	# 关掉 Boss 攻击：这段测的是走位，不是伤害（而且 `_busy` 期间会停止移动，会干扰）
	GameSettingsScript.call("set_value", "boss_attack", false)

	var level := (load(LEVEL) as PackedScene).instantiate()
	root.add_child(level)
	for i in 4:
		await process_frame
	var boss := level.get_node_or_null(BOSS)
	if boss == null:
		print("!! 找不到 %s" % BOSS)
		quit(1)
		return
	if not bool(boss.get("_booted")):
		boss.call("_boot")
	for i in 40:
		await process_frame

	var player := level.get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		print("!! 场景里没有玩家")
		quit(1)
		return

	print("")
	print("========== 1. 会朝玩家跑过来 ==========")
	# 把玩家放到 Boss 前方 30 m（在通知范围 60 m 内、拴绳 45 m 内）
	var home: Vector3 = boss.get("_home")
	player.global_position = home + Vector3(0, 0, 30)
	for i in 10:
		await process_frame
	var d0 := _flat_dist(boss, player)
	var p0: Vector3 = boss.global_position
	for i in RUN_FRAMES:
		await process_frame
	var d1 := _flat_dist(boss, player)
	var moved := _flat_len(p0, boss.global_position)
	print("        距离 %.1f m → %.1f m（拉近 %.1f m）｜ 本体移动 %.1f m" % [
		d0, d1, d0 - d1, moved])
	_check(d1 < d0 - 8.0, "玩家不动时它会主动贴近（拉近 %.1f m > 8 m）" % (d0 - d1))
	_check(moved > 8.0, "本体真的在移动（%.1f m > 8 m）" % moved)

	print("")
	print("========== 2. 会转身朝向玩家 ==========")
	var to_player: Vector3 = player.global_position - boss.global_position
	to_player.y = 0.0
	var f: Vector3 = boss.call("facing")
	var dot := f.normalized().dot(to_player.normalized())
	print("        朝向点积 %.3f（1 = 正对）" % dot)
	_check(dot > 0.85, "正面朝着玩家（点积 %.2f > 0.85）" % dot)

	print("")
	print("========== 3. 不会贴到玩家身上（停在攻击距离外）==========")
	# 把玩家挪到 Boss 面前 2 m —— 比 chase_stop_distance(7 m) 还近，它应该**不前进**
	for i in 20:
		await process_frame
	var near_before := _flat_dist(boss, player)
	player.global_position = boss.global_position + f.normalized() * 2.0
	player.global_position.y = boss.global_position.y
	for i in 40:
		await process_frame
	var near_after := _flat_dist(boss, player)
	var stop_dist: float = boss.get("chase_stop_distance")
	print("        玩家贴到 2 m，%.2f s 后距离 %.2f m（停下阈值 %.1f m）" % [
		40.0 / 60.0, near_after, stop_dist])
	_check(near_after < stop_dist + 6.0,
		"没有一直顶着玩家往前碾（最终 %.2f m < %.1f m）" % [near_after, stop_dist + 6.0])
	_check(near_after > 0.5, "也没有和玩家重合在一起（%.2f m）" % near_after)

	print("")
	print("========== 4. 腿真的在摆（不是滑步）==========")
	# 让玩家回到 30 m 外，重新跑起来，抓同一根大腿骨在两个时刻的旋转
	player.global_position = boss.global_position + f.normalized() * 30.0
	for i in 10:
		await process_frame
	var skel: Skeleton3D = boss.call("_best_skeleton", boss.get("model"))
	var thigh := skel.find_bone("Bone.014") if skel != null else -1
	if thigh < 0:
		_check(false, "找得到大腿骨 Bone.014")
	else:
		var qs: Array[Quaternion] = []
		for i in 24:
			await process_frame
			qs.append(skel.get_bone_pose_rotation(thigh))
		var max_delta := 0.0
		for k in range(1, qs.size()):
			max_delta = maxf(max_delta, qs[k].angle_to(qs[k - 1]))
		print("        大腿骨相邻帧最大转动 %.2f°（0 = 完全没动）" % rad_to_deg(max_delta))
		_check(rad_to_deg(max_delta) > 0.15,
			"跑动时大腿骨在摆动（%.2f° > 0.15°）" % rad_to_deg(max_delta))

	print("")
	print("========== 5. 贴地（不会浮空 / 陷进地里）==========")
	var y0: float = boss.global_position.y
	var y_min := y0
	var y_max := y0
	for i in 60:
		await process_frame
		y_min = minf(y_min, boss.global_position.y)
		y_max = maxf(y_max, boss.global_position.y)
	print("        y 范围 %.2f ~ %.2f（出生点 y = %.2f）" % [y_min, y_max, home.y])
	_check(absf(y_max - home.y) < 3.0 and absf(y_min - home.y) < 3.0,
		"跑动时没有飞起来也没扎进地里（y 偏差 < 3 m）")

	print("")
	print("========== 6. 拴绳：跑太远会回家 ==========")
	# 把玩家丢到很远处（超出 notice_range），Boss 应当**不再跟着走**
	var far_pos: Vector3 = home + Vector3(0, 0, 200)
	player.global_position = far_pos
	for i in 30:
		await process_frame
	var stay := _flat_len(boss.global_position, home)
	print("        玩家被丢到 200 m 外，%d 帧后本体离出生点 %.1f m（拴绳 %.1f m）" % [
		30, stay, float(boss.get("chase_leash"))])
	_check(stay <= float(boss.get("chase_leash")) + 12.0,
		"不会追出拴绳范围（%.1f m ≤ %.1f m）" % [
			stay, float(boss.get("chase_leash")) + 12.0])

	print("")
	print("========== 结果 ==========")
	if _fail == 0:
		print("全部 %d 项通过" % _pass)
	else:
		print("%d 项通过，%d 项失败" % [_pass, _fail])
	GameSettingsScript.call("set_value", "boss_attack", true)
	quit(0 if _fail == 0 else 1)


func _flat_dist(a: Node3D, b: Node3D) -> float:
	return _flat_len(a.global_position, b.global_position)


func _flat_len(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
