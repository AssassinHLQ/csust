extends SceneTree
## 自检：打倒飞猪后 HUD 上**真的弹了飘字**。
##
## 用户 2026-11-09：「为什么飞猪优香打完不掉钱了，要银行卡的1w」
## 根因之一是完全没有反馈（第一场景没有银行卡 HUD）。
##
## 这条自检盯三件事：
##   ① HUD 进了 `hud` 组（`boss.gd::_float_reward()` 靠它找）
##   ② HUD 有 `show_float_text()` 方法
##   ③ 打倒飞猪后 HUD 下真的多了一个 Label，且文字含「银行卡」和「1.0 万」
##
## 用法：
##   & <godot> --headless --path . --script res://scripts/_verify_pig_float.gd -- --no-capture

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


## 数 HUD 下有多少个「裸 Label」（跳过那些有名字的固定控件）
func _count_floaters(hud: Node) -> int:
	var n := 0
	for c in hud.get_children():
		if c is Label and (c as Label).name.begins_with("@"):
			n += 1
	return n


func _run() -> void:
	print("========== 飞猪掉落飘字 ==========")
	var ps := load(GAME) as PackedScene
	if ps == null:
		push_error("[diag] 加载不了 %s" % GAME)
		quit(1)
		return
	var level := ps.instantiate()
	root.add_child(level)
	for _i in 15:
		await process_frame

	# ① HUD 在组里吗
	var hud := get_first_node_in_group("hud")
	_check(hud != null, "HUD 进了 hud 组（找到 %s）" % (str(hud.name) if hud else "null"))
	if hud == null:
		quit(1)
		return

	# ② 有那个方法吗
	_check(hud.has_method("show_float_text"), "HUD 有 show_float_text() 方法")

	# ③ 打飞猪之前先数一遍
	var before := _count_floaters(hud)
	print("  击杀前 HUD 下的飘字 Label 数 = %d" % before)

	var pig := level.get_node_or_null("BossPig")
	if pig == null:
		push_error("[diag] 没有 BossPig")
		quit(1)
		return
	pig.call("take_damage", 999999.0)
	await process_frame
	await process_frame

	var after := _count_floaters(hud)
	print("  击杀后 HUD 下的飘字 Label 数 = %d" % after)
	_check(after > before, "击杀后多了一个飘字 Label（%d → %d）" % [before, after])

	# ④ 文字内容对不对
	var found := ""
	for c in hud.get_children():
		if c is Label and (c as Label).name.begins_with("@"):
			found = (c as Label).text
	print("  飘字内容 = 「%s」" % found)
	_check(found.contains("银行卡"), "飘字里提到「银行卡」")
	_check(found.contains("1.0 万") or found.contains("10000"), "飘字里金额是 1 万")

	print("\n========== 结果 ==========")
	print("  通过 %d，失败 %d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
