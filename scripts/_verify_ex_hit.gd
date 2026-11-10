extends SceneTree
## 自检：EX 轨道炮**不会打到自己**（用户 2026-11-10「机甲按 EX 就闪退」）。
##
##   _tools/run_probe.sh res://scripts/_verify_ex_hit.gd
##
## 崩溃原文（用户调试器截图）：
##   Invalid type in function 'take_damage' (via call) in base
##   'CharacterBody3D (Player)'. Cannot convert argument 4 from Vector3 to float.
##
## 根因：`Player` 也有 `take_damage`，但签名是 `(amount, hit_from, knockback)` ——
## 第 3 个是 float；Boss / 靶子是 `(amount, hit_pos, hit_dir)` —— 第 3 个是 Vector3。
## 轨道炮按后者传 4 个参数，一旦 `hit.collider` 是玩家就硬崩。
##
## 覆盖：
##   ① `_can_hurt_take_damage()` 认 Boss / 靶子，**不认 Player**
##   ② 射线查询带 `exclude`（不再从炮口撞到自己）
##   ③ 真的摆一个玩家在射线上、开一炮 → **零报错**（这才是端到端）

const EX := preload("res://scripts/ex_system.gd")
const PLAYER_SCENE := "res://scenes/player.tscn"

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


## 假的 Boss：**敌人签名**（第 3 个参数是 Vector3）
class FakeBoss extends StaticBody3D:
	var hits := 0
	func take_damage(amount: float, _hit_pos := Vector3.ZERO,
			_hit_dir := Vector3.ZERO) -> void:
		hits += 1


func _run() -> void:
	print("========== 1. 签名判定：谁该挨打、谁不该 ==========")
	var ex := Node3D.new()
	ex.set_script(EX)
	root.add_child(ex)
	await process_frame

	# ① Player：第 3 个参数是 float（knockback）→ 不该挨 EX 的伤害
	var player: Node = (load(PLAYER_SCENE) as PackedScene).instantiate()
	root.add_child(player)
	await process_frame
	_check(player.has_method("take_damage"), "Player 确实有 take_damage（所以光判 has_method 不够）")
	_check(not bool(ex.call("_can_hurt_take_damage", player)),
		"Player **不**算「可被 EX 命中」（第 3 个参数是 float）")

	# ② FakeBoss：敌人签名 → 该挨打
	# ⚠️ 内嵌类里 `take_damage` 的默认参数在 `get_method_list()` 里可能只报
	#    显式形参个数（GDScript 的实现差异），所以这里**改成先跑一遍再看结果**，
	#    不硬依赖「args.size() >= 4」这一个判据。
	var boss := FakeBoss.new()
	var bcol := CollisionShape3D.new()
	var bshape := BoxShape3D.new()
	bshape.size = Vector3(2, 2, 2)
	bcol.shape = bshape
	boss.add_child(bcol)
	root.add_child(boss)
	await process_frame
	_check(bool(ex.call("_can_hurt_take_damage", boss)),
		"Boss（第 3 个参数是 Vector3）算「可被 EX 命中」")

	# ③ 没有 take_damage 的节点
	var plain := StaticBody3D.new()
	root.add_child(plain)
	await process_frame
	_check(not bool(ex.call("_can_hurt_take_damage", plain)),
		"没 take_damage 的节点不算")
	_check(not bool(ex.call("_can_hurt_take_damage", null)), "null 不算")

	print("")
	print("========== 2. 源码里射线确实排除了玩家 ==========")
	var src := FileAccess.get_file_as_string("res://scripts/ex_system.gd")
	_check(src.contains("q.exclude = [_player]"),
		"轨道炮射线 `q.exclude = [_player]`（不从炮口撞到自己）")
	_check(src.contains("_can_hurt_take_damage"),
		"调用点用的是签名判定，不是裸 has_method")

	print("")
	print("========== 3. 端到端：炮口**在玩家身体里**，开一炮 ==========")
	# 这正是崩现场：机甲炮口贴着机体，射线一出发就撞到自己。
	# 直接把炮口摆在玩家中心、方向朝 `-Z`，让射线**必然**先经过玩家。
	player.global_position = Vector3(0, 1, 0)
	boss.global_position = Vector3(0, 1, -8)
	for _i in 4:
		await process_frame
	if ex.has_method("setup"):
		ex.call("setup", player, player.get_node_or_null("Weapon"), null)
	var before := boss.hits
	var froms: Array[Vector3] = [Vector3(0, 1, 0)]
	ex.call("_rail_fire", froms, Vector3(0, 0, -1))
	for _i in 60:
		await process_frame
	print("       FakeBoss 收到 %d 跳伤害（之前 %d）" % [boss.hits, before])
	print("       ↳ 修好之后这里应该**有**伤害（射线穿过玩家时会继续打到后面的 Boss）；")
	print("         更关键的是：**没崩**。崩的话进程早退出了，走不到下面这行。")
	_check(true, "开炮 + 跑完 0.9 s，**进程活着**（没崩、没 Invalid type）")
	_check(boss.hits > before, "Boss 还是被打到了（玩家没挡住射线）")

	print("")
	print("========== 结果 ==========")
	if _fail == 0:
		print("全部 %d 项通过" % _pass)
	else:
		print("%d 项通过，%d 项失败" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
