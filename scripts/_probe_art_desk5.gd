extends SceneTree
## 探针 5（订正版）：**屏幕空间框选点云**，把「老师左边那张木办公桌」单独抠出来。
##
## 为什么要这一步：高度图 / 水平面连通块都分不开 —— 桌面前沿被靠背椅（背高约 1.0 m）
## 挡掉一截，桌腿又和画架腿在 5 cm 网格里连成一片。可靠的判据是**在渲染图上指一块
## 矩形**，然后只取该矩形里、每个像素最近的那个点（等价于一次 z-buffer 拾取），
## 背景地板 / 墙会被前台自动挡住。
##
## ⚠️ 相机必须**由 Sensei 反算**，不能手写朝向：上一版把 x 的符号写反，
##    画面直接左右镜像，框到的是一片画架 + 地板（6.2 × 5.1 × 7.1 m）。
##
## 输出 `_arisu_captures/_artdesk/probe05.txt` + `p5_*.png`
## 用法：godot --path . --script res://scripts/_probe_art_desk5.gd

const OUT_ABS := "C:/Users/WY157/Desktop/GODOT/_arisu_captures/_artdesk"
const GAME_PATH := "res://scenes/game.tscn"
## z-buffer 分辨率（和最终 PNG 无关；投影用归一化 uv，所以不影响对位）
const W := 1024
const H := 576

## 待试的框（归一化 u, v, w, h）。
## 基准是 p4_01_spawn_sensei.png：桌面在 u≈0.27~0.41、v≈0.49~0.55，桌腿到 v≈0.81。
const RECTS := [
	{"name": "desk_full", "u": 0.270, "v": 0.480, "w": 0.145, "h": 0.340},
	{"name": "desk_top", "u": 0.272, "v": 0.487, "w": 0.140, "h": 0.075},
	{"name": "desk_right_only", "u": 0.330, "v": 0.490, "w": 0.085, "h": 0.320},
	{"name": "chair_front", "u": 0.300, "v": 0.390, "w": 0.055, "h": 0.430},
]

var _rep := PackedStringArray()
var _vp := Vector2.ONE


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
	_p("等 %d 帧；点数 %d；玩家 %s；Sensei %s"
		% [waited, xyz.size(), str(ppos.snappedf(0.01)), str(sp.snappedf(0.01))])

	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.02
	cam.far = 400.0
	root.add_child(cam)
	var eye := Vector3(ppos.x, ppos.y + 1.57, ppos.z)
	var look := Vector3(sp.x, sp.y + 1.30, sp.z)
	cam.global_position = eye
	cam.look_at(look, Vector3.UP)
	cam.make_current()
	await _settle()
	_p("相机 %s → %s（朝向 %s）" % [str(eye.snappedf(0.01)), str(look.snappedf(0.01)),
		str((-cam.global_transform.basis.z).snappedf(0.001))])

	# ⚠️ 视口尺寸要**在建 z-buffer 的同一刻**读，且投影只用归一化 uv ——
	#    窗口被 `_fit_render_scale` 改成最大化，渲染尺寸和 `get_visible_rect()` 不是一回事。
	_vp = root.get_visible_rect().size
	var img_size := root.get_texture().get_image().get_size()
	_p("视口 %s，实际渲染 %s" % [str(_vp), str(img_size)])

	# ── z-buffer ────────────────────────────────────────────────────────────
	var zbuf := PackedFloat32Array()
	zbuf.resize(W * H)
	zbuf.fill(1e9)
	var pw := PackedVector3Array()
	pw.resize(W * H)
	pw.fill(Vector3.ZERO)
	var t0 := Time.get_ticks_msec()
	var i := 0
	var n := xyz.size()
	var inside := 0
	while i < n:
		var w: Vector3 = pc_xf * xyz[i]
		i += 1
		if cam.is_position_behind(w):
			continue
		var s := cam.unproject_position(w)
		var px := int(s.x / _vp.x * float(W))
		var py := int(s.y / _vp.y * float(H))
		if px < 0 or px >= W or py < 0 or py >= H:
			continue
		var k := px + py * W
		var d := w.distance_to(eye)
		inside += 1
		if d < zbuf[k]:
			zbuf[k] = d
			pw[k] = w
	_p("投影 %d 点进屏，z-buffer %.2f s" % [inside,
		float(Time.get_ticks_msec() - t0) / 1000.0])

	# ── 框选 + 框内按 4 cm 做高度直方图，找「桌面那一层」 ────────────────────
	_p("\n=== 框选 ===")
	var best: Dictionary = {}
	for rd in RECTS:
		# ⚠️ RECTS 是 const，里面的 Dictionary 是**只读**的：直接写 d[...] = ... 会报
		#    "Invalid assignment on read-only value"。必须先 duplicate() 一份。
		var d: Dictionary = (rd as Dictionary).duplicate()
		var u := float(d["u"])
		var v := float(d["v"])
		var ww := float(d["w"])
		var hh := float(d["h"])
		var x0 := int(u * float(W))
		var y0 := int(v * float(H))
		var x1 := int((u + ww) * float(W))
		var y1 := int((v + hh) * float(H))
		var pts := PackedVector3Array()
		for py in range(maxi(y0, 0), mini(y1, H)):
			for px in range(maxi(x0, 0), mini(x1, W)):
				var k2 := px + py * W
				if zbuf[k2] < 1e8:
					pts.append(pw[k2])
		_p("\n  [%s] uv(%.3f,%.3f)+（%.3f,%.3f）→ %d px" % [String(d["name"]),
			u, v, ww, hh, pts.size()])
		if pts.size() < 50:
			_p("    （太少，跳过）")
			continue
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for p in pts:
			lo = lo.min(p)
			hi = hi.max(p)
		_p("    原始 AABB x[%7.3f,%7.3f] y[%7.3f,%7.3f] z[%7.3f,%7.3f]  尺寸 %.2f×%.2f×%.2f"
			% [lo.x, hi.x, lo.y, hi.y, lo.z, hi.z, hi.x - lo.x, hi.y - lo.y, hi.z - lo.z])
		# 高度直方图（2 cm 一格）
		var hist := PackedInt32Array()
		hist.resize(110)
		hist.fill(0)
		for p in pts:
			var b := int((p.y + 0.10) / 0.02)
			if b >= 0 and b < 110:
				hist[b] += 1
		var top := PackedStringArray()
		for b in range(0, 110):
			if hist[b] > 20:
				top.append("%.0fcm:%d" % [-10.0 + float(b) * 2.0, hist[b]])
		_p("    高度直方图（>20 点）：%s" % " ".join(top))
		# 桌面层：y∈[0.60,0.95] 里点数最多的 4 cm 窗口
		var best_lo := 0.0
		var best_n := 0
		var y := 0.60
		while y <= 0.90:
			var s2 := 0
			for p in pts:
				if p.y >= y and p.y < y + 0.04:
					s2 += 1
			if s2 > best_n:
				best_n = s2
				best_lo = y
			y += 0.01
		_p("    最高密度水平层 y=%.2f~%.2f（%d 点 / %.3f m² 投影）"
			% [best_lo, best_lo + 0.04, best_n, float(best_n) * 0.0001])
		# 该层点的 AABB
		var l2 := Vector3(INF, INF, INF)
		var h2 := Vector3(-INF, -INF, -INF)
		var c2 := 0
		for p in pts:
			if p.y >= best_lo and p.y < best_lo + 0.04:
				l2 = l2.min(p)
				h2 = h2.max(p)
				c2 += 1
		if c2 > 10:
			_p("    该层 AABB x[%7.3f,%7.3f] z[%7.3f,%7.3f]  %.2f×%.2f m  y=%.3f"
				% [l2.x, h2.x, l2.z, h2.z, h2.x - l2.x, h2.z - l2.z,
					(l2.y + h2.y) * 0.5])
		d["pts"] = pts
		d["lo"] = lo
		d["hi"] = hi
		d["plane_lo"] = l2
		d["plane_hi"] = h2
		if String(d["name"]) == "desk_full":
			best = d

	# ── 出图：把 desk_full 框到的点画成红球，贴回同一视角 ────────────────────
	var bp: PackedVector3Array = best.get("pts", PackedVector3Array())
	var rd0: Dictionary = RECTS[0]
	var rect := Rect2(float(rd0["u"]), float(rd0["v"]), float(rd0["w"]), float(rd0["h"]))
	await _paint(cam, bp, OUT_ABS.path_join("p5_00_highlight.png"), rect)

	# ── 俯视这张桌子 ────────────────────────────────────────────────────────
	var plo: Vector3 = best["plane_lo"]
	var phi: Vector3 = best["plane_hi"]
	var clo: Vector3 = best["lo"]
	var chi: Vector3 = best["hi"]
	var ctr := Vector3((plo.x + phi.x) * 0.5, 0.0, (plo.z + phi.z) * 0.5)
	var top := Camera3D.new()
	top.projection = Camera3D.PROJECTION_ORTHOGONAL
	top.size = 3.2
	top.near = 0.02
	top.far = 30.0
	root.add_child(top)
	top.make_current()
	top.global_position = Vector3(ctr.x, 6.0, ctr.z)
	top.look_at(Vector3(ctr.x, 0.0, ctr.z), Vector3(0.0, 0.0, -1.0))
	await _settle()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT_ABS.path_join("p5_01_top.png"))
	_p("\n[img] p5_01_top.png 正交俯视 size=3.2 m，中心 %s" % str(ctr.snappedf(0.01)))
	var sd := Camera3D.new()
	sd.fov = 55.0
	sd.near = 0.02
	sd.far = 60.0
	root.add_child(sd)
	sd.make_current()
	sd.global_position = Vector3(ctr.x + 0.4, 1.75, ctr.z + 2.6)
	sd.look_at(Vector3(ctr.x, 0.70, ctr.z), Vector3.UP)
	await _settle()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT_ABS.path_join("p5_02_side.png"))
	_p("[img] p5_02_side.png 相机 (%.2f,%.2f,%.2f)" % [sd.global_position.x,
		sd.global_position.y, sd.global_position.z])
	_p("\n最终：框内全部点 AABB x[%.3f,%.3f] y[%.3f,%.3f] z[%.3f,%.3f]"
		% [clo.x, chi.x, clo.y, chi.y, clo.z, chi.z])

	_flush()
	quit(0)


## 把框选到的点画成红球贴回原视角，并描出矩形
func _paint(cam: Camera3D, pts: PackedVector3Array, path: String, rect: Rect2) -> void:
	if pts.size() > 0:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var bm := SphereMesh.new()
		bm.radius = 0.010
		bm.height = 0.020
		bm.radial_segments = 6
		bm.rings = 3
		mm.mesh = bm
		mm.instance_count = pts.size()
		for i in pts.size():
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pts[i]))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.15, 0.1)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true
		mat.render_priority = 5
		mmi.material_override = mat
		root.add_child(mmi)
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	var vp := root.get_visible_rect().size
	var p0 := Vector2(rect.position.x * vp.x, rect.position.y * vp.y)
	var p1 := Vector2((rect.position.x + rect.size.x) * vp.x,
		(rect.position.y + rect.size.y) * vp.y)
	for seg in [[p0, Vector2(p1.x, p0.y)], [p1, Vector2(p0.x, p1.y)]]:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var cr := ColorRect.new()
		cr.color = Color(1.0, 0.2, 0.1, 0.95)
		cr.position = a.min(b) - Vector2(1, 1)
		cr.size = (b - a).abs() + Vector2(2, 2)
		layer.add_child(cr)
	cam.make_current()
	await _settle()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	_p("\n[img] %s（红球 %d 个）" % [path.get_file(), pts.size()])


func _settle() -> void:
	for _i in 10:
		await process_frame


func _p(s: String) -> void:
	_rep.append(s)


func _flush() -> void:
	var f := FileAccess.open(OUT_ABS.path_join("probe05.txt"), FileAccess.WRITE)
	if f == null:
		print("\n".join(_rep))
		return
	f.store_string("\n".join(_rep) + "\n")
	f.close()
	print("[probe5] 写入 %s/probe05.txt" % OUT_ABS)
