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
## 皮肤是**可换的一整套**（见 `SKINS`）：一个目录 + 一套配色 + 九宫格边距。
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
const SKINS := [
	{
		"label": "Sprout Lands",
		"dir": "res://assets/ui_sprout/",
		"margin": 12.0,                   # 106×122 的面板，圆角比 Kenney 的大
		"panel_tint": Color(1, 1, 1, 1),  # 面板本身就是米色，不用再染
		"button_tint": Color(1, 1, 1, 1),
		"text": Color(0.34, 0.22, 0.12),  # 深棕字压在米色面板上
		"subtext": Color(0.46, 0.33, 0.20),
		"trough": Color(0.78, 0.66, 0.50),
		"fill": Color(0.53, 0.74, 0.42),  # 草绿，跟素材的农场色调一套
		"grabber": Color(0.99, 0.94, 0.83),
		"dim": Color(0.07, 0.06, 0.05, 0.55),
	},
	{
		"label": "Kenney（内置）",
		"dir": "res://assets/ui/",
		"margin": 8.0,                    # 32×32 的像素块，边框约 6 px
		"panel_tint": Color(0.17, 0.20, 0.26, 1.0),
		"button_tint": Color(0.42, 0.47, 0.56),
		"text": Color(0.93, 0.95, 1.0),
		"subtext": Color(0.68, 0.73, 0.83),
		"trough": Color(0.10, 0.12, 0.16),
		"fill": Color(0.52, 0.72, 0.95),
		"grabber": Color(0.95, 0.96, 1.0),
		"dim": Color(0.04, 0.05, 0.08, 0.62),
	},
]

const FONT_SIZE := 16
const LABEL_WIDTH := 150.0
const VALUE_WIDTH := 84.0
const PANEL_WIDTH := 620.0
const ROW_GAP := 10

var is_open := false

var _root: Control
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


## 选第一套**关键文件齐**的皮肤。判据只查面板与字体：有这两样就能画出完整界面；
## 按钮缺 `button_hover.png` 时会退回 normal + 提亮（见 `_button_style`）。
func _pick_skin() -> Dictionary:
	for skin in SKINS:
		var dir: String = skin["dir"]
		if ResourceLoader.exists(dir + "panel.png") \
				and ResourceLoader.exists(dir + "font.ttf"):
			return skin
	push_warning("[SettingsMenu] 两套皮肤的素材都没找到，界面会是空的")
	return SKINS[SKINS.size() - 1]


func _tex(name: String) -> String:
	return String(_skin["dir"]) + name


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
	# 打一行日志：这个菜单会**暂停游戏 + 释放鼠标**，症状和「进游戏动不了」一模一样。
	# 有这行，下次在控制台就能一眼分辨「是我按了 Esc」还是别的原因。
	print("[SettingsMenu] 打开：已暂停 + 释放鼠标（再按 Esc 或点关闭恢复）")
	opened_changed.emit(true)


func close() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().paused = false
	print("[SettingsMenu] 关闭：已恢复 + 重新捕获鼠标")
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

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 14)
	vbox.add_child(buttons)
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
		b.pressed.connect(handler)
	return b


## 按钮三态。`button_hover.png` 是**可选**的：没有就用 normal 的图 + 提亮 tint，
## 这样换一套只给 normal/pressed 的皮肤（比如这里裁出来的 Sprout）也不用改代码。
func _button_style(kind: String) -> StyleBoxTexture:
	var base: Color = _skin["button_tint"]
	match kind:
		"hover":
			if ResourceLoader.exists(_tex("button_hover.png")):
				return _make_style(_tex("button_hover.png"), base)
			return _make_style(_tex("button.png"), Color(
				minf(base.r * 1.25, 1.0), minf(base.g * 1.25, 1.0),
				minf(base.b * 1.25, 1.0), base.a))
		"pressed":
			if ResourceLoader.exists(_tex("button_pressed.png")):
				return _make_style(_tex("button_pressed.png"), base)
			return _make_style(_tex("button.png"), Color(
				base.r * 0.8, base.g * 0.8, base.b * 0.8, base.a))
		_:
			return _make_style(_tex("button.png"), base)


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
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


func _make_style(tex_path: String, tint: Color) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load(tex_path)
	var m: float = _skin["margin"]
	sb.texture_margin_left = m
	sb.texture_margin_right = m
	sb.texture_margin_top = m
	sb.texture_margin_bottom = m
	sb.modulate_color = tint
	return sb


func _make_theme() -> Theme:
	var theme := Theme.new()
	var font := load(_tex("font.ttf")) as FontFile
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
