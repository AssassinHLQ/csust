extends SceneTree
## 探针 12（定位收尾）：正交俯视 + **世界坐标网格**，把桌子的四条边直接读出来。
##
## 前面几版为什么定不准：屏幕矩形总会连背景（透视重叠），点云连通域顺着地板漏成
## 一整片。这一版换成正交俯视 —— 正交投影**没有透视缩放**，1 m = 固定像素数，
## 于是画上 0.25 m 的网格并标注米数之后，桌面的四条边可以直接读成世界坐标。
## 同时打印该 footpring 内点云的 y 直方图，确认桌面高度。
##
## 输出 `_arisu_captures/_artdesk/probe12.txt` + `p12_*.png`
## 用法：godot --path . --script res://scripts/_probe_art_desk12.gd

const OUT_ABS := "C:/Users/WY157/Desktop/GODOT/_arisu_captures/_artdesk"
const GAME_PATH := "res://scenes/game.tscn"
## 正交俯视的中心与世界尺寸（米）
const VIEW_CTR := Vector2(1.35, 1.55)
const VIEW_SIZE := 5.0

var _rep := PackedStringArray()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_ABS)
	var game: Node = (load(GAME_PATH) as PackedScene).instantiate()
	root.add_child(game)
	var room := game.get_node_or_null("Room609") as Node3D
	var waited := 0
	while waited < 9000 and (room == null or not bool(room.call("is_ready"))):
		await process_frame
		waited += 1
	paused = false
	for c in game.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
		elif c is Companion:
			(c as Node3D).visible = false

	var splat := room.get("splat_node") as Node3D
	var res: Resource = splat.get("gaussian")
	var xyz: PackedVector3Array = res.get("xyz")
	var pc_xf: Transform3D = room.global_transform * splat.transform
	_p("等 %d 帧；点数 %d" % [waited, xyz.size()])

	# ── 该 footprint 内的 y 直方图（1 cm 一格，只统计 0.30~1.30 m） ────────
	var x0 := VIEW_CTR.x - VIEW_SIZE * 0.5
	var x1 := VIEW_CTR.x + VIEW_SIZE * 0.5
	var z0 := VIEW_CTR.y - VIEW_SIZE * 0.5
	var z1 := VIEW_CTR.y + VIEW_SIZE * 0.5
	var hist := PackedInt32Array()
	hist.resize(101)
	hist.fill(0)
	var i := 0
	var n := xyz.size()
	while i < n:
		var w: Vector3 = pc_xf * xyz[i]
		i += 1
		if w.x < x0 or w.x > x1 or w.z < z0 or w.z > z1:
			continue
		if w.y < 0.30 or w.y > 1.30:
			continue
		var b := int((w.y - 0.30) / 0.01)
		if b >= 0 and b < 101:
			hist[b] += 1
	_p("\n=== y 直方图（x[%.2f,%.2f] z[%.2f,%.2f]，1 cm 一格，>500 点才列） ==="
		% [x0, x1, z0, z1])
	var cur := 0.0
	while cur < 1.30:
		var b2 := int((cur - 0.30) / 0.01)
		if b2 >= 0 and b2 < 101 and hist[b2] > 500:
			_p("  y=%.2f : %6d %s" % [cur, hist[b2], "#".repeat(int(minf(
				float(hist[b2]) / 400.0, 60.0)))])
		cur += 0.01

	# ── 正交俯视 ───────────────────────────────────────────────────────────
	var top := Camera3D.new()
	top.projection = Camera3D.PROJECTION_ORTHOGONAL
	top.size = VIEW_SIZE
	top.near = 0.02
	top.far = 40.0
	root.add_child(top)
	# ⚠️ 相机必须放在**天花板以下**：`content_top_y()` = 5.43 m，从 8 m 俯视拍到的是
	#    天花板顶面（整张图糊成一片白）。4.0 m 在吊扇（约 3.2 m）之上、天花板之下。
	top.global_position = Vector3(VIEW_CTR.x, 4.0, VIEW_CTR.y)
	top.look_at(Vector3(VIEW_CTR.x, 0.0, VIEW_CTR.y), Vector3(0.0, 0.0, -1.0))
	top.make_current()
	for _i in 10:
		await process_frame
	var vp := root.get_visible_rect().size
	# 正交：视口高度 = VIEW_SIZE 米，宽度按 aspect 放大
	var m_per_px_v := VIEW_SIZE / vp.y
	var m_per_px_h := VIEW_SIZE / vp.y   # 正交的 size 是**垂直**尺寸，水平按 aspect 自动放大
	var half_w := VIEW_SIZE * 0.5 * (vp.x / vp.y)
	_p("\n正交：视口 %s；垂直 %.4f m/px，水平同（size 是垂直尺寸）→ 水平可见 %.2f m"
		% [str(vp), m_per_px_v, half_w * 2.0])

	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	# 每 0.25 m 一条线，每 1.00 m 加粗 + 标数字
	var gx := floorf(x0 / 0.25) * 0.25
	while gx <= x1:
		var major := absf(fmod(gx + 0.0001, 1.0)) < 0.01
		var sx := vp.x * 0.5 + (gx - VIEW_CTR.x) / m_per_px_h
		var cr := ColorRect.new()
		cr.color = Color(1.0, 0.85, 0.1, 0.9) if major else Color(0.2, 1.0, 1.0, 0.35)
		cr.position = Vector2(sx - (1.5 if major else 0.5), 0.0)
		cr.size = Vector2(3.0 if major else 1.0, vp.y)
		layer.add_child(cr)
		if major:
			var l := _lab("x=%.0f" % gx, Vector2(sx + 3.0, 30.0), 24)
			layer.add_child(l)
		gx += 0.25
	var gz := floorf(z0 / 0.25) * 0.25
	while gz <= z1:
		var major2 := absf(fmod(gz + 0.0001, 1.0)) < 0.01
		var sz := vp.y * 0.5 + (gz - VIEW_CTR.y) / m_per_px_v
		var cr2 := ColorRect.new()
		cr2.color = Color(1.0, 0.85, 0.1, 0.9) if major2 else Color(0.2, 1.0, 1.0, 0.35)
		cr2.position = Vector2(0.0, sz - (1.5 if major2 else 0.5))
		cr2.size = Vector2(vp.x, 3.0 if major2 else 1.0)
		layer.add_child(cr2)
		if major2:
			layer.add_child(_lab("z=%.0f" % gz, Vector2(6.0, sz + 2.0), 24))
		gz += 0.25
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT_ABS.path_join("p12_00_top_grid.png"))
	_p("[img] p12_00_top_grid.png（正交俯视 %.1f m + 0.25 m 网格）" % VIEW_SIZE)

	_flush()
	quit(0)


func _lab(text: String, pos: Vector2, fs: int) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_color_override("font_color", Color(1.0, 0.95, 0.2))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 7)
	l.add_theme_font_size_override("font_size", fs)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _p(s: String) -> void:
	_rep.append(s)


func _flush() -> void:
	var f := FileAccess.open(OUT_ABS.path_join("probe12.txt"), FileAccess.WRITE)
	if f == null:
		print("\n".join(_rep))
		return
	f.store_string("\n".join(_rep) + "\n")
	f.close()
	print("[probe12] 写入 %s/probe12.txt" % OUT_ABS)