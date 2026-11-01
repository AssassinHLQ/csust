extends SceneTree
## 探针 10：**截掉地板后做三维连通域**，把房间里的家具一件一件分出来。
##
## 前面所有"找水平面"的尝试都失败，根因是**地板把所有东西连成了一片**：桌腿、
## 椅腿、画架腿都落在地面上，任何基于网格/连通性的分割都会顺着地面漏出去
## （探针 7 只跑出一个 4.97×2.16×6.64 m 的巨块，就是证据）。
##
## 这里换两个约束：
##   1. **只取 y ∈ [0.12, 1.60]** —— 把地板砍掉，家具的腿在 0.12 m 处被切断，
##      于是每件家具变成独立连通体；
##   2. **排除五个墙盒内部的点**（墙盒坐标已经在探针 1 里量准），免得家具
##      贴墙时和墙连成一体。
##
## 输出 `_arisu_captures/_artdesk/probe10.txt` + `p10_*.png`
## 用法：godot --path . --script res://scripts/_probe_art_desk10.gd

const OUT_ABS := "C:/Users/WY157/Desktop/GODOT/_arisu_captures/_artdesk"
const GAME_PATH := "res://scenes/game.tscn"
const VOX := 0.04
## 砍掉地板的切割高度
const CUT_Y := 0.12
## 只看到这个高度（再往上是吊扇 / 灯管 / 挂画，会把相邻家具连起来）
const TOP_Y := 1.60
## 只统计离 Sensei 这么远的（画室很深，远端的东西跟"老师左边"无关）
const NEAR_R := 6.0

## 五个墙盒的世界 AABB（探针 1 实测值，外扩 3 cm）
const WALLS := [
	[-5.879, -5.519, -6.660, 13.776],   # xneg  x0,x1,z0,z1
	[4.526, 4.886, -1.682, 13.805],     # xpos
	[-5.761, 4.800, -6.809, -6.449],    # znegA
	[4.478, 4.838, -6.775, -3.731],     # znegB
	[-5.809, 4.823, 13.531, 13.891],    # zpos
]

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
	_p("等 %d 帧；点数 %d；Sensei %s" % [waited, xyz.size(), str(sp.snappedf(0.01))])

	# ── 过滤 + 体素 ─────────────────────────────────────────────────────────
	var pts := PackedVector3Array()
	var i := 0
	var n := xyz.size()
	var wall_drop := 0
	while i < n:
		var w: Vector3 = pc_xf * xyz[i]
		i += 1
		if w.y < CUT_Y or w.y > TOP_Y:
			continue
		var dx := w.x - sp.x
		var dz := w.z - sp.z
		if dx * dx + dz * dz > NEAR_R * NEAR_R:
			continue
		var in_wall := false
		for wb in WALLS:
			if w.x >= float(wb[0]) and w.x <= float(wb[1]) \
					and w.z >= float(wb[2]) and w.z <= float(wb[3]):
				in_wall = true
				break
		if in_wall:
			wall_drop += 1
			continue
		pts.append(w)
	_p("y∈[%.2f,%.2f]、离 Sensei ≤%.1f m、非墙内 → %d 点（墙内被剔 %d）"
		% [CUT_Y, TOP_Y, NEAR_R, pts.size(), wall_drop])
	if pts.size() < 1000:
		_flush()
		quit(1)
		return

	var vox := {}
	var inv := 1.0 / VOX
	for k in pts.size():
		var p: Vector3 = pts[k]
		var key := Vector3i(int(floor(p.x * inv)), int(floor(p.y * inv)),
			int(floor(p.z * inv)))
		if vox.has(key):
			var lst: PackedInt32Array = vox[key]
			lst.append(k)
			vox[key] = lst
		else:
			vox[key] = PackedInt32Array([k])
	_p("体素 %.0f cm → %d 个" % [VOX * 100.0, vox.size()])

	# ── 26 邻接洪水填充 ────────────────────────────────────────────────────
	var visited := {}
	var comps: Array = []
	for start in vox.keys():
		if visited.has(start):
			continue
		var stack: Array[Vector3i] = [start]
		visited[start] = true
		var members: PackedInt32Array = PackedInt32Array()
		while not stack.is_empty():
			var ck: Vector3i = stack.pop_back()
			members.append_array(vox[ck])
			for dz in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					for dx2 in [-1, 0, 1]:
						var nk := Vector3i(ck.x + dx2, ck.y + dy, ck.z + dz)
						if vox.has(nk) and not visited.has(nk):
							visited[nk] = true
							stack.append(nk)
		if members.size() < 400:
			continue
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for mi in members.size():
			var p2: Vector3 = pts[members[mi]]
			lo = lo.min(p2)
			hi = hi.max(p2)
		comps.append({"pts": members.size(), "lo": lo, "hi": hi,
			"size": hi - lo, "members": members})
	comps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["pts"]) > int(b["pts"]))

	_p("\n=== 连通体（≥400 点，按点数倒序） ===")
	_p("  n   点数    尺寸 W×H×D          世界 AABB x/y/z                          中心相对Sensei")
	var shown := 0
	for c in comps:
		var d: Dictionary = c
		if shown >= 18:
			break
		shown += 1
		var lo2: Vector3 = d["lo"]
		var hi2: Vector3 = d["hi"]
		var sz: Vector3 = d["size"]
		_p("  %-2d %6d  %5.2f×%5.2f×%5.2f  x[%6.2f,%6.2f] y[%5.2f,%5.2f] z[%6.2f,%6.2f]  Δ(%5.2f,%5.2f)"
			% [shown, int(d["pts"]), sz.x, sz.y, sz.z, lo2.x, hi2.x, lo2.y, hi2.y,
				lo2.z, hi2.z, (lo2.x + hi2.x) * 0.5 - sp.x,
				(lo2.z + hi2.z) * 0.5 - sp.z])

	# ── 桌面判据 ───────────────────────────────────────────────────────────
	_p("\n=== 桌面判据（外框 0.5~2.5 m 见方、高 0.5~1.5、顶面 y 0.6~1.1、点数 ≥3000） ===")
	var desks: Array = []
	for c in comps:
		var d: Dictionary = c
		var sz: Vector3 = d["size"]
		var hi2: Vector3 = d["hi"]
		var lo2: Vector3 = d["lo"]
		if sz.x < 0.5 or sz.x > 2.5 or sz.z < 0.5 or sz.z > 2.5:
			continue
		if sz.y < 0.5 or sz.y > 1.5:
			continue
		if hi2.y < 0.60 or hi2.y > 1.10:
			continue
		if int(d["pts"]) < 3000:
			continue
		desks.append(d)
		_p("  ✔ 点数 %6d  %5.2f×%5.2f×%5.2f  顶 y=%.3f  底 y=%.3f  x[%.2f,%.2f] z[%.2f,%.2f]"
			% [int(d["pts"]), sz.x, sz.y, sz.z, hi2.y, lo2.y, lo2.x, hi2.x, lo2.z, hi2.z])
	if desks.is_empty():
		_p("  （一个都没有 —— 说明桌面和别的东西连成一体了）")

	# ── 出图：候选各染一色 + 图例 ───────────────────────────────────────────
	var colors := [Color(1.0, 0.10, 0.05), Color(0.10, 1.0, 0.20), Color(0.15, 0.35, 1.0),
		Color(1.0, 0.95, 0.10), Color(1.0, 0.15, 0.90), Color(0.10, 1.0, 1.0)]
	var k2 := 0
	for d in desks:
		if k2 >= 6:
			break
		var members: PackedInt32Array = d["members"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var bm := SphereMesh.new()
		bm.radius = 0.012
		bm.height = 0.024
		bm.radial_segments = 5
		bm.rings = 3
		mm.mesh = bm
		mm.instance_count = members.size()
		for mi in members.size():
			mm.set_instance_transform(mi, Transform3D(Basis.IDENTITY, pts[members[mi]]))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = colors[k2 % colors.size()]
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true
		mat.render_priority = 6
		mmi.material_override = mat
		root.add_child(mmi)
		k2 += 1

	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.02
	cam.far = 400.0
	root.add_child(cam)
	var player := game.get_node_or_null("Player") as Node3D
	var ppos := player.global_position if player != null else Vector3(0.0, 0.0, 6.0)
	cam.global_position = Vector3(ppos.x, ppos.y + 1.57, ppos.z)
	cam.look_at(Vector3(sp.x, sp.y + 1.30, sp.z), Vector3.UP)
	cam.make_current()
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	var vp := root.get_visible_rect().size
	var legend := PackedStringArray()
	for k3 in mini(desks.size(), 6):
		var d3: Dictionary = desks[k3]
		var lo3: Vector3 = d3["lo"]
		var hi3: Vector3 = d3["hi"]
		var sz3: Vector3 = d3["size"]
		legend.append("#%d %.2f×%.2f×%.2f  x[%.2f,%.2f] z[%.2f,%.2f] top y%.2f"
			% [k3 + 1, sz3.x, sz3.y, sz3.z, lo3.x, hi3.x, lo3.z, hi3.z, hi3.y])
	var lt := Label.new()
	lt.text = "\n".join(legend)
	lt.position = Vector2(10.0, vp.y * 0.60)
	lt.add_theme_color_override("font_color", Color(1, 1, 1))
	lt.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lt.add_theme_constant_override("outline_size", 8)
	lt.add_theme_font_size_override("font_size", 24)
	layer.add_child(lt)
	for _i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT_ABS.path_join("p10_00_desks.png"))
	_p("\n[img] p10_00_desks.png（%d 个候选染色）" % mini(desks.size(), 6))

	_flush()
	quit(0)


func _p(s: String) -> void:
	_rep.append(s)


func _flush() -> void:
	var f := FileAccess.open(OUT_ABS.path_join("probe10.txt"), FileAccess.WRITE)
	if f == null:
		print("\n".join(_rep))
		return
	f.store_string("\n".join(_rep) + "\n")
	f.close()
	print("[probe10] 写入 %s/probe10.txt" % OUT_ABS)