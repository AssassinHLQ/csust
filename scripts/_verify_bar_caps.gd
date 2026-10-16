extends SceneTree
## 验「**Boss 血条两端的像素圆角不随血量缩水**」——把「帽宽」量成像素。
##
## 用户报：「血条有时候会回退到长方形没有圆边」。
##
## ── 根因（
## `_probe_boss_bar_caps.gd` + 逐像素量截图）──
## `ProgressBar` 把 `fill` 样式盒**整张拉伸**进「按血量缩短后的矩形」：既不裁剪、
## 也不给帽保留最小宽度。而像素圆角是**烤在贴图两端**的（`mc_bar_texture`），
## 于是帽宽 ∝ 血量比例 —— 满血 9 px，半血 5 px，10% 血不到 1 px（看着就是长方形）。
##
## ── 修法 ──
## 给 `StyleBoxTexture` 开**九宫格**（`texture_margin_left/right`）让帽不参与拉伸。
## ⚠️ 但实测九宫格边距是**按源像素 1:1** 画的：182 px 宽的贴图设 12，屏幕上只有 4 px。
## 所以 `UiSkin.mc_bar_style(..., cap_px)` 先把贴图**横向烘大** `cap_px / 4` 倍，
## 再设边距 = `4 * hscale` —— 帽宽恰好 = 满血时的大小，与血量无关。
##
## ── 判据 ──
##   · 四档血量（100% / 50% / 25% / 6%）的**帽宽都必须一样**（9 px、顶行缺口 3 px）
##   · 满血的外观**一个像素都不能变**（新写法的 100% 与老写法的 100% 逐像素相等）
##   · 反向对照：老写法半血时必须**量得到缩水**，否则说明这条自检根本没在测东西
##
## 用法：godot --path <工程> --script res://scripts/_verify_bar_caps.gd -- --splat=off

const BAR_W := 546.0
const BAR_H := 27.0        ## 实际渲染高度（`ProgressBar` 的最小高度会顶掉常量里的 12）
const PAGE := Color(0.35, 0.42, 0.57)
const RATIOS := [1.0, 0.5, 0.25, 0.06]
const CAP_PX := 12.0       ## 满血帽宽 = MC_CAP_COLS / 182 × 546
const CAP_COLORED := 9     ## 帽里**有色**的像素 = 3 源列 × 3 倍烘焙
const CAP_NOTCH := 3       ## 顶行的透明缺口 = 1 源列 × 3 倍烘焙

var _fail := 0
var _pass := 0
var _m := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	await _test_skin()
	await _test_render()
	await _test_hud()
	print("\n================ 结果 ================")
	print("通过 %d 项" % _pass)
	print("\n帽宽（逻辑 px，条框左沿起算）")
	print("  血量      100%%   50%%   25%%    6%%")
	print("  老写法      %s" % _row(_m.get("old", [])))
	print("  新写法      %s" % _row(_m.get("new", [])))
	_quit()


# --- 1. 样式盒本身 ---------------------------------------------------------------

func _test_skin() -> void:
	print("========== 1. 样式盒 ==========")
	var cap := UiSkin.mc_bar_cap_px(BAR_W)
	_check(is_equal_approx(cap, CAP_PX),
		"满血帽宽 = 4 源列 / 182 × 条宽 %.0f = %.1f px" % [BAR_W, cap])

	var bright := UiSkin.mc_color("pink")
	var style := UiSkin.mc_bar_style(bright, true, cap)
	var tex := style.texture as ImageTexture
	_check(tex != null and tex.get_width() == int(BAR_W) and tex.get_height() == 5,
		"填充贴图按 3 倍横向烘大：%s（原 182×5 会被九宫格按 1:1 画，帽只剩 4 px）"
		% str(Vector2i(tex.get_width(), tex.get_height()) if tex else Vector2i.ZERO))
	_check(is_equal_approx(style.texture_margin_left, CAP_PX)
		and is_equal_approx(style.texture_margin_right, CAP_PX),
		"左右九宫格边距 = %.0f px（帽不参与拉伸）" % style.texture_margin_left)
	_check(is_equal_approx(style.texture_margin_top, 0.0)
		and is_equal_approx(style.texture_margin_bottom, 0.0),
		"竖向**不开**九宫格（开了 5 行的比例会散）")
	_check(style.axis_stretch_horizontal == StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
		and style.axis_stretch_vertical == StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH,
		"两轴都是 STRETCH（中间那 522 列平色正好 1:1）")

	var old := UiSkin.mc_bar_style(bright, true)
	_check((old.texture as ImageTexture).get_width() == 182
		and is_equal_approx(old.texture_margin_left, 0.0),
		"`cap_px = 0` 保留老行为（182×5、无边距）—— 自检要拿它当反向对照")


# --- 2. 真渲染：逐像素量帽宽 -----------------------------------------------------

func _test_render() -> void:
	print("\n========== 2. 逐像素（SubViewport 真渲染）==========")
	var vp := SubViewport.new()
	vp.size = Vector2i(600, 20 + RATIOS.size() * 2 * 32 + 20)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var back := ColorRect.new()
	back.color = PAGE
	back.size = Vector2(vp.size)
	vp.add_child(back)

	var bright := UiSkin.mc_color("pink")
	var cap := UiSkin.mc_bar_cap_px(BAR_W)
	var bars: Array = []
	var y := 20.0
	for ratio in RATIOS:
		for variant in [{"n": "old", "cap": 0.0}, {"n": "new", "cap": cap}]:
			var bar := ProgressBar.new()
			bar.position = Vector2(20, y)
			bar.size = Vector2(BAR_W, BAR_H)
			bar.max_value = 1.0
			bar.value = ratio
			bar.show_percentage = false
			bar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			bar.add_theme_stylebox_override("background",
				UiSkin.mc_bar_style(bright, false, variant["cap"]))
			bar.add_theme_stylebox_override("fill",
				UiSkin.mc_bar_style(bright, true, variant["cap"]))
			vp.add_child(bar)
			bars.append({"n": variant["n"], "ratio": ratio, "bar": bar})
			y += 32.0

	for _i in 8:
		await process_frame
	var img := vp.get_texture().get_image()

	var old_caps: Array = []
	var new_caps: Array = []
	var new_notch: Array = []
	var rows := {}
	for b in bars:
		var bar: ProgressBar = b["bar"]
		var x0 := int(bar.global_position.x)
		var y0 := int(bar.global_position.y)
		var mid := y0 + int(BAR_H * 0.3)
		var m := _cap(img, x0, mid, float(b["ratio"]))
		var notch := _cap(img, x0, y0 + 2, float(b["ratio"]))
		rows["%s@%.2f" % [b["n"], b["ratio"]]] = _hex(img, x0, mid, 14)
		if b["n"] == "old":
			old_caps.append(m["all"])
		else:
			new_caps.append(m["all"])
			new_notch.append(notch["all"] - notch["colored"])
	_m["old"] = old_caps
	_m["new"] = new_caps

	_check(new_caps == [CAP_COLORED, CAP_COLORED, CAP_COLORED, CAP_COLORED],
		"**新写法四档血量的帽宽完全一样**：%s（期望全是 %d px）"
		% [str(new_caps), CAP_COLORED])
	_check(new_notch == [CAP_NOTCH, CAP_NOTCH, CAP_NOTCH, CAP_NOTCH],
		"顶行的透明缺口也一样：%s（期望全是 %d px，圆角就靠它）"
		% [str(new_notch), CAP_NOTCH])
	_check(old_caps[1] < old_caps[0],
		"反向对照：老写法半血时帽宽从 %d px 缩到 %d px —— 这就是用户看到的现象，"
		% [old_caps[0], old_caps[1]] + "说明这条自检抓得住")
	_check(rows["new@1.00"] == rows["old@1.00"],
		"满血的外观**一个像素都没变**（新写法 100% == 老写法 100%）")
	_check(rows["new@0.06"] == rows["new@1.00"],
		"6% 血的外观和满血一致（低血不再变长方形）")
	_check(rows["new@0.50"] != rows["old@0.50"],
		"半血时新老写法确实不同（新写法保住了帽）")
	vp.queue_free()


# --- 3. 真 HUD 挂的就是这套样式盒 -----------------------------------------------

func _test_hud() -> void:
	print("\n========== 3. 真 HUD ==========")
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _steps(30)
	var hud: CanvasLayer = game.get_node_or_null("HUD") as CanvasLayer
	if hud == null:
		_check(false, "场景里有 HUD")
		return
	var count := 0
	for i in 2:
		var bar := hud.get_node_or_null("BossBar%d" % i) as ProgressBar
		if bar == null:
			continue
		count += 1
		var fill := bar.get_theme_stylebox("fill") as StyleBoxTexture
		var bg := bar.get_theme_stylebox("background") as StyleBoxTexture
		_check(fill != null and is_equal_approx(fill.texture_margin_left, CAP_PX)
			and is_equal_approx(fill.texture_margin_right, CAP_PX),
			"BossBar%d 的填充条开了 %.0f px 九宫格" % [i, CAP_PX])
		_check(bg != null and is_equal_approx(bg.texture_margin_left, CAP_PX),
			"BossBar%d 的槽也开了一样的九宫格（满血时两者圆角重合）" % i)
		_check(fill != null and (fill.texture as ImageTexture).get_width() == int(BAR_W),
			"BossBar%d 的填充贴图烘到 %.0f 宽" % [i, BAR_W])
	_check(count == 2, "两位 Boss 的条都查到了（%d 根）" % count)


# --- 工具 -----------------------------------------------------------------------

## 量一根条的一行：`all` = 条框左沿到第一颗平色（含透明缺口），
## `colored` = 其中**有色**的像素数，`fill` = 平色的连续宽。
func _cap(img: Image, x0: int, y: int, ratio: float) -> Dictionary:
	var fill_w := int(ratio * BAR_W)
	# 参考色取**填充正中**：满血时靠右取会取到右帽的颜色
	var ref := img.get_pixel(x0 + maxi(fill_w / 2, 1), y)
	var all := 0
	var colored := 0
	for dx in int(BAR_W):
		var c := img.get_pixel(x0 + dx, y)
		if _same(c, ref):
			all = dx
			break
		if not _same(c, PAGE):
			colored += 1
	return {"all": all, "colored": colored, "fill": maxi(fill_w - all, 0)}


func _hex(img: Image, x0: int, y: int, n: int) -> String:
	var s := ""
	for dx in n:
		var c := img.get_pixel(x0 + dx, y)
		s += "%02X%02X%02X" % [int(c.r * 255.0), int(c.g * 255.0), int(c.b * 255.0)]
	return s


func _same(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.02 and absf(a.g - b.g) < 0.02 and absf(a.b - b.b) < 0.02


func _row(v: Array) -> String:
	return "  ".join(v.map(func(n): return "%4d" % n))


func _steps(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame


func _check(cond: bool, label: String) -> void:
	print("  [%s] %s" % ["PASS" if cond else "FAIL", label])
	if cond:
		_pass += 1
	else:
		_fail += 1


func _quit() -> void:
	print("失败 %d 项" % _fail)
	quit(1 if _fail > 0 else 0)
