extends SceneTree
## 验收：终端 `help` 能不能列出**所有**可用命令，以及别名 / 未知命令 / 滚屏。
##
## 用户 2026-11-12：「现在写 help 命令，输入可以弹出所有可以用的命令」。
##
## ⚠️ 独立跑，不加载 game.tscn —— `game.gd:105` preload 的 `title_intro.gd`
##    当时被另一个会话改到一半（缩进语法错），任何加载 game.tscn 的探针都会连带失败。
##    这里直接实例化 `ArchTerminal`（尺寸照抄屏幕 SubViewport 的 832×664）。
##
##   godot --path . --script res://scripts/_verify_terminal_help.gd -- --no-capture

const OFF := preload("res://scripts/offscreen_window.gd")
const Terminal := preload("res://scripts/arch_terminal.gd")
const VP := Vector2i(832, 664)

var _pass := 0
var _fail := 0
var _term: Control


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await OFF.apply(self, Vector2i(900, 720))
	for _i in 3:
		await process_frame
	print("═══ 终端 help · 独立验收 ═══\n")

	_term = Terminal.new()
	_term.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_term)
	await _wait(4)
	_term.size = Vector2(VP)
	await _wait(2)

	# ── ① 敲 help ──
	await _type("help")
	var text := String(_term.call("screen_text"))

	var missing: Array[String] = []
	for c in Terminal.COMMANDS:
		var nm := String(c["name"])
		if not text.contains(nm):
			missing.append(nm)
	_check(missing.is_empty(), "help 列出了全部 %d 个命令%s"
		% [Terminal.COMMANDS.size(),
			"" if missing.is_empty() else "（漏了 %s）" % ", ".join(missing)])

	# ── ② 每条命令右边都要有说明（不能只是干巴巴一列名字）──
	var described := 0
	for c in Terminal.COMMANDS:
		if text.contains(String(c["desc"])):
			described += 1
	_check(described == Terminal.COMMANDS.size(),
		"每个命令都带一句说明（%d/%d）" % [described, Terminal.COMMANDS.size()])

	# ── ③ 别名要露出来 ──
	_check(text.contains("aka: bili"), "help 里标出了别名（bilibili 的 bili/b23/blbl）")

	# ── ④ 行数不超过 ROWS（超了会画到屏幕外）──
	var lines := int(_term.call("line_count"))
	_check(lines <= Terminal.ROWS, "行数 %d ≤ ROWS %d（没有溢出屏幕）"
		% [lines, Terminal.ROWS])

	await _shot("help_list")

	# ── ⑤ help <命令> 只讲一条 ──
	await _type("help arona")
	var t2 := String(_term.call("screen_text"))
	_check(t2.contains("wake up ARONA"), "help arona 给出了那一条的说明")

	# ── ⑥ 用别名也能问 ──
	await _type("help bili")
	var t3 := String(_term.call("screen_text"))
	_check(t3.contains("fake bilibili"), "help bili 走别名也能查到")

	# ── ⑦ 未知命令 ──
	await _type("frobnicate")
	var t4 := String(_term.call("screen_text"))
	_check(t4.contains("command not found: frobnicate"), "未知命令提示 command not found")
	_check(t4.contains("run `help`"), "未知命令顺带提示去看 help")

	# ── ⑧ 别名直接执行：bili 应该发出「开 B 站」信号 ──
	var fired := [false]
	_term.open_bili_requested.connect(func(): fired[0] = true)
	await _type("bili")
	_check(fired[0], "敲别名 bili 触发了 open_bili_requested")

	# ── ⑨ 滚屏：连敲很多次 clear/neofetch 后行数仍受控 ──
	for i in 6:
		await _type("neofetch")
	var lines2 := int(_term.call("line_count"))
	_check(lines2 <= Terminal.ROWS, "连续输出后行数仍 ≤ ROWS（%d）" % lines2)

	await _shot("help_after")
	_summary()
	quit(0)


func _type(line: String) -> void:
	for ch in line:
		var e := InputEventKey.new()
		e.pressed = true
		e.keycode = _code(ch)
		e.physical_keycode = e.keycode
		e.unicode = ch.unicode_at(0)
		_term.feed(e)
		await _wait(1)
	var enter := InputEventKey.new()
	enter.pressed = true
	enter.keycode = KEY_ENTER
	enter.physical_keycode = KEY_ENTER
	_term.feed(enter)
	await _wait(2)


func _code(ch: String) -> int:
	var up := ch.to_upper()
	if up.length() == 1 and up.unicode_at(0) >= 65 and up.unicode_at(0) <= 90:
		return KEY_A + (up.unicode_at(0) - 65)
	return KEY_SPACE


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(name: String) -> void:
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_terminal_help")
	DirAccess.make_dir_recursive_absolute(out)
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("%s.png" % name))
	print("  [img] %s" % out.path_join("%s.png" % name))


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % what)
	else:
		_fail += 1
		print("  ✗ %s" % what)


func _summary() -> void:
	print("\n═══ 通过 %d / 失败 %d ═══" % [_pass, _fail])
