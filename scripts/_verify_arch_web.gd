extends SceneTree
## 验：终端敲 `archlinux` → 打开**能点、能滚、能前进后退**的假浏览器。
##
## 用户 2026-11-13：「https://archlinux.org/ 可以加浏览器吗…」→
##              「可以滚动点开页面吗，像真正的网站一样」。
##
## 页面是画出来的（Godot 没 webview、这台机器不联网），但**交互照真浏览器做**：
##   · 导航栏 / 新闻标题 / 包名 / Quick links / Download 全是可点链接；
##   · 前进 / 后退按钮维护一条页面历史；
##   · 地址栏跟着页面变；滚轮 / 方向键滚页面。
##
## ⚠️ 探针不靠 Godot 的 GUI 管线（SubViewport 里送不到）：直接读页面自己维护的
##    `_links` 命中表，把鼠标事件按画布坐标喂给 `feed()`。
##
##   godot --path . --script res://scripts/_verify_arch_web.gd -- --no-capture

const OFF := preload("res://scripts/offscreen_window.gd")

var _pass := 0
var _fail := 0
var _web: ArchWeb


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await OFF.apply(self, Vector2i(1280, 720))
	for _i in 3:
		await process_frame
	print("═══ 假浏览器 · 能点开的多页站点 ═══\n")

	var comp := HutComputer.new()
	comp.name = "HutComputer"
	root.add_child(comp)
	await _wait(4)
	comp.call("use_for_test")
	await _wait(4)

	var term: ArchTerminal = comp.get("terminal")
	_web = comp.get("web")
	_check(term != null, "拿到终端")
	_check(_web != null, "建出了假浏览器")
	if term == null or _web == null:
		_summary()
		quit(1)
		return
	_check(not _web.visible, "开始时浏览器是关着的")

	# 命令表 / 别名
	var in_table := false
	for c in ArchTerminal.COMMANDS:
		if String(c["name"]) == "archlinux":
			in_table = true
	_check(in_table, "`archlinux` 已登记进 COMMANDS")
	_check(term._canonical("arch") == "archlinux", "别名 `arch` 解析到 archlinux")

	# ── 打开 ──
	_cmd(term, "archlinux")
	await _wait(6)
	await _draw_frame()
	_check(_web.visible, "敲 archlinux 之后浏览器打开")
	_check(_web.page_name() == "home", "落在首页（`%s`）" % _web.page_name())
	_check(_web.address() == "https://archlinux.org/",
		"地址栏是 archlinux.org（`%s`）" % _web.address())
	_check(bool(term.visible), "终端没被藏起来（浏览器盖在它上面）")

	# ── 点链接：导航空 / 包名 / 回退 ──
	_check(_click_link("packages"), "点导航栏 Packages")
	await _wait(2)
	_check(_web.page_name() == "packages", "跳到 Packages 页（`%s`）" % _web.page_name())
	_check(_web.address().ends_with("/packages/"),
		"地址栏跟着变（`%s`）" % _web.address())
	_check(_web.can_back(), "这时可以后退")

	await _draw_frame()
	_check(_click_link("pkg:pacman"), "点包名 pacman")
	await _wait(2)
	_check(_web.page_name() == "pkg:pacman", "进了包详情页（`%s`）" % _web.page_name())
	await _draw_frame()
	var shot_pkg := true
	if shot_pkg:
		await _shot("03_package_page")

	# 后退按钮（点外壳上的 `<`）
	_check(_click_chrome("back"), "点后退按钮")
	await _wait(2)
	_check(_web.page_name() == "packages", "退回 Packages（`%s`）" % _web.page_name())
	_check(_web.can_forward(), "这时可以前进")
	_check(_click_chrome("forward"), "点前进按钮")
	await _wait(2)
	_check(_web.page_name() == "pkg:pacman", "又回到包详情（`%s`）" % _web.page_name())

	# ── 首页那条新闻也能点开 ──
	_cmd(term, "archlinux")
	await _wait(4)
	await _draw_frame()
	_check(_web.page_name() == "home", "再敲一次回到首页")
	_check(_click_link("news:1"), "点首页第二条新闻")
	await _wait(2)
	_check(_web.page_name() == "news:1", "新闻详情打开了（`%s`）" % _web.page_name())
	await _draw_frame()
	_check(_click_link("news"), "点「<- back to news」")
	await _wait(2)
	_check(_web.page_name() == "news", "退回新闻列表（`%s`）" % _web.page_name())

	# Download 也点得开（回首页再点那个蓝色按钮）
	_cmd(term, "archlinux")
	await _wait(4)
	await _draw_frame()
	_check(_web.page_name() == "home", "回首页")
	_check(_click_link("download"), "点首页的 Download 按钮")
	await _wait(2)
	await _draw_frame()
	_check(_web.page_name() == "download", "Download 页打开了（`%s`）" % _web.page_name())
	await _shot("02_download")

	# ── 悬停高亮 ──
	_cmd(term, "archlinux")
	await _wait(4)
	await _draw_frame()
	var hit := _link_rect("wiki")
	if hit.size != Vector2.ZERO:
		_web.feed(_motion(hit.get_center() + Vector2(0, ArchWeb.CHROME_H)))
		await _wait(1)
		_check(String(_web.get("_hover")) == "wiki",
			"鼠标悬停到链接上会高亮（_hover=`%s`）" % String(_web.get("_hover")))
	else:
		_check(false, "能在命中表里找到 wiki 链接")

	# ── 滚动（内容比一屏长）──
	_check(float(_web.get("_max_scroll")) > 0.0,
		"页面比一屏长、可以滚（max_scroll=%.0f）" % float(_web.get("_max_scroll")))
	var s0 := _web.scroll_offset()
	for _i in 3:
		_web.feed(_wheel(MOUSE_BUTTON_WHEEL_DOWN))
	await _wait(2)
	_check(_web.scroll_offset() > s0, "滚轮能往下翻（%.0f → %.0f）"
		% [s0, _web.scroll_offset()])
	for _i in 30:
		_web.feed(_wheel(MOUSE_BUTTON_WHEEL_UP))
	await _wait(2)
	_check(is_equal_approx(_web.scroll_offset(), 0.0), "一直往上滚停在 0")

	await _shot("01_archlinux_org")

	# ── Esc 退回终端 / 合电脑收掉 ──
	var k := InputEventKey.new()
	k.pressed = true
	k.keycode = KEY_ESCAPE
	k.physical_keycode = KEY_ESCAPE
	comp.call("_input", k)
	await _wait(4)
	_check(not _web.visible, "Esc 关掉浏览器")
	_check(bool(term.visible), "终端还在（回到 shell）")

	_cmd(term, "archlinux")
	await _wait(4)
	_check(_web.visible, "再敲一次还能打开")
	comp.call("close_for_test")
	await _wait(2)
	_check(not _web.visible, "合上电脑时浏览器一起收掉")

	_summary()
	quit(0 if _fail == 0 else 1)


# ── 工具 ──────────────────────────────────────────────────────────────────────

## 等一帧真正画出来（`_links` 是在 `_draw()` 里建的）
func _draw_frame() -> void:
	_web.queue_redraw()
	await RenderingServer.frame_post_draw
	await process_frame


func _link_rect(target: String) -> Rect2:
	for it in (_web.get("_links") as Array):
		if String(it["target"]) == target:
			return it["rect"] as Rect2
	return Rect2()


## 内容坐标 → 屏幕坐标（去掉外壳、加回滚动）
func _content_to_screen(r: Rect2) -> Rect2:
	return Rect2(r.position + Vector2(0, ArchWeb.CHROME_H - _web.scroll_offset()),
		r.size)


func _click_link(target: String) -> bool:
	var r := _link_rect(target)
	if r.size == Vector2.ZERO:
		return false
	var c := _content_to_screen(r).get_center()
	_web.feed(_motion(c))
	_web.feed(_mb(MOUSE_BUTTON_LEFT, c))
	return true


func _click_chrome(target: String) -> bool:
	for it in (_web.get("_chrome_links") as Array):
		if String(it["target"]) == target:
			var c := (it["rect"] as Rect2).get_center()
			_web.feed(_motion(c))
			_web.feed(_mb(MOUSE_BUTTON_LEFT, c))
			return true
	return false


func _mb(button: MouseButton, pos: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = true
	e.position = pos
	e.global_position = pos
	return e


func _motion(pos: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	return e


func _wheel(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = true
	return e


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
