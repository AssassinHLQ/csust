extends SceneTree
## 从校园泼溅点云离线烘「建筑盒碰撞」：
##   _tools/run_probe.sh res://scripts/_bake_campus_collision.gd -- --write --force
##
## 为什么这么做：615 万点没有现成三角网，直接拿一个 576×483 的大盒当地板
## 等于校园里什么都不挡（用户 2026-10-28：「这个碰撞太敷衍了，怎么只有一个长方体」）。
## 这里按 12 m 网格统计每格的「高于地面 12 m 的点数」，够密的格子就算建筑/树冠，
## 再把相邻格子按行合并成长方体，写成 scenes/campus_collision.tscn。
##
## 产物是**烘好的节点**（每块一个 StaticBody3D + BoxShape3D），可以在编辑器里
## 单独拖动/缩放；重烘要加 --force。
##
## 只统计结构、不统计地面 —— 地面仍然由 next_level.tscn 里那块 CampusFloor 负责。

const LEVEL_PATH := "res://scenes/next_level.tscn"
const OUT_PATH := "res://scenes/campus_collision.tscn"

## 网格边长（世界单位，已按放大后的校园调）
var cell := 12.0
## 高出地面多少米才算「结构」（树冠/建筑）。低于它的格子不生成碰撞。
var min_high := 12.0
## 一格至少要有多少点 / 多少点高于 min_high 才考虑
var min_points := 200
var min_high_points := 200
## 盒顶取「从高往低累计到这么多点」的高度，避免单个离群点把盒子顶到天上
var top_points := 40
## 桥头留出的安全走廊（世界坐标），避免出口正对着树/楼的盒子
var corridor := Rect2(2.0, -98.0, 16.0, 26.0)   # x, z, w, h
var ground_y := -0.02
var bin_size := 2.0
var max_height := 80.0

var _w := 0
var _h := 0
var _bins := 0
var _counts := PackedInt32Array()
var _high := PackedInt32Array()
var _hist := PackedInt32Array()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var write := false
	var force := false
	var show_map := false
	for a in OS.get_cmdline_user_args():
		if a == "--write":
			write = true
		elif a == "--force":
			force = true
		elif a == "--map":
			show_map = true
		elif a.begins_with("--cell="):
			cell = float(a.substr(7))
		elif a.begins_with("--min-high="):
			min_high = float(a.substr(11))

	if write and FileAccess.file_exists(OUT_PATH) and not force:
		print("[bake] %s 已存在；要覆盖请加 -- --force" % OUT_PATH)
		quit(0)
		return

	var level := (load(LEVEL_PATH) as PackedScene).instantiate()
	root.add_child(level)
	var campus := level.get_node_or_null("Campus")
	if campus == null:
		print("[bake] next_level.tscn 里没有 Campus")
		quit(1)
		return
	campus.call("force_start")
	var t0 := Time.get_ticks_msec()
	while not bool(campus.call("is_ready")) and Time.get_ticks_msec() - t0 < 180000:
		await process_frame
	if not bool(campus.call("is_ready")):
		print("[bake] 校园没加载完")
		quit(1)
		return

	var node := campus.get("splat_node") as Node3D
	var res = node.get("gaussian")
	var xyz: PackedVector3Array = res.get("xyz")
	var xf := node.global_transform
	var box: AABB = campus.call("content_world_aabb")
	print("[bake] 内容盒 pos %s size %s" % [
		str(box.position.snappedf(0.1)), str(box.size.snappedf(0.1))])
	print("[bake] 地面 y=%.2f，结构阈值 %.1f m，网格 %.1f m，点数 %d"
		% [ground_y, min_high, cell, xyz.size()])

	_w = int(ceil(box.size.x / cell))
	_h = int(ceil(box.size.z / cell))
	_bins = int(ceil(max_height / bin_size)) + 1
	_counts.resize(_w * _h)
	_high.resize(_w * _h)
	_hist.resize(_w * _h * _bins)

	var t_scan := Time.get_ticks_msec()
	var hi_bin := int((min_high - 0.0) / bin_size)
	for i in xyz.size():
		var w: Vector3 = xf * xyz[i]
		var ix := int((w.x - box.position.x) / cell)
		var iz := int((w.z - box.position.z) / cell)
		if ix < 0 or ix >= _w or iz < 0 or iz >= _h:
			continue
		var k := iz * _w + ix
		_counts[k] += 1
		var hgt := w.y - ground_y
		if hgt <= 0.0:
			continue
		var bi := int(hgt / bin_size)
		if bi >= _bins:
			bi = _bins - 1
		_hist[k * _bins + bi] += 1
		if bi >= hi_bin:
			_high[k] += 1
	print("[bake] 扫描 %d 点，%.1f s" % [xyz.size(), float(Time.get_ticks_msec() - t_scan) / 1000.0])

	# 每格顶面高度（从高往低累计 top_points 个点）
	var tops := PackedFloat32Array()
	tops.resize(_w * _h)
	var cand := PackedByteArray()
	cand.resize(_w * _h)
	var candidates := 0
	for iz in _h:
		for ix in _w:
			var k := iz * _w + ix
			var cx := box.position.x + (float(ix) + 0.5) * cell
			var cz := box.position.z + (float(iz) + 0.5) * cell
			if corridor.has_point(Vector2(cx, cz)):
				continue
			if _counts[k] < min_points or _high[k] < min_high_points:
				continue
			var need := mini(top_points, _high[k])
			var acc := 0
			var top := 0.0
			for bi in range(_bins - 1, hi_bin - 1, -1):
				acc += _hist[k * _bins + bi]
				if acc >= need:
					top = (float(bi) + 1.0) * bin_size
					break
			if top < min_high:
				continue
			tops[k] = top
			cand[k] = 1
			candidates += 1
	print("[bake] 候选格 %d / %d（%.1f%%）" % [candidates, _w * _h,
		100.0 * float(candidates) / float(_w * _h)])

	if show_map:
		print("[bake] 俯视地图（# = 有结构，. = 空，C = 走廊，行 z 从远到近）")
		for iz in _h:
			var line := ""
			for ix in _w:
				var k := iz * _w + ix
				var cx := box.position.x + (float(ix) + 0.5) * cell
				var cz := box.position.z + (float(iz) + 0.5) * cell
				if corridor.has_point(Vector2(cx, cz)):
					line += "C"
				else:
					line += "#" if cand[k] == 1 else "."
			print("  %s" % line)

	var rects := _merge_rects(cand, tops)
	print("[bake] 合并后 %d 个长方体" % rects.size())

	if show_map or not write:
		for i in mini(rects.size(), 16):
			var r: Array = rects[i]
			print("  #%02d x[%d..%d) z[%d..%d) top=%.1f" % [i,
				int(r[0]), int(r[2]), int(r[1]), int(r[3]), float(r[4])])
		quit(0)
		return

	var root_node := Node3D.new()
	root_node.name = "CampusCollision"
	var body_count := 0
	for r in rects:
		var x0 := box.position.x + float(r[0]) * cell
		var z0 := box.position.z + float(r[1]) * cell
		var x1 := box.position.x + float(r[2]) * cell
		var z1 := box.position.z + float(r[3]) * cell
		var top := float(r[4])
		var base := ground_y - 1.0
		var size := Vector3(x1 - x0, top - base, z1 - z0)
		if size.x <= 0.1 or size.z <= 0.1 or size.y <= 0.5:
			continue
		var body := StaticBody3D.new()
		body.name = "Box%03d" % body_count
		body.position = Vector3((x0 + x1) * 0.5, (base + top) * 0.5,
			(z0 + z1) * 0.5)
		var shape := BoxShape3D.new()
		shape.size = size
		var cs := CollisionShape3D.new()
		cs.name = "Collision"
		cs.shape = shape
		body.add_child(cs)
		root_node.add_child(body)
		body_count += 1
	root.add_child(root_node)
	_own(root_node, root_node)
	var ps := PackedScene.new()
	var err := ps.pack(root_node)
	if err != OK:
		print("[bake] pack 失败：%d" % err)
		quit(1)
		return
	err = ResourceSaver.save(ps, OUT_PATH)
	if err != OK:
		print("[bake] save 失败：%d" % err)
		quit(1)
		return
	print("[bake] %s ← %d 个盒（%.1f KB）" % [OUT_PATH, body_count,
		float(FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(OUT_PATH)).size()) / 1024.0])
	quit(0)


## 正确的矩形合并：先按行找连续段，跨行时要求 x 段完全相同才继续。
## 返回 [ix0, iz0, ix1, iz1, top]（右/下开区间）。
func _merge_rects(cand: PackedByteArray, tops: PackedFloat32Array) -> Array:
	# 每行的段：{x0: [len, top]}
	var rows: Array = []
	for iz in _h:
		var runs := {}
		var ix := 0
		while ix < _w:
			if cand[iz * _w + ix] == 0:
				ix += 1
				continue
			var x0 := ix
			var t := tops[iz * _w + ix]
			ix += 1
			while ix < _w and cand[iz * _w + ix] == 1:
				t = maxf(t, tops[iz * _w + ix])
				ix += 1
			runs[x0] = [ix - x0, t]
		rows.append(runs)
	var rects: Array = []
	var open := {}
	for iz in _h:
		var runs: Dictionary = rows[iz]
		var next_open := {}
		for x0 in runs:
			var r: Array = runs[x0]
			var key := "%d|%d" % [x0, int(r[0])]
			if open.has(key):
				var rect: Array = open[key]
				rect[3] = iz + 1
				rect[4] = maxf(float(rect[4]), float(r[1]))
				next_open[key] = rect
			else:
				next_open[key] = [x0, iz, x0 + int(r[0]), iz + 1, float(r[1])]
		for key in open:
			if not next_open.has(key):
				rects.append(open[key])
		open = next_open
	for key in open:
		rects.append(open[key])
	return rects


func _own(n: Node, root_node: Node) -> void:
	for c in n.get_children():
		c.owner = root_node
		_own(c, root_node)
