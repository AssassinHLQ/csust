extends SceneTree
## 探针：画室609 里「老师左边那张桌子」到底在哪儿，以及现在是不是真的打空。
##
## 为什么不能靠眼睛估：`Room609` 是高斯泼溅（277 万点），不是网格；场景里唯一的
## 碰撞是 `Room609/RoomCollision` 下五个手摆的墙盒。桌子在渲染图上看得见、在
## 物理世界里不存在 —— 所以先用**点云本身**量出家具的高度图（桌面是一个平台），
## 再用**物理点查询**画一张「哪里根本没碰撞」的图，两张对照才敢下结论。
##
## 输出（都写进文件，不依赖控制台编码）：
##   `_arisu_captures/_artdesk/probe01.txt`   全部数字 + 两张 ASCII 图
##   `_arisu_captures/_artdesk/p1_*.png`      若干张房间内部照片
##
## 用法（**不要**加 `--splat=off`，这套测量要真点云；也不要 `--headless`，要出图）：
##   godot --path . --script res://scripts/_probe_art_desk.gd

const OUT_ABS := "C:/Users/WY157/Desktop/GODOT/_arisu_captures/_artdesk"
const GAME_PATH := "res://scenes/game.tscn"
const ROOM_PATH := "Room609"
const WALLS_PATH := "Room609/RoomCollision"
const SENSEI_PATH := "Sensei"

## 点云抽稀步长。277 万点全转要十几秒，取每 3 点一个（约 92 万）足够画高度图。
const STRIDE := 3
## 高度图单元边长（米）。桌面是 0.7~0.8 m 的平板，5 cm 够分辨。
const CELL := 0.05
## 只统计这个高度以下的点：再往上是吊扇 / 灯管 / 天花板，会把整张图糊成一片。
const CEIL_CUT := 2.04
## 桌面高度候选区间（相对地面）。办公桌 0.72~0.80、画桌略高。
const TOP_LO := 0.62
const TOP_HI := 0.95
## 玩家胶囊（照抄 scenes/player.tscn 的 Cap_player）
const CAP_RADIUS := 0.3
const CAP_HEIGHT := 1.5

## 报告行（最后一次性写文件，避免控制台 UTF-16 乱码）
var _rep := PackedStringArray()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(OUT_ABS)

	var game: Node = (load(GAME_PATH) as PackedScene).instantiate()
	root.add_child(game)
	for _i in 90:
		await process_frame
	# 开场剧情在 --script 下不播，但保险：把暂停解开、把 HUD / 同伴藏掉
	paused = false
	for c in game.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
		elif c is Companion:
			(c as Node3D).visible = false

	var room := game.get_node_or_null(ROOM_PATH) as Node3D
	if room == null:
		_p("!! 场景里没有 %s" % ROOM_PATH)
		_flush()
		quit(1)
		return
	var sensei := game.get_node_or_null(SENSEI_PATH) as Node3D

	# ⚠️ 泼溅是**解码线程**：277 万点冷启动约 21 s（有 user:// 缓存约 2 s）。
	#    只等固定帧数会在解码完成前就开始量，`splat_node` 还是 null、高度图全空。
	var waited := 0
	while waited < 9000 and not bool(room.call("is_ready")):
		await process_frame
		waited += 1
	_p("等待泼溅就位：%d 帧（%.1f s），is_ready=%s"
		% [waited, float(waited) / 60.0, str(room.call("is_ready"))])

	# ── A. 节点与变换 ────────────────────────────────────────────────────────
	var xf := room.global_transform
	_p("=== A. Room609 全局变换 ===")
	_p("origin = (%.6f, %.6f, %.6f)" % [xf.origin.x, xf.origin.y, xf.origin.z])
	var b := xf.basis
	_p("basis.x = (%.6f, %.6f, %.6f)" % [b.x.x, b.x.y, b.x.z])
	_p("basis.y = (%.6f, %.6f, %.6f)" % [b.y.x, b.y.y, b.y.z])
	_p("basis.z = (%.6f, %.6f, %.6f)" % [b.z.x, b.z.y, b.z.z])
	var sc := b.get_scale()
	_p("缩放 = (%.6f, %.6f, %.6f)  正交 = %s" % [sc.x, sc.y, sc.z,
		str(absf(b.determinant() - sc.x * sc.y * sc.z) < 1e-5)])
	var kids := PackedStringArray()
	for c in room.get_children():
		kids.append("%s(%s)" % [c.name, c.get_class()])
	_p("子节点 = %s" % ", ".join(kids))
	var splat_node := room.get("splat_node") as Node3D
	_p("splat_node 存在 = %s" % str(splat_node != null))
	if splat_node != null:
		_p("  splat_node 名字 = %s" % splat_node.name)
		var st := splat_node.transform
		_p("  splat_node.origin = (%.6f, %.6f, %.6f)" % [st.origin.x, st.origin.y, st.origin.z])
	_p("Sensei 世界位置 = %s" % [str(sensei.global_position) if sensei != null else "—"])

	# ── B. 五个墙盒的世界 AABB ──────────────────────────────────────────────
	_p("\n=== B. Room609/RoomCollision 的碰撞盒（世界） ===")
	var walls := game.get_node_or_null(WALLS_PATH) as Node3D
	var room_lo := Vector3(INF, INF, INF)
	var room_hi := Vector3(-INF, -INF, -INF)
	var wall_count := 0
	if walls == null:
		_p("!! 没有 %s" % WALLS_PATH)
	else:
		for c in walls.get_children():
			var cs := c as CollisionShape3D
			if cs == null or not (cs.shape is BoxShape3D):
				_p("  %s：不是 BoxShape3D" % c.name)
				continue
			var size: Vector3 = (cs.shape as BoxShape3D).size
			var g := cs.global_transform
			# 墙盒可能带旋转（WallZNegB 是 -90°），用 AABB 拐角变换取真实外框
			var bb: AABB = g * AABB(-size * 0.5, size)
			_p("  %-10s 中心(%7.3f,%7.3f,%7.3f) 尺寸(%6.3f,%6.3f,%6.3f)"
				% [cs.name, g.origin.x, g.origin.y, g.origin.z, size.x, size.y, size.z])
			_p("             世界AABB x[%7.3f,%7.3f] y[%7.3f,%7.3f] z[%7.3f,%7.3f]"
				% [bb.position.x, bb.position.x + bb.size.x,
					bb.position.y, bb.position.y + bb.size.y,
					bb.position.z, bb.position.z + bb.size.z])
			room_lo = room_lo.min(bb.position)
			room_hi = room_hi.max(bb.position + bb.size)
			wall_count += 1
	_p("墙盒 %d 个；房间外框 x[%.3f,%.3f] y[%.3f,%.3f] z[%.3f,%.3f]"
		% [wall_count, room_lo.x, room_hi.x, room_lo.y, room_hi.y, room_lo.z, room_hi.z])

	var space := root.world_3d.direct_space_state
	var exclude: Array[RID] = []
	for n in ["Player", "CompanionKoyuki", "CompanionYuuka", "CompanionNoa",
			"CompanionMomoi", "CompanionMidori", "CompanionYuzu", "CompanionKei"]:
		var co := game.get_node_or_null(n) as CollisionObject3D
		if co != null:
			exclude.append(co.get_rid())

	# ── C. 点云信息 ──────────────────────────────────────────────────────────
	_p("\n=== C. 泼溅点云 ===")
	var xyz := PackedVector3Array()
	var pc_xf := Transform3D()
	if splat_node == null:
		_p("!! 泼溅没加载（是不是加了 --splat=off？），高度图做不了")
	else:
		var res: Resource = splat_node.get("gaussian")
		if res == null:
			_p("!! splat 节点上没有 gaussian 资源")
		else:
			xyz = res.get("xyz")
			pc_xf = room.global_transform * splat_node.transform
			_p("点数 = %d（抽稀步长 %d）" % [xyz.size(), STRIDE])
			var cbox: AABB = room.call("content_world_aabb")
			_p("content_world_aabb pos %s size %s"
				% [str(cbox.position.snappedf(0.01)), str(cbox.size.snappedf(0.01))])

	# ── D. 高度图（每个 5 cm 格子里点云的最大 y） ───────────────────────────
	var nx := int(ceil((room_hi.x - room_lo.x) / CELL)) + 1
	var nz := int(ceil((room_hi.z - room_lo.z) / CELL)) + 1
	var hmap := PackedFloat32Array()
	hmap.resize(nx * nz)
	hmap.fill(-9.0)
	var t0 := Time.get_ticks_msec()
	var sampled := 0
	if xyz.size() > 0:
		var i := 0
		var n := xyz.size()
		while i < n:
			var w: Vector3 = pc_xf * xyz[i]
			if w.y <= CEIL_CUT and w.x >= room_lo.x and w.x <= room_hi.x \
					and w.z >= room_lo.z and w.z <= room_hi.z:
				var ix := int((w.x - room_lo.x) / CELL)
				var iz := int((w.z - room_lo.z) / CELL)
				if ix >= 0 and ix < nx and iz >= 0 and iz < nz:
					var k := ix + iz * nx
					if w.y > hmap[k]:
						hmap[k] = w.y
					sampled += 1
			i += STRIDE
	_p("\n=== D. 高度图（点云俯视最大 y；%d 点进入统计，%.2f s） ==="
		% [sampled, float(Time.get_ticks_msec() - t0) / 1000.0])

	var lows := PackedFloat32Array()
	for k in hmap.size():
		if hmap[k] > -1.0 and hmap[k] < 0.25:
			lows.append(hmap[k])
	var floor_y := 0.0
	if lows.size() > 0:
		lows.sort()
		floor_y = lows[lows.size() / 2]
	_p("地面 y 中位数 = %.3f（%d 个格子）；后续「桌面高度」都相对它" % [floor_y, lows.size()])

	_p("\n粗图：1 格 = %.2f m，列 = +x，行 = +z（第一行 z=%.2f）" % [CELL * 4.0, room_lo.z])
	_p("图例  '.' y<0.10  '-' <0.35  '+' <0.62  '=' <0.95(桌面)  '#' <1.30  'A' <2.04  ' ' 无点")
	_p(_header(nx, room_lo.x, CELL, 4))
	var rows := _ascii(hmap, nx, nz, 4)
	for ri in rows.size():
		_p("%7.2f %s" % [room_lo.z + float(ri) * CELL * 4.0, rows[ri]])

	# ── E. 桌面高度上的连通块 = 候选桌面 ─────────────────────────────────────
	_p("\n=== E. y ∈ [%.2f, %.2f] 的连通块（候选桌面，按面积倒序） ==="
		% [floor_y + TOP_LO, floor_y + TOP_HI])
	var cands: Array = _clusters(hmap, nx, nz, room_lo, floor_y + TOP_LO,
		floor_y + TOP_HI, 12)
	var sensei_pos := Vector3.ZERO
	if sensei != null:
		sensei_pos = sensei.global_position
	var inv := room.global_transform.affine_inverse()
	for c in cands:
		var d: Dictionary = c
		var lo: Vector3 = d["lo"]
		var hi: Vector3 = d["hi"]
		var ctr := (lo + hi) * 0.5
		var lc: Vector3 = inv * ctr
		_p("  #%-2d x[%7.2f,%7.2f] z[%7.2f,%7.2f]  %.2f×%.2f m  面积 %5.2f m²  平均y %.2f"
			% [int(d["id"]), lo.x, hi.x, lo.z, hi.z, hi.x - lo.x, hi.z - lo.z,
				float(d["area"]), float(d["y"])])
		_p("      中心 世界(%7.3f,%6.3f,%7.3f)  局部(%7.3f,%6.3f,%7.3f)  相对Sensei Δ(%.2f,%.2f)"
			% [ctr.x, ctr.y, ctr.z, lc.x, lc.y, lc.z,
				ctr.x - sensei_pos.x, ctr.z - sensei_pos.z])

	var shown := 0
	for c in cands:
		if shown >= 3:
			break
		var d: Dictionary = c
		var lo: Vector3 = d["lo"]
		var hi: Vector3 = d["hi"]
		_p("\n  --- 候选 #%d 细图（1 格 = 0.05 m）---" % int(d["id"]))
		_detail(hmap, nx, nz, room_lo, lo - Vector3(0.5, 0.0, 0.5),
			hi + Vector3(0.5, 0.0, 0.5))
		shown += 1

	# ── F. 物理点查询：这些位置到底有没有碰撞 ────────────────────────────────
	_p("\n=== F. 物理点查询（y=0.50 有碰撞 = 'X'，空 = '.'） ===")
	_p("桌子所在格子若是 '.' 就是打空 —— 这就是「玩家能穿过去」的直接证据")
	_p(_header(nx, room_lo.x, CELL, 4))
	var ri := 0
	while ri < nz:
		var line := ""
		var cix := 0
		while cix < nx:
			var hit := false
			for dz in 4:
				for dx in 4:
					var jx := cix + dx
					var jz := ri + dz
					if jx < nx and jz < nz and _solid(space, exclude, room_lo, jx, jz, 0.50):
						hit = true
			line += "X" if hit else "."
			cix += 4
		_p("%7.2f %s" % [room_lo.z + float(ri) * CELL, line])
		ri += 4

	# ── G. cast_motion：玩家胶囊从桌子一侧走到另一侧 ────────────────────────
	_p("\n=== G. cast_motion（玩家胶囊；1.0 = 一路走通，<1.0 = 被挡） ===")
	var cap := CapsuleShape3D.new()
	cap.radius = CAP_RADIUS
	cap.height = CAP_HEIGHT
	var probe_y := floor_y + 0.80   # 胶囊中心：底面离地 5 cm，只量水平有没有东西挡
	for c in cands:
		var d: Dictionary = c
		var lo: Vector3 = d["lo"]
		var hi: Vector3 = d["hi"]
		var ctr := (lo + hi) * 0.5
		var half_x := (hi.x - lo.x) * 0.5 + 0.9
		var from := Vector3(ctr.x - half_x, probe_y, ctr.z)
		var f := _cast(space, exclude, cap, from, Vector3(half_x * 2.0, 0.0, 0.0))
		_p("  #%-2d 沿 +x 穿过 from(%7.2f,%5.2f,%7.2f) motion(%5.2f,0,0) → safe=%.4f"
			% [int(d["id"]), from.x, from.y, from.z, half_x * 2.0, f])

	var mid_z := (room_lo.z + room_hi.z) * 0.5
	var f_wall := _cast(space, exclude, cap,
		Vector3(room_lo.x + 2.0, probe_y, mid_z), Vector3(-6.0, 0.0, 0.0))
	_p("  对照：朝 x− 墙走 6 m → safe=%.4f（应当 <1.0）" % f_wall)
	var f_door := _cast(space, exclude, cap,
		Vector3(room_lo.x + 4.7, probe_y, room_lo.z + 1.0), Vector3(0.0, 0.0, -6.0))
	_p("  对照：朝 z− 方向走 6 m（门在 z−）→ safe=%.4f" % f_door)

	# ── H. 出图 ──────────────────────────────────────────────────────────────
	_p("\n=== H. 出图 ===")
	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.02
	cam.far = 400.0
	root.add_child(cam)
	cam.make_current()
	var ctr_room := (room_lo + room_hi) * 0.5
	var shots := [
		["p1_a_from_zpos.png", Vector3(ctr_room.x, 1.62, room_hi.z - 2.2),
			Vector3(ctr_room.x, 1.20, room_lo.z + 3.0)],
		["p1_b_from_zneg.png", Vector3(ctr_room.x + 1.0, 1.62, room_lo.z + 2.4),
			Vector3(ctr_room.x, 1.20, room_hi.z - 3.0)],
		["p1_c_from_xneg.png", Vector3(room_lo.x + 1.4, 1.62, ctr_room.z),
			Vector3(room_hi.x - 1.0, 1.20, ctr_room.z)],
		["p1_d_from_xpos.png", Vector3(room_hi.x - 1.4, 1.62, ctr_room.z),
			Vector3(room_lo.x + 1.0, 1.20, ctr_room.z)],
		["p1_e_at_sensei.png", sensei_pos + Vector3(0.0, 1.62, 0.0),
			sensei_pos + Vector3(-4.0, 1.05, -1.0)],
		["p1_f_look_down.png", Vector3(ctr_room.x, 2.60, room_hi.z - 3.0),
			Vector3(ctr_room.x, 0.0, ctr_room.z)],
	]
	for s in shots:
		var pos: Vector3 = s[1]
		var tgt: Vector3 = s[2]
		cam.global_position = pos
		cam.look_at(tgt, Vector3.UP)
		await _shot(cam, OUT_ABS.path_join(String(s[0])))

	_flush()
	quit(0)


## 列号标尺（每 block 个格子打一个 x 的个位数）
func _header(nx: int, x0: float, cell: float, block: int) -> String:
	var hdr := "        "
	var ix := 0
	while ix < nx:
		hdr += str(posmod(int(floor(x0 + float(ix) * cell)), 10))
		ix += block
	return hdr


## 高度图 → 字符行。block = 每格合并多少个 5 cm 单元格。
func _ascii(hmap: PackedFloat32Array, nx: int, nz: int, block: int) -> PackedStringArray:
	var out := PackedStringArray()
	var iz := 0
	while iz < nz:
		var line := ""
		var ix := 0
		while ix < nx:
			var best := -9.0
			for dz in block:
				for dx in block:
					var jx := ix + dx
					var jz := iz + dz
					if jx < nx and jz < nz:
						best = maxf(best, hmap[jx + jz * nx])
			line += _glyph(best)
			ix += block
		out.append(line)
		iz += block
	return out


func _glyph(y: float) -> String:
	if y < -1.0:
		return " "
	if y < 0.10:
		return "."
	if y < 0.35:
		return "-"
	if y < 0.62:
		return "+"
	if y < 0.95:
		return "="
	if y < 1.30:
		return "#"
	return "A"


## 在 [lo,hi] 这个矩形里按 5 cm 画细节图
func _detail(hmap: PackedFloat32Array, nx: int, nz: int, room_lo: Vector3,
		lo: Vector3, hi: Vector3) -> void:
	var x0 := maxi(0, int((lo.x - room_lo.x) / CELL))
	var x1 := mini(nx - 1, int((hi.x - room_lo.x) / CELL))
	var z0 := maxi(0, int((lo.z - room_lo.z) / CELL))
	var z1 := mini(nz - 1, int((hi.z - room_lo.z) / CELL))
	_p(_header(x1 - x0 + 1, room_lo.x + float(x0) * CELL, CELL, 1))
	for iz in range(z0, z1 + 1):
		var line := ""
		for ix in range(x0, x1 + 1):
			line += _glyph(hmap[ix + iz * nx])
		_p("%7.2f %s" % [room_lo.z + float(iz) * CELL, line])


## 桌面高度上的 8 邻接连通块
func _clusters(hmap: PackedFloat32Array, nx: int, nz: int, room_lo: Vector3,
		y_lo: float, y_hi: float, min_cells: int) -> Array:
	var seen := PackedByteArray()
	seen.resize(nx * nz)
	seen.fill(0)
	var out: Array = []
	for iz in nz:
		for ix in nx:
			var k0 := ix + iz * nx
			if seen[k0] != 0:
				continue
			var y0 := hmap[k0]
			if y0 < y_lo or y0 > y_hi:
				continue
			var stack: Array[int] = [k0]
			seen[k0] = 1
			var n := 0
			var lox := float(ix)
			var hix := float(ix)
			var loz := float(iz)
			var hiz := float(iz)
			var ysum := 0.0
			while not stack.is_empty():
				var k: int = stack.pop_back()
				var kx := k % nx
				var kz := k / nx
				n += 1
				ysum += hmap[k]
				lox = minf(lox, float(kx))
				hix = maxf(hix, float(kx))
				loz = minf(loz, float(kz))
				hiz = maxf(hiz, float(kz))
				var dz := -1
				while dz <= 1:
					var dx := -1
					while dx <= 1:
						var jx: int = kx + dx
						var jz: int = kz + dz
						if jx >= 0 and jx < nx and jz >= 0 and jz < nz:
							var jk := jx + jz * nx
							if seen[jk] == 0:
								var yj := hmap[jk]
								if yj >= y_lo and yj <= y_hi:
									seen[jk] = 1
									stack.append(jk)
						dx += 1
					dz += 1
			if n < min_cells:
				continue
			out.append({
				"id": 0,
				"lo": Vector3(room_lo.x + lox * CELL, ysum / float(n),
					room_lo.z + loz * CELL),
				"hi": Vector3(room_lo.x + (hix + 1.0) * CELL, ysum / float(n),
					room_lo.z + (hiz + 1.0) * CELL),
				"area": float(n) * CELL * CELL,
				"cells": n,
				"y": ysum / float(n),
			})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["area"]) > float(b["area"]))
	for i in out.size():
		out[i]["id"] = i + 1
	return out


## 某个网格单元（世界 x,z）在给定 y 上有没有碰撞体
func _solid(space: PhysicsDirectSpaceState3D, exclude: Array[RID],
		room_lo: Vector3, ix: int, iz: int, y: float) -> bool:
	var q := PhysicsPointQueryParameters3D.new()
	q.position = Vector3(room_lo.x + (float(ix) + 0.5) * CELL, y,
		room_lo.z + (float(iz) + 0.5) * CELL)
	q.collision_mask = 1
	q.exclude = exclude
	q.collide_with_areas = false
	q.collide_with_bodies = true
	return not space.intersect_point(q, 4).is_empty()


func _cast(space: PhysicsDirectSpaceState3D, exclude: Array[RID],
		shape: Shape3D, from: Vector3, motion: Vector3) -> float:
	var p := PhysicsShapeQueryParameters3D.new()
	p.shape = shape
	p.transform = Transform3D(Basis.IDENTITY, from)
	p.motion = motion
	p.collision_mask = 1
	p.exclude = exclude
	var r := space.cast_motion(p)
	return float(r[0]) if r.size() > 0 else 1.0


func _shot(cam: Camera3D, path: String) -> void:
	var before := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	while Engine.get_frames_drawn() == before and Time.get_ticks_msec() - t0 < 3000:
		await process_frame
	for _i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	_p("[img] %s  相机 (%.2f,%.2f,%.2f)" % [path.get_file(),
		cam.global_position.x, cam.global_position.y, cam.global_position.z])


func _p(s: String) -> void:
	_rep.append(s)


func _flush() -> void:
	var f := FileAccess.open(OUT_ABS.path_join("probe01.txt"), FileAccess.WRITE)
	if f == null:
		print("\n".join(_rep))
		return
	f.store_string("\n".join(_rep) + "\n")
	f.close()
	print("[probe] 报告已写入 %s (probe01.txt, %d 行)" % [OUT_ABS, _rep.size()])
