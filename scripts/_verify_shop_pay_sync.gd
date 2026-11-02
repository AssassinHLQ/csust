extends SceneTree
## 自检：商店买整机后，银行卡 / 期货 bank_yuan / HUD 三处必须同步扣款。
##   _tools/run_probe.sh res://scripts/_verify_shop_pay_sync.gd -- --splat=off --story=off
##
## 之前只调 BankCard.spend()，HUD 还显示旧余额，而且下一次结算会按旧 bank_yuan
## 把钱写回卡里（等于白送一台电脑）。

const BankCard := preload("res://scripts/bank_card.gd")
var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, msg: String) -> void:
	print(("[ OK ] " if ok else "[FAIL] ") + msg)
	if not ok:
		_fails += 1


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(30)

	var fut := get_first_node_in_group("futures") as ParkourFutures
	_check(fut != null, "期货节点在 futures 组里")
	if fut == null:
		quit(1)
		return
	var clerk := ShopClerk.new()
	root.add_child(clerk)
	await _wait(2)

	# 模拟拿到 149 颗 CPU 后的余额（¥685,251），买 ¥670,000 的整机
	BankCard.set_balance(685251)
	fut.bank_yuan = BankCard.balance()
	fut.call("_update_hud_text")
	clerk.call("_on_dialogue_custom", "pay", {"amount": ShopClerk.DESK_PRICE, "label": "八卡 5090 工作站"})
	await _wait(4)

	var hud := ""
	var label = fut.get("_debt_label")
	if label != null:
		hud = String((label as Label).text)
	print("[pay] 银行卡=%d　fut.bank_yuan=%d　HUD=%s" % [BankCard.balance(), fut.bank_yuan, hud])
	_check(BankCard.balance() == 685251 - 670000, "银行卡扣到 ¥15,251（实测 ¥%d）" % BankCard.balance())
	_check(fut.bank_yuan == BankCard.balance(), "期货 bank_yuan 与银行卡一致")
	_check(hud.contains("银行卡 ¥15,251 元"), "HUD 立刻显示新余额")
	_check(clerk.call("bought"), "标记已购买，后续对话换成交货/查单")

	# 结算时 `BankCard.set_balance(bank_yuan)` 不应把钱写回去
	var before := BankCard.balance()
	BankCard.set_balance(fut.bank_yuan)
	_check(BankCard.balance() == before, "按 bank_yuan 落盘不会复原已花的钱")

	# 钱不够时一分不扣
	ShopClerk._bought = false
	BankCard.set_balance(1000)
	fut.bank_yuan = 1000
	fut.call("_update_hud_text")
	clerk.call("_on_dialogue_custom", "pay", {"amount": ShopClerk.DESK_PRICE, "label": "八卡 5090 工作站"})
	_check(BankCard.balance() == 1000 and fut.bank_yuan == 1000, "余额不足时不扣款、不记账")
	_check(not clerk.call("bought"), "余额不足不算成交")

	if _fails == 0:
		print("[pay] 结论：OK")
		quit(0)
	else:
		print("[pay] 结论：FAIL %d 项" % _fails)
		quit(1)
