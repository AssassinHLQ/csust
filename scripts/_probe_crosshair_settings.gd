extends SceneTree
## 探针：准星的「颜色 / 双色渐变 / 粗细 / 每个部件透明度」在 Esc 设置里调过之后，
## 到底有没有**真的落到画面上**（不是只把值存进 cfg）。
##
## 三类验收：
##   ① 几何：物理像素矩形 = 设置里的 dot/thick/arm（且四条边仍在整数上）
##   ② 数据：着色器 uniform 与各 `ColorRect.color.a` 跟设置一致
##   ③ 像素：截一张图，上臂偏红、下臂偏蓝、中心点居中 —— 证明渐变是沿**整条准星**
##      的高度插值的，而不是每个部件各画各的
##
## 用法：godot --path <工程> --script res://scripts/_probe_crosshair_settings.gd -- --splat=off --no-capture
## 出图：_arisu_captures/_hud/97_crosshair_settings.png、98_crosshair_menu.png

const KEYS := ["crosshair_color", "crosshair_color2", "crosshair_gradient",
	"crosshair_dot_px", "crosshair_thick_px", "crosshair_arm_px",
	"crosshair_dot_alpha", "crosshair_arm_alpha"]

var _fail := 0
var _saved := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# 用**非整数缩放**的窗口：1600×900 是 1.0 缩放，验不出像素换算的问题
	root.size = Vector2i(2560, 1334)
	for k in KEYS:
		_saved[k] = GameSettings.value(k, null)

	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 40:
		await process_frame
	paused = false
	var dlg := game.get_node_or_null("DialogueBox") as CanvasLayer
	if dlg != null:
		dlg.visible = false
		if dlg.has_method("skip_all"):
			dlg.call("skip_all")

	var hud := game.get_node_or_null("HUD")
	if hud == null or hud.get_node_or_null("Crosshair") == null:
		print("!! 找不到 HUD/Crosshair")
		_restore()
		quit(1)
		return
	for _i in 40:
		await process_frame     # 等扩散量稳定

	print("========== 1. 几何：尺寸全部来自设置 ==========")
	_put("crosshair_dot_px", 5.0)
	_put("crosshair_thick_px", 5.0)
	_put("crosshair_arm_px", 12.0)
	_put("crosshair_dot_alpha", 1.0)
	_put("crosshair_arm_alpha", 1.0)
	await _frames(6)

	var rects: Dictionary = hud.call("crosshair_physical_rects")
	_expect_size(rects["Dot"], 5, 5, "中心点")
	_expect_size(rects["T"], 5, 12, "上臂")
	_expect_size(rects["B"], 5, 12, "下臂")
	_expect_size(rects["L"], 12, 5, "左臂")
	_expect_size(rects["R"], 12, 5, "右臂")
	var all_int := true
	for k in ["Dot", "T", "B", "L", "R"]:
		var r: Rect2 = rects[k]
		for v in [r.position.x, r.position.y, r.size.x, r.size.y]:
			if absf(v - round(v)) > 0.01:
				all_int = false
	_check(all_int, "五块矩形四条边依旧全落在整数物理像素上")

	# 尺寸改回小一点，方便看渐变（19 px 高的范围内会跨好几个像素）
	_put("crosshair_dot_px", 3.0)
	_put("crosshair_thick_px", 3.0)
	_put("crosshair_arm_px", 9.0)
	await _frames(6)

	print("\n========== 2. 颜色 / 渐变 / 透明度落到材质上 ==========")
	_put("crosshair_color", Color(1, 0, 0))
	_put("crosshair_color2", Color(0, 0, 1))
	_put("crosshair_gradient", true)
	await _frames(4)
	var cfg: Dictionary = hud.call("crosshair_config")
	_check(cfg["top_color"] == Color(1, 0, 0), "渐变色1 = 红（uniform top_color = %s）"
		% str(cfg["top_color"]))
	_check(cfg["bottom_color"] == Color(0, 0, 1), "渐变色2 = 蓝（uniform bottom_color = %s）"
		% str(cfg["bottom_color"]))
	_check(bool(cfg["gradient"]), "渐变开关是开着的")

	_put("crosshair_gradient", false)
	await _frames(4)
	cfg = hud.call("crosshair_config")
	_check(cfg["bottom_color"] == Color(1, 0, 0),
		"关掉渐变 → 下色被强制等于上色（%s）" % str(cfg["bottom_color"]))

	_put("crosshair_gradient", true)
	_put("crosshair_dot_alpha", 0.5)
	_put("crosshair_arm_alpha", 0.3)
	await _frames(4)
	cfg = hud.call("crosshair_config")
	var pa: Dictionary = cfg["part_alpha"]
	_check(absf(float(pa["Dot"]) - 0.5) < 0.001, "中心点透明度 0.5（实测 %.2f）" % float(pa["Dot"]))
	var arms_ok := true
	for k in ["T", "B", "L", "R"]:
		if absf(float(pa[k]) - 0.3) > 0.001:
			arms_ok = false
	_check(arms_ok, "四条臂透明度 0.3（实测 %s）" % str(pa))

	print("\n========== 3. 像素：渐变方向对不对 ==========")
	# 拍图时必须把透明度拉满，否则采样到的是和天空混过的颜色
	_put("crosshair_dot_alpha", 1.0)
	_put("crosshair_arm_alpha", 1.0)
	await _frames(8)
	rects = hud.call("crosshair_physical_rects")
	var dot_r: Rect2 = rects["Dot"]
	var t_r: Rect2 = rects["T"]
	var b_r: Rect2 = rects["B"]
	var ox := int(round(dot_r.position.x)) + 3 / 2
	var oy := int(round(dot_r.position.y)) + 3 / 2
	var img := root.get_texture().get_image()
	var p_top := img.get_pixel(ox, int(round(t_r.position.y)) + 4)
	var p_bot := img.get_pixel(ox, int(round(b_r.position.y)) + 4)
	var p_dot := img.get_pixel(ox, oy)
	print("  上臂像素 %s（%d,%d）" % [p_top.to_html(false), ox, int(round(t_r.position.y)) + 4])
	print("  下臂像素 %s（%d,%d）" % [p_bot.to_html(false), ox, int(round(b_r.position.y)) + 4])
	print("  中心像素 %s（%d,%d）" % [p_dot.to_html(false), ox, oy])
	_check(p_top.r > p_top.b + 0.10, "上臂偏红（r %.2f > b %.2f）" % [p_top.r, p_top.b])
	_check(p_bot.b > p_bot.r + 0.10, "下臂偏蓝（b %.2f > r %.2f）" % [p_bot.b, p_bot.r])
	_check(p_dot.r > 0.2 and p_dot.b > 0.2, "中心点取到两色中间（r %.2f / b %.2f）"
		% [p_dot.r, p_dot.b])

	print("\n========== 4. 设置界面里真的有这几格 ==========")
	var menu := game.get_node_or_null("SettingsMenu")
	if menu == null:
		_check(false, "场景里有 SettingsMenu")
	else:
		var rows: Dictionary = menu.get("_rows")
		_check(rows.has("crosshair_color") and rows["crosshair_color"]["control"] is ColorPickerButton,
			"准星颜色 = ColorPickerButton")
		_check(rows.has("crosshair_color2") and rows["crosshair_color2"]["control"] is ColorPickerButton,
			"渐变第二色 = ColorPickerButton")
		_check(rows.has("crosshair_gradient") and rows["crosshair_gradient"]["control"] is CheckButton,
			"双色渐变 = CheckButton")
		var sliders_ok := true
		for k in ["crosshair_dot_px", "crosshair_thick_px", "crosshair_arm_px",
				"crosshair_dot_alpha", "crosshair_arm_alpha"]:
			var row: Dictionary = rows.get(k, {})
			if not (row.get("control") is HSlider):
				sliders_ok = false
				print("      %s 的控件不是滑块：%s" % [k, str(row.get("control"))])
		_check(sliders_ok, "尺寸 3 项 + 透明度 2 项都是**滑块**")
		var header := false
		for n in menu.find_children("*", "Label", true, false):
			if (n as Label).text == "准星":
				header = true
		_check(header, "分组标题叫「准星」")

	var out_dir := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_hud")
	DirAccess.make_dir_recursive_absolute(out_dir)
	img.save_png(out_dir.path_join("97_crosshair_settings.png"))
	print("  [img] %s" % out_dir.path_join("97_crosshair_settings.png"))

	print("\n========== 5. 落盘 ==========")
	var cfgfile := ConfigFile.new()
	var err := cfgfile.load("user://settings.cfg")
	_check(err == OK, "user://settings.cfg 读得出来（err=%d）" % err)
	if err == OK:
		var saved_ok := true
		for k in KEYS:
			if not cfgfile.has_section_key("settings", k):
				saved_ok = false
				print("      没有落盘：%s" % k)
		_check(saved_ok, "八个准星项全部落盘")

	# 渲一张设置界面（滚到「准星」那一组），给人眼看
	if menu != null:
		menu.call("open")
		await _frames(10)
		var scroll := menu.find_child("SettingsScroll", true, false) as ScrollContainer
		if scroll != null:
			scroll.scroll_vertical = 100000
			await _frames(10)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out_dir.path_join("98_crosshair_menu.png"))
		print("  [img] %s" % out_dir.path_join("98_crosshair_menu.png"))
		menu.call("close")
		await _frames(3)

	_restore()
	print("\n================ 结果 ================")
	print("失败 %d 项" % _fail)
	quit(1 if _fail > 0 else 0)


func _put(key: String, v: Variant) -> void:
	GameSettings.set_value(key, v)


func _restore() -> void:
	for k in _saved.keys():
		if _saved[k] != null:
			GameSettings.set_value(k, _saved[k])


func _expect_size(r: Rect2, w: int, h: int, title: String) -> void:
	_check(int(round(r.size.x)) == w and int(round(r.size.y)) == h,
		"%s = %d×%d px（实测 %.0f×%.0f）" % [title, w, h, r.size.x, r.size.y])


func _check(cond: bool, label: String) -> void:
	print("  [%s] %s" % ["PASS" if cond else "FAIL", label])
	if not cond:
		_fail += 1


func _frames(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
