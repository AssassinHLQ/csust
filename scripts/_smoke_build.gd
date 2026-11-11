extends SceneTree
## 打包前冒烟：主场景能起来、玩家能开火、普通攻击打出来的**是飞行光点**。
##
## 用户 2026-11-09：「先打包有人要检查 exe」。打包前必须证明这一版不是坏版本 ——
## 当时本喵刚把普通状态从实弹机枪改成激光机枪（`weapon.gd::laser_gun`），
## 这条冒烟就是「那一枪到底出的什么」的直接证据。
##
## ⚠️ 2026-11-11：普通攻击的**外观**又改了两轮（先关枪口/命中两颗球，再把光柱本身
##    换成「发光光点」，见 README §14.1）。所以第 ⑥ 条现在断言的是
##    **`_in_flight` 里有弹丸、`_beams` 是空的** —— 别再改回「光束 > 0」。
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

	# ⑥ 普通攻击打出来的是**飞行光点**，不是光柱
	#    （2026-11-11 用户：「这个光柱还是不好看，改成光点吧，就是发光子弹那种」——
	#      `_spawn_laser_bolt()` 往 `_in_flight` 里塞弹丸；`_beams` 只剩机甲会用）
	#
	# ⚠️ 必须**打完当帧就读**：弹丸 260 m/s，等几帧它已经撞墙被回收了，读到 0 个
	#    （出图探针那边就栽过这个跟头）。`shoot()` 是同步生成弹丸的。
	wpn.set("_cooldown", 0.0)
	var shot := bool(wpn.call("shoot"))
	var bolts: int = (wpn.get("_in_flight") as Array).size()
	var beams: int = (wpn.get("_beams") as Array).size()
	print("  又打一发 = %s   在飞光点 = %d   光束节点 = %d" % [str(shot), bolts, beams])
	_check(shot, "还能再打出一发")
	_check(bolts > 0, "开火打出飞行光点（%d 个弹丸）" % bolts)
	_check(beams == 0, "普通攻击**没有**光柱（光束节点 %d，应为 0）" % beams)

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
