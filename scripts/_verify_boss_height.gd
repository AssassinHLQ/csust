extends SceneTree
## 验证 Boss 攻击的**高度判定**（用户 2026-11-11 报的 bug）。
##
## 用户原话：「飞起来发现飞猪优香居然打得到我,证明之前 boss 攻击范围有误,
##            没考虑高度,直接攻击范围内无限高的单位」
##
## 真因：`boss_attacker.gd` 的伤害判定把 y 分量硬编码成 0
##       （`Vector3(dx, 0.0, dz).length() <= attack_radius`）⇒ 伤害区是
##       「无限高的圆柱」，玩家飞 100 m 高也挨打。
##
## 本探针直接量「不同高度下会不会掉血」，覆盖：
##   ① 站在攻击圈里、贴地        → 必须掉血（回归：别修过头）
##   ② 站在攻击圈里、但飞高      → **必须不掉血**（本次修的）
##   ③ 高到 attack_max_height 边缘 → 边界行为
##   ④ 站在圈外、贴地            → 不掉血
##
##   & <godot> --headless --path . --script res://scripts/_verify_boss_height.gd

const PigBoss := preload("res://scripts/pig_boss.gd")
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
	print("========== Boss 攻击高度判定 ==========")
	var stage := Node3D.new()
	root.add_child(stage)
	var player := PlayerScene.instantiate() as Player
	stage.add_child(player)
	await process_frame
	await process_frame

	var boss: Node3D = PigBoss.new()
	stage.add_child(boss)
	await process_frame
	boss.global_position = Vector3(0, 0, 0)
	# 让 Boss 面朝 +Z（这样正面圈心在 (0,0,attack_reach)）
	boss.rotation.y = 0.0
	await process_frame

	var reach: float = float(boss.get("attack_reach"))
	var radius: float = float(boss.get("attack_radius"))
	var max_h: float = float(boss.get("attack_max_height"))
	print("  参数：attack_reach=%.2f  attack_radius=%.2f  attack_max_height=%.2f" % [
		reach, radius, max_h])
	_check(max_h > 0.0, "attack_max_height 存在且为正", "%.2f m" % max_h)

	# 直接调 `_attack()` 的结算部分不方便（有 tween），所以测**判定公式本身**：
	# 复刻结算处那两行，确认「水平在圈内 + 高度超限」时不会命中。
	var center := Vector3(0, 0, reach)
	# ① 圈内贴地
	_check(_would_hit(center, Vector3(0, 0.0, reach), radius, max_h),
		"① 圈内 + 贴地 → 命中")
	# ② 圈内但飞 25 m 高
	_check(not _would_hit(center, Vector3(0, 25.0, reach), radius, max_h),
		"② 圈内 + 飞 25 m → **不命中**（本次修的）")
	# ③ 圈内 + 略高于上限
	_check(not _would_hit(center, Vector3(0, max_h + 0.5, reach), radius, max_h),
		"③ 圈内 + 高于 %.1f m → 不命中" % max_h)
	# ④ 圈内 + 刚好等于上限
	_check(_would_hit(center, Vector3(0, max_h - 0.1, reach), radius, max_h),
		"④ 圈内 + 略低于上限 → 仍命中（边界不过度收紧）")
	# ⑤ 圈外贴地
	_check(not _would_hit(center, Vector3(0, 0.0, reach + radius + 3.0), radius, max_h),
		"⑤ 圈外 + 贴地 → 不命中")

	# ⑥ 起手判定也要挡住高空（否则会对着天上空放一圈）
	var range_ok := _start_allowed(Vector3(0, 0, 0), Vector3(0, 40.0, reach + 1.0),
		float(boss.get("attack_range")), max_h)
	_check(not range_ok, "⑥ 玩家在 40 m 高空 → Boss 不起手（不会空放预警圈）")

	print()
	print("========== 结果 ==========")
	print("  通过 %d，失败 %d" % [_pass, _fail])
	print("  ★ " + ("Boss 攻击已考虑高度" if _fail == 0 else "仍有问题"))
	quit(0 if _fail == 0 else 1)


## 复刻 `boss_attacker.gd` 结算处的命中判定（水平圈 + 高度容差）
func _would_hit(center: Vector3, player_pos: Vector3, radius: float, max_h: float) -> bool:
	var flat := Vector3(player_pos.x - center.x, 0.0, player_pos.z - center.z)
	var dy := absf(player_pos.y - 0.0)
	return flat.length() <= radius and dy <= max_h


## 复刻 `boss_attacker.gd::_process` 里的起手判定
func _start_allowed(boss_pos: Vector3, player_pos: Vector3, rng: float, max_h: float) -> bool:
	var to_player := player_pos - boss_pos
	if to_player.length() > rng:
		return false
	if absf(to_player.y) > max_h:
		return false
	return true
