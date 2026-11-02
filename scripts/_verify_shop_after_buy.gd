extends SceneTree
## 验：买完整机后再找芹香，对话换成「送货/查单/确认地址」；
## 选项①再看 5090 配置单，选项②弹游戏开发部活动室图 + 配文。
const BankCard := preload("res://scripts/bank_card.gd")


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	var old := BankCard.balance()
	BankCard.set_balance(1000000)
	var clerk := ShopClerk.new()
	root.add_child(clerk)
	var box := DialogueBox.new()
	root.add_child(box)
	await process_frame
	box.set_cps(100000.0)

	# ① 模拟成交（等价于把第一单走完）
	clerk.call("_on_dialogue_custom", "pay", {"amount": 670000, "label": "八卡 5090 工作站"})
	print("[after] 成交=%s 余额=%s（期望 true / ¥33.0 万）" % [
		str(clerk.call("bought")), BankCard.format_yuan(BankCard.balance())])

	# ② 买完后的第一句 + 两个选项
	clerk.call("_talk", box)
	await _wait(5)
	print("[after] 第一句 = 「%s」" % box.current_text())
	box.advance()
	await _wait(5)
	print("[after] 选项 %d 个：%s / %s" % [
		box.choice_count(), box.choice_text(0), box.choice_text(1)])

	# ③ 选项①：再看 5090 配置单
	box.call("_confirm_choice")
	await _wait(5)
	print("[after] 选项①台词 = 「%s」" % box.current_text())
	box.advance()
	await _wait(5)
	var base: Texture2D = (box.get("_sheet_base") as TextureRect).texture
	print("[after] 选项①配置单 = %s（期望 config_sheet_5090.png）" % (
		base.resource_path if base != null else "没弹"))
	box.advance()
	await _wait(3)
	box.finish()
	await _wait(3)

	# ④ 选项②：确认收货地址 → 图 + 配文
	clerk.call("_talk", box)
	await _wait(5)
	box.advance()
	await _wait(5)
	box.set("_choice_index", 1)
	box.call("_refresh_choices")
	box.call("_confirm_choice")
	await _wait(5)
	print("[after] 选项②台词 = 「%s」" % box.current_text())
	box.advance()
	await _wait(5)
	print("[after] 配图 = %s　配文 = 「%s」" % [box.current_image_path(), box.current_image_caption()])
	box.finish()
	BankCard.set_balance(old)
	quit(0)
