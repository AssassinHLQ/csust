extends SceneTree
## 探针 13（定位定案）：**收窄矩形 + 限深**的屏幕拾取，直接算出桌子 AABB。
##
## 探针 9 的矩形偏大（u1 到 0.480、v0 到 0.500），把远处走廊和近处地板都框了进来，
## 于是报出 5 × 11 m 的假框。从 p6 网格图读准的桌面范围是
##   u 0.345~0.437（再右就是 Sensei/同伴）、v 0.552~0.805（0.50 以上是远端墙）。
## 再加景深上限 6 m，把远处一切切掉。
##
## 输出 `_arisu_captures/_artdesk/probe13.txt` + `p13_00_pick.png`
## 用法：godot --path . --script res://scripts/_probe_art_desk13.gd

const OUT_ABS := "C:/Users/WY157/Desktop/GODOT/_arisu_captures/_artdesk"
const GAME_PATH := "res://scenes/game.tscn"
const W := 1280
const H := 720
const MAX_DIST := 6.0

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
	var sensei := game.get_node_or_null("Sensei") as Node3D
	if sensei != null:
		(sensei as Node3D).visible = false   # 老师自己挡住桌子右半边

	var splat := room.get("splat_node") as Node3D
	var res: Resource = splat.get("gaussian")
	var xyz: PackedVector3Array = res.get("xyz")
	var pc_xf: Transform3D = room.global_transform * splat.transform
	var player := game.get_node_or_null("Player") as Node3D
	var ppos := player.global_position if player != null else Vector3(0.0, 0.0, 6.0)
	var eye := Vector3(ppos.x, ppos.y + 1.57, ppos.z)
	var sp := Vector3(1.8, 0.0, 2.6)

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
	_p("等 %d 帧；视口 %s；相机 %s" % [waited, str(vp), str(eye.snappedf(0.01))])

	# ── 逐候选矩形 ─────────────────────────────────────────────────────────
	var boxes := [
		{"n": "tight", "u0": 0.345, "v0": 0.552, "u1": 0.437, "v1": 0.805},
		{"n": "top_only", "u0": 0.345, "v0": 0.552, "u1": 0.437, "v1": 0.620},
		{"n": "body_only", "u0": 0.345, "v0": 0.620, "u1": 0.437, "v1": 0.805},
		{"n": "wide", "u0": 0.330, "v0": 0.545, "u1": 0.450, "v1": 0.820},
	]
	# z-buffer（每像素最近点，仅限 MAX_DIST 内）
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
		var d := w.distance_to(eye)
		if d > MAX_DIST:
			continue
		var s := cam.unproject_position(w)
		var px := int(s.x / vp.x * float(W))
		var py := int(s.y / vp.y * float(H))
		if px < 0 or px >= W or py < 0 or py >= H:
			continue
		var k := px + py * W
		if d < zbuf[k]:
			zbuf[k] = d
			pw[k] = w

	_p("\n=== 限深 %.1f m 后的框拾取 ===" % MAX_DIST)
	var chosen: Dictionary = {}
	for bd in boxes:
		var d2: Dictionary = bd
		var u0 := float(d2["u0"])
		var v0 := float(d2["v0"])
		var u1 := float(d2["u1"])
		var v1 := float(d2["v1"])
		var x0 := int(u0 * float(W))
		var y0 := int(v0 * float(H))
		var x1 := int(u1 * float(W))
		var y1 := int(v1 * float(H))
		var pts := PackedVector3Array()
		for py in range(y0, mini(y1, H)):
			for px in range(x0, mini(x1, W)):
				var k2 := px + py * W
				if zbuf[k2] < 1e8:
					pts.append(pw[k2])
		_p("\n[%s] uv(%.3f,%.3f)-(%.3f,%.3f) → %d px" % [String(d2["n"]), u0, v0, u1, v1,
			pts.size()])
		if pts.size() < 40:
			continue
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for p in pts:
			lo = lo.min(p)
			hi = hi.max(p)
		_p("  AABB x[%6.3f,%6.3f] y[%6.3f,%6.3f] z[%6.3f,%6.3f]  尺寸 %.2f×%.2f×%.2f"
			% [lo.x, hi.x, lo.y, hi.y, lo.z, hi.z, hi.x - lo.x, hi.y - lo.y, hi.z - lo.z])
		# y 直方图（5 cm）
		var hist := PackedInt32Array()
		hist.resize(40)
		hist.fill(0)
		for p in pts:
			var bi := int(p.y / 0.05)
			if bi >= 0 and bi < 40:
				hist[bi] += 1
		var hs := PackedStringArray()
		for bi in 40:
			if hist[bi] > 20:
				hs.append("%.2f:%d" % [float(bi) * 0.05, hist[bi]])
		_p("  y 直方图(>20)：%s" % " ".join(hs))
		d2["pts"] = pts
		d2["lo"] = lo
		d2["hi"] = hi
		if String(d2["n"]) == "tight":
			chosen = d2

	# ── 把 tight 框到的点染红贴回去 ─────────────────────────────────────────
	if chosen.has("pts"):
		var pts3: PackedVector3Array = chosen["pts"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var bm := SphereMesh.new()
		bm.radius = 0.011
		bm.height = 0.022
		bm.radial_segments = 5
		bm.rings = 3
		mm.mesh = bm
		mm.instance_count = pts3.size()
		for mi in pts3.size():
			mm.set_instance_transform(mi, Transform3D(Basis.IDENTITY, pts3[mi]))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.10, 0.05)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true
		mat.render_priority = 6
		mmi.material_override = mat
		root.add_child(mmi)
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	var rd: Dictionary = boxes[0]
	var p0 := Vector2(float(rd["u0"]) * vp.x, float(rd["v0"]) * vp.y)
	var p1 := Vector2(float(rd["u1"]) * vp.x, float(rd["v1"]) * vp.y)
	for seg in [[p0, Vector2(p1.x, p0.y)], [p1, Vector2(p0.x, p1.y)]]:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var cr := ColorRect.new()
		cr.color = Color(0.1, 1.0, 0.2)
		cr.position = a.min(b) - Vector2(1.5, 1.5)
		cr.size = (b - a).abs() + Vector2(3, 3)
		layer.add_child(cr)
	for _i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT_ABS.path_join("p13_00_pick.png"))
	_p("\n[img] p13_00_pick.png")

	_flush()
	quit(0)


func _p(s: String) -> void:
	_rep.append(s)


func _flush() -> void:
	var f := FileAccess.open(OUT_ABS.path_join("probe13.txt"), FileAccess.WRITE)
	if f == null:
		print("\n".join(_rep))
		return
	f.store_string("\n".join(_rep) + "\n")
	f.close()
	print("[probe13] 写入 %s/probe13.txt" % OUT_ABS)