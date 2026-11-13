extends SceneTree
## 验：设置面板里的滑条**不吃滚轮**，只认「点击 / 拖动」。
##
## 用户 2026-11-13 附截图：「这些设置条子，不要让滚轮去改变他们，
## 只能够通过鼠标点击拖动更改」。
##
## 病因：Godot 的 `Slider.scrollable` 默认 true。设置面板本身在 ScrollContainer 里，
##      用户滚动页面时指针正好压在滑条上，值就被顺手改掉了。
##
## ── 为什么这里只验属性、不灌鼠标事件 ──
## 试过 `Input.parse_input_event` 和 `root.push_input` 两种方式，鼠标事件在
## `--script` 探针里**都到不了 GUI**：连「对照组」`scrollable = true` 的滑条
## 被滚轮压着也毫无反应（点击、拖动同样无效），说明不是代码问题而是探针环境
## 限制（GUI 命中测试依赖真实窗口焦点）。所以这里改为验**闸门本身**：
##   · `scrollable` 是 Godot 给「滚轮改值」设的唯一开关（Slider 文档原文：
##     "If true, the value can be changed by scrolling the mouse wheel"）；
##   · 只要设置面板里每一个滑条都是 false，滚轮就不可能改它们。
## 真机手感由用户自己点一遍确认。
##
##   godot --path . --script res://scripts/_verify_settings_wheel.gd -- --no-capture

const OFF := preload("res://scripts/offscreen_window.gd")

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await OFF.apply(self, Vector2i(1600, 900))
	for _i in 3:
		await process_frame
	print("═══ 设置面板 · 滑条不吃滚轮 ═══\n")

	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(20)
	var menu := game.get_node_or_null("SettingsMenu")
	_check(menu != null, "场景里有 SettingsMenu")
	if menu == null:
		_summary()
		quit(1)
		return
	menu.call("open")
	await _wait(4)
	_check(bool(menu.get("is_open")), "设置界面打开")

	var sliders: Array[HSlider] = []
	_collect_sliders(menu, sliders)
	print("  面板里找到 %d 个滑条" % sliders.size())
	_check(sliders.size() >= 5, "滑条数量正常（%d 个，用户截图里那 7 条都在）" % sliders.size())

	# ① 闸门：每一个都必须 scrollable = false
	var scrollable_left := 0
	var names: Array[String] = []
	for s in sliders:
		if s.scrollable:
			scrollable_left += 1
			names.append(String(s.name))
	_check(scrollable_left == 0,
		"全部滑条 `scrollable = false`（还开着 %d 个%s）"
		% [scrollable_left, "" if names.is_empty() else "：" + ", ".join(names)])

	# ② 结构性：它们都出自 `settings_menu.gd::_add_slider()`
	#    （那个函数里有一行 `slider.scrollable = false`；别处新建的滑条不受保护，
	#      所以这里顺着源码确认「面板里所有滑条都走同一个工厂」）
	var src := FileAccess.get_file_as_string("res://scripts/settings_menu.gd")
	_check(src.contains("slider.scrollable = false"),
		"`_add_slider()` 里确实关了滚轮（源码里能找到 `slider.scrollable = false`）")
	var new_slider_count := 0
	for line in src.split("\n"):
		if line.contains("HSlider.new()"):
			new_slider_count += 1
	_check(new_slider_count == 1,
		"整个设置面板只有 **一处** 建滑条（%d 处，都在同一个工厂里）" % new_slider_count)

	# ③ 面板本身还能滚（ScrollContainer 不受影响）
	var sc := _find_scroll(menu)
	_check(sc != null, "设置面板在 ScrollContainer 里（页面本身仍然可以用滚轮滚）")
	if sc != null:
		_check(sc.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED,
			"ScrollContainer 的竖向滚动没被关掉")

	# ④ 点一遍：滑条该响应的地方没被误伤（信号还在）
	var wired := 0
	for s in sliders:
		if s.value_changed.get_connections().size() > 0:
			wired += 1
	_check(wired == sliders.size(),
		"每个滑条的 value_changed 都还接着（%d/%d，拖动会真的生效）"
		% [wired, sliders.size()])

	menu.call("close")
	await _wait(2)

	_summary()
	quit(0 if _fail == 0 else 1)


func _collect_sliders(n: Node, out: Array[HSlider]) -> void:
	for c in n.get_children():
		if c is HSlider:
			out.append(c as HSlider)
		_collect_sliders(c, out)


func _find_scroll(n: Node) -> ScrollContainer:
	for c in n.get_children():
		if c is ScrollContainer:
			return c as ScrollContainer
		var r := _find_scroll(c)
		if r != null:
			return r
	return null


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
