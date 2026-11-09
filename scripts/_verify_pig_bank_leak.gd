extends SceneTree
## 诊断 ②：飞猪那 1w 会不会被跑酷结算**盖掉**？
##
## 背景：`boss.gd::_die()` 走 `BankCard.add()` 直接写卡，但 `parkour_futures.gd`
## 里自己还有一份 `bank_yuan`，结算时用 `BankCard.set_balance(bank_yuan)` 回写。
## 如果两个数不同步，飞猪那 1w 会被 `bank_yuan` 的旧值覆盖。
##
## 本探针模拟「先打飞猪 → 再进跑酷 → 结算」，看钱还在不在。
##
## 用法：
##   & <godot> --headless --path . --script res://scripts/_verify_pig_bank_leak.gd -- --no-capture

const GAME := "res://scenes/game.tscn"
const BankCard := preload("res://scripts/bank_card.gd")

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
	print("========== 飞猪 1w 会不会被结算盖掉 ==========")
	BankCard.set_balance(0)

	var ps := load(GAME) as PackedScene
	if ps == null:
		push_error("[diag] 加载不了 %s" % GAME)
		quit(1)
		return
	var level := ps.instantiate()
	root.add_child(level)
	for _i in 15:
		await process_frame

	# ① 确认 Futures 已就位，并记下它内部的 bank_yuan
	var fut := get_first_node_in_group("futures")
	if fut == null:
		push_error("[diag] 没有 futures 节点")
		quit(1)
		return
	var fut_before := int(fut.get("bank_yuan"))
	print("\n── 打飞猪之前 ──")
	print("  BankCard.balance() = %d" % BankCard.balance())
	print("  futures.bank_yuan  = %d" % fut_before)

	# ② 打死飞猪
	var pig := level.get_node_or_null("BossPig")
	if pig == null:
		push_error("[diag] 没有 BossPig")
		quit(1)
		return
	pig.call("take_damage", 999999.0)
	await process_frame
	await process_frame

	var card_after_kill := BankCard.balance()
	var fut_after_kill := int(fut.get("bank_yuan"))
	print("\n── 打死飞猪之后 ──")
	print("  BankCard.balance() = %d   （+%d）" % [card_after_kill, card_after_kill])
	print("  futures.bank_yuan  = %d   （+%d）" % [fut_after_kill, fut_after_kill - fut_before])
	_check(card_after_kill == 10000, "银行卡 +10000（实际 %d）" % card_after_kill)

	# ③ 关键：两个数一致吗？不一致 → 结算会互相覆盖
	var synced := (fut_after_kill == card_after_kill)
	_check(synced,
		"futures.bank_yuan 与银行卡**已同步**（futures=%d / card=%d）—— 不同步结算会盖掉飞猪的钱"
		% [fut_after_kill, card_after_kill])

	# ④ 模拟结算：`BankCard.set_balance(bank_yuan)`（parkour_futures.gd:1023 就是这么写的）
	BankCard.set_balance(fut_after_kill)
	var after_settle := BankCard.balance()
	print("\n── 模拟结算 set_balance(futures.bank_yuan) 之后 ──")
	print("  BankCard.balance() = %d" % after_settle)
	_check(after_settle >= 10000,
		"结算后飞猪的 1w 还在（实际 %d）—— 若为 0 就说明被盖掉了" % after_settle)

	print("\n========== 结果 ==========")
	print("  通过 %d，失败 %d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
