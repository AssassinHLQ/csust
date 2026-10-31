extends SceneTree
## 在校园里摆一批「可走进去」的网格建筑（Godot 原生几何 + 盒子碰撞），烘成场景。
##   _tools/run_probe.sh res://scripts/_bake_campus_buildings.gd               # 只找位置、打印
##   _tools/run_probe.sh res://scripts/_bake_campus_buildings.gd -- --write    # 写 scenes/campus_buildings.tscn
##   ... --write --force
##
## 选址（全自动，靠 physics 射线，不靠猜）：
##   · 在入口一带（z -95 ~ -300、|x| ≤ 90）按 8 m 网格撒点；
##   · 楼座四个角 + 中心，1 m 高四周 0.6 m 内不能有碰撞（树、墙不要）；
##   · 地面从上往下打射线，落点必须在 -0.6 ~ +0.3 m（校园地面是平的）；
##   · 四角地面高差 < 0.5 m；
##   · 离主路中线 |x| ≥ 16 m，楼与楼之间 ≥ 28 m。
##
## 产物：scenes/campus_buildings.tscn（root 是 Node3D，每栋一个 StaticBody3D）
## 每栋楼：地坪 + 四面墙（正面留门洞）+ 屋顶 + 女儿墙 + 每层窗带；全部是 BoxMesh/BoxShape，
## 编辑器里能单独拖。

const LEVEL := "res://scenes/next_level.tscn"
const OUT := "res://scenes/campus_buildings.tscn"

const GRID := 8.0
const AREA := Rect2(-90, -300, 180, 205)   # x, z, w, h（z 是负数，取 min/max 手写）
const ROAD_HALF := 16.0
const MIN_GAP := 28.0

var _write := false
var _force := false

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--write":
			_write = true
		elif a == "--force":
			_force = true
	if _write and FileAccess.file_exists(OUT) and not _force:
		print("[bldg] %s 已存在；覆盖请加 -- --force" % OUT)
		quit(0)
		return

	var level := (load(LEVEL) as PackedScene).instantiate()
	root.add_child(level)
	await process_frame
	await process_frame
	var campus := level.get_node_or_null("Campus")
	if campus != null:
		campus.set("auto_start", false)
		campus.set_process(false)
	await physics_frame
	var space: PhysicsDirectSpaceState3D = level.get_world_3d().direct_space_state

	# 三种类型各找一堆候选，再按「离入口近 + 彼此 ≥ 45 m」贪心挑 8 个，
	# 免得全挤在网格扫描的第一列
	var pool: Array = []
	for kind in ["teaching", "dorm", "small"]:
		pool.append_array(_find_spots(space, kind, []))
	pool.sort_custom(func(a, b): return _dist(a[0]) < _dist(b[0]))
	var spots: Array = []
	for cand in pool:
		var ok := true
		for s2 in spots:
			if Vector2(cand[0].x - s2[0].x, cand[0].z - s2[0].z).length() < 45.0:
				ok = false
				break
		if ok:
			spots.append(cand)
		if spots.size() >= 8:
			break
	print("[bldg] 候选 %d 个" % spots.size())
	for s in spots:
		print("      (%.0f, %.0f) y=%.2f  类型 %s" % [s[0].x, s[0].z, s[1], s[2]])

	if not _write:
		level.free()
		quit(0)
		return

	var root_node := Node3D.new()
	root_node.name = "CampusBuildings"
	var i := 0
	for s in spots:
		i += 1
		var b := _make_building(s[0], s[1], String(s[2]), i)
		root_node.add_child(b)
	_own(root_node, root_node)
	var ps := PackedScene.new()
	var err := ps.pack(root_node)
	if err != OK:
		print("[bldg] pack 失败 %d" % err)
		quit(1)
		return
	err = ResourceSaver.save(ps, OUT)
	print("[bldg] %s ← %d 栋，%d 个节点，%.0f KB，err=%d"
		% [OUT, i, _count(root_node),
			float(FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(OUT)).size()) / 1024.0, err])
	level.free()
	quit(0)


func _dist(p: Vector3) -> float:
	return Vector2(p.x, p.z).distance_to(Vector2(0, -95))


# ───────────────────────────── 选址 ─────────────────────────────

func _find_spots(space: PhysicsDirectSpaceState3D, kind: String, placed: Array) -> Array:
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = 1
	var out: Array = []
	var w0 := 30.0 if kind == "teaching" else (20.0 if kind == "dorm" else 8.0)
	var d0 := 16.0 if kind == "teaching" else (12.0 if kind == "dorm" else 8.0)
	var x := AREA.position.x
	while x <= AREA.position.x + AREA.size.x:
		var z := -95.0
		while z >= -300.0:
			if absf(x) >= ROAD_HALF:
				var g := _ground_ok(space, q, Vector3(x, 0, z), w0, d0)
				if g > -900.0:
					var p := Vector3(x, g, z)
					if _good_gap(p, placed + out, maxf(w0, d0)):
						out.append([p, g, kind])
			z -= GRID
		x += GRID
	return out


## 返回地面高度；不合格返回 -999
func _ground_ok(space: PhysicsDirectSpaceState3D, q: PhysicsRayQueryParameters3D,
		c: Vector3, w: float, d: float) -> float:
	var hx := w * 0.5 - 1.0
	var hz := d * 0.5 - 1.0
	var hs: Array[float] = []
	var pts := [Vector3(0, 0, 0), Vector3(hx, 0, hz), Vector3(-hx, 0, hz),
		Vector3(hx, 0, -hz), Vector3(-hx, 0, -hz)]
	for p in pts:
		# 1 m 高四周探针：脚下有树/墙就不要
		for dir in [Vector3(0.6, 0, 0), Vector3(-0.6, 0, 0), Vector3(0, 0, 0.6), Vector3(0, 0, -0.6)]:
			q.from = Vector3(c.x + p.x, 1.0, c.z + p.z)
			q.to = q.from + dir
			if not space.intersect_ray(q).is_empty():
				return -999.0
		q.from = Vector3(c.x + p.x, 40.0, c.z + p.z)
		q.to = Vector3(c.x + p.x, -5.0, c.z + p.z)
		var r: Dictionary = space.intersect_ray(q)
		if r.is_empty():
			return -999.0
		hs.append((r["position"] as Vector3).y)
	# 门前 3 m 得是空的，否则门开在树里进不去
	var dx := c.x - w * 0.22
	q.from = Vector3(dx, 1.1, c.z + d * 0.5 + 3.0)
	q.to = Vector3(dx, 1.1, c.z + d * 0.5 + 0.2)
	if not space.intersect_ray(q).is_empty():
		return -999.0
	var mn: float = hs[0]
	var mx: float = hs[0]
	for h in hs:
		mn = minf(mn, h)
		mx = maxf(mx, h)
	if mn < -0.6 or mx > 0.35 or (mx - mn) > 0.5:
		return -999.0
	return (mn + mx) * 0.5


func _good_gap(p: Vector3, placed: Array, own_size: float) -> bool:
	for s in placed:
		var q: Vector3 = s[0]
		if Vector2(p.x - q.x, p.z - q.z).length() < MIN_GAP + own_size * 0.5:
			return false
	return true


# ───────────────────────────── 造楼 ─────────────────────────────

func _make_building(pos: Vector3, ground: float, kind: String, idx: int) -> Node3D:
	var floors := 4
	var w := 30.0
	var d := 16.0
	var fh := 3.6
	if kind == "dorm":
		floors = 6
		w = 20.0
		d = 12.0
	elif kind == "small":
		floors = 1
		w = 8.0
		d = 8.0
	var h := floors * fh

	var body := StaticBody3D.new()
	body.name = "Building%02d_%s" % [idx, kind]
	body.position = Vector3(pos.x, ground, pos.z)

	var wall := StandardMaterial3D.new()
	wall.albedo_color = Color(0.86, 0.85, 0.82)
	wall.roughness = 0.9
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.16, 0.22, 0.28)
	glass.metallic = 0.4
	glass.roughness = 0.25
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.42, 0.42, 0.44)
	trim.roughness = 0.95

	# 地坪 + 屋顶
	_slab(body, Vector3(0, 0.15, 0), Vector3(w, 0.3, d), wall)
	_slab(body, Vector3(0, h + 0.15, 0), Vector3(w + 0.4, 0.3, d + 0.4), trim)
	# 女儿墙
	var ph := 0.8
	_slab(body, Vector3(0, h + ph * 0.5, d * 0.5 - 0.15), Vector3(w + 0.4, ph, 0.3), trim)
	_slab(body, Vector3(0, h + ph * 0.5, -d * 0.5 + 0.15), Vector3(w + 0.4, ph, 0.3), trim)
	_slab(body, Vector3(w * 0.5 - 0.15, h + ph * 0.5, 0), Vector3(0.3, ph, d + 0.4), trim)
	_slab(body, Vector3(-w * 0.5 + 0.15, h + ph * 0.5, 0), Vector3(0.3, ph, d + 0.4), trim)

	# 四面墙；正面（+z，朝玩家来的方向）留 2.6×2.4 的门洞
	var t := 0.3
	var door_w := 2.6
	var door_h := minf(2.4, h - 0.2)
	_slab(body, Vector3(0, h * 0.5, -d * 0.5 + t * 0.5), Vector3(w, h, t), wall)
	_slab(body, Vector3(w * 0.5 - t * 0.5, h * 0.5, 0), Vector3(t, h, d), wall)
	_slab(body, Vector3(-w * 0.5 + t * 0.5, h * 0.5, 0), Vector3(t, h, d), wall)
	# 正面：左右两段 + 门楣。门故意偏到左边，别正对中间那道隔墙
	var door_x := -w * 0.22
	var left_w := (door_x - door_w * 0.5) - (-w * 0.5)
	var right_w := (w * 0.5) - (door_x + door_w * 0.5)
	_slab(body, Vector3(-w * 0.5 + left_w * 0.5, h * 0.5, d * 0.5 - t * 0.5),
		Vector3(left_w, h, t), wall)
	_slab(body, Vector3(w * 0.5 - right_w * 0.5, h * 0.5, d * 0.5 - t * 0.5),
		Vector3(right_w, h, t), wall)
	if h - door_h > 0.1:
		_slab(body, Vector3(door_x, door_h + (h - door_h) * 0.5, d * 0.5 - t * 0.5),
			Vector3(door_w, h - door_h, t), wall)

	# 一层隔墙：把大厅分成两间（中间留 1.8 m 门洞）
	if kind != "small":
		var gap := 1.8
		var seg := (d - gap) * 0.5
		var py := fh * 0.5
		_slab(body, Vector3(0, py, (gap * 0.5 + seg * 0.5)),
			Vector3(t, fh, seg), wall)
		_slab(body, Vector3(0, py, -(gap * 0.5 + seg * 0.5)),
			Vector3(t, fh, seg), wall)
		_slab(body, Vector3(0, fh - 0.3, 0), Vector3(t, 0.6, gap), wall)

	# 窗带：每层一圈，凸出墙面 6 cm
	for f in floors:
		var y := fh * f + fh * 0.55
		var band := 1.0 if kind != "small" else 2.2
		if kind == "small":
			y = 1.6
		_slab(body, Vector3(0, y, d * 0.5 + 0.03), Vector3(w - 2.0, band, 0.06), glass, false)
		_slab(body, Vector3(0, y, -d * 0.5 - 0.03), Vector3(w - 2.0, band, 0.06), glass, false)
		_slab(body, Vector3(w * 0.5 + 0.03, y, 0), Vector3(0.06, band, d - 2.0), glass, false)
		_slab(body, Vector3(-w * 0.5 - 0.03, y, 0), Vector3(0.06, band, d - 2.0), glass, false)
		# 层间腰线
		if f > 0:
			_slab(body, Vector3(0, fh * f, d * 0.5 + 0.05), Vector3(w, 0.18, 0.1), trim, false)
			_slab(body, Vector3(0, fh * f, -d * 0.5 - 0.05), Vector3(w, 0.18, 0.1), trim, false)

	return body


## 一块板：MeshInstance3D + CollisionShape3D（同一个 BoxShape）
func _slab(parent: Node, pos: Vector3, size: Vector3, mat: Material, solid := true) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	if solid:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		cs.position = pos
		parent.add_child(cs)


func _own(n: Node, root_node: Node) -> void:
	for c in n.get_children():
		c.owner = root_node
		_own(c, root_node)


func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c
