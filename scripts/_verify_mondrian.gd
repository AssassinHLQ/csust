extends SceneTree
## 验数（**判定修正版**）：只抓「真的会闪」的共面重叠。
##   godot --path . --headless --script res://scripts/_verify_mondrian.gd -- --splat=off
##
## ⚠️ 老探针（`_probe_zfight.gd`）的判定太宽：只要两个 AABB 在某一轴的**边界重合**
##    就算共面。但「A 的正面和 B 的背面贴在同一张平面上」这种背靠背关系，
##    两个面**法线相反**、深度相等但朝向不同，光栅化时不会互相抢像素 —— 不闪。
##
## 真要闪的情形只有一种：**两个面的法线朝同一侧，且落在同一张平面上**。
## 对轴对齐的盒子来说就是：
##   · 两盒的 +面与 +面重合（都在同一个坐标上，比如都是顶面）
##   · 或 −面与 −面重合（都是底面）
##   · 而「A 的 +面 = B 的 −面」是**贴在一起**（正面接背面），不闪。
##
## 这条区别很要紧：商店那次的墙角是「两块墙的**外表面**都在 x = ±L/2」
## （+面 = +面），所以真的闪；而本探针最初把大量「贴面」也算进去，
## 报出 72 组虚警，差点把正常的接缝全拆了。
func _initialize() -> void:
	_run.call_deferred()


const EPS := 0.002


func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 120:
		await process_frame
	paused = false
	var house := game.get_node_or_null("MondrianHouse") as Node3D
	if house == null:
		print("[错误] 没有 MondrianHouse")
		quit(1)
		return
	var hp := house.global_position
	var player := game.get("_player") as CharacterBody3D

	# ══ 1. 大门通行 ══
	print("=== 1. 大门通行（从门外真按键走进来）===")
	player.global_position = Vector3(hp.x, 0.10, hp.z - 10.0)
	player.velocity = Vector3.ZERO
	for _f in 20:
		await process_frame
	Input.action_press("move_back")
	for _f in 200:
		await process_frame
	Input.action_release("move_back")
	for _f in 15:
		await process_frame
	var p := player.global_position
	print("起点 z=%.2f → 终点 (%.2f, %.3f, %.2f)  进室内：%s"
		% [hp.z - 10.0, p.x, p.y, p.z, "是" if p.z > hp.z - 5.9 else "否"])

	# ══ 2. 二层可站立 ══
	print("\n=== 2. 二层可站立 ===")
	player.global_position = Vector3(hp.x + 2.0, 4.35, hp.z + 1.0)
	player.velocity = Vector3.ZERO
	for _f in 90:
		await process_frame
	print("放到 y=4.35 一秒后 y=%.3f（应 ≈4.200）" % player.global_position.y)

	# ══ 3. 共面重叠（只算同向面）══
	print("\n=== 3. 共面重叠（仅同向面：+面=+面 或 −面=−面）===")
	var list: Array = []
	for mi in house.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		# ⚠️ 斜坡/斜栏板/彩带是旋转过的盒子：AABB 会被撑大，
		#    拿它判「同向面重合」只会得到假阳性。轴对齐的网格才进判定。
		var bb := m.global_transform.basis
		var skew := absf(bb.x.y) + absf(bb.x.z) + absf(bb.y.x) + absf(bb.y.z) \
			+ absf(bb.z.x) + absf(bb.z.y)
		if skew > 1e-3:
			continue
		list.append({"n": m.name, "a": m.global_transform * m.mesh.get_aabb()})
	var found: Array = []
	for i in list.size():
		for j in range(i + 1, list.size()):
			var a: AABB = list[i]["a"]
			var b: AABB = list[j]["a"]
			for axis in 3:
				var a0: float = a.position[axis]
				var a1: float = a0 + a.size[axis]
				var b0: float = b.position[axis]
				var b1: float = b0 + b.size[axis]
				# 同向才算：max= max 或 min = min
				var same_max := absf(a1 - b1) < EPS
				var same_min := absf(a0 - b0) < EPS
				if not same_max and not same_min:
					continue
				# 另两轴的真实重叠面积
				var area := 1.0
				for ax in 3:
					if ax == axis:
						continue
					var lo: float = maxf(a.position[ax], b.position[ax])
					var hi: float = minf(a.position[ax] + a.size[ax],
						b.position[ax] + b.size[ax])
					area *= maxf(hi - lo, 0.0)
				if area > 0.02:
					found.append({"a": list[i]["n"], "b": list[j]["n"], "ax": axis,
						"area": area, "face": "+" if same_max else "-"})
	found.sort_custom(func(x, y): return float(x["area"]) > float(y["area"]))
	print("真共面（同向）重叠对 %d 组" % found.size())
	for h in found.slice(0, 12):
		print("  %-18s ↔ %-18s 轴%d %s面  面积 %.3f m²"
			% [h["a"], h["b"], h["ax"], h["face"], h["area"]])
	print("网格 %d 个" % list.size())

	# ══ 4. 楼梯到头：真走一遍 ══
	print("\n=== 4. 楼梯（真按键，从一层走到二层）===")
	player.global_position = Vector3(hp.x - 6.95, 0.10, hp.z - 5.60)
	player.velocity = Vector3.ZERO
	for _f in 20:
		await process_frame
	Input.action_press("move_back")
	var t0 := Time.get_ticks_msec()
	var trace: Array = []
	var next_trace := 0.0
	while Time.get_ticks_msec() - t0 < 15000:
		await process_frame
		var elapsed := float(Time.get_ticks_msec() - t0) / 1000.0
		if elapsed >= next_trace:
			trace.append("t=%.1fs y=%.2f" % [elapsed, player.global_position.y])
			next_trace += 0.5
		if player.global_position.y >= 4.15:
			break
	Input.action_release("move_back")
	for _f in 15:
		await process_frame
	for t in trace:
		print("  %s" % t)
	var top := player.global_position.y
	print("  终点 y=%.3f（≥4.15 即上到二层）  [%s]"
		% [top, "PASS" if top >= 4.15 else "FAIL"])
	quit(0)
