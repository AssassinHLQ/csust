extends SceneTree
## 自检：对话框的选项（W/S 移动、空格确认、then 后续台词）
##   godot --path . --headless --script res://scripts/_verify_choice.gd

var _pass := 0
var _fail := 0


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % what)
	else:
		_fail += 1
		print("  ✗ %s" % what)


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


func _run() -> void:
	var box := DialogueBox.new()
	root.add_child(box)
	await process_frame
	box.set_cps(100000.0)
	var steps := [
		{"kind": "say", "who": "芹香", "text": "你配电脑吗?"},
		{"kind": "choice", "options": [
			{"text": "商人啊!我正是为此而来!", "value": 1,
				"then": [{"kind": "say", "who": "芹香", "text": "好嘞！那咱把配置单摊开对一对。"}]},
			{"text": "[观察了银行卡的余额,摇了摇头]", "value": 2,
				"then": [{"kind": "say", "who": "芹香", "text": "……先看看也行，不着急买。"}]},
		]},
	]
	box.play_steps(steps, "verify")
	for _i in 20:
		await process_frame
	print("[choice] 第一句=%s" % box.current_text())
	_check(box.current_text().begins_with("你配电脑吗"), "第一句是「你配电脑吗?」")

	box.advance()
	for _i in 10:
		await process_frame
	_check(box.choice_count() == 2, "进入选择，选项数=%d（期望 2）" % box.choice_count())
	_check(box.current_choice() == 0, "默认选中第 1 项（current=%d）" % box.current_choice())
	_check(box.choice_text(0) == "商人啊!我正是为此而来!", "第 1 项文案：%s" % box.choice_text(0))
	_check(box.choice_text(1) == "[观察了银行卡的余额,摇了摇头]", "第 2 项文案：%s" % box.choice_text(1))

	# W / S
	_key(KEY_S)
	for _i in 4:
		await process_frame
	_check(box.current_choice() == 1, "按 S 下移 → current=%d（期望 1）" % box.current_choice())
	_key(KEY_W)
	for _i in 4:
		await process_frame
	_check(box.current_choice() == 0, "按 W 上移 → current=%d（期望 0）" % box.current_choice())
	_key(KEY_S)
	for _i in 4:
		await process_frame

	# 空格确认第 2 项 → 应播 then 里那句
	_key(KEY_SPACE)
	for _i in 20:
		await process_frame
	print("[choice] 选完后的正文=%s" % box.current_text())
	_check(box.current_text().begins_with("……先看看也行"), "选项 2 的后续台词接上了")
	_check(box.choice_count() == 0, "选项面板已收起")

	box.advance()
	for _i in 10:
		await process_frame
	_check(not box.is_active(), "对话正常结束（is_active=%s）" % str(box.is_active()))
	print("[choice] 结果：%d 通过 / %d 失败" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
