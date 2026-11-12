extends SceneTree
## 验收：用电脑时**字母 f 能打进终端**，以及退出键不再是 F。
##
## 用户 2026-11-12：「电脑取消，不能用 F 取消因为输入不了命令」
## —— 原来 `hut_computer._input()` 在把按键转给终端**之前**就 `KEY_F → _close()`，
##    于是 `neofetch` / `df` / `sudo` 这些带 f 的命令根本敲不出来。
##
## 这里直接调 `hut_computer._input()` 喂真键盘事件（和游戏里同一条派发路径），
## 断言：
##   ① 敲 `neofetch`（含 f）能完整打进终端、能执行
##   ② 单按 F **不会**关电脑，而且 f 会进到输入行
##   ③ Ctrl+Q 能关
##   ④ Esc 也能关（终端 exit_requested）
##
##   godot --path . --script res://scripts/_verify_computer_keys.gd -- --no-capture

const OFF := preload("res://scripts/offscreen_window.gd")

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await OFF.apply(self, Vector2i(900, 720))
	for _i in 3:
		await process_frame
	print("═══ 电脑键盘 · 字母 f 能不能打 ═══\n")

	ShopClerk._bought = true
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _f in 90:
		await process_frame
	paused = false

	var pc := get_first_node_in_group("hut_computer")
	_check(pc != null, "找到小屋电脑")
	if pc == null:
		_summary()
		quit(1)
		return
	pc.call("use_for_test")
	await _wait(8)
	var term = pc.get("terminal")
	_check(term != null and bool(pc.call("is_using")), "电脑已打开")

	# ── ① 敲 neofetch（含 f）：应该完整进到输入行 ──
	for ch in "neofetch":
		_feed_key(pc, _code(ch), ch.unicode_at(0))
		await _wait(1)
	var typing := String(term.get("_typing"))
	_check(typing == "neofetch", "`neofetch` 全部打进去了（实际：「%s」）" % typing)
	_check(bool(pc.call("is_using")), "打的过程中电脑一直开着（没被 f 关掉）")

	# 回车执行：屏幕最后应有升级/配置相关内容，且提示符回来了
	_feed_key(pc, KEY_ENTER, 0)
	await _wait(4)
	var screen := String(term.call("screen_text"))
	_check(screen.contains("nvidia") or screen.contains("CPU") or screen.contains("RTX"),
		"`neofetch` 真的执行了（屏幕上有配置内容）")
	_check(String(term.get("_typing")) == "", "回车后输入行已清空")

	# ── ② 单按 F：不关电脑，f 进输入行 ──
	_feed_key(pc, KEY_F, 102)          # 102 = 'f'
	await _wait(2)
	_check(bool(pc.call("is_using")), "单按 F **不会**关电脑")
	_check(String(term.get("_typing")) == "f", "f 进到了输入行（实际：「%s」）"
		% String(term.get("_typing")))

	# 清掉这一行，免得影响后面的断言
	_feed_key(pc, KEY_U, 0, true)      # Ctrl+U 清行
	await _wait(2)

	# ── ③ Ctrl+Q 关电脑 ──
	_feed_key(pc, KEY_Q, 0, true)
	await _wait(4)
	_check(not bool(pc.call("is_using")), "Ctrl+Q 关掉电脑")

	# ── ④ 重开，Esc 也能关 ──
	pc.call("use_for_test")
	await _wait(8)
	_check(bool(pc.call("is_using")), "重新打开")
	_feed_key(pc, KEY_ESCAPE, 0)
	await _wait(6)
	_check(not bool(pc.call("is_using")), "Esc 关掉电脑")

	_summary()
	quit(0)


## 走游戏里同一条路径：`hut_computer._input()`
func _feed_key(pc: Node, code: int, unicode: int, ctrl := false) -> void:
	var e := InputEventKey.new()
	e.pressed = true
	e.keycode = code
	e.physical_keycode = code
	e.unicode = unicode
	e.ctrl_pressed = ctrl
	pc.call("_input", e)


func _code(ch: String) -> int:
	var up := ch.to_upper()
	if up.length() == 1 and up.unicode_at(0) >= 65 and up.unicode_at(0) <= 90:
		return KEY_A + (up.unicode_at(0) - 65)
	return KEY_SPACE


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % what)
	else:
		_fail += 1
		print("  ✗ %s" % what)


func _summary() -> void:
	print("\n═══ 通过 %d / 失败 %d ═══" % [_pass, _fail])
