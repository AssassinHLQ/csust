extends SceneTree
## 探针 9：屏幕矩形拾取（订正版）—— 用**真实读出来的**矩形，且同一次跑多个框。
##
## 前面失败的根因：矩形是肉眼在缩略图上估的，而缩略图 1114 px 宽 vs 渲染 2560 px，
## 差 2.3 倍；加上最初手写相机朝向把 x 写反过一次。这一版：
##   1. 相机由 `Sensei` 反算，不手写方向；
##   2. 矩形用 u/v 归一化，和分辨率无关；
##   3. **一次跑多个框、各染一色贴回画面**，看一眼就知道哪个框对了。
##
## 输出 `_arisu_captures/_artdesk/probe09.txt` + `p9_*.png`
## 用法：godot --path . --script res://scripts/_probe_art_desk9.gd

const OUT_ABS := "C:/Users/WY157/Desktop/GODOT/_arisu_captures/_artdesk"
const GAME_PATH := "res://scenes/game.tscn"
const W := 1280
const H := 720

## 归一化矩形（u0, v0, u1, v1）+ 颜色
const BOXES := [
	{"name": "desk_all", "u0": 0.330, "v0": 0.500, "u1": 0.480, "v1": 0.845,
		"col": Color(1.0, 0.10, 0.05)},
	{"name": "desk_top", "u0": 0.335, "v0": 0.505, "u1": 0.478, "v1": 0.585,
		"col": Color(0.10, 1.0, 0.20)},
	{"name": "desk_front", "u0": 0.400, "v0": 0.600, "u1": 0.480, "v1": 0.830,
		"col": Color(0.15, 0.35, 1.0)},
	{"name": "desk_inner", "u0": 0.345, "v0": 0.545, "u1": 0.430, "v1": 0.805,
		"col": Color(1.0, 0.95, 0.10)},
]

var _rep := PackedStringArray()


func _initialize() -> void:
	# 不抢用户前台（AGENTS.md 硬要求，2026-11-09）：取消最大化 + 禁止聚焦 + 挪出屏幕
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
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
	var sensei := game.get_node_or_null("Sensei") as Node3D
	var sp := sensei.global_position if sensei != null else Vector3(1.8, 0.0, 2.6)
	var player := game.get_node_or_null("Player") as Node3D
	var ppos := player.global_position if player != null else Vector3(0.0, 0.0, 6.0)
	var eye := Vector3(ppos.x, ppos.y + 1.57, ppos.z)

	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.02
	cam.far = 400.0
	root.add_child(cam)
	cam.global_position = eye
	cam.look_at(Vector3(sp.x, sp.y + 1.30, sp.z), Vector3.UP)
	cam.make_current()
	for _i in 10:
		await process_frame
	var vp := root.get_visible_rect().size
	_p("等 %d 帧；视口 %s；相机 %s → %s" % [waited, str(vp),
		str(eye.snappedf(0.01)), str(sp.snappedf(0.01))])

	# ── z-buffer（每像素最近点） ─────────────────────────────────────────────
	var zbuf := PackedFloat32Array()
	zbuf.resize(W * H)
	zbuf.fill(1e9)
	var pw := PackedVector3Array()
	pw.resize(W * H)
	pw.fill(Vector3.ZERO)
	var i := 0
	var n := xyz.size()
	while i < n:
		var w: Vector3 = pc_xf * xyz[i]
		i += 1
		if cam.is_position_behind(w):
			continue
		var s := cam.unproject_position(w)
		var px := int(s.x / vp.x * float(W))
		var py := int(s.y / vp.y * float(H))
		if px < 0 or px >= W or py < 0 or py >= H:
			continue
		var d := w.distance_to(eye)
		var k := px + py * W
		if d < zbuf[k]:
			zbuf[k] = d
			pw[k] = w

	# ── 逐框：拾取 + 统计 ───────────────────────────────────────────────────
	_p("\n=== 框拾取 ===")
	var painted: Array = []
	for bd in BOXES:
		var d: Dictionary = (bd as Dictionary).duplicate()
		var u0 := float(d["u0"])
		var v0 := float(d["v0"])
		var u1 := float(d["u1"])
		var v1 := float(d["v1"])
		var x0 := int(u0 * float(W))
		var y0 := int(v0 * float(H))
		var x1 := int(u1 * float(W))
		var y1 := int(v1 * float(H))
		var pts := PackedVector3Array()
		for py in range(maxi(y0, 0), mini(y1, H)):
			for px in range(maxi(x0, 0), mini(x1, W)):
				var k2 := px + py * W
				if zbuf[k2] < 1e8:
					pts.append(pw[k2])
		_p("\n[%s] uv(%.3f,%.3f)-(%.3f,%.3f) → %d px" % [String(d["name"]), u0, v0, u1, v1,
			pts.size()])
		if pts.size() < 40:
			continue
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for p in pts:
			lo = lo.min(p)
			hi = hi.max(p)
		_p("  全框 AABB x[%7.2f,%7.2f] y[%6.2f,%6.2f] z[%7.2f,%7.2f]  %.2f×%.2f×%.2f"
			% [lo.x, hi.x, lo.y, hi.y, lo.z, hi.z, hi.x - lo.x, hi.y - lo.y, hi.z - lo.z])
		# 直方图（5 cm）
		var hist := PackedInt32Array()
		hist.resize(60)
		hist.fill(0)
		for p in pts:
			var bi := int((p.y + 0.20) / 0.05)
			if bi >= 0 and bi < 60:
				hist[bi] += 1
		var hs := PackedStringArray()
		for bi in 60:
			if hist[bi] > 30:
				hs.append("%+.2f:%d" % [-0.20 + float(bi) * 0.05, hist[bi]])
		_p("  高度直方图(>30)：%s" % " ".join(hs))
		# 桌面：找 0.55~1.0 之间最密的一层，再取该层水平 AABB
		var best_y := 0.0
		var best_c := 0
		var yy := 0.55
		while yy <= 0.95:
			var cc := 0
			for p in pts:
				if p.y >= yy and p.y < yy + 0.04:
					cc += 1
			if cc > best_c:
				best_c = cc
				best_y = yy
			yy += 0.01
		var plo := Vector3(INF, INF, INF)
		var phi := Vector3(-INF, -INF, -INF)
		var pc2 := 0
		for p in pts:
			if p.y >= best_y and p.y < best_y + 0.04:
				plo = plo.min(p)
				phi = phi.max(p)
				pc2 += 1
		if pc2 > 10:
			_p("  桌面层 y∈[%.3f,%.3f] %d 点 水平 AABB x[%7.2f,%7.2f] z[%7.2f,%7.2f]  %.2f×%.2f"
				% [best_y, best_y + 0.04, pc2, plo.x, phi.x, plo.z, phi.z,
					phi.x - plo.x, phi.z - plo.z])
		# 桌下（0.15~0.55）有没有东西 = 抽屉柜
		var lowc := 0
		var llo := Vector3(INF, INF, INF)
		var lhi := Vector3(-INF, -INF, -INF)
		for p in pts:
			if p.y >= 0.12 and p.y <= 0.58:
				lowc += 1
				llo = llo.min(p)
				lhi = lhi.max(p)
		if lowc > 10:
			_p("  桌下层(0.12~0.58) %d 点 水平 AABB x[%7.2f,%7.2f] z[%7.2f,%7.2f]"
				% [lowc, llo.x, lhi.x, llo.z, lhi.z])
		d["pts"] = pts
		d["lo"] = lo
		d["hi"] = hi
		painted.append(d)

	# ── 每个框一色贴回画面 ──────────────────────────────────────────────────
	for d in painted:
		var pts2: PackedVector3Array = d["pts"]
		var col: Color = d["col"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var bm := SphereMesh.new()
		bm.radius = 0.011
		bm.height = 0.022
		bm.radial_segments = 5
		bm.rings = 3
		mm.mesh = bm
		mm.instance_count = pts2.size()
		for mi in pts2.size():
			mm.set_instance_transform(mi, Transform3D(Basis.IDENTITY, pts2[mi]))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = col
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true
		mat.render_priority = 5
		mmi.material_override = mat
		root.add_child(mmi)
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	var legend := PackedStringArray()
	for d in painted:
		var lo2: Vector3 = d["lo"]
		var hi2: Vector3 = d["hi"]
		var sz := hi2 - lo2
		legend.append("%s  %.2f×%.2f×%.2f  x[%.2f,%.2f] z[%.2f,%.2f]"
			% [String(d["name"]), sz.x, sz.y, sz.z, lo2.x, hi2.x, lo2.z, hi2.z])
	var txt := Label.new()
	txt.text = "\n".join(legend)
	txt.position = Vector2(10.0, vp.y * 0.62)
	txt.add_theme_color_override("font_color", Color(1, 1, 1))
	txt.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	txt.add_theme_constant_override("outline_size", 8)
	txt.add_theme_font_size_override("font_size", 22)
	layer.add_child(txt)
	# 矩形描边
	for d in painted:
		var col2: Color = d["col"]
		var p0 := Vector2(float(d["u0"]) * vp.x, float(d["v0"]) * vp.y)
		var p1 := Vector2(float(d["u1"]) * vp.x, float(d["v1"]) * vp.y)
		for seg in [[p0, Vector2(p1.x, p0.y)], [p1, Vector2(p0.x, p1.y)]]:
			var a: Vector2 = seg[0]
			var b: Vector2 = seg[1]
			var cr := ColorRect.new()
			cr.color = col2
			cr.position = a.min(b) - Vector2(1.5, 1.5)
			cr.size = (b - a).abs() + Vector2(3, 3)
			layer.add_child(cr)
	for _i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT_ABS.path_join("p9_00_boxes.png"))
	_p("\n[img] p9_00_boxes.png")

	_flush()
	quit(0)


func _p(s: String) -> void:
	_rep.append(s)


func _flush() -> void:
	var f := FileAccess.open(OUT_ABS.path_join("probe09.txt"), FileAccess.WRITE)
	if f == null:
		print("\n".join(_rep))
		return
	f.store_string("\n".join(_rep) + "\n")
	f.close()
	print("[probe9] 写入 %s/probe09.txt" % OUT_ABS)