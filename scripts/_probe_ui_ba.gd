extends SceneTree
## 出图：**BA（蔚蓝档案）皮肤**的全套界面长什么样。
##
##   _tools/run_shot.sh res://scripts/_probe_ui_ba.gd
##
## 出四张：
##   01_gallery   —— 皮肤样式总览：面板 / 按钮三态 / 名牌 / 数值片 / 剧情框 / 量条
##   02_dialogue  —— 对话框 + 选项面板
##   03_hud       —— 游戏内 HUD（血量面板 / 弹药面板 / COST 条）
##   04_settings  —— Esc 设置菜单
##
## ⚠️ 不抢前台（AGENTS.md 硬要求）：`OffWin.apply()` 取消最大化 + 挪出屏幕，
##    命令行还要带 `--no-capture`（`_tools/run_shot.sh` 已写死）。

const OffWin := preload("res://scripts/offscreen_window.gd")
const UiSkinRef := preload("res://scripts/ui_skin.gd")
const CostGauge := preload("res://scripts/cost_gauge.gd")
const HUD_SCENE := "res://scenes/hud.tscn"

const OUT_NAME := "_ui_ba"

var _out := ""
var _n := 0
var _skin := {}
var _font: Font = null
var _probe: Control = null
## 每一节新建一层；清理时**整层 free**，不要像第一版那样去 free `_probe` 的兄弟
## （那样会把 `_probe` 自己也 queue_free 掉，下一节再调它就崩 —— 实测卡在 HUD 那步）
var _layers: Array[Node] = []


func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	_n += 1
	var p := "%s/%02d_%s.png" % [_out, _n, name]
	var err := root.get_texture().get_image().save_png(p)
	print("      出图 %s → %s" % ["OK" if err == OK else "失败(%d)" % err, p])


## 一张干净的舞台：深色渐变底 + 返回根 Control
func _stage() -> Control:
	var layer := CanvasLayer.new()
	layer.layer = 0
	root.add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.14, 0.20, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bg)
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(c)
	_layers.append(layer)
	return c


## 一块带边框的占位（用来「看见」样式盒本身）
func _swatch(parent: Control, style: StyleBox, pos: Vector2, size: Vector2,
		label: String) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", style)
	parent.add_child(p)
	if not label.is_empty():
		var l := Label.new()
		l.text = label
		l.position = Vector2(pos.x, pos.y - 22.0)
		if _font != null:
			l.add_theme_font_override("font", _font)
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_color_override("font_color", Color(0.72, 0.82, 0.92))
		parent.add_child(l)
	return p


## 清掉之前所有舞台（**整层 free**，见 `_layers` 上面那条注释）
func _clean() -> void:
	for l in _layers:
		if is_instance_valid(l):
			l.queue_free()
	_layers.clear()
	_probe = null


func _run() -> void:
	root.size = Vector2i(1280, 720)
	await OffWin.apply(self, Vector2i(1280, 720))
	_out = ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_NAME)
	DirAccess.make_dir_recursive_absolute(_out)

	_skin = UiSkinRef.pick()
	_font = UiSkinRef.ui_font()
	print("[probe] 皮肤 = %s（dir=「%s」procedural=%s）"
		% [_skin["label"], _skin["dir"], str(UiSkinRef.is_procedural(_skin))])

	var safe: Array = OffWin.is_safe()
	print("[probe] 窗口安全检查：%s（%s）" % ["通过" if safe[0] else "⚠️ 不通过", safe[1]])

	# ── ① 样式总览 ──────────────────────────────────────────────────────────
	_probe = _stage()
	_swatch(_probe, UiSkinRef.panel_style(_skin), Vector2(60, 90), Vector2(330, 150),
		"panel_style —— 菜单 / HUD 面板")
	_swatch(_probe, UiSkinRef.story_panel_style(_skin), Vector2(60, 320), Vector2(330, 150),
		"story_panel_style —— 剧情对话框")
	_swatch(_probe, UiSkinRef.chip_style(_skin), Vector2(60, 540), Vector2(150, 56),
		"chip_style（数值片）")
	_swatch(_probe, UiSkinRef.name_tag_style(_skin), Vector2(240, 540), Vector2(150, 56),
		"name_tag_style（名牌）")

	var bx := 470.0
	_swatch(_probe, UiSkinRef.button_style(_skin, "normal"), Vector2(bx, 90),
		Vector2(240, 56), "button normal")
	_swatch(_probe, UiSkinRef.button_style(_skin, "hover"), Vector2(bx, 180),
		Vector2(240, 56), "button hover")
	_swatch(_probe, UiSkinRef.button_style(_skin, "pressed"), Vector2(bx, 270),
		Vector2(240, 56), "button pressed")

	var tx := 790.0
	_swatch(_probe, UiSkinRef.bar_trough(_skin), Vector2(tx, 90), Vector2(420, 26),
		"bar_trough / bar_fill（量条）")
	var fillbar := Panel.new()
	fillbar.position = Vector2(tx + 2, 92)
	fillbar.size = Vector2(250, 22)
	fillbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fillbar.add_theme_stylebox_override("panel", UiSkinRef.bar_fill(_skin, 1.0))
	_probe.add_child(fillbar)
	_swatch(_probe, UiSkinRef.bar_fill(_skin, 0.1), Vector2(tx, 150), Vector2(420, 26),
		"bar_fill（低血量那档）")
	_swatch(_probe, UiSkinRef.chip_style(_skin), Vector2(tx, 240), Vector2(110, 44), "")
	_swatch(_probe, UiSkinRef.button_style(_skin, "normal"), Vector2(tx + 130, 240),
		Vector2(110, 44), "")

	# 两套贴图皮肤做对照（有素材才画）
	var old: Dictionary = {}
	for s in UiSkinRef.SKINS:
		if not UiSkinRef.is_procedural(s):
			old = s
			break
	if not old.is_empty():
		var ok := ResourceLoader.exists(String(old["dir"]) + "panel.png")
		var l := Label.new()
		l.text = "（对照：上一套皮肤「%s」%s）" % [old["label"], "" if ok else "（素材不在，跳过）"]
		l.position = Vector2(60, 636)
		if _font != null:
			l.add_theme_font_override("font", _font)
		l.add_theme_font_size_override("font_size", 14)
		l.add_theme_color_override("font_color", Color(0.55, 0.64, 0.74))
		_probe.add_child(l)
		if ok:
			_swatch(_probe, UiSkinRef.panel_style(old), Vector2(900, 400), Vector2(160, 90),
				old["label"])
	for _i in 6:
		await process_frame
	await _shot("gallery")

	# ── ② 对话框 + 选项 ────────────────────────────────────────────────────
	_clean()
	_probe = _stage()
	var box: Node = (load("res://scripts/dialogue_box.gd") as GDScript).new()
	root.add_child(box)
	await process_frame
	box.call("set_cps", 100000.0)
	box.call("play_steps", [
		{"kind": "say", "who": "芹香", "text": "你配电脑吗？"},
		{"kind": "choice", "options": [
			{"text": "商人啊！我正是为此而来！", "disabled": true,
				"disabled_hint": "银行卡余额不足：还差 ¥67.0 万（卡上 ¥0）"},
			{"text": "[观察了银行卡的余额，摇了摇头]"},
		]},
	], "shot")
	for _i in 30:
		await process_frame
	box.call("advance")
	for _i in 40:
		await process_frame
	await _shot("dialogue")
	box.queue_free()

	# ── ②b 说话人配色一览（每个人一个名牌，验证 SPEAKER_COLORS 真的用上了）──
	_clean()
	_probe = _stage()
	var tag_label := Label.new()
	tag_label.text = "SPEAKER_COLORS —— 说话人名牌配色（本喵配的，不是官方设定，见 ui_skin.gd 头注）"
	tag_label.position = Vector2(70, 70)
	if _font != null:
		tag_label.add_theme_font_override("font", _font)
	tag_label.add_theme_font_size_override("font_size", 16)
	tag_label.add_theme_color_override("font_color", Color(0.72, 0.82, 0.92))
	_probe.add_child(tag_label)
	var names: Array = UiSkinRef.SPEAKER_COLORS.keys()
	for i in names.size():
		var who := String(names[i])
		var col := i % 4
		var row := i / 4
		var p := Panel.new()
		p.position = Vector2(70.0 + float(col) * 290.0, 110.0 + float(row) * 78.0)
		p.size = Vector2(180.0, 46.0)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_theme_stylebox_override("panel", UiSkinRef.name_tag_style_for(_skin, who))
		_probe.add_child(p)
		var l2 := Label.new()
		l2.text = who
		l2.set_anchors_preset(Control.PRESET_FULL_RECT)
		l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if _font != null:
			l2.add_theme_font_override("font", _font)
		l2.add_theme_font_size_override("font_size", 22)
		l2.add_theme_color_override("font_color", UiSkinRef.name_tag_text(_skin, who))
		p.add_child(l2)
	for _i in 6:
		await process_frame
	await _shot("speakers")

	# ── ③ HUD ──────────────────────────────────────────────────────────────
	_clean()
	_probe = _stage()
	for _i in 4:
		await process_frame
	var hud := (load(HUD_SCENE) as PackedScene).instantiate() as CanvasLayer
	root.add_child(hud)
	for _i in 6:
		await process_frame
	CostGauge.set_cost_for_test(6.0)
	hud.call("_refresh_cost")
	for _i in 4:
		await process_frame
	await _shot("hud")
	hud.queue_free()

	# ── ④ 设置菜单 ─────────────────────────────────────────────────────────
	_clean()
	_probe = _stage()
	for _i in 4:
		await process_frame
	var sm := load("res://scripts/settings_menu.gd")
	if sm == null:
		print("[probe] ⚠️ 拿不到 settings_menu.gd，跳过设置菜单那两张")
	else:
		var menu := CanvasLayer.new()
		menu.set_script(sm)
		root.add_child(menu)
		for _i in 8:
			await process_frame
		if menu.has_method("open"):
			menu.call("open")
		for _i in 20:
			await process_frame
		await _shot("settings")

	print("[probe] 输出目录 %s" % _out)
	quit(0)
