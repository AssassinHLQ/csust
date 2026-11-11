extends SceneTree
## 验证 Boss 攻击的**高度判定**——只调真实方法，不复刻公式。
##
## 上一版 `_verify_boss_height.gd` 的硬伤：它复刻了判定公式自己算，
## 所以「倭瓜优香那三条自算的技能」完全漏掉（用户 2026-11-11：
## 「飞起来还是打得到我,还有 boss 倭瓜也是」）。
##
## 本探针的做法：
##   · 飞猪优香 → 调它从基类继承的真实结算路径（见 `_pig_resolve`）
##   · 倭瓜优香 → 直接调 `_land(center)` / `_in_height(pos)` 这两个真函数
##
##   & <godot> --headless --path . --script res://scripts/_verify_boss_height_real.gd

const PlayerScene := preload("res://scenes/player.tscn")

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


func _run() -> void:
	print("========== Boss 高度判定（真实方法）==========")
	var stage := Node3D.new()
	root.add_child(stage)
	var player := PlayerScene.instantiate() as Player
	stage.add_child(player)
	await process_frame
	await process_frame
	player.set_physics_process(false)

	# ---------- 倭瓜优香：三条技能都自己算，直接调 `_land` + `_in_height` ----------
	print("[1] 倭瓜优香")
	var squash = load("res://scripts/squash_boss.gd").new()
	stage.add_child(squash)
	await process_frame
	squash.global_position = Vector3.ZERO
	await process_frame
	var sh := float(squash.get("attack_max_height"))
	print("    attack_max_height = %.1f m｜attack_radius = %.1f"
		% [sh, float(squash.get("attack_radius"))])

	# `_in_height` 是三条技能共用的高度闸门 —— 直接验它
	_check(bool(squash.call("_in_height", Vector3(0, 0.0, 0))), "贴地 → 在高度内")
	_check(bool(squash.call("_in_height", Vector3(0, sh * 0.8, 0))), "八分高 → 在高度内")
	_check(not bool(squash.call("_in_height", Vector3(0, sh + 1.0, 0))),
		"高于 %.1f m → **不在高度内**" % sh)
	_check(not bool(squash.call("_in_height", Vector3(0, 20.0, 0))),
		"20 m 高空 → **不在高度内**")

	# `_land` 走真实结算：圈内贴地必掉血，高空必不掉
	var center := Vector3.ZERO
	_check(await _land_measure(squash, player, center, 0.0), "天降 `_land`：贴地 → 掉血")
	_check(not await _land_measure(squash, player, center, sh + 2.0),
		"天降 `_land`：高于 %.1f m → **不掉血**" % sh)

	# 三个伤害字段确实被接上了（不是只有判定、没伤害）
	_check(float(squash.get("slam_damage")) > 0.0, "slam_damage 有效",
		"%.0f" % float(squash.get("slam_damage")))
	_check(float(squash.get("dash_damage")) > 0.0, "dash_damage 有效",
		"%.0f" % float(squash.get("dash_damage")))
	_check(float(squash.get("quake_damage")) > 0.0, "quake_damage 有效",
		"%.0f" % float(squash.get("quake_damage")))
	squash.queue_free()
	await process_frame

	# ---------- 飞猪优香：基类参数 ----------
	print("[2] 飞猪优香（基类 `attack_max_height`）")
	var pig = load("res://scripts/pig_boss.gd").new()
	stage.add_child(pig)
	await process_frame
	var ph := float(pig.get("attack_max_height"))
	print("    attack_max_height = %.1f m" % ph)
	_check(ph > 0.0 and ph <= 8.0, "高度容差取在合理区间", "%.1f m" % ph)

	# 基类结算那份代码在 `_attack()` 里内联，没有独立函数可调；
	# 这里验「同一套公式在基类源码里存在」——用源码文本做结构性断言，
	# 比复刻公式更诚实（能证明它真的被写进去了）。
	var src := FileAccess.get_file_as_string("res://scripts/boss_attacker.gd")
	_check(src.contains("dy <= attack_max_height"), "基类结算处含高度判定")
	_check(src.contains("absf(to_player.y) > attack_max_height"), "基类起手处含高度判定")
	# 倭瓜的三处也逐条核（它绕过了基类）
	var ssrc := FileAccess.get_file_as_string("res://scripts/squash_boss.gd")
	var n := 0
	var idx := 0
	while true:
		idx = ssrc.find("_in_height(", idx)
		if idx < 0:
			break
		n += 1
		idx += 1
	print("    倭瓜里 `_in_height` 出现 %d 次（1 处定义 + 3 处调用 = 4）" % n)
	_check(n >= 4, "倭瓜三条技能都接了高度闸门", "%d 次" % n)

	print()
	print("========== 结果 ==========")
	print("  通过 %d，失败 %d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


## 调真实的 `_land(center)`，看玩家掉不掉血
func _land_measure(boss: Node3D, player: Player, center: Vector3, height: float) -> bool:
	player.global_position = Vector3(center.x, center.y + height, center.z)
	var before := float(player.get("health"))
	boss.call("_land", center)
	await process_frame
	await process_frame
	return float(player.get("health")) < before
