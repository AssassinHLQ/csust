extends Node3D
## 电竞房的自动碰撞（2026-11-09 重写）。
##
## 使用者原话：
##   「碰撞错了，电竞房你的碰撞，先总结面数低于 50 的块，再给这些低面的物体生成碰撞，
##     这些低面的大概率就是墙体，然后底座碰撞也要，家具用小的方盒子代替」
##
## ── ⚠️ 先说清一件事：「低面 = 墙体」在这个模型上**不成立** ──
## `_probe_esports_blocks.gd` 量过：低模档 59 个网格里，面数 < 50 的**只有 3 个**，
## 而且都不是墙：
##   `M_JS168_JS028`            10 面  尺寸 0.00×0.00×4.41  ← **零厚度的线**（线缆）
##   `M_集简空间h06_m21090364`    24 面  尺寸 1.89×2.31×0.03  ← 3 cm 薄板（玻璃/白板）
##   `M_集简空间h06_m21090362`    48 面  尺寸 1.93×2.33×0.04  ← 4 cm 薄板
##
## **墙在 `M_材质_3` 里：141,228 面、10.40×3.30×16.84**（地板/天花板/四面墙全合并在这一块）。
## 所以墙必须**按外壳 AABB 拆盒子**，不能靠面数找。
##
## ── 旧版真正的毛病（本版修的就是这个）──
## 1. **三档 LOD 被一起扫**：`esports_lod.gd` 会实例化 `HighModel` / `MidModel`，
##    而旧版用 `find_children("*", "MeshInstance3D")` 遍历**全部**网格 ——
##    59×3 = 177 个，碰撞盒 **152 个**（本该 ~50 个）。
##    ⇒ 本版**只看低模档 `Room`**。
##
## 2. **大家具变成一个实心大盒子，把路堵死**（使用者说的「碰撞错了」）：
##    实测 `M_JS149`（2072 面）的世界 AABB 是 **7.55×3.00×2.91 m**，
##    横在房间中间，生成一个盒子后**人根本走不过去**；
##    `M_集简空间h06_m210903`（10.73×3.30×9.20）更夸张，几乎填满整间房。
##    ⇒ 本版**家具按体素切成小盒子**（`CELL = 0.6 m`），只保留**真的有三角面**的格子，
##      空的地方不生成 —— 这样桌子底下能钻、床边能走，而不会变成一堵墙。
##
## ── 底座 ──
## 外壳盒子只有 0.22 m 厚，人从外面掉进来时容易穿过去。本版在房间底下**再加一层厚底座**
## （`BASE_DEPTH = 1.5 m`），确保踩得住。

## 房间外壳的网格名片段（按材质名命名的那个大网格）
const SHELL_HINT := "材质_3"
## 内壳：这一块是「室内墙面衬板 + 地板」，**不能**当家具切成盒子（会把房间填实）
const INNER_SHELL := "M_集简空间h06_m210903"
## 墙厚 / 地板天花板厚
const WALL_T := 0.22
## 门洞宽 / 高（本地 +Z 那一头是门）
const DOOR_WIDTH := 2.4
const DOOR_HEIGHT := 2.4
## 底座厚度（地板往下再垫这么厚，防止穿地）
const BASE_DEPTH := 1.5
## 家具体素边长（米）。越小越贴合，盒子也越多。
## 0.6 m 实测：房间总盒数从 152 降到 ~120，且不再堵路。
const CELL := 0.6
## 小于这个体积的网格直接给一个盒子（省得为小件切格子）
const TINY_VOLUME := 0.02
## 碰撞层：1 = 世界层
const LAYER := 1

var _built := false


func _ready() -> void:
	await get_tree().process_frame
	if _built:
		return
	_do_build()


## 对外入口（探针直接调）：**强制重建**
func build_collision() -> void:
	_do_build()


func _do_build() -> void:
	_built = true
	for c in get_children():
		if c is StaticBody3D and c.name.begins_with("AutoCol"):
			remove_child(c)
			c.queue_free()

	var t0 := Time.get_ticks_msec()

	# ⚠️ **只看低模档**：三档 LOD 的网格位置完全一样，扫三遍纯属浪费（旧版 152 个盒子）。
	var low := get_node_or_null("Room") as Node3D
	var scan_root: Node3D = low if low != null else self

	var meshes: Array[MeshInstance3D] = []
	for n in scan_root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			meshes.append(mi)
	if meshes.is_empty():
		push_warning("[EsportsCol] 没找到网格，跳过")
		return
	print("[EsportsCol] 扫描 %s：%d 个网格（只看低模档，避开 LOD 三档重复）"
		% [scan_root.name, meshes.size()])

	var body := StaticBody3D.new()
	body.name = "AutoCol"
	body.collision_layer = LAYER
	body.collision_mask = 0
	add_child(body)

	var n_added := 0
	var shell := _find_shell(meshes)
	var room_aabb := AABB(Vector3(-5.2, 0.0, -8.42), Vector3(10.4, 3.6, 16.84))
	if shell != null:
		room_aabb = shell.global_transform * shell.mesh.get_aabb()

	# ── ① 外壳：地板 / 天花板 / 四面墙 + 底座 ──
	if shell != null:
		n_added += _add_room_boxes(body, room_aabb)
		print("[EsportsCol] 外壳 %s aabb=%s" % [shell.name, _fmt(room_aabb)])

	# ── ② 家具：体素切成小盒子 ──
	var n_small := 0
	var n_voxel := 0
	for mi in meshes:
		if SHELL_HINT in mi.name or String(mi.name) == INNER_SHELL:
			continue
		var a: AABB = mi.global_transform * mi.mesh.get_aabb()
		# 包住整间房的网格一律跳过（那是壳，做成实心盒会堵死）
		if a.size.x >= room_aabb.size.x * 0.9 and a.size.z >= room_aabb.size.z * 0.9:
			continue
		if a.size.x * a.size.y * a.size.z < 0.0005:
			continue
		if a.size.x + a.size.y + a.size.z < 0.15:
			continue
		var vol := a.size.x * a.size.y * a.size.z
		if vol < TINY_VOLUME:
			_add_box(body, a.get_center(), a.size)
			n_small += 1
			continue
		var made := _voxelize(body, mi, CELL)
		n_voxel += made

	print("[EsportsCol] 共建 %d 个盒子（外壳 %d + 小件 %d + 体素 %d）耗时 %d ms" % [
		n_added + n_small + n_voxel, n_added, n_small, n_voxel,
		Time.get_ticks_msec() - t0])


## 把一个网格按体素切成小盒子，**只保留真的有三角面的格子**。
##
## 这就是使用者要的「家具用小的方盒子代替」：
## 大 AABB 盒会把家具（和它周围的空地）一起填实，切成体素后
## 只有实体部分有碰撞 —— 桌子底下能钻、床边能走。
func _voxelize(body: StaticBody3D, mi: MeshInstance3D, cell: float) -> int:
	var am := mi.mesh as ArrayMesh
	if am == null:
		return 0
	var xf := mi.global_transform
	var cells := {}
	for si in am.get_surface_count():
		var arr := am.surface_get_arrays(si)
		if arr.size() <= Mesh.ARRAY_VERTEX:
			continue
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		if verts.is_empty():
			continue
		var idx := PackedInt32Array()
		if arr.size() > Mesh.ARRAY_INDEX and arr[Mesh.ARRAY_INDEX] != null:
			idx = arr[Mesh.ARRAY_INDEX]
		var tri_n := (idx.size() / 3) if idx.size() > 0 else (verts.size() / 3)
		for t in tri_n:
			var a: Vector3
			var b: Vector3
			var c: Vector3
			if idx.size() > 0:
				a = verts[idx[t * 3]]
				b = verts[idx[t * 3 + 1]]
				c = verts[idx[t * 3 + 2]]
			else:
				a = verts[t * 3]
				b = verts[t * 3 + 1]
				c = verts[t * 3 + 2]
			a = xf * a
			b = xf * b
			c = xf * c
			# 这个三角占的格子范围
			var lo := a.min(b).min(c)
			var hi := a.max(b).max(c)
			var x0 := int(floor(lo.x / cell))
			var x1 := int(floor(hi.x / cell))
			var y0 := int(floor(lo.y / cell))
			var y1 := int(floor(hi.y / cell))
			var z0 := int(floor(lo.z / cell))
			var z1 := int(floor(hi.z / cell))
			for cx in range(x0, x1 + 1):
				for cy in range(y0, y1 + 1):
					for cz in range(z0, z1 + 1):
						cells[Vector3i(cx, cy, cz)] = true
	var n := 0
	for k in cells.keys():
		var v: Vector3i = k
		var center := Vector3((v.x + 0.5) * cell, (v.y + 0.5) * cell, (v.z + 0.5) * cell)
		_add_box(body, center, Vector3(cell, cell, cell))
		n += 1
	return n


## 挑体积最大的那个「外壳」网格
func _find_shell(meshes: Array[MeshInstance3D]) -> MeshInstance3D:
	var best: MeshInstance3D = null
	var best_vol := 0.0
	for mi in meshes:
		if not (SHELL_HINT in mi.name):
			continue
		var a: AABB = mi.global_transform * mi.mesh.get_aabb()
		var v := a.size.x * a.size.y * a.size.z
		if v > best_vol:
			best_vol = v
			best = mi
	return best


## 外壳 AABB → 地板 / 天花板 / 四面墙（含门洞）+ 厚底座。
## ⚠️ 本地 +Z 那一头是**门口**，所以那面墙拆成「左墩 + 门楣 + 右墩」。
func _add_room_boxes(body: StaticBody3D, a: AABB) -> int:
	var c := a.get_center()
	var s := a.size
	var t := WALL_T
	var y0 := a.position.y
	var y1 := a.position.y + s.y
	var n := 0

	# 地板 / 天花板
	_add_box(body, Vector3(c.x, y0 + t * 0.5, c.z), Vector3(s.x, t, s.z))
	_add_box(body, Vector3(c.x, y1 - t * 0.5, c.z), Vector3(s.x, t, s.z))
	n += 2

	# 底座：地板往下垫厚（使用者：「底座碰撞也要」）
	_add_box(body, Vector3(c.x, y0 - BASE_DEPTH * 0.5, c.z),
		Vector3(s.x, BASE_DEPTH, s.z))
	n += 1

	# 两面 X 向的墙
	_add_box(body, Vector3(a.position.x + t * 0.5, c.y, c.z), Vector3(t, s.y, s.z))
	_add_box(body, Vector3(a.position.x + s.x - t * 0.5, c.y, c.z), Vector3(t, s.y, s.z))
	n += 2

	# -Z 那面墙（实墙）
	_add_box(body, Vector3(c.x, c.y, a.position.z + t * 0.5), Vector3(s.x, s.y, t))
	n += 1

	# +Z 那面墙 = **门口**：左墩 + 门楣 + 右墩
	var z_wall := a.position.z + s.z - t * 0.5
	var door_x := c.x
	var door_w := DOOR_WIDTH
	var door_h := DOOR_HEIGHT
	var lx0 := a.position.x
	var lx1 := door_x - door_w * 0.5
	var rx0 := door_x + door_w * 0.5
	var rx1 := a.position.x + s.x
	if lx1 - lx0 > 0.02:
		_add_box(body, Vector3((lx0 + lx1) * 0.5, c.y, z_wall), Vector3(lx1 - lx0, s.y, t))
		n += 1
	if rx1 - rx0 > 0.02:
		_add_box(body, Vector3((rx0 + rx1) * 0.5, c.y, z_wall), Vector3(rx1 - rx0, s.y, t))
		n += 1
	var lintel_h := s.y - door_h
	if lintel_h > 0.02:
		_add_box(body, Vector3(door_x, y0 + door_h + lintel_h * 0.5, z_wall),
			Vector3(door_w, lintel_h, t))
		n += 1
	return n


func _add_box(body: StaticBody3D, center: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(size.x, 0.02), maxf(size.y, 0.02), maxf(size.z, 0.02))
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	# ⚠️ 必须用 global_position：`center` 是世界坐标
	cs.global_position = center


func _fmt(a: AABB) -> String:
	return "pos(%.2f,%.2f,%.2f) size(%.2f,%.2f,%.2f)" % [
		a.position.x, a.position.y, a.position.z, a.size.x, a.size.y, a.size.z]
