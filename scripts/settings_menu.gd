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
## 皮肤集中在 `assets/ui/`：Kenney「UI Pack - Pixel Adventure」的九宫格切片（CC0）
## + FusionPixel 像素字体（OFL）。**想整体换风格，替换那几张图和字体就够了** ——
## Sprout Lands 的素材到位后，换的就是这一处。

signal opened_changed(is_open: bool)

const UI_DIR := "res://assets/ui/"
const TEX_PANEL := UI_DIR + "tile_panel.png"
const TEX_BUTTON := UI_DIR + "tile_button.png"
const TEX_BUTTON_HOVER := UI_DIR + "tile_button_hover.png"
const TEX_BUTTON_PRESSED := UI_DIR + "tile_button_pressed.png"
const FONT_PATH := UI_DIR + "font_pixel.ttf"

## 九宫格边距。素材是 32×32 的像素块、边框约 6 px，取 8 更稳（不会被拉花）
const NINE_MARGIN := 8.0
const FONT_SIZE := 16
const LABEL_WIDTH := 150.0
const VALUE_WIDTH := 84.0
const PANEL_WIDTH := 620.0
const ROW_GAP := 10

var is_open := false

var _root: Control
## key -> {"control": Control, "value": Label}
var _rows := {}


func _ready() -> void:
	layer = 10                       # 压在 HUD（默认层）之上
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false
	GameSettings.listen(_on_setting_changed)


# --- 开关 ---

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo or key.keycode != KEY_ESCAPE:
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
	opened_changed.emit(true)


func close() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().paused = false
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
	dim.color = Color(0.04, 0.05, 0.08, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	# ⚠️ 面板要**接近不透明**：第一版用了 0.96，结果背后的模型和红方块透上来压着文字，
	#    截图里能清楚看到后面的同伴 —— 面板是拿来读字的，不是拿来透景的。
	panel.add_theme_stylebox_override("panel",
		_make_style(TEX_PANEL, Color(0.17, 0.20, 0.26, 1.0)))
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
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	# 数值型给滑块、布尔型给开关 —— 判据就是 GameSettings 里有没有 RANGES
	for key in GameSettings.keys():
		if GameSettings.is_numeric(key):
			_add_slider(vbox, key)
		else:
			_add_check(vbox, key)

	vbox.add_child(HSeparator.new())

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 14)
	vbox.add_child(buttons)
	buttons.add_child(_make_button("恢复默认", _on_reset))
	buttons.add_child(_make_button("关闭 (Esc)", close))

	var hint := Label.new()
	hint.text = "Esc 关闭并回到游戏"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1, 1, 1, 0.55)
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
	row.add_child(value_label)

	slider.value_changed.connect(func(v: float) -> void:
		GameSettings.set_value(key, v))
	_rows[key] = {"control": slider, "value": value_label}


func _add_check(parent: Node, key: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var name_label := Label.new()
	name_label.text = GameSettings.label(key)
	name_label.custom_minimum_size.x = LABEL_WIDTH
	row.add_child(name_label)

	var check := CheckButton.new()
	check.button_pressed = bool(GameSettings.value(key))
	check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(check)

	var value_label := Label.new()
	value_label.text = _on_off(check.button_pressed)
	value_label.custom_minimum_size.x = VALUE_WIDTH
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)

	check.toggled.connect(func(on: bool) -> void:
		GameSettings.set_value(key, on))
	_rows[key] = {"control": check, "value": value_label}


func _make_button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(160.0, 40.0)
	b.add_theme_stylebox_override("normal", _make_style(TEX_BUTTON, Color(0.42, 0.47, 0.56)))
	b.add_theme_stylebox_override("hover", _make_style(TEX_BUTTON_HOVER, Color(0.62, 0.68, 0.78)))
	b.add_theme_stylebox_override("pressed", _make_style(TEX_BUTTON_PRESSED, Color(0.34, 0.38, 0.46)))
	# 像素风不需要焦点虚线框
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_size_override("font_size", FONT_SIZE)
	b.pressed.connect(handler)
	return b


## 滑块：**刻意不用九宫格素材** —— 槽只有约 8 px 高，而九宫格的边距是 8 px，
## 一拉伸就直接错位。这里换成与面板同色系的平色块，grabber 用代码生成的方块，
## 既统一配色又保持像素感（Godot 默认那颗圆点和整套 UI 不搭）。
func _style_slider(slider: HSlider) -> void:
	var trough := StyleBoxFlat.new()
	trough.bg_color = Color(0.10, 0.12, 0.16)
	trough.border_color = Color(0.34, 0.39, 0.47)
	trough.set_border_width_all(2)
	trough.set_corner_radius_all(0)
	slider.add_theme_stylebox_override("slider", trough)

	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.52, 0.72, 0.95)
	fill.set_corner_radius_all(0)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)

	slider.add_theme_icon_override("grabber", _solid_texture(12, Color(0.95, 0.96, 1.0)))
	slider.add_theme_icon_override("grabber_highlight", _solid_texture(12, Color.WHITE))
	slider.add_theme_icon_override("grabber_disabled",
		_solid_texture(12, Color(0.45, 0.48, 0.54)))


## 纯色小方块纹理（给 grabber 用）。像素风不需要渐变和圆角。
static func _solid_texture(size: int, color: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


func _make_style(tex_path: String, tint: Color) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load(tex_path)
	sb.texture_margin_left = NINE_MARGIN
	sb.texture_margin_right = NINE_MARGIN
	sb.texture_margin_top = NINE_MARGIN
	sb.texture_margin_bottom = NINE_MARGIN
	sb.modulate_color = tint
	return sb


func _make_theme() -> Theme:
	var theme := Theme.new()
	var font := load(FONT_PATH) as FontFile
	if font != null:
		theme.default_font = font
	theme.default_font_size = FONT_SIZE
	return theme


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
