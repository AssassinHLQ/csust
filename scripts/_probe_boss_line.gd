extends SceneTree
## 探针：倭瓜优香那句登场台词改成**两行**之后，HUD 上到底长什么样。
##
## 查四件事：
##   1. `Parkour.BOSS_LINE` 常量里确实是两行（`\n` 在不在、顺序对不对）
##   2. `boss_line()` 之后 Label 的 `get_line_count()` == 2
##   3. Label 的实际矩形：有没有超出屏幕、有没有压到 HUD 其他元素（血条那几行）
##   4. 出图（人工看一眼：两行是不是居中、字有没有被裁）
##
## 用法：godot --path <工程> --script res://scripts/_probe_boss_line.gd -- --splat=off
## 输出：`_arisu_captures/_hud/90_boss_line_2rows.png`

const SHOT := "90_boss_line_2rows.png"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 24:
		await process_frame
	# 开场对话框会挡住中间那块，先收起来（台词跟它不在同一层）
	var dlg := game.get_node_or_null("DialogueBox") as CanvasLayer
	if dlg != null:
		dlg.visible = false
		if dlg.has_method("skip_all"):
			dlg.call("skip_all")

	print("── 台词常量 ──")
	var line: String = Parkour.BOSS_LINE
	var rows := line.split("\n")
	print("  行数 %d" % rows.size())
	for i in rows.size():
		print("  第 %d 行：「%s」（%d 字）" % [i + 1, rows[i], rows[i].length()])

	var fut := get_first_node_in_group("futures")
	if fut == null:
		print("!! 场景里没有 futures 组，台词发不出去")
		quit(1)
		return
	fut.call("boss_line", line)
	for _i in 6:
		await process_frame

	var lb := fut.get("_line_label") as Label
	if lb == null:
		print("!! 找不到 _line_label")
		quit(1)
		return
	var r := lb.get_global_rect()
	# ⚠️ 这里不能用 `root.size`：项目是 canvas_items 拉伸 + 基准 1600×900，
	#    Control 的坐标系是**逻辑画布**（1600×900），不是窗口像素（1280×720）。
	#    拿窗口尺寸去比，会把「居中」误判成「偏右 160 px」。
	var area := lb.get_parent_area_size()
	print("\n── Label 实测 ──")
	print("  文本「%s」" % lb.text.replace("\n", " / "))
	print("  行数 %d（应为 2）" % lb.get_line_count())
	print("  字体 %d px，自动换行 %d（0=关），竖排对齐 %d（1=居中）" % [
		lb.get_theme_font_size("font_size"), lb.autowrap_mode, lb.vertical_alignment])
	print("  逻辑画布 %.0f×%.0f　窗口 %d×%d" % [area.x, area.y, root.size.x, root.size.y])
	print("  矩形 x %.1f…%.1f　y %.1f…%.1f" % [
		r.position.x, r.end.x, r.position.y, r.end.y])
	print("  画布内：%s　水平居中（±2 px）：%s" % [
		r.position.x >= 0.0 and r.end.x <= area.x
			and r.position.y >= 0.0 and r.end.y <= area.y,
		absf((r.position.x + r.end.x) * 0.5 - area.x * 0.5) < 2.0])
	print("  两行都没被裁：%s（框高 %.0f ≥ 行高 × 2 + 描边）" % [
		r.size.y >= 2.0 * float(lb.get_theme_font_size("font_size")),
		r.size.y])

	var out_dir := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_hud")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var path := out_dir.path_join(SHOT)
	await _shot(path)
	print("\n出图：%s" % path)
	quit(0)


func _shot(path: String) -> void:
	var before := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	while Engine.get_frames_drawn() == before and Time.get_ticks_msec() - t0 < 2000:
		await process_frame
	for _i in 6:
		await process_frame
	root.get_texture().get_image().save_png(path)
	print("[shot] %s" % path.get_file())
