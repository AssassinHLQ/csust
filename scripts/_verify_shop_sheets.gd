extends SceneTree
## 验：柴关电脑城连着弹的两张配置单，底图真的是两张不同的图（B300 / 八卡 5090）。
##   godot --path . --headless --script res://scripts/_verify_shop_sheets.gd
const BankCard := preload("res://scripts/bank_card.gd")


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	var old := BankCard.balance()
	BankCard.set_balance(800000)

	var clerk := ShopClerk.new()
	root.add_child(clerk)
	var box := DialogueBox.new()
	root.add_child(box)
	await process_frame
	box.set_cps(100000.0)
	clerk.call("_talk", box)
	await _wait(4)
	print("[sheets] 第一句 = 「%s」" % box.current_text())
	box.advance()
	await _wait(4)
	print("[sheets] 选项数 = %d（期望 2）" % box.choice_count())
	box.call("_confirm_choice")
	await _wait(4)
	print("[sheets] 选中后 = 「%s」" % box.current_text())

	# 往前翻到第一张单子
	var guard := 0
	while not box.is_showing_sheet() and guard < 10:
		box.advance()
		await _wait(3)
		guard += 1
	var tex1: Texture2D = (box.get("_sheet_base") as TextureRect).texture
	print("[sheets] 第 1 张 = %s　热区 %d" % [
		tex1.resource_path, box.sheet_zone_count()])
	box.advance()   # 关掉第一张
	await _wait(4)
	print("[sheets] 关掉后 mouse_mode = %d（headless 下 VISIBLE=0，仅记录）" % Input.mouse_mode)

	# 后面还有 4 句台词，翻到第二张单子
	guard = 0
	while not box.is_showing_sheet() and guard < 12:
		box.advance()
		await _wait(3)
		guard += 1
	var tex2: Texture2D = (box.get("_sheet_base") as TextureRect).texture
	print("[sheets] 第 2 张 = %s　热区 %d" % [
		tex2.resource_path, box.sheet_zone_count()])
	print("[sheets] 结论：%s" % (
		"OK 两张不同" if tex1 != null and tex2 != null and tex1 != tex2
		and tex1.resource_path.ends_with("config_sheet.png")
		and tex2.resource_path.ends_with("config_sheet_5090.png")
		else "FAIL 两张单子一样或路径不对"))
	box.finish()
	BankCard.set_balance(old)
	quit(0)
