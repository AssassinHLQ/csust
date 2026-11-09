extends SceneTree
## 出图：**BA 风格的 COST 量**长什么样（`scripts/cost_bar.gd`）。
##
##   _tools/run_shot.sh res://scripts/_probe_cost_ui.gd
##
## 出两张东西：
##   ① `01_hud_00/03/06/10.png` —— **真 HUD 里**那一行的样子（4 个费用值），
##      证明它是接在右下角弹药面板上的、不是单独画的条。
##   ② `05_strip.png` —— 0~10 逐个值排一列，看填充 / 刻度 / 攒满换色。
##   ③ `06_zoom.png` —— 2 倍尺寸，看斜切端与圆角（自绘是按 `size` 现算的，
##      所以放大是真·矢量放大，不是拉位图）。
##
## ⚠️ 不抢前台（AGENTS.md 硬要求）：`OffWin.apply()` 取消最大化 + 挪出屏幕，
##    命令行还要带 `--no-capture`（`_tools/run_shot.sh` 已写死）。

const OffWin := preload("res://scripts/offscreen_window.gd")
const CostGauge := preload("res://scripts/cost_gauge.gd")
const CostBarView := preload("res://scripts/cost_bar.gd")
const UiSkinRef := preload("res://scripts/ui_skin.gd")
const HUD_SCENE := "res://scenes/hud.tscn"

const OUT_NAME := "_cost_ui"

var _out := ""
var _n := 0


func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	_n += 1
	var p := "%s/%02d_%s.png" % [_out, _n, name]
	var err := root.get_texture().get_image().save_png(p)
	print("      出图 %s → %s" % ["OK" if err == OK else "失败(%d)" % err, p])


func _bg() -> void:
	var rect := ColorRect.new()
	rect.color = Color(0.09, 0.11, 0.15, 1.0)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(rect)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	await OffWin.apply(self, Vector2i(1280, 720))
	_out = ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_NAME)
	DirAccess.make_dir_recursive_absolute(_out)

	var safe: Array = OffWin.is_safe()
	print("[probe] 窗口安全检查：%s（%s）" % ["通过" if safe[0] else "⚠️ 不通过", safe[1]])

	# ── ① 真 HUD ────────────────────────────────────────────────────────────
	_bg()
	var hud := (load(HUD_SCENE) as PackedScene).instantiate() as CanvasLayer
	root.add_child(hud)
	for _i in 6:
		await process_frame

	var bar := hud.get_node_or_null("Panel/Margin/VBox/CostBar") as Control
	if bar == null:
		print("[probe] ✗ 没找到 CostBar，HUD 那几张贴不出")
	else:
		print("[probe] CostBar 实际尺寸 = %s（斜切量按高算，见 cost_bar.gd）" % str(bar.size))
		for v in [0.0, 3.0, 6.0, 10.0]:
			CostGauge.set_cost_for_test(v)
			hud.call("_refresh_cost")
			for _i in 4:
				await process_frame
			await _shot("hud_%02d" % int(v))

	# ── ② 0~10 竖排条 ───────────────────────────────────────────────────────
	hud.queue_free()
	for _i in 4:
		await process_frame
	_bg()
	var font: Font = UiSkinRef.hud_number_font(UiSkinRef.pick())
	var strip := Control.new()
	strip.set_anchors_preset(Control.PRESET_FULL_RECT)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(strip)
	var x0 := 300.0
	var y0 := 96.0
	var step := 46.0
	var bw := 620.0
	for i in 11:
		var lab := Label.new()
		lab.text = "%2d" % i
		lab.position = Vector2(x0 - 52.0, y0 + float(i) * step + 2.0)
		lab.size = Vector2(40.0, 34.0)
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if font != null:
			lab.add_theme_font_override("font", font)
		lab.add_theme_font_size_override("font_size", 26)
		lab.add_theme_color_override("font_color", Color(0.85, 0.90, 0.96))
		strip.add_child(lab)
		var b := CostBarView.new()
		b.position = Vector2(x0, y0 + float(i) * step)
		b.size = Vector2(bw, 31.0)
		b.value = float(i)
		strip.add_child(b)
	for _i in 6:
		await process_frame
	await _shot("strip")

	# ── ③ 2 倍尺寸（真·矢量放大）────────────────────────────────────────────
	strip.queue_free()
	for _i in 4:
		await process_frame
	_bg()
	var big := Control.new()
	big.set_anchors_preset(Control.PRESET_FULL_RECT)
	big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(big)
	for j in 3:
		var v: float = [0.4, 6.0, 10.0][j]
		var b2 := CostBarView.new()
		b2.position = Vector2(70.0, 250.0 + float(j) * 100.0)
		b2.size = Vector2(1140.0, 62.0)
		b2.value = v
		big.add_child(b2)
		var lab2 := Label.new()
		lab2.text = "value = %.1f" % v
		lab2.position = Vector2(70.0, 216.0 + float(j) * 100.0)
		if font != null:
			lab2.add_theme_font_override("font", font)
		lab2.add_theme_font_size_override("font_size", 22)
		lab2.add_theme_color_override("font_color", Color(0.85, 0.90, 0.96))
		big.add_child(lab2)
	for _i in 6:
		await process_frame
	await _shot("zoom")

	print("[probe] 输出目录 %s" % _out)
	quit(0)
