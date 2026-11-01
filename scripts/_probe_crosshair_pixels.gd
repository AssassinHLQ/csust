extends SceneTree
## 把准星**真正渲染出来的像素**抓下来，一格一格打成字符图 —— 专门用来定位
## 用户说的「右下明显多了像素」。
##   godot --path . --script res://scripts/_probe_crosshair_pixels.gd -- --splat=off
##
## 做法：把 3D 世界全藏掉（只留 HUD），先拍一张「有准星」的、再拍一张
## 「`Crosshair.visible = false`」的，两张**逐像素相减** —— 差出来的就是准星画的像素，
## 一个不多一个不少。然后把这块差值打成 ASCII 图（`#` = 有像素、`.` = 没有），
## 并和 `crosshair_physical_rects()` 报的矩形对照。
##
## 出图：_arisu_captures/_crosshair/{visible,clean,crop}.png
## ⚠️ 窗口尺寸按用户那台来（2560×1334 → 画布缩放 1.6）—— 「多出来的像素」是
##    缩放 ≠ 1 时才会暴露的对齐问题，1600×900 下反而看不出来。

const OUT_DIR := "_arisu_captures/_crosshair"
const PAD := 22          # 字符图取中心 ±22 px


func _initialize() -> void:
	_run.call_deferred()


func _shot(path: String) -> Image:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(path)
	return img


## 打一遍五个元素的物理矩形 + 由矩形算出的四条间隙（左右/上下应该相等）。
func _dump_rects(hud: Node, cross: Control) -> void:
	print("  缩放 %.4f，原点逻辑坐标 (%.4f, %.4f)"
		% [hud.call("crosshair_scale"), cross.offset_left, cross.offset_top])
	var rects: Dictionary = hud.call("crosshair_physical_rects")
	for k in rects:
		var r: Rect2 = rects[k]
		var whole: bool = absf(r.position.x - roundf(r.position.x)) < 0.0001 \
			and absf(r.end.x - roundf(r.end.x)) < 0.0001 \
			and absf(r.position.y - roundf(r.position.y)) < 0.0001 \
			and absf(r.end.y - roundf(r.end.y)) < 0.0001
		print("  %-4s x [%9.4f, %9.4f)  y [%9.4f, %9.4f)  %s"
			% [k, r.position.x, r.end.x, r.position.y, r.end.y,
				"整格" if whole else "**踩在小数上**"])
	if rects.has("Dot"):
		var d: Rect2 = rects["Dot"]
		print("  间隙  左 %.4f  右 %.4f  上 %.4f  下 %.4f"
			% [d.position.x - (rects["L"] as Rect2).end.x,
				(rects["R"] as Rect2).position.x - d.end.x,
				d.position.y - (rects["T"] as Rect2).end.y,
				(rects["B"] as Rect2).position.y - d.end.y])


## 沿一行/一列扫描「有准星 vs 没准星」的差异，返回从 center 起 ±30 内的区间列表。
func _runs(a: Image, b: Image, fixed: int, horizontal: bool, center: int) -> String:
	var lo := maxi(center - 30, 0)
	var hi := mini(center + 30, (a.get_width() if horizontal else a.get_height()) - 1)
	var out := PackedStringArray()
	var start := -1
	for i in range(lo, hi + 1):
		var p := Vector2i(i, fixed) if horizontal else Vector2i(fixed, i)
		var diff := a.get_pixelv(p) != b.get_pixelv(p)
		if diff and start < 0:
			start = i
		elif not diff and start >= 0:
			out.append("[%d,%d)" % [start, i])
			start = -1
	if start >= 0:
		out.append("[%d,%d)" % [start, hi + 1])
	return " ".join(out)


func _run() -> void:
	root.size = Vector2i(2560, 1334)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 90:
		await process_frame
	paused = false
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out)

	var hud := game.get_node_or_null("HUD") as CanvasLayer
	var cross := game.get_node_or_null("HUD/Crosshair") as Control
	if hud == null or cross == null:
		print("[错误] 没有 HUD/Crosshair")
		quit(1)
		return
	# 只留 HUD：3D 全藏掉 → 底色变成一块纯色，逐像素相减才干净
	for c in game.get_children():
		if c is CanvasLayer:
			continue
		if c is Node3D:
			(c as Node3D).visible = false
	for c in game.find_children("*", "CanvasLayer", true, false):
		var cl: CanvasLayer = c as CanvasLayer
		if cl != null and cl != hud:
			cl.visible = false
	# find_children 的类型过滤会混进非目标节点，这里逐个判空（见交接文档 6.2）
	for c in game.find_children("*", "Window", true, false):
		var win: Window = c as Window
		if win != null and win != root:
			win.visible = false

	print("窗口 %s；画布缩放 = %.4f" % [str(root.size), cross.get_viewport()
		.get_final_transform().get_scale().x])
	var cfg: Dictionary = hud.call("crosshair_config")
	print("crosshair_config() = %s" % str(cfg))

	# 让扩散值稳定下来再拍（矩形要在**拍照的同一帧**打，否则 _spread 还会漂）
	for _f in 40:
		await process_frame
	# 冻结排版：_process 每帧都会 _layout_crosshair()，不冻住的话「量」和「拍」不同帧
	hud.set_process(false)
	hud.call("_layout_crosshair")
	_dump_rects(hud, cross)
	var a := await _shot(out.path_join("visible.png"))
	print("\n[拍完 visible.png 的同一帧] 矩形：")
	_dump_rects(hud, cross)
	cross.visible = false
	for _f in 3:
		await process_frame
	var b := await _shot(out.path_join("clean.png"))
	cross.visible = true
	print("\n[拍照后] 再打一遍矩形，和上面那组比，看有没有漂：")
	_dump_rects(hud, cross)

	# ── 逐像素相减 ──
	var w := a.get_width()
	var h := a.get_height()
	var cx := w / 2
	var cy := h / 2
	var pts: Array[Vector2i] = []
	for y in range(cy - PAD, cy + PAD):
		for x in range(cx - PAD, cx + PAD):
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				pts.append(Vector2i(x, y))
	print("\n中心 (%d, %d)；差出来的准星像素 %d 个，包围盒：" % [cx, cy, pts.size()])
	if pts.is_empty():
		print("  （一个都没有 —— 准星没画出来？）")
		quit(1)
		return
	var mn := pts[0]
	var mx := pts[0]
	for p in pts:
		mn.x = mini(mn.x, p.x)
		mn.y = mini(mn.y, p.y)
		mx.x = maxi(mx.x, p.x)
		mx.y = maxi(mx.y, p.y)
	print("  x %d ~ %d（宽 %d）、y %d ~ %d（高 %d）"
		% [mn.x, mx.x, mx.x - mn.x + 1, mn.y, mx.y, mx.y - mn.y + 1])
	print("  相对中心：x %+d ~ %+d、y %+d ~ %+d"
		% [mn.x - cx, mx.x - cx, mn.y - cy, mx.y - cy])
	print("\n中心行 y=%d 差异列：%s" % [cy, _runs(a, b, cy, true, cx)])
	print("中心列 x=%d 差异行：%s" % [cx, _runs(a, b, cx, false, cy)])
	# 逐像素红通道（十六进制）：整格应该是同值块，半透明/抗锯齿会看到中间值
	var row := PackedStringArray()
	for x in range(cx - 24, cx + 26):
		var ca := a.get_pixel(x, cy)
		var cb := b.get_pixel(x, cy)
		row.append("--" if ca == cb else "%02x" % int(ca.r8))
	print("中心行红通道（从 x=%d 起，-- = 与「无准星」图相同）：" % (cx - 24))
	print("  " + " ".join(row))

	# ── 字符图：按颜色分两张 ──
	#   上臂是「粉」、下臂与左右是「黄绿」（live 设置里就是 pink → yellow-green）
	print("\n字符图（`#` = 准星画的像素；左=粉、右=黄绿、`+` = 两者都算）：")
	var head := "      "
	for x in range(cx - PAD, cx + PAD):
		head += "%d" % (absi(x - cx) / 10 % 10)
	print(head + "   ← 十位数（相对中心）")
	for y in range(cy - PAD, cy + PAD):
		var line := "%+4d  " % (y - cy)
		for x in range(cx - PAD, cx + PAD):
			if a.get_pixel(x, y) == b.get_pixel(x, y):
				line += "."
				continue
			var c := a.get_pixel(x, y)
			line += "#" if c.r >= c.g else "+"
		print(line)
	print("（`#` = 偏粉（r≥g，上臂那一色）；`+` = 偏黄绿（下臂/左右臂那一色））")

	# 中心 64×64 放大 8 倍，肉眼确认用
	var crop := a.get_region(Rect2i(cx - 32, cy - 32, 64, 64))
	crop.resize(512, 512, Image.INTERPOLATE_NEAREST)
	crop.save_png(out.path_join("crop.png"))
	print("\n[截图] %s" % out)
	quit(0)
