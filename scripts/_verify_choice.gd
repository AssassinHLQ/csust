extends SceneTree
## 自检：对话框的选项（W/S 移动、空格确认、then 后续台词、无 then 直接结束）
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


func _make_steps() -> Array:
	return [
		{"kind": "say", "who": "芹香", "text": "你配电脑吗?"},
		{"kind": "choice", "options": [
			{"text": "商人啊!我正是为此而来!", "value": 1,
				"then": [{"kind": "say", "who": "芹香", "text": "老板,看这套配置怎么样[TVT]"}]},
			{"text": "观察了银行卡的余额,摇了摇头", "value": 2},
		]},
	]


func _open(box: DialogueBox) -> void:
	box.play_steps(_make_steps(), "verify")
	for _i in 20:
		await process_frame


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var box := DialogueBox.new()
	root.add_child(box)
	await process_frame
	box.set_cps(100000.0)

	# ── ① 选第二项：去括号、讲完直接结束 ──
	await _open(box)
	print("[choice] 第一句=%s" % box.current_text())
	_check(box.current_text().begins_with("你配电脑吗"), "第一句是「你配电脑吗?」")
	box.advance()
	for _i in 10:
		await process_frame
	_check(box.choice_count() == 2, "进入选择，选项数=%d（期望 2）" % box.choice_count())
	_check(box.current_choice() == 0, "默认选中第 1 项（current=%d）" % box.current_choice())
	_check(box.choice_text(0) == "商人啊!我正是为此而来!", "第 1 项：%s" % box.choice_text(0))
	_check(box.choice_text(1) == "观察了银行卡的余额,摇了摇头",
		"第 2 项（已去括号）：%s" % box.choice_text(1))
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
	_key(KEY_SPACE)
	for _i in 30:
		await process_frame
	_check(not box.is_active(), "选第 2 项后对话直接结束（is_active=%s）" % str(box.is_active()))
	_check(box.current_text().is_empty() or not box.is_active(), "选第 2 项没有多余台词")

	# ── ② 选第一项：接「老板,看这套配置怎么样[TVT]」 ──
	await _open(box)
	box.advance()
	for _i in 10:
		await process_frame
	_key(KEY_SPACE)
	for _i in 30:
		await process_frame
	print("[choice] 选第 1 项后的正文=%s" % box.current_text())
	_check(box.current_text() == "老板,看这套配置怎么样[TVT]", "第 1 项的反应台词正确")
	box.advance()
	for _i in 10:
		await process_frame
	_check(not box.is_active(), "第 1 项说完也正常结束")
	print("[choice] 结果：%d 通过 / %d 失败" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
