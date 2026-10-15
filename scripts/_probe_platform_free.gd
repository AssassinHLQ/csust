extends SceneTree
## 探针：量出「记忆平台」上还剩哪块空地，好决定手工搭的网格小屋摆哪儿。
##
## ── 为什么需要它 ──
## 平台只有 40 × 40 m，上面已经挤着：
##   · 画室609 —— **斜的**（yaw 248.6°），它的世界轴对齐包围盒 23.9 × 27.2 m
##     比房间自己（22.6 × 16.8 m）大一圈，四个角其实是空的（README §6.8 踩过）
##   · 两位 Boss、3 根柱子、5 个靶子
##   · 一条**不能碰的自检弹道**：玩家(6, −4) → 靶1(6, −10)
##     （§7.3：猪猪优香当初摆在 x = 9 就是吃掉了这条弹道，害得 3 套自检集体变红）
##
## 斜着的东西手算极容易错（README §8.2 那句「本喵算了两次都错」），所以直接量：
## 用**真场景**里的 `content_world_aabb()` 与每个 `CollisionShape3D`，
## 再用「分离轴」判旋转矩形与候选框相交 —— 不是拿包围盒糊弄。
##
## 用法：
##   godot --path <工程> --script res://scripts/_probe_platform_free.gd
##
## ⚠️ **不能加 `--splat=off`**：画室的真实占位要等泼溅解码完
##    （`content_min/max` 才有值）。首次约 21 s，有缓存约 2 s。
## ⚠️ 要真渲染，不要 `--headless`。
##
## 输出四段：
##   1. 每个障碍物的世界 AABB（x/z 范围 + 高度）
##   2. 平台的 40 × 40 ASCII 地图（一格 1 m，画室画的是**真旋转矩形**而不是包围盒）
##   3. 候选落点表：能塞下那块 footprint 的中心点，按与最近障碍的净距排序
##   4. 第二张地图：哪些格子放得下（`O` = 放得下）

## 要摆进去的东西整体占多大（含屋檐外挑、门前木箱、灯柱）
const COMPOUND_W := 9.5
const COMPOUND_D := 7.0
## 与任何障碍物之间至少要留的净距（米）
const CLEAR := 1.0
## 离平台边缘至少留多少（免得东西挂在半空、或玩家绕不过去）
const EDGE := 1.0
## 平台半边长（game.tscn 的地板是 40 × 40，顶面 y = 0）
const HALF := 20.0
## 地图的格子边长（米）
const CELL := 1.0

## 一条已知**不能占用**的自检弹道：玩家(6, −4) → 靶1(6, −10)。
## 这里当成一个 1 m 宽、2 m 高的走廊一起躲开。
const SHOT_FROM := Vector2(6, -4)
const SHOT_TO := Vector2(6, -10)
const SHOT_HALF := 0.6
const SHOT_TOP := 2.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(10)

	var room: SplatScene = game.get_node_or_null("Room609") as SplatScene
	if room == null:
		print("!! 场景里没有 Room609")
		quit(1)
		return
	var guard := 0
	while guard < 60000 and not room.is_ready():
		await process_frame
		guard += 1
	print("画室609 解码完成：%s（等了 %d 帧）" % [str(room.is_ready()), guard])

	# ── 1. 收集障碍 ──────────────────────────────────────────────────────────
	var items: Array = []
	if room.is_ready():
		var aabb := room.content_world_aabb()
		items.append({
			"tag": "R", "name": "画室609（内容包围盒）",
			"box": aabb, "poly": _room_poly(room),
		})
	for c in _children_of(game, "Room609/RoomCollision"):
		var b := _cs_aabb(c as CollisionShape3D)
		if b.size != Vector3.ZERO:
			items.append({"tag": "r", "name": "画室609 墙 %s" % c.name, "box": b,
				"poly": PackedVector2Array()})
	for path in ["Boss", "BossPig", "Pillar1", "Pillar2", "Pillar3",
			"Target1", "Target2", "Target3", "Target4", "Target5"]:
		var node := game.get_node_or_null(path)
		if node == null:
			continue
		var col := node.get_node_or_null("Collision") as CollisionShape3D
		if col == null:
			continue
		var tag := "t"
		if path.begins_with("Boss"):
			tag = "B"
		elif path.begins_with("Pillar"):
			tag = "I"
		items.append({"tag": tag, "name": "%s 的碰撞盒" % path,
			"box": _cs_aabb(col), "poly": PackedVector2Array()})
	# 自检弹道：合成一个薄盒
	var shot := AABB(
		Vector3(minf(SHOT_FROM.x, SHOT_TO.x) - SHOT_HALF, 0.0,
			minf(SHOT_FROM.y, SHOT_TO.y) - SHOT_HALF),
		Vector3(absf(SHOT_TO.x - SHOT_FROM.x) + SHOT_HALF * 2.0, SHOT_TOP,
			absf(SHOT_TO.y - SHOT_FROM.y) + SHOT_HALF * 2.0))
	items.append({"tag": "x", "name": "自检弹道 玩家(6,−4)→靶1(6,−10)（不许挡）",
		"box": shot, "poly": PackedVector2Array()})

	print("\n========== 1. 障碍物（世界空间）==========")
	print("%-40s %8s %8s %8s %8s %7s %7s" % [
		"名字", "x最小", "x最大", "z最小", "z最大", "y底", "y顶"])
	for it in items:
		var b: AABB = it["box"]
		print("%-40s %8.2f %8.2f %8.2f %8.2f %7.2f %7.2f" % [
			String(it["name"]), b.position.x, b.position.x + b.size.x,
			b.position.z, b.position.z + b.size.z,
			b.position.y, b.position.y + b.size.y])

	# 顺手把玩家/同伴的出生点也打出来（它们会动，不当障碍物）
	print("\n玩家出生点 = %s" % str(_flat(game.get_node_or_null("Player"))))
	var mates: Array[String] = []
	for child in game.get_children():
		if child is Companion:
			mates.append("%s%s" % [child.name, str(_flat(child))])
	print("同伴出生点 = %s" % ", ".join(PackedStringArray(mates)))

	# ── 2. 平台地图 ──────────────────────────────────────────────────────────
	print("\n========== 2. 平台地图（一格 %.0f m，画室画的是真旋转矩形）==========" % CELL)
	print("   图例： R 画室内容  r 画室墙  B Boss  I 柱子  t 靶子  x 自检弹道  . 空")
	var grid := _blank()
	for it in items:
		_stamp(grid, it)
	print(_draw(grid, "x →"))

	# ── 3. 候选落点 ─────────────────────────────────────────────────────────
	var cands: Array = []
	var cx := -HALF + COMPOUND_W * 0.5
	while cx <= HALF - COMPOUND_W * 0.5:
		var cz := -HALF + COMPOUND_D * 0.5
		while cz <= HALF - COMPOUND_D * 0.5:
			var r := _evaluate(items, Vector2(cx, cz))
			if r["ok"]:
				cands.append({"pos": Vector2(cx, cz), "clear": float(r["clear"])})
			cz += 0.5
		cx += 0.5
	cands.sort_custom(func(a, b): return float(a["clear"]) > float(b["clear"]))

	print("\n========== 3. 放得下 %.1f × %.1f（净距 ≥ %.1f、离边 ≥ %.1f）的落点 ==========" % [
		COMPOUND_W, COMPOUND_D, CLEAR, EDGE])
	print("共 %d 个（0.5 m 网格，已合并相邻）；按与最近障碍的净距排序：" % cands.size())
	print("%4s %9s %9s %9s %s" % ["#", "中心x", "中心z", "净距", "最近的是谁"])
	var shown := 0
	for c in cands:
		if shown >= 12:
			break
		var r := _evaluate(items, c["pos"])
		print("%4d %9.1f %9.1f %9.2f %s" % [shown + 1,
			c["pos"].x, c["pos"].y, c["clear"], String(r["who"])])
		shown += 1

	if cands.is_empty():
		print("  ⚠️ **一个都放不下** —— footprint 得缩小，或者接受更小的净距")

	print("\n========== 4. 哪些格子放得下（O = 小屋中心可以在这里）==========")
	var grid2 := _blank()
	var fits := {}
	for c in cands:
		fits["%d_%d" % [int(round(c["pos"].x)), int(round(c["pos"].y))]] = true
	# 候选是按 0.5 m 扫的，这里落到格子上
	var gx := -HALF + COMPOUND_W * 0.5
	while gx <= HALF - COMPOUND_W * 0.5:
		var gz := -HALF + COMPOUND_D * 0.5
		while gz <= HALF - COMPOUND_D * 0.5:
			if _evaluate(items, Vector2(gx, gz))["ok"]:
				_set_cell(grid2, gx, gz, "O")
			gz += CELL
		gx += CELL
	for it in items:
		if String(it["tag"]) in ["R", "B", "I", "t", "x"]:
			_stamp(grid2, it, true)
	print(_draw(grid2, "x →"))
	print("\n（`O` 是**小屋中心**能放的格子；小屋本身还要往外占 %.1f × %.1f）"
		% [COMPOUND_W, COMPOUND_D])
	quit(0)


# --- 判据 ---------------------------------------------------------------------

## 候选中心能不能放下 COMPOUND 这块 footprint。返回 {ok, clear, who}。
func _evaluate(items: Array, center: Vector2) -> Dictionary:
	var mn := center - Vector2(COMPOUND_W, COMPOUND_D) * 0.5
	var mx := center + Vector2(COMPOUND_W, COMPOUND_D) * 0.5
	# 离平台边缘
	var edge := minf(minf(mn.x + HALF, HALF - mx.x), minf(mn.y + HALF, HALF - mx.y))
	if edge < EDGE:
		return {"ok": false, "clear": edge, "who": "平台边缘"}
	var worst := INF
	var who := ""
	for it in items:
		var b: AABB = it["box"]
		var poly: PackedVector2Array = it["poly"]
		var g := 0.0
		if poly.is_empty():
			g = _gap_box_box(mn, mx, b)
		else:
			g = _gap_box_poly(mn, mx, poly)
		if g < worst:
			worst = g
			who = String(it["name"])
	return {"ok": worst >= CLEAR, "clear": worst, "who": who}


## 两根轴对齐矩形的水平净距（相交 = 0）
func _gap_box_box(mn: Vector2, mx: Vector2, b: AABB) -> float:
	var bmn := Vector2(b.position.x, b.position.z)
	var bmx := bmn + Vector2(b.size.x, b.size.z)
	var dx := maxf(0.0, maxf(mn.x - bmx.x, bmn.x - mx.x))
	var dz := maxf(0.0, maxf(mn.y - bmx.y, bmn.y - mx.y))
	return sqrt(dx * dx + dz * dz)


## 轴对齐矩形 ↔ 凸多边形（旋转矩形）的水平净距。
## 两个凸多边形的最近距离一定落在**某一方的顶点**上，所以取两边顶点到对方的距离最小值就够。
func _gap_box_poly(mn: Vector2, mx: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	for p in [mn, Vector2(mx.x, mn.y), mx, Vector2(mn.x, mx.y)]:
		best = minf(best, _dist_point_poly(p, poly))
	for p in poly:
		best = minf(best, _dist_point_box(p, mn, mx))
	return best


## 分离轴：轴对齐矩形 [mn, mx] 与凸多边形 poly 是否分离。
## 对两个凸多边形，只要这 4 根轴（我方 2 根 + 对方 2 根法线）都投不出缝隙，就是相交。
func _separated(mn: Vector2, mx: Vector2, poly: PackedVector2Array) -> bool:
	var axes: Array[Vector2] = [Vector2(1, 0), Vector2(0, 1)]
	for i in poly.size():
		var e := poly[(i + 1) % poly.size()] - poly[i]
		var n := Vector2(-e.y, e.x)
		if n.length_squared() > 1e-12:
			axes.append(n.normalized())
	var mine := [mn, Vector2(mx.x, mn.y), mx, Vector2(mn.x, mx.y)]
	for ax in axes:
		var a0 := INF
		var a1 := -INF
		for p in mine:
			var v: float = p.dot(ax)
			a0 = minf(a0, v)
			a1 = maxf(a1, v)
		var b0 := INF
		var b1 := -INF
		for p in poly:
			var v: float = p.dot(ax)
			b0 = minf(b0, v)
			b1 = maxf(b1, v)
		if a1 < b0 or b1 < a0:
			return true
	return false


func _dist_point_poly(p: Vector2, poly: PackedVector2Array) -> float:
	var mn := poly[0]
	var mx := poly[0]
	for q in poly:
		mn = Vector2(minf(mn.x, q.x), minf(mn.y, q.y))
		mx = Vector2(maxf(mx.x, q.x), maxf(mx.y, q.y))
	if not _separated(mn, mx, poly) and _point_in(p, poly):
		return 0.0
	var best := INF
	for i in poly.size():
		best = minf(best, _dist_point_seg(p, poly[i], poly[(i + 1) % poly.size()]))
	return best


func _point_in(p: Vector2, poly: PackedVector2Array) -> bool:
	var inside := false
	var n := poly.size()
	var j := n - 1
	for i in n:
		var a := poly[i]
		var b := poly[j]
		if (a.y > p.y) != (b.y > p.y) \
				and p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x:
			inside = not inside
		j = i
	return inside


func _dist_point_box(p: Vector2, mn: Vector2, mx: Vector2) -> float:
	return p.distance_to(Vector2(clampf(p.x, mn.x, mx.x), clampf(p.y, mn.y, mx.y)))


func _dist_point_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-12:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


# --- 场景读取 -----------------------------------------------------------------

## 画室地板在世界空间的 4 个角（**真旋转矩形**，不是包围盒）。
## 算法与 game.gd 的 `_carve_fallback_floor()` 同源，所以两边永远指着同一块地。
func _room_poly(room: SplatScene) -> PackedVector2Array:
	var out := PackedVector2Array()
	if room.splat_node == null:
		return out
	var xf := room.global_transform * room.splat_node.transform
	var a := room.content_min
	var b := room.content_max
	for c in [Vector2(a.x, a.z), Vector2(b.x, a.z), Vector2(b.x, b.z), Vector2(a.x, b.z)]:
		var w: Vector3 = xf * Vector3(c.x, 0.0, c.y)
		out.append(Vector2(w.x, w.z))
	return out


## 一个 `CollisionShape3D` 在世界空间的包围盒（按形状自己算，不信节点的缩放）。
func _cs_aabb(cs: CollisionShape3D) -> AABB:
	if cs == null or cs.disabled or cs.shape == null:
		return AABB()
	var s := cs.shape
	var local := AABB()
	if s is BoxShape3D:
		local = AABB(-(s as BoxShape3D).size * 0.5, (s as BoxShape3D).size)
	elif s is SphereShape3D:
		var r := (s as SphereShape3D).radius
		local = AABB(Vector3(-r, -r, -r), Vector3(r * 2, r * 2, r * 2))
	elif s is CapsuleShape3D:
		var c := s as CapsuleShape3D
		local = AABB(Vector3(-c.radius, -c.height * 0.5, -c.radius),
			Vector3(c.radius * 2, c.height, c.radius * 2))
	elif s is CylinderShape3D:
		var cy := s as CylinderShape3D
		var rr := maxf(cy.top_radius, cy.bottom_radius)
		local = AABB(Vector3(-rr, -cy.height * 0.5, -rr),
			Vector3(rr * 2, cy.height, rr * 2))
	elif s is ConcavePolygonShape3D:
		var faces := (s as ConcavePolygonShape3D).get_faces()
		if faces.size() == 0:
			return AABB()
		local = AABB(faces[0], Vector3.ZERO)
		for i in range(1, faces.size()):
			local = local.expand(faces[i])
	else:
		print("   （跳过不认识的形状类型：%s）" % s.get_class())
		return AABB()
	return cs.global_transform * local


func _children_of(root_node: Node, path: String) -> Array:
	var out: Array = []
	var n := root_node.get_node_or_null(path)
	if n == null:
		return out
	for c in n.get_children():
		if c is CollisionShape3D:
			out.append(c)
	return out


func _flat(n: Node) -> String:
	if n == null or not (n is Node3D):
		return "「无」"
	var p := (n as Node3D).global_position
	return "(%.1f, %.1f)" % [p.x, p.z]


# --- 地图 ---------------------------------------------------------------------

func _blank() -> Array:
	var g: Array = []
	for _r in int(HALF * 2.0 / CELL):
		g.append(".".repeat(int(HALF * 2.0 / CELL)))
	return g


func _set_cell(grid: Array, x: float, z: float, ch: String) -> void:
	var c := int(floor((x + HALF) / CELL))
	var r := int(floor((HALF - z) / CELL))
	if r < 0 or r >= grid.size() or c < 0 or c >= String(grid[r]).length():
		return
	var line := String(grid[r])
	grid[r] = line.substr(0, c) + ch + line.substr(c + 1)


func _stamp(grid: Array, it: Dictionary, only_outside := false) -> void:
	var b: AABB = it["box"]
	var ch := String(it["tag"])
	var poly: PackedVector2Array = it["poly"]
	if poly.is_empty():
		var z := b.position.z
		while z <= b.position.z + b.size.z:
			var x := b.position.x
			while x <= b.position.x + b.size.x:
				if not only_outside or String(grid[_row(z)][_col(x)]) in [".", "O"]:
					_set_cell(grid, x, z, ch)
				x += CELL
			z += CELL
	else:
		# 真旋转矩形：逐格做点在多边形内测试
		var r := 0
		while r < grid.size():
			var c := 0
			while c < String(grid[r]).length():
				var px := -HALF + (float(c) + 0.5) * CELL
				var pz := HALF - (float(r) + 0.5) * CELL
				if _point_in(Vector2(px, pz), poly):
					if not only_outside or String(grid[r])[c] in [".", "O"]:
						grid[r] = String(grid[r]).substr(0, c) + ch \
							+ String(grid[r]).substr(c + 1)
				c += 1
			r += 1


func _row(z: float) -> int:
	return int(floor((HALF - z) / CELL))


func _col(x: float) -> int:
	return int(floor((x + HALF) / CELL))


func _draw(grid: Array, label: String) -> String:
	var head := "      "
	var ticks := "      "
	var c := 0
	while c < String(grid[0]).length():
		var x := -HALF + (float(c) + 0.5) * CELL
		if int(x) % 5 == 0:
			var s := "%d" % int(x)
			head += s[0]
			ticks += " "
		else:
			head += " "
			ticks += " "
		c += 1
	var out := [label, head, ticks]
	for r in grid.size():
		var z := HALF - (float(r) + 0.5) * CELL
		out.append("%5d %s" % [int(z), String(grid[r])])
	return "\n".join(PackedStringArray(out))


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
