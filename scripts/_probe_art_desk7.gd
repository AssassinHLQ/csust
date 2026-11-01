extends SceneTree
## 探针 7：在屏幕粗框内做**三维连通域**，把桌子作为一个独立物体切出来。
##
## 为什么不再靠屏幕矩形：桌子和它前面的靠背椅在屏幕上**重叠**（椅子背挡在桌沿前），
## 任何一块屏幕矩形都会同时框到两件东西。但它们在三维里是分开的两个连通体 ——
## 桌子离椅子 40 cm 以上。所以：先在屏幕上粗框一个**足够大**的范围（允许框进椅子、
## 地板、画架），再做 3 cm 体素的 26 邻接洪水填充，每个连通体单独报尺寸。
## 桌子会以一个「1.2 × 0.8 m 上下、点数上万」的体出现，和椅子/地板/墙分得开。
##
## 输出 `_arisu_captures/_artdesk/probe07.txt` + `p7_*.png`
## 用法：godot --path . --script res://scripts/_probe_art_desk7.gd

const OUT_ABS := "C:/Users/WY157/Desktop/GODOT/_arisu_captures/_artdesk"
const GAME_PATH := "res://scenes/game.tscn"
const VOX := 0.03
const W := 1024
const H := 576
## 粗框（归一化）。故意放宽：宁可多框，连通域会把多余的剔掉。
const BOX_U0 := 0.26
const BOX_U1 := 0.58
const BOX_V0 := 0.42
const BOX_V1 := 0.88
## 景深上限：再远的点（对墙、对走廊尽头）不要，免得整个房间连成一体
const MAX_DIST := 9.0

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
	var vp := root.get_visible_rect().size
	_p("等 %d 帧；点数 %d；视口 %s" % [waited, xyz.size(), str(vp)])
	_p("相机 %s → Sensei %s" % [str(eye.snappedf(0.01)), str(sp.snappedf(0.01))])
	for _i in 10:
		await process_frame

	# ── 收集粗框内、近景的点 ────────────────────────────────────────────────
	var keep := PackedVector3Array()
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
		var u := s.x / vp.x
		var v := s.y / vp.y
		if u < BOX_U0 or u > BOX_U1 or v < BOX_V0 or v > BOX_V1:
			continue
		keep.append(w)
	_p("粗框 u[%.2f,%.2f] v[%.2f,%.2f] 景深 ≤%.1f m → %d 点"
		% [BOX_U0, BOX_U1, BOX_V0, BOX_V1, MAX_DIST, keep.size()])
	if keep.is_empty():
		_flush()
		quit(1)
		return

	# ── 3 cm 体素哈希 ──────────────────────────────────────────────────────
	var vox := {}
	var inv := 1.0 / VOX
	for k in keep.size():
		var p: Vector3 = keep[k]
		var key := Vector3i(int(floor(p.x * inv)), int(floor(p.y * inv)),
			int(floor(p.z * inv)))
		if vox.has(key):
			var lst: PackedInt32Array = vox[key]
			lst.append(k)
			vox[key] = lst
		else:
			vox[key] = PackedInt32Array([k])
	_p("体素 %.0f cm → %d 个体素（%d 点）" % [VOX * 100.0, vox.size(), keep.size()])

	var visited := {}
	var comps: Array = []
	for start in vox.keys():
		if visited.has(start):
			continue
		var stack: Array[Vector3i] = [start]
		visited[start] = true
		var members: PackedInt32Array = PackedInt32Array()
		var vcount := 0
		while not stack.is_empty():
			var ck: Vector3i = stack.pop_back()
			vcount += 1
			members.append_array(vox[ck])
			for dz in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						var nk := Vector3i(ck.x + dx, ck.y + dy, ck.z + dz)
						if vox.has(nk) and not visited.has(nk):
							visited[nk] = true
							stack.append(nk)
		if members.size() < 300:
			continue
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for mi in members.size():
			var p2: Vector3 = keep[members[mi]]
			lo = lo.min(p2)
			hi = hi.max(p2)
		comps.append({
			"pts": members.size(), "vox": vcount, "lo": lo, "hi": hi,
			"size": hi - lo, "members": members,
		})
	comps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["pts"]) > int(b["pts"]))
	_p("\n=== 连通域（≥300 点），按点数倒序 ===")
	_p("  n  点数   体素   尺寸 W×H×D          世界 AABB x/y/z")
	var shown := 0
	for c in comps:
		var d: Dictionary = c
		if shown >= 14:
			break
		shown += 1
		var lo: Vector3 = d["lo"]
		var hi: Vector3 = d["hi"]
		var sz: Vector3 = d["size"]
		_p("  %-2d %6d %6d  %5.2f×%5.2f×%5.2f   x[%7.2f,%7.2f] y[%6.2f,%6.2f] z[%7.2f,%7.2f]"
			% [shown, int(d["pts"]), int(d["vox"]), sz.x, sz.y, sz.z,
				lo.x, hi.x, lo.y, hi.y, lo.z, hi.z])

	# ── 桌面判据：水平尺寸 ≥0.8×0.4、高 0.5~1.3、顶面 y∈[0.6,1.0]、点数多 ──
	_p("\n=== 桌面判据筛选（宽≥0.80、深≥0.40、高 0.4~1.3、顶面 y 0.55~1.05） ===")
	var desks: Array = []
	for c in comps:
		var d: Dictionary = c
		var sz: Vector3 = d["size"]
		var lo: Vector3 = d["lo"]
		var hi: Vector3 = d["hi"]
		var horiz_ok := (sz.x >= 0.80 and sz.z >= 0.40) or (sz.z >= 0.80 and sz.x >= 0.40)
		if horiz_ok and sz.y >= 0.40 and sz.y <= 1.30 and hi.y >= 0.55 and hi.y <= 1.05:
			desks.append(d)
			_p("  ✔ 点数 %6d  尺寸 %5.2f×%5.2f×%5.2f  顶面 y=%.3f  底面 y=%.3f  AABB x[%.2f,%.2f] z[%.2f,%.2f]"
				% [int(d["pts"]), sz.x, sz.y, sz.z, hi.y, lo.y, lo.x, hi.x, lo.z, hi.z])
	if desks.is_empty():
		_p("  （无）")

	# ── 出图：把每个候选染成不同颜色贴回去 ──────────────────────────────────
	var colors := [
		Color(1.0, 0.15, 0.10), Color(0.15, 1.0, 0.25), Color(0.2, 0.4, 1.0),
		Color(1.0, 0.9, 0.1), Color(1.0, 0.2, 0.9), Color(0.1, 1.0, 1.0),
	]
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	var legend := PackedStringArray()
	for k in mini(desks.size(), 6):
		var d: Dictionary = desks[k]
		var members: PackedInt32Array = d["members"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var bm := SphereMesh.new()
		bm.radius = 0.010
		bm.height = 0.020
		bm.radial_segments = 5
		bm.rings = 3
		mm.mesh = bm
		mm.instance_count = members.size()
		for mi in members.size():
			mm.set_instance_transform(mi,
				Transform3D(Basis.IDENTITY, keep[members[mi]]))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = colors[k % colors.size()]
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true
		mat.render_priority = 5
		mmi.material_override = mat
		root.add_child(mmi)
		var sz2: Vector3 = d["size"]
		var lo2: Vector3 = d["lo"]
		var hi2: Vector3 = d["hi"]
		legend.append("#%d %.2f×%.2f×%.2f 顶y%.2f AABBx[%.2f,%.2f]z[%.2f,%.2f]"
			% [k + 1, sz2.x, sz2.y, sz2.z, hi2.y, lo2.x, hi2.x, lo2.z, hi2.z])
	var txt := Label.new()
	txt.text = "\n".join(legend)
	txt.position = Vector2(10.0, vp.y * 0.55)
	for k in mini(desks.size(), 6):
		var d: Dictionary = desks[k]
		var lo2: Vector3 = d["lo"]
		var hi2: Vector3 = d["hi"]
		var ctr := Vector3((lo2.x + hi2.x) * 0.5, (lo2.y + hi2.y) * 0.5,
			(lo2.z + hi2.z) * 0.5)
		if cam.is_position_behind(ctr):
			continue
		var sl := Label.new()
		sl.text = "→ #%d" % (k + 1)
		sl.position = cam.unproject_position(ctr) + Vector2(6, -12)
		sl.add_theme_color_override("font_color", colors[k % colors.size()])
		sl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		sl.add_theme_constant_override("outline_size", 7)
		sl.add_theme_font_size_override("font_size", 24)
		layer.add_child(sl)
	txt.add_theme_color_override("font_color", Color(1, 1, 1))
	txt.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	txt.add_theme_constant_override("outline_size", 7)
	txt.add_theme_font_size_override("font_size", 17)
	layer.add_child(txt)
	cam.make_current()
	for _i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT_ABS.path_join("p7_00_comps.png"))
	_p("\n[img] p7_00_comps.png（每个候选一色）")

	# 最大候选的正交俯视 + 侧面
	if not desks.is_empty():
		var d0: Dictionary = desks[0]
		var lo3: Vector3 = d0["lo"]
		var hi3: Vector3 = d0["hi"]
		var ctr3 := Vector3((lo3.x + hi3.x) * 0.5, 0.0, (lo3.z + hi3.z) * 0.5)
		var top := Camera3D.new()
		top.projection = Camera3D.PROJECTION_ORTHOGONAL
		top.size = maxf(hi3.x - lo3.x, hi3.z - lo3.z) * 2.0 + 0.8
		top.near = 0.02
		top.far = 30.0
		root.add_child(top)
		top.make_current()
		top.global_position = Vector3(ctr3.x, 6.0, ctr3.z)
		top.look_at(Vector3(ctr3.x, 0.0, ctr3.z), Vector3(0.0, 0.0, -1.0))
		for _i in 10:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT_ABS.path_join("p7_01_top.png"))
		_p("[img] p7_01_top.png size=%.2f m" % top.size)

	_flush()
	quit(0)


func _p(s: String) -> void:
	_rep.append(s)


func _flush() -> void:
	var f := FileAccess.open(OUT_ABS.path_join("probe07.txt"), FileAccess.WRITE)
	if f == null:
		print("\n".join(_rep))
		return
	f.store_string("\n".join(_rep) + "\n")
	f.close()
	print("[probe7] 写入 %s/probe07.txt" % OUT_ABS)