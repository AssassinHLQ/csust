extends SceneTree
## 验「余额不足不能买 / 买完扣 67 万 / custom 步骤能扣款」。
##   godot --path . --headless --script res://scripts/_verify_shop_pay.gd
const BankCard := preload("res://scripts/bank_card.gd")

var _seen := ""


func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	Input.parse_input_event(e)
	var up := InputEventKey.new()
	up.keycode = code
	up.physical_keycode = code
	up.pressed = false
	Input.parse_input_event(up)


func _initialize() -> void:
	_run.call_deferred()


func _on_custom(n: String, d: Dictionary) -> void:
	_seen = n
	if n == "pay":
		BankCard.spend(int(d.get("amount", 0)))


func _run() -> void:
	var old := BankCard.balance()
	BankCard.set_balance(800000)

	var box := DialogueBox.new()
	root.add_child(box)
	await process_frame
	box.custom_step.connect(_on_custom)
	box.set_cps(100000.0)

	# ① 余额够：能选，选完 custom 扣款
	box.play_steps([
		{"kind": "choice", "options": [
			{"text": "买", "value": 1},
			{"text": "不买", "value": 2},
		]},
		{"kind": "custom", "name": "pay", "data": {"amount": 670000}},
		{"kind": "narrate", "text": "扣完了"},
	], "pay")
	for _i in 10:
		await process_frame
	_key(KEY_SPACE)
	for _i in 20:
		await process_frame
	print("[pay] custom=%s 余额=%s（期望 13.0 万）" % [_seen, BankCard.format_yuan(BankCard.balance())])
	print("[pay] 旁白=%s" % box.current_text())

	# ② 余额不足：禁用项按下不推进
	BankCard.set_balance(300000)
	var box2 := DialogueBox.new()
	root.add_child(box2)
	await process_frame
	box2.set_cps(100000.0)
	box2.play_steps([
		{"kind": "choice", "options": [
			{"text": "买", "value": 1, "disabled": true,
				"disabled_hint": "银行卡余额不足：还差 ¥37.0 万（卡上 ¥13.0 万）"},
			{"text": "不买", "value": 2},
		]},
		{"kind": "narrate", "text": "结束了"},
	], "nogood")
	for _i in 10:
		await process_frame
	print("[pay] 选择中=%s 选项数=%d" % [str(box2.current_choice() >= 0), box2.choice_count()])
	_key(KEY_SPACE)   # 按空格 = 确认禁用项
	for _i in 10:
		await process_frame
	print("[pay] 按确认后仍在选择=%s（期望 true）" % str(box2.current_choice() >= 0))
	var notice := box2.get_node_or_null("Root/Choices/ChoiceNotice") as Label
	print("[pay] 提示=%s" % (("「%s」" % notice.text) if notice != null and notice.visible else "没显示"))

	BankCard.set_balance(old)
	print("[pay] 已把余额还原成 %s" % BankCard.format_yuan(old))
	quit(0)
