extends SceneTree
## 打包前冒烟：主场景能起来、玩家能开火、激光机枪真的出光束。
##
## 用户 2026-11-09：「先打包有人要检查 exe」。打包前必须证明这一版不是坏版本 ——
## 本喵刚把普通状态从实弹机枪改成激光机枪（`weapon.gd::laser_gun`），
## 这条冒烟就是「那一枪到底出的什么」的直接证据。
##
## 用法：
##   & <godot> --headless --path . --script res://scripts/_smoke_build.gd -- --no-capture

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
	print("========== 打包前冒烟 ==========")

	# ① 主场景能实例化
	var ps := load(GAME) as PackedScene
	_check(ps != null, "能加载 %s" % GAME)
	if ps == null:
		_finish()
		return
	var level := ps.instantiate()
	root.add_child(level)
	for _i in 20:
		await process_frame
	_check(level.is_inside_tree(), "主场景进入场景树")

	# ② 玩家与武器就位
	var player := level.get_node_or_null("Player")
	_check(player != null, "找到 Player")
	if player == null:
		_finish()
		return
	var wpn := player.get_node_or_null("Weapon")
	_check(wpn != null, "找到 Weapon")
	if wpn == null:
		_finish()
		return

	# ③ 激光机枪开关是开的（玩家 2026-11-09 要求的普通状态改动）
	var laser_on := bool(wpn.get("laser_gun"))
	_check(laser_on, "普通状态 laser_gun = true（实际 %s）" % str(laser_on))

	# ④ 机甲模式没被误开（那是另一条路，无限弹）
	var beam_on := bool(wpn.get("beam_mode"))
	_check(not beam_on, "机甲 beam_mode = false（实际 %s）—— 普通状态不该无限弹" % str(beam_on))

	# ⑤ 普通状态照常扣弹匣（激光机枪不等于无限子弹）
	var ammo0 := int(wpn.get("current_ammo"))
	wpn.call("trigger_down")
	await process_frame
	wpn.call("trigger_up")
	for _i in 6:
		await process_frame
	var ammo1 := int(wpn.get("current_ammo"))
	print("  弹匣：%d → %d" % [ammo0, ammo1])
	_check(ammo1 < ammo0, "开火后扣了弹（%d → %d）" % [ammo0, ammo1])

	# ⑥ 真的画出了光束（`_spawn_beam` 会往 `_beams` 里塞 holder）
	var beams: int = (wpn.get("_beams") as Array).size()
	print("  光束节点数 = %d" % beams)
	_check(beams > 0, "开火生成了激光光束（%d 个节点）" % beams)

	# ⑦ 关键控件都在
	_check(level.get_node_or_null("HUD") != null, "HUD 在场景里")
	var hud_in_group := get_first_node_in_group("hud") != null
	_check(hud_in_group, "HUD 进了 hud 组（掉落飘字要用）")

	_finish()


func _finish() -> void:
	print("\n========== 结果 ==========")
	print("  通过 %d，失败 %d" % [_pass, _fail])
	print("  %s" % ("★ 可以打包" if _fail == 0 else "✗ 有失败项，不要打包"))
	quit(0 if _fail == 0 else 1)
