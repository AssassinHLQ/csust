extends SceneTree
## 探针：Boss 血条「血量不满时圆角消失」的机制 + 九宫格修法验证。
##
## 起因（用户报）：「血条有时候会回退到长方形没有圆边」。
##
## ── 机制（`ProgressBar` + 烤在图两端的像素圆角）──
##   `ProgressBar` 把 `fill` 样式盒**整张拉伸**进「按血量缩短后的矩形」——
##   既不裁剪、也不给帽保留最小宽度。于是帽宽 ∝ 血量比例：
##   满血 182 源 px → 546 逻辑 px（3 倍）帽 12 px；10% 血时整张贴图被压进 55 px，
##   帽不到 1 px ⇒ 看上去就是长方形。
##
## ── 修法 ──
##   给 `StyleBoxTexture` 开**九宫格**（`texture_margin_left/right`），帽就不参与拉伸。
##   ⚠️ 但实测 Godot 的九宫格边距是**按源像素 1:1** 画的：给 182 px 宽的贴图设 12，
##   屏幕上只有 4 px（真正有色的源列数）。所以 `mc_bar_style(..., cap_px)` 先把贴图
##   **横向烘大** `cap_px / 4` 倍，再设边距 = `4 * hscale`，帽宽才恰好 = 满血时的大小。
##
## 本探针画 6 根：老写法（cap=0）× 满血/半血 对照，新写法（cap=12）× 四档血量，
## 逐像素量「帽的总宽 / 有色帽宽」，并出图给人眼看。
##
## 用法：godot --path <工程> --script res://scripts/_probe_boss_bar_caps.gd -- --splat=off
## 输出：`user://boss_bar_caps.png` + 控制台读数

const BAR_W := 546.0
const BAR_H := 27.0          ## 实际渲染高度（`ProgressBar` 的最小高度会顶掉 12，见报告）
const PAGE := Color(0.35, 0.42, 0.57)
const OUT_USER := "user://boss_bar_caps.png"

var _vp: SubViewport


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(600, 220)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(_vp)

	var back := ColorRect.new()
	back.color = PAGE
	back.size = Vector2(_vp.size)
	_vp.add_child(back)

	var bright := UiSkin.mc_color("pink")
	var cap := UiSkin.mc_bar_cap_px(BAR_W)
	print("[probe] 条框宽 %.0f → 满血帽宽 cap_px = %.1f" % [BAR_W, cap])
	var rows := [
		{"name": "A 老写法 cap=0", "cap": 0.0, "ratio": 1.0},
		{"name": "A 老写法 cap=0", "cap": 0.0, "ratio": 0.5},
		{"name": "B 新写法 cap=12", "cap": cap, "ratio": 1.0},
		{"name": "B 新写法 cap=12", "cap": cap, "ratio": 0.5},
		{"name": "B 新写法 cap=12", "cap": cap, "ratio": 0.25},
		{"name": "B 新写法 cap=12", "cap": cap, "ratio": 0.06},
	]
	var bars: Array = []
	var y := 20.0
	for r in rows:
		var bar := ProgressBar.new()
		bar.position = Vector2(20, y)
		bar.size = Vector2(BAR_W, BAR_H)
		bar.max_value = 1.0
		bar.value = r["ratio"]
		bar.show_percentage = false
		bar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		bar.add_theme_stylebox_override("background",
			UiSkin.mc_bar_style(bright, false, r["cap"]))
		bar.add_theme_stylebox_override("fill",
			UiSkin.mc_bar_style(bright, true, r["cap"]))
		_vp.add_child(bar)
		bars.append({"row": r, "bar": bar})
		y += 32.0

	for _i in 8:
		await process_frame
	var img := _vp.get_texture().get_image()
	print("[probe] save_png err = %d → %s"
		% [img.save_png(OUT_USER), ProjectSettings.globalize_path(OUT_USER)])

	print("\n===== 帽宽（逻辑 px，条框左沿起算）=====")
	print("%-18s %6s %8s %8s %8s %8s" % ["写法", "血量", "高光帽", "有色", "顶行缺口", "填充px"])
	for b in bars:
		var bar: ProgressBar = b["bar"]
		var r: Dictionary = b["row"]
		var x0 := int(bar.global_position.x)
		var y0 := int(bar.global_position.y)
		var mid := y0 + int(BAR_H * 0.3)      # 第 2 行（高光行）
		var top := y0 + 2                     # 第 1 行（有像素圆角的缺口）
		var m := _cap(img, x0, mid, float(r["ratio"]))
		var notch := _cap(img, x0, top, float(r["ratio"]))
		print("%-18s %6.2f %8d %8d %8d %8d"
			% [r["name"], r["ratio"], m["all"], m["colored"],
				notch["all"] - notch["colored"], m["fill"]])
		for pair in [["顶行", top], ["高光", mid]]:
			var s := ""
			for dx in 14:
				var c := img.get_pixel(x0 + dx, pair[1])
				s += "%02X%02X%02X " % [int(c.r * 255.0), int(c.g * 255.0), int(c.b * 255.0)]
			print("     %s 14px: %s" % [pair[0], s])

	quit()


## 量一根条的一行：`all` = 从条框左沿到第一颗平色（含透明缺口），
## `colored` = 其中**有色**的（透明像素不算），`fill` = 平色的连续宽。
func _cap(img: Image, x0: int, y: int, ratio: float) -> Dictionary:
	var fill_w := int(ratio * BAR_W)
	# 参考色取**填充正中**：满血时取靠右会在右帽里取到错色
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


func _same(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.02 and absf(a.g - b.g) < 0.02 and absf(a.b - b.b) < 0.02
