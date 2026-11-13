extends SceneTree
## 验：终端敲 `archlinux` → 打开**假浏览器**，显示画出来的 archlinux.org 首页。
##
## 用户 2026-11-13：「https://archlinux.org/ 可以加浏览器吗，输入 ARCHLINUX
## 进入浏览器页面的这个网站」。
##
## Godot 没有内置 webview、这台机器也不联网，所以页面是**画出来的**（见
## `scripts/arch_web.gd`）。这个探针验的是「能不能进得去、能不能滚、能不能退回来」，
## 另外出图给人眼确认版面。
##
##   godot --path . --script res://scripts/_verify_arch_web.gd -- --no-capture

const OFF := preload("res://scripts/offscreen_window.gd")

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await OFF.apply(self, Vector2i(1280, 720))
	for _i in 3:
		await process_frame
	print("═══ 假浏览器 · archlinux.org 验收 ═══\n")

	var comp := HutComputer.new()
	comp.name = "HutComputer"
	root.add_child(comp)
	await _wait(4)
	comp.call("use_for_test")
	await _wait(4)

	var term: ArchTerminal = comp.get("terminal")
	var web: ArchWeb = comp.get("web")
	_check(term != null, "拿到终端")
	_check(web != null, "建出了假浏览器")
	if term == null or web == null:
		_summary()
		quit(1)
		return
	_check(not web.visible, "开始时浏览器是关着的")

	# 命令表里有它（help 也能看到）
	var in_table := false
	for c in ArchTerminal.COMMANDS:
		if String(c["name"]) == "archlinux":
			in_table = true
	_check(in_table, "`archlinux` 已经登记进 COMMANDS（help 会列出来）")
	_check(term._canonical("arch") == "archlinux", "别名 `arch` 解析到 archlinux")
	_check(term._canonical("www") == "archlinux", "别名 `www` 解析到 archlinux")

	# ── 敲 archlinux ──
	_cmd(term, "archlinux")
	await _wait(6)
	_check(web.visible, "敲 archlinux 之后浏览器打开")
	_check(web.page_name() == "archlinux", "页面是 archlinux.org（`%s`）" % web.page_name())
	_check(bool(term.visible), "终端没被藏起来（浏览器盖在它上面）")

	# 页面画得出来（渲染一帧再量）
	await RenderingServer.frame_post_draw
	await _wait(2)
	var max_scroll := float(web.get("_max_scroll"))
	_check(max_scroll > 0.0, "页面比一屏长、可以滚（max_scroll=%.0f）" % max_scroll)

	var s0 := web.scroll_offset()
	for _i in 3:
		web.feed(_wheel(MOUSE_BUTTON_WHEEL_DOWN))
	await _wait(2)
	var s1 := web.scroll_offset()
	_check(s1 > s0, "滚轮往下能翻页面（%.0f → %.0f）" % [s0, s1])
	web.feed(_wheel(MOUSE_BUTTON_WHEEL_UP))
	await _wait(2)
	_check(web.scroll_offset() < s1, "滚轮往上能翻回来（%.0f）" % web.scroll_offset())

	# 上翻到底 / 下翻到底都不越界
	for _i in 30:
		web.feed(_wheel(MOUSE_BUTTON_WHEEL_UP))
	await _wait(2)
	_check(is_equal_approx(web.scroll_offset(), 0.0), "一直往上滚停在 0")
	for _i in 60:
		web.feed(_wheel(MOUSE_BUTTON_WHEEL_DOWN))
	await _wait(2)
	_check(is_equal_approx(web.scroll_offset(), max_scroll), "一直往下滚停在底部")

	# 回顶部出一张图给人眼确认
	for _i in 60:
		web.feed(_wheel(MOUSE_BUTTON_WHEEL_UP))
	await _wait(2)
	await _shot("01_archlinux_org")
	# 滚一半再一张（看 News / Quick links 那一段）
	for _i in 3:
		web.feed(_wheel(MOUSE_BUTTON_WHEEL_DOWN))
	await _wait(2)
	await _shot("02_archlinux_scrolled")

	# ── Esc 退回终端 ──
	var k := InputEventKey.new()
	k.pressed = true
	k.keycode = KEY_ESCAPE
	k.physical_keycode = KEY_ESCAPE
	comp.call("_input", k)
	await _wait(4)
	_check(not web.visible, "Esc 关掉浏览器")
	_check(bool(term.visible), "终端还在（回到 shell）")

	# 关电脑时也要把它收掉，别下次一打开就看到网页
	_cmd(term, "archlinux")
	await _wait(4)
	_check(web.visible, "再敲一次还能打开")
	comp.call("close_for_test")
	await _wait(2)
	_check(not web.visible, "合上电脑时浏览器一起收掉")

	_summary()
	quit(0 if _fail == 0 else 1)


## 往终端里敲一条命令（打字 + 回车）
func _cmd(term: ArchTerminal, s: String) -> void:
	for ch in s:
		var e := InputEventKey.new()
		e.pressed = true
		var up := ch.to_upper()
		e.keycode = KEY_A + (up.unicode_at(0) - 65) if up.unicode_at(0) >= 65 \
			and up.unicode_at(0) <= 90 else KEY_SPACE
		e.physical_keycode = e.keycode
		e.unicode = ch.unicode_at(0)
		term.feed(e)
	var enter := InputEventKey.new()
	enter.pressed = true
	enter.keycode = KEY_ENTER
	enter.physical_keycode = KEY_ENTER
	term.feed(enter)


func _wheel(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = true
	return e


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(name: String) -> void:
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_archweb")
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
