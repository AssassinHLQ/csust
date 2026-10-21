extends SceneTree
## 探针：准星到底占几个**物理像素**——不是读代码，是**数画面**。
##
## 用户 2026-10-21：「编辑器里是一像素点，实机却多了三个像素变成 2×2 正方形」
## 根因：1 px 的矩形若把**中心**吸到整数坐标，左右边就落在 n±0.5，跨两格各 50% 透明，
## 渲染出来正是 2×2 的灰块。修法是让四条边都落在整数上（`hud.gd::_layout_crosshair`）。
##
## 验收方式：同一帧拍两张（准星藏起来 / 显出来）相减，差分就是准星覆盖的像素，
## 再用 ASCII 把 19×19 的范围画出来 —— 是不是 1 px，一眼就能数。
##
## 用法：godot --path <工程> --script res://scripts/_probe_crosshair_px.gd -- --splat=off --no-capture
## 输出：_arisu_captures/_hud/boss_line... 不，是 98_crosshair_px.png（放大前的原图）

const OUT := "_hud"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# ⚠️ 必须用**非整数缩放**的窗口来验：1600×900 恰好等于基准分辨率（scale=1.0），
	#    那种情况下旧代码也是准的，验不出「1 px 变 2×2」。2560×1334 ⇒ scale 1.6。
	root.size = Vector2i(2560, 1334)
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
	var ch := hud.get_node_or_null("Crosshair") as Control if hud != null else null
	if hud == null or ch == null:
		print("!! 找不到 HUD/Crosshair")
		quit(1)
		return

	# 让扩散量稳定下来（待机 → 目标 7.5）
	for _i in 40:
		await process_frame

	var rects: Dictionary = hud.call("crosshair_physical_rects")
	print("── 各元素在**物理像素**上的矩形 ──")
	var all_int := true
	for k in ["Dot", "T", "B", "L", "R"]:
		var r: Rect2 = rects[k]
		# 容差 0.01 px：浮动误差下 1280.0000 会读成 1279.9998，别用 is_equal_approx 误杀
		var int_edges := absf(r.position.x - round(r.position.x)) < 0.01 \
			and absf(r.position.y - round(r.position.y)) < 0.01 \
			and absf(r.size.x - round(r.size.x)) < 0.01 \
			and absf(r.size.y - round(r.size.y)) < 0.01
		all_int = all_int and int_edges
		print("  %-3s x %8.2f~%8.2f  y %8.2f~%8.2f  %.0f×%.0f px  %s" % [
			k, r.position.x, r.end.x, r.position.y, r.end.y, r.size.x, r.size.y,
			"边全在整数上" if int_edges else "**有半像素边**"])
	print("  → 四条边都是整数：%s" % ("✔" if all_int else "✘"))
	print("  缩放（逻辑→物理）= %.4f" % float(hud.call("crosshair_scale")))

	ch.visible = false
	await _frames(6)
	var img_a := root.get_texture().get_image()
	ch.visible = true
	await _frames(6)
	var img_b := root.get_texture().get_image()

	var dot_r: Rect2 = rects["Dot"]
	var cx := int(round(dot_r.position.x))
	var cy := int(round(dot_r.position.y))
	var half := 24
	print("\n── 画面差分（'#' = 准星画到的像素，'.' = 没画到；中心 %d,%d）──" % [cx, cy])
	var total := 0
	for y in range(cy - half, cy + half + 1):
		var row := ""
		for x in range(cx - half, cx + half + 1):
			if x < 0 or y < 0 or x >= img_a.get_width() or y >= img_a.get_height():
				row += "?"
				continue
			var ca := img_a.get_pixel(x, y)
			var cb := img_b.get_pixel(x, y)
			var diff := maxf(maxf(absf(ca.r - cb.r), absf(ca.g - cb.g)), absf(ca.b - cb.b))
			if diff > 0.02:
				row += "#"
				total += 1
			else:
				row += "."
		print("  %s" % row)
	print("  差分像素总数：%d" % total)

	# 量中心点：以 dot 矩形左上角起、2×2 范围内有没有多出来的像素
	var dot_px := 0
	for y in range(cy - 1, cy + 3):
		for x in range(cx - 1, cx + 3):
			var ca := img_a.get_pixel(x, y)
			var cb := img_b.get_pixel(x, y)
			if maxf(maxf(absf(ca.r - cb.r), absf(ca.g - cb.g)), absf(ca.b - cb.b)) > 0.02:
				dot_px += 1
	print("  中心点附近 4×4 里的准星像素：%d 个（1 px 点应该只有 1 个）" % dot_px)

	var out_dir := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT)
	DirAccess.make_dir_recursive_absolute(out_dir)
	img_b.save_png(out_dir.path_join("98_crosshair_px.png"))
	print("\n出图：%s" % out_dir.path_join("98_crosshair_px.png"))
	quit(0)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame
