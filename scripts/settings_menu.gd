extends CanvasLayer
## Esc 设置界面。
##
## ⚠️ 它**接管了 Esc**：原来 `player.gd` 里 Esc 只是来回切「鼠标捕获」，
##    现在改成「开 / 关设置界面」，打开时一并释放鼠标 + 暂停游戏。
##
## ⚠️ 为什么必须是 `PROCESS_MODE_ALWAYS`：菜单一打开就把游戏暂停了，
##    如果它自己也跟着暂停，`_input()` 就再也收不到 Esc —— **一开就关不掉**。
##    这也是为什么 Esc 的监听放在这里、而不是留在 player 那边：
##    player 在暂停时收不到输入，它没法负责「关掉菜单」。
##
## UI 全部**代码构建**（与 `hud.gd` 里 Boss 血条的做法一致），不写 .tscn。
##
## 皮肤是**可换的一整套**（见 `ui_skin.gd` 的 `SKINS`）：一个目录 + 一套配色 + 九宫格边距。
## 两套皮肤的文件名刻意保持一致（`panel.png` / `button*.png` / `font.ttf`），
## 所以「换皮肤」只是换目录，加载代码一行都不用动。

signal opened_changed(is_open: bool)

## 皮肤候选，**按优先级**排：第一套关键文件齐就用它，否则顺延。
##
## ⚠️ Sprout Lands 那套**不在版本库里** —— 它的授权原文写着
##    「You can not redistribute or resale, even if modified.」，
##    属于「可本地使用、不可再分发」，和角色模型 / 泼溅数据同一类处理：
##    本地放进 `assets/ui_sprout/` 就自动启用，克隆仓库的人没有它会回退到
##    仓库自带的 Kenney 那套（CC0，可分发）。详见 THIRD_PARTY.md。
## 皮肤数据（两套目录 + 配色 + 九宫格边距）搬去了 `ui_skin.gd`：
## HUD 的血条和 Boss 血条要用**同一套**配色，各留一份迟早会走散。
## 这里只留布局常量。

const FONT_SIZE := 16
const LABEL_WIDTH := 150.0
const VALUE_WIDTH := 84.0
const PANEL_WIDTH := 620.0
const ROW_GAP := 10
## 致谢面板：比设置面板宽一倍（每条素材要排下「作者 / 许可 / 来源 / 备注」四行）
const CREDITS_WIDTH := 900.0
## 滚动区高度。1600×900 的窗口下，这个高度不会让面板超出屏幕。
const CREDITS_HEIGHT := 520.0

## 操作说明 / 场地说明。
##
## 原来它是 HUD 底部的一个 `Label`（`HUD/Hint`），常驻画面、右端还会被右下角的
## 弹药面板压住。用户要求收进这里 —— **只在 Esc 设置打开时出现**，平时不占画面。
const HELP_TEXT := "WASD 移动　Shift 跑动　Ctrl 蹲行　空格 跳跃　右键 瞄准　左键 开火　R 换弹　滚轮 远近\n" \
	+ "7 名同伴会帮你打：小雪・优香・诺亚・小桃・小绿・柚子・凯伊\n" \
	+ "屋内是画室609，平台下是校园"

var is_open := false

var _root: Control
## 致谢面板（懒建：第一次点「致谢与素材署名」才生成）
var _credits_root: Control
var _credits_scroll: ScrollContainer
var _skin: Dictionary = {}
## key -> {"control": Control, "value": Label}
var _rows := {}


func _ready() -> void:
	layer = 10                       # 压在 HUD（默认层）之上
	process_mode = Node.PROCESS_MODE_ALWAYS
	_skin = _pick_skin()
	_build()
	_root.visible = false
	GameSettings.listen(_on_setting_changed)
	print("[SettingsMenu] 皮肤 = %s（%s）" % [_skin["label"], _skin["dir"]])


## 挑皮肤的判据在 `ui_skin.gd`：只查面板与字体，有这两样就能画出完整界面；
## 按钮缺 `button_hover.png` 时会退回 normal + 提亮（见 `UiSkin.button_style`）。
func _pick_skin() -> Dictionary:
	return UiSkin.pick()


func _tex(name: String) -> String:
	return UiSkin.tex(_skin, name)


# --- 开关 ---

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo or key.keycode != KEY_ESCAPE:
		return
	# 致谢面板开着时，Esc 先关它（不然一按就直接退出整个设置界面）
	if _credits_root != null and _credits_root.visible:
		close_credits()
		get_viewport().set_input_as_handled()
		return
	toggle()
	# 吃掉这次 Esc：不然它还会漏给别的节点（比如 player 的转向门控）
	get_viewport().set_input_as_handled()


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open() -> void:
	if is_open:
		return
	is_open = true
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	# 打一行日志：这个菜单会**暂停游戏 + 释放鼠标**，症状和「进游戏动不了」一模一样。
	# 有这行，下次在控制台就能一眼分辨「是我按了 Esc」还是别的原因。
	print("[SettingsMenu] 打开：已暂停 + 释放鼠标（再按 Esc 或点关闭恢复）")
	Sfx.play("ui_open")
	opened_changed.emit(true)


func close() -> void:
	if not is_open:
		return
	close_credits()
	is_open = false
	_root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().paused = false
	print("[SettingsMenu] 关闭：已恢复 + 重新捕获鼠标")
	Sfx.play("ui_close")
	opened_changed.emit(false)


# --- 构建 UI ---

func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = _make_theme()
	add_child(_root)

	# 压暗背景：既提示「游戏已暂停」，也让面板上的字更清楚
	var dim := ColorRect.new()
	dim.color = _skin["dim"]
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	# ⚠️ 面板要**不透明**：半透明会让背后的模型透上来压着文字
	#    （Sprout 的面板本身实心米色，Kenney 那张要靠这个 tint 压成深色）
	panel.add_theme_stylebox_override("panel",
		_make_style(_tex("panel.png"), _skin["panel_tint"]))
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", ROW_GAP)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "设置"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", _skin["text"])
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	# 三种控件：离散型给分段按钮、数值型给滑块、其余给开关 ——
	# 判据全在 GameSettings 里（CHOICES / RANGES）
	for key in GameSettings.keys():
		if GameSettings.is_choice(key):
			_add_choice(vbox, key)
		elif GameSettings.is_numeric(key):
			_add_slider(vbox, key)
		else:
			_add_check(vbox, key)

	vbox.add_child(HSeparator.new())

	# 操作说明（原来贴在 HUD 底部那两行）
	var help_title := Label.new()
	help_title.text = "操作"
	help_title.add_theme_font_size_override("font_size", 15)
	help_title.add_theme_color_override("font_color", _skin["text"])
	vbox.add_child(help_title)

	var help := Label.new()
	help.name = "Help"
	help.text = HELP_TEXT
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size.x = PANEL_WIDTH - 44.0
	help.add_theme_font_size_override("font_size", 13)
	help.add_theme_color_override("font_color", _skin["subtext"])
	vbox.add_child(help)

	vbox.add_child(HSeparator.new())

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 14)
	vbox.add_child(buttons)
	buttons.add_child(_make_button("致谢与素材署名", open_credits))
	buttons.add_child(_make_button("恢复默认", _on_reset))
	buttons.add_child(_make_button("关闭 (Esc)", close))

	var hint := Label.new()
	hint.text = "Esc 关闭并回到游戏"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", _skin["subtext"])
	hint.add_theme_font_size_override("font_size", 13)
	vbox.add_child(hint)


func _add_slider(parent: Node, key: String) -> void:
	var spec := GameSettings.spec(key)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var name_label := Label.new()
	name_label.text = GameSettings.label(key)
	name_label.custom_minimum_size.x = LABEL_WIDTH
	name_label.add_theme_color_override("font_color", _skin["text"])
	row.add_child(name_label)

	var slider := HSlider.new()
	slider.min_value = spec[0]
	slider.max_value = spec[1]
	slider.step = spec[2]
	slider.value = float(GameSettings.value(key))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.y = 26.0
	_style_slider(slider)
	row.add_child(slider)

	var value_label := Label.new()
	value_label.text = _format(key, slider.value)
	value_label.custom_minimum_size.x = VALUE_WIDTH
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_color_override("font_color", _skin["text"])
	row.add_child(value_label)

	slider.value_changed.connect(func(v: float) -> void:
		Sfx.play("ui_slider")
		GameSettings.set_value(key, v))
	_rows[key] = {"control": slider, "value": value_label}


func _add_check(parent: Node, key: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var name_label := Label.new()
	name_label.text = GameSettings.label(key)
	name_label.custom_minimum_size.x = LABEL_WIDTH
	name_label.add_theme_color_override("font_color", _skin["text"])
	row.add_child(name_label)

	var check := CheckButton.new()
	check.button_pressed = bool(GameSettings.value(key))
	# ⚠️ 不能 EXPAND_FILL：开关会跟着撑满整行，变成一条长绿条（第一版就是这样）。
	#    固定成一个小控件、靠右对齐即可。
	check.size_flags_horizontal = Control.SIZE_SHRINK_END
	check.custom_minimum_size = Vector2(76.0, 28.0)
	_style_check(check)
	row.add_child(check)

	var value_label := Label.new()
	value_label.text = _on_off(check.button_pressed)
	value_label.custom_minimum_size.x = VALUE_WIDTH
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_color_override("font_color", _skin["text"])
	row.add_child(value_label)

	check.toggled.connect(func(on: bool) -> void:
		Sfx.play("ui_toggle")
		GameSettings.set_value(key, on))
	_rows[key] = {"control": check, "value": value_label}


## 离散型（画质档位）：一排**分段按钮**，选中的那个用 `pressed` 皮肤。
##
## 为什么不用 OptionButton：那是个下拉弹窗，弹出来的列表不受本皮肤控制，
## 在像素风面板上会很突兀；分段按钮直接复用已有的按钮三态皮肤，两套皮肤都不用改。
##
## ⚠️ 用 `ButtonGroup`（`allow_unpress = false`）而不是自己管高亮：这样「同时只有一个
##    按下」由 Godot 保证，切换时也自动重画皮肤。
## ⚠️ 回调必须用 `bind(key, choice)` 而不是在循环里写 lambda —— GDScript 的 lambda
##    捕获的是变量本身，循环变量会被后续迭代改写，五个按钮会一起指向最后一个档位。
func _add_choice(parent: Node, key: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var name_label := Label.new()
	name_label.text = GameSettings.label(key)
	name_label.custom_minimum_size.x = LABEL_WIDTH
	name_label.add_theme_color_override("font_color", _skin["text"])
	row.add_child(name_label)

	var group := ButtonGroup.new()
	group.allow_unpress = false
	var seg := HBoxContainer.new()
	seg.add_theme_constant_override("separation", 4)
	seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(seg)

	var current := str(GameSettings.value(key))
	var buttons := {}
	for choice in GameSettings.choices(key):
		var b := _make_button(GameSettings.choice_label(key, choice), Callable())
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = (String(choice) == current)
		# 五个档位挤一行，按钮比原来的对话框按钮小一圈
		b.custom_minimum_size = Vector2(0.0, 32.0)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(_on_choice_pressed.bind(key, choice))
		seg.add_child(b)
		buttons[String(choice)] = b

	var value_label := Label.new()
	value_label.text = _choice_value_text(key)
	value_label.custom_minimum_size.x = VALUE_WIDTH
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_color_override("font_color", _skin["text"])
	row.add_child(value_label)

	_rows[key] = {"control": seg, "value": value_label, "buttons": buttons}


func _on_choice_pressed(key: String, choice: Variant) -> void:
	Sfx.play("ui_press")
	GameSettings.set_value(key, choice)


## 分段按钮右侧那列数值：画质档位显示成「1.00× · 60 fps」，比只重复一遍档位名有用
func _choice_value_text(key: String) -> String:
	if key == "render_quality":
		var q := GameSettings.quality_spec()
		var fps := int(q["fps"])
		return "%.2f× · %s" % [float(q["scale"]), "vsync" if fps <= 0 else "%d fps" % fps]
	return str(GameSettings.value(key))


func _make_button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(160.0, 40.0)
	b.add_theme_stylebox_override("normal", _button_style("normal"))
	b.add_theme_stylebox_override("hover", _button_style("hover"))
	b.add_theme_stylebox_override("pressed", _button_style("pressed"))
	# 像素风不需要焦点虚线框
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_size_override("font_size", FONT_SIZE)
	b.add_theme_color_override("font_color", _skin["text"])
	b.add_theme_color_override("font_hover_color", _skin["text"])
	b.add_theme_color_override("font_pressed_color", _skin["text"])
	# ⚠️ 空 Callable 不能 connect（会报 `at: connect`）——分段按钮自己接
	#    `_on_choice_pressed`，所以这里允许传空。
	if handler.is_valid():
		b.pressed.connect(func() -> void:
			Sfx.play("ui_press")
			handler.call())
	return b


## 按钮三态由 `UiSkin.button_style` 给，HUD 想画按钮时也是同一份实现。
func _button_style(kind: String) -> StyleBoxTexture:
	return UiSkin.button_style(_skin, kind)


## 滑块：**刻意不用九宫格素材** —— 槽只有约 8 px 高，而九宫格的边距有 8~12 px，
## 一拉伸就直接错位。这里改用与皮肤同色系的平色块，grabber 用代码生成的方块，
## 既统一配色又保持像素感（Godot 默认那颗圆点和整套 UI 不搭）。
func _style_slider(slider: HSlider) -> void:
	var trough := StyleBoxFlat.new()
	trough.bg_color = _skin["trough"]
	trough.border_color = _skin["text"]
	trough.border_color.a = 0.45
	trough.set_border_width_all(2)
	trough.set_corner_radius_all(0)
	slider.add_theme_stylebox_override("slider", trough)

	var fill := StyleBoxFlat.new()
	fill.bg_color = _skin["fill"]
	fill.set_corner_radius_all(0)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)

	var grab: Color = _skin["grabber"]
	slider.add_theme_icon_override("grabber", _solid_texture(12, grab))
	slider.add_theme_icon_override("grabber_highlight", _solid_texture(12, grab.lightened(0.15)))
	slider.add_theme_icon_override("grabber_disabled",
		_solid_texture(12, grab.darkened(0.35)))


## 开关（CheckButton）。默认那颗深色椭圆胶囊和米色面板对比太冲，改成
## 「凹槽 + 方块指示」：关=米色槽+深色方块，开=草绿槽+米白方块，都是像素块。
func _style_check(check: CheckButton) -> void:
	var off := StyleBoxFlat.new()
	off.bg_color = _skin["trough"]
	off.border_color = _skin["text"]
	off.border_color.a = 0.55
	off.set_border_width_all(2)
	off.set_corner_radius_all(0)
	check.add_theme_stylebox_override("normal", off)
	check.add_theme_stylebox_override("hover", off)

	var on := StyleBoxFlat.new()
	on.bg_color = _skin["fill"]
	on.border_color = _skin["text"]
	on.border_color.a = 0.55
	on.set_border_width_all(2)
	on.set_corner_radius_all(0)
	check.add_theme_stylebox_override("pressed", on)
	check.add_theme_stylebox_override("hover_pressed", on)

	check.add_theme_icon_override("checked", _solid_texture(14, _skin["grabber"]))
	check.add_theme_icon_override("unchecked", _solid_texture(14, _skin["subtext"]))
	check.add_theme_icon_override("checked_disabled",
		_solid_texture(14, _skin["grabber"].darkened(0.3)))
	check.add_theme_icon_override("unchecked_disabled",
		_solid_texture(14, _skin["subtext"].darkened(0.3)))


## 纯色小方块纹理（给 grabber 用）。像素风不需要渐变和圆角。
static func _solid_texture(size: int, color: Color) -> ImageTexture:
	return UiSkin.solid_texture(size, color)


func _make_style(tex_path: String, tint: Color) -> StyleBoxTexture:
	return UiSkin.make_style(_skin, tex_path, tint)


func _make_theme() -> Theme:
	return UiSkin.make_theme(_skin)


# --- 致谢与素材署名（用户要求：所有资源都要署名）---

## 面板内容全部来自 `credits.gd` 的 `ENTRIES` —— **不在这里抄第二份**，
## 否则「游戏里写的」和「仓库里写的」迟早会走散。
func open_credits() -> void:
	if _credits_root == null:
		_build_credits()
	_credits_root.visible = true
	if _credits_scroll != null:
		_credits_scroll.scroll_vertical = 0
	Sfx.play("ui_press")


func close_credits() -> void:
	if _credits_root != null:
		_credits_root.visible = false


func _build_credits() -> void:
	_credits_root = Control.new()
	_credits_root.name = "CreditsPanel"
	_credits_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_credits_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_credits_root.theme = _make_theme()
	add_child(_credits_root)

	var dim := ColorRect.new()
	dim.color = _skin["dim"]
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_credits_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_credits_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(CREDITS_WIDTH, 0.0)
	panel.add_theme_stylebox_override("panel",
		_make_style(_tex("panel.png"), _skin["panel_tint"]))
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "致谢与素材署名"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", _skin["text"])
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.custom_minimum_size = Vector2(0.0, CREDITS_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	_credits_scroll = scroll

	var body := Label.new()
	body.name = "Body"
	body.text = Credits.plain_text()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = CREDITS_WIDTH - 52.0
	body.add_theme_font_size_override("font_size", 13)
	body.add_theme_color_override("font_color", _skin["subtext"])
	scroll.add_child(body)

	vbox.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(row)
	row.add_child(_make_button("返回设置 (Esc)", close_credits))


# --- 控件 <-> 设置 同步 ---

## 任何来源的改动都同步回控件（最典型的是「恢复默认」）。
## ⚠️ 必须用 `set_value_no_signal` / `set_pressed_no_signal`：
##    普通 setter 会再发一次 value_changed → set_value → changed → 回到这里，
##    变成回环（值相同所以不会死循环，但会白写盘好几次）。
func _on_setting_changed(key: String, _value: Variant) -> void:
	if not _rows.has(key):
		return
	var row: Dictionary = _rows[key]
	var control: Control = row["control"]
	var value_label: Label = row["value"]
	if control is HSlider:
		var slider := control as HSlider
		slider.set_value_no_signal(float(GameSettings.value(key)))
		value_label.text = _format(key, slider.value)
	elif control is CheckButton:
		var check := control as CheckButton
		check.set_pressed_no_signal(bool(GameSettings.value(key)))
		value_label.text = _on_off(check.button_pressed)
	elif row.has("buttons"):
		# ⚠️ 必须 `set_pressed_no_signal`：普通 setter 会再发一次 pressed → set_value → 回到这里
		var buttons: Dictionary = row["buttons"]
		var current := str(GameSettings.value(key))
		for choice in buttons.keys():
			(buttons[choice] as Button).set_pressed_no_signal(String(choice) == current)
		value_label.text = _choice_value_text(key)


func _on_reset() -> void:
	GameSettings.reset_all()


func _on_off(on: bool) -> String:
	return "开" if on else "关"


func _format(key: String, v: float) -> String:
	match key:
		"mouse_sensitivity":
			return "%.4f" % v
		"master_volume":
			return "%d%%" % int(round(v * 100.0))
		_:
			return "%.0f" % v


## 当前用的皮肤目录（自检/调试用）
func skin_dir() -> String:
	return String(_skin.get("dir", ""))


func skin_label() -> String:
	return String(_skin.get("label", ""))
