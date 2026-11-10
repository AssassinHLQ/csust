extends SceneTree
## 真窗口验：**真人按 F3** 到底能不能开开发者模式 + 帧率浮层。
##
##   _tools/run_shot.sh res://scripts/_probe_f3.gd
##
## 为什么要真窗口：`_verify_dev_keys.gd` 是直接调 `player._dev_key(KEY_F3)`，
## 绕过了「操作系统 → 窗口 → Godot → _input」这一整段（本工程为此误判过两轮，
## 见 `game.gd::_watch_input()` 的注释）。人按 F3 走的是后者。
##
## 做法：开真窗口、`Input.parse_input_event()` 注入 F3（比 headless 更接近真实链路），
## 然后读三样东西：`DevMode.is_on()`、`game._perf_layer.visible`、`game._keys_seen`。
## 另外把 `-- --simulate-pause` 传进来时，先开一次 Esc 菜单再按 F3，
## 复现「暂停时按 F3 没反应」这个真实场景。

const OffWin := preload("res://scripts/offscreen_window.gd")
const DevMode := preload("res://scripts/dev_mode.gd")

var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fail += 1


func _press(key: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = key
	ev.physical_keycode = key
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventKey.new()
	up.keycode = key
	up.physical_keycode = key
	up.pressed = false
	Input.parse_input_event(up)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	await OffWin.apply(self, Vector2i(1280, 720))
	var safe: Array = OffWin.is_safe()
	print("[f3] 窗口安全检查：%s（%s）" % ["通过" if safe[0] else "⚠️ 不通过", safe[1]])

	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 20:
		await process_frame

	var player: Node = game.get_node_or_null("Player")
	_check(player != null, "场景里有 Player")
	# 先关掉（静态变量可能被上一个自检留在「开」）
	DevMode.set_on(false)
	for _i in 4:
		await process_frame

	print("========== 1. 正常状态按 F3 ==========")
	# ⚠️ `_keys_seen` 只统计**暂停以外**的按键，而且 `game.gd::_input` 排在
	#    `player.gd::_input` **之后**（树里 Player 在前）—— player 一
	#    `set_input_as_handled()`，game 就收不到了。所以这里**不能拿 _keys_seen
	#    当判据**（本喵第一版就是这么误判成「事件没进 Godot」的）。
	#    真正要验的是「人按一下，两个东西都亮」。
	_press(KEY_F3)
	for _i in 10:
		await process_frame
	_check(DevMode.is_on(), "开发者模式 = 开（player.gd 那边切的）")
	var perf: CanvasLayer = game.get("_perf_layer") as CanvasLayer
	_check(perf != null, "帧率浮层已建出来")
	if perf != null:
		_check(perf.visible, "帧率浮层 = 显示")
	if perf == null:
		print("       ⚠️ 帧率浮层没建出来 ⇒ 多半是 `game.gd::_input` 没收到 F3：")
		print("          player 先吃掉并 set_input_as_handled()，game 就轮不到了。")

	print("========== 2. 再按一次 F3 ==========")
	_press(KEY_F3)
	for _i in 10:
		await process_frame
	_check(not DevMode.is_on(), "开发者模式 = 关")
	if perf != null:
		_check(not perf.visible, "帧率浮层 = 隐藏")

	print("========== 3. 暂停时按 F3（开 Esc 菜单）==========")
	# ⚠️ 变量名**不能叫 `paused`**：`SceneTree` 自己有一个 `paused` 属性，
	#    在 `extends SceneTree` 的脚本里 `var paused := ...` 会把 parse 整个搞错
	#    （本喵第一版就是这么翻车的，日志里却没报 ── 因为它压根没跑到这里）。
	var was_paused := bool(paused)
	var menu: Node = game.get_node_or_null("SettingsMenu")
	if menu != null:
		menu.call("open")
		for _i in 10:
			await process_frame
		_check(bool(paused), "游戏已暂停（菜单开着）")
		DevMode.set_on(false)
		_press(KEY_F3)
		for _i in 10:
			await process_frame
		var paused_ok := DevMode.is_on()
		var p2: CanvasLayer = game.get("_perf_layer") as CanvasLayer
		var p2v := p2 != null and p2.visible
		print("       暂停中按 F3 → DevMode=%s  浮层=%s  按键计数=%d" % [
			str(paused_ok), str(p2v), int(game.get("_keys_seen"))])
		_check(paused_ok, "暂停时 F3 **仍然**开了开发者模式")
		_check(p2v, "暂停时 F3 **仍然**开了帧率浮层")
		if not paused_ok:
			print("       ⇒ 这就是「F3 不见了」的真因：暂停时 game.gd 收到按键，")
			print("         但 player.gd 是 PAUSABLE，收不到 _input。")
		menu.call("close")
		for _i in 6:
			await process_frame
	else:
		print("  SKIP  场景里没有 SettingsMenu")

	print("")
	print("结果：%s" % ("全部通过" if _fail == 0 else "%d 项失败" % _fail))
	quit(0 if _fail == 0 else 1)
