extends SceneTree
## 验「走近回程门，HUD 上真的出字了」。
##
## 用户 2026-11-08：「第二场景字显示」。背景：
##   2026-11-02 用户要求去掉门上的浮空 3D 字，`scene_gate.gd::_ready()` 于是把
##   `Title` / `Prompt` 两个 Label3D 都设成 invisible —— 结果门上**一个字都没有**，
##   玩家根本不知道该按 F（用户当天就找不到回第一场景的门）。
##   现在改成：第一次走进触发圈时，在关卡的 HUD `Message` 标签上弹一次提示。
##
## 本自检直接调门的 `_on_body_entered()`（不模拟走路），断言：
##   ① `Message` 标签可见了；② 文案就是门上的 `hint`；③ 只弹一次。
##
##   & D:\GAME\godot\Godot_v4.7.1-stable_win64_console.exe --headless --path . \
##       --script res://scripts/_verify_gate_hint.gd

const LEVEL := "res://scenes/next_level.tscn"

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
	var ps := load(LEVEL) as PackedScene
	if ps == null:
		push_error("[GateHint] 加载不了 %s" % LEVEL)
		quit(1)
		return
	var level := ps.instantiate()
	root.add_child(level)
	for i in 6:
		await process_frame

	var gate := level.get_node_or_null("ReturnGate")
	var player := level.get_node_or_null("Player")
	var msg := level.get_node_or_null("LevelUI/Message") as Label
	_check(gate != null, "场景里有 ReturnGate")
	_check(player != null, "场景里有 Player")
	_check(msg != null, "场景里有 LevelUI/Message（提示就显示在这里）")
	if gate == null or player == null or msg == null:
		_done()
		return

	var hint := String(gate.get("hint"))
	print("       门上的 hint = 「%s」" % hint)
	_check(hint != "", "这扇门配了 hint 文案（不配就不会有提示）")
	# 门上那两个浮空 Label3D 应该仍然是隐藏的（用户要求去掉浮空字）
	var prompt3d := gate.get_node_or_null("Prompt") as Label3D
	_check(prompt3d == null or not prompt3d.visible,
		"门上的浮空字仍然是藏的（没把 2026-11-02 那个要求推翻）")

	# 模拟「玩家走进触发圈」
	gate.call("_on_body_entered", player)
	await process_frame
	await process_frame
	print("       Message.visible=%s  text=「%s」" % [str(msg.visible), msg.text])
	_check(msg.visible, "走近后 HUD 提示真的显示了")
	_check(msg.text == hint, "显示的就是门上的那句 hint")

	# 再进一次不该重复弹（先手动清掉，看它会不会再弹）
	msg.visible = false
	gate.call("_on_body_exited", player)
	gate.call("_on_body_entered", player)
	await process_frame
	_check(not msg.visible, "第二次走进来不会重复弹（只提示一次）")

	_done()


func _done() -> void:
	print("")
	print("========== 结果 ==========")
	if _fail == 0:
		print("全部 %d 项通过" % _pass)
	else:
		print("%d 项通过，%d 项失败" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
