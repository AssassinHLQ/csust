extends SceneTree
## 验收：终端 `help` 能不能列出**所有**可用命令，以及别名 / 未知命令 / 滚屏。
##
## 用户 2026-11-12：「现在写 help 命令，输入可以弹出所有可以用的命令」。
##
## ⚠️ 独立跑，不加载 game.tscn —— `game.gd:105` preload 的 `title_intro.gd`
##    当时被另一个会话改到一半（缩进语法错），任何加载 game.tscn 的探针都会连带失败。
##    这里直接实例化 `ArchTerminal`（尺寸照抄屏幕 SubViewport 的 1280×720）。
##
##   godot --path . --script res://scripts/_verify_terminal_help.gd -- --no-capture

const OFF := preload("res://scripts/offscreen_window.gd")
const Terminal := preload("res://scripts/arch_terminal.gd")
const VP := Vector2i(1280, 720)

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
	_check(t2.contains("ARONA shows up"), "help arona 给出了那一条的说明")

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

	# ── ⑩ 回滚：历史要留得住、滚轮要能翻、打字要能跳回最新 ──
	#    用户 2026-11-13：「怎么不能滚轮滑动」—— 之前超出 ROWS 就从顶上删，
	#    等于没有历史。现在 `_text` 留 HISTORY_MAX 行，滚轮 / PgUp / PgDn 翻。
	var hist := int(_term.call("history_count"))
	_check(hist > Terminal.ROWS,
		"历史比一屏长（%d 行 > ROWS %d）—— 有东西可滚" % [hist, Terminal.ROWS])
	var bottom := int(_term.call("_max_view_top"))
	_check(int(_term.call("view_top")) == bottom, "默认贴着最新内容（view_top = %d）" % bottom)

	# 滚轮往上 = 看更旧的
	_wheel(MOUSE_BUTTON_WHEEL_UP, 3)
	var up1 := int(_term.call("view_top"))
	_check(up1 < bottom, "滚轮上翻生效（%d → %d）" % [bottom, up1])

	# 滚轮往下 = 回新
	_wheel(MOUSE_BUTTON_WHEEL_DOWN, 1)
	var down1 := int(_term.call("view_top"))
	_check(down1 > up1, "滚轮下翻生效（%d → %d）" % [up1, down1])

	# 往上翻到底 = 0，且不会变成负数
	_wheel(MOUSE_BUTTON_WHEEL_UP, 120)
	_check(int(_term.call("view_top")) == 0, "一直往上翻停在 0（不越界）")

	# 往下翻到底 = 贴回最新，且不会超出
	_wheel(MOUSE_BUTTON_WHEEL_DOWN, 60)
	_check(int(_term.call("view_top")) == int(_term.call("_max_view_top")),
		"一直往下翻回到底（不越界）")

	# 翻上去之后打字 = 自动跳回最新（不然字会写进屏幕外那行）
	_wheel(MOUSE_BUTTON_WHEEL_UP, 5)
	var bottom2 := int(_term.call("_max_view_top"))
	var scrolled := int(_term.call("view_top"))
	_check(scrolled < bottom2, "已上翻（%d < %d）" % [scrolled, bottom2])
	await _type("ls")
	# ⚠️ 提交一行后历史会 +1，所以重新算「贴底」应该是多少，别拿旧值比
	_check(int(_term.call("view_top")) == int(_term.call("_max_view_top")),
		"打字后自动跳回最新")
	# 刚敲的这条要真的落在提示符那行上（不是被吞掉）
	var landed := false
	for line in String(_term.call("screen_text")).split("\n"):
		if line.begins_with("alice@arisu:") and line.contains("ls"):
			landed = true
	_check(landed, "输入确实落在了提示符那行（`alice@arisu:~$ls`）")

	await _shot("help_scrolled")
	_summary()
	quit(0)


## 发一个鼠标滚轮事件（`feed()` 认 `InputEventMouseButton`）
func _wheel(button: MouseButton, times: int) -> void:
	for _i in times:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.pressed = true
		_term.feed(e)


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
