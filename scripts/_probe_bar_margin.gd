extends SceneTree
## 一次性探针：`ProgressBar` 的 `background` 样式盒**内容边距到底吃不吃**。
##
## 起因：HUD 换 Sprout 皮肤后，血条外框（HP 的草绿描边、Boss 的木板九宫格）在
## 截图里**一点都看不到**，红条从条框最外沿就开始画。怀疑 `ProgressBar` 只把
## `background` 当背景画、不拿它的 `get_margin()` 去内缩 `fill`。
##
## 四组对照（全部画进一个 SubViewport 再存图）：
##   A  ProgressBar.background = 带 2px 边框的 StyleBoxFlat   ← 现在 HUD 的写法
##   B  PanelContainer.panel  = 同一个样式盒，里面放空背景的 ProgressBar ← 备选写法
##   C  ProgressBar.background = 九宫格 StyleBoxTexture（纹理边距 12 + 内容边距 8）
##   D  PanelContainer.panel  = 九宫格 StyleBoxTexture，里面放空背景的 ProgressBar
##
## 用法：godot --path <工程> --script res://scripts/_probe_bar_margin.gd
## 输出：`user://bar_margin.png`（绝对路径会打印出来）+ 控制台打印 `get_margin()` 的读数

const OUT_USER := "user://bar_margin.png"
const TEX := "res://assets/ui_sprout/panel.png"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(520, 420)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(vp)

	var back := ColorRect.new()
	back.color = Color(0.35, 0.38, 0.42)
	back.size = Vector2(520, 420)
	vp.add_child(back)

	# 带边框的槽（HP 用的那种）
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(0.35, 0.25, 0.16)
	flat.border_color = Color(0.53, 0.74, 0.42)
	flat.set_border_width_all(2)
	flat.set_corner_radius_all(2)
	print("[probe] StyleBoxFlat  get_margin L/T/R/B = %s / %s / %s / %s" % [
		flat.get_margin(SIDE_LEFT), flat.get_margin(SIDE_TOP),
		flat.get_margin(SIDE_RIGHT), flat.get_margin(SIDE_BOTTOM)])
	print("[probe] StyleBoxFlat  content_margin_left = %s" % flat.content_margin_left)

	# 九宫格（Boss 用的那种）
	var tex := StyleBoxTexture.new()
	tex.texture = load(TEX)
	tex.texture_margin_left = 12.0
	tex.texture_margin_right = 12.0
	tex.texture_margin_top = 12.0
	tex.texture_margin_bottom = 12.0
	tex.content_margin_left = 8.0
	tex.content_margin_right = 8.0
	tex.content_margin_top = 8.0
	tex.content_margin_bottom = 8.0
	print("[probe] StyleBoxTexture get_margin L/T/R/B = %s / %s / %s / %s" % [
		tex.get_margin(SIDE_LEFT), tex.get_margin(SIDE_TOP),
		tex.get_margin(SIDE_RIGHT), tex.get_margin(SIDE_BOTTOM)])

	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.86, 0.24, 0.18)

	var empty := StyleBoxEmpty.new()

	# A / C：background 直接挂在 ProgressBar 上（现在 HUD 的写法）
	_add_label(vp, Vector2(14, 6), "A  ProgressBar.background = Flat(2px)")
	_add_bar(vp, Rect2(14, 26, 492, 40), flat, fill)

	_add_label(vp, Vector2(14, 76), "C  ProgressBar.background = Texture(12 + content 8)")
	_add_bar(vp, Rect2(14, 96, 492, 40), tex, fill)

	# B / D：槽用 PanelContainer 画，里面放空背景的 ProgressBar（备选写法）
	_add_label(vp, Vector2(14, 146), "B  PanelContainer.panel = Flat(2px) + Bar(背景空)")
	_add_bar_in_panel(vp, Rect2(14, 166, 492, 40), flat, empty, fill)

	_add_label(vp, Vector2(14, 216), "D  PanelContainer.panel = Texture(12) + Bar(背景空)")
	_add_bar_in_panel(vp, Rect2(14, 236, 492, 40), tex, empty, fill)

	# E：九宫格挂 ProgressBar.background，但把 content_margin 设成 0
	var tex0 := StyleBoxTexture.new()
	tex0.texture = load(TEX)
	tex0.texture_margin_left = 12.0
	tex0.texture_margin_right = 12.0
	tex0.texture_margin_top = 12.0
	tex0.texture_margin_bottom = 12.0
	_add_label(vp, Vector2(14, 286), "E  background = Texture(12), content 默认")
	_add_bar(vp, Rect2(14, 306, 492, 40), tex0, fill)

	_add_label(vp, Vector2(14, 356), "F  A 同款但 ratio = 0.35（看描边是否随比例被截断）")
	_add_bar(vp, Rect2(14, 376, 492, 34), flat, fill, 0.35)

	for i in range(6):
		await process_frame
	var img := vp.get_texture().get_image()
	var err := img.save_png(OUT_USER)
	print("[probe] save_png err = %d → %s" % [err, ProjectSettings.globalize_path(OUT_USER)])
	quit()


func _add_label(vp: SubViewport, pos: Vector2, text: String) -> void:
	var l := Label.new()
	l.position = pos
	l.text = text
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	vp.add_child(l)


func _add_bar(vp: SubViewport, rect: Rect2, bg: StyleBox, fill: StyleBox, ratio := 1.0) -> void:
	var bar := ProgressBar.new()
	bar.position = rect.position
	bar.size = rect.size
	bar.max_value = 1.0
	bar.value = ratio
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	vp.add_child(bar)


func _add_bar_in_panel(vp: SubViewport, rect: Rect2, bg: StyleBox,
		fill_bg: StyleBox, fill: StyleBox, ratio := 1.0) -> void:
	var pc := PanelContainer.new()
	pc.position = rect.position
	pc.size = rect.size
	pc.add_theme_stylebox_override("panel", bg)
	vp.add_child(pc)
	var bar := ProgressBar.new()
	bar.max_value = 1.0
	bar.value = ratio
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 0)
	bar.add_theme_stylebox_override("background", fill_bg)
	bar.add_theme_stylebox_override("fill", fill)
	pc.add_child(bar)
