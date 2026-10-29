extends SceneTree
## 量校园碰撞网格（campus_collision_mesh.scn）和点云地面的贴合度。
##   _tools/run_probe.sh res://scripts/_probe_campus_collision_fit.gd
##
## 地面真值的取法（比「分位数」稳）：每根柱子里把点按 0.25 m 分箱，
## 只统计 y < 5 m 的箱子，取**点数最多的那一箱**作为地面（地面是柱子里面积最大的
## 表面，树冠在 5 m 以上被排除）。射线从「地面 + 1.5 m」往下打 4.5 m，
## 这样即使空中有树冠也不会误命中，量到的就是脚下的碰撞面。

const LEVEL := "res://scenes/next_level.tscn"
const STEP := 20.0
const COL_R := 1.5          # 真值柱子半径（米）
const BIN := 0.25           # y 分箱高度
const FLOOR_CAP := 5.0      # 只看 y < 5 的点（排除树冠/屋顶）
const MIN_PTS := 12

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var level := (load(LEVEL) as PackedScene).instantiate()
	root.add_child(level)
	await process_frame
	await process_frame

	var campus := level.get_node_or_null("Campus")
	if campus != null:
		campus.set("auto_start", false)
		campus.set_process(false)

	# 关掉平板地面 / 坠落区，只量网格
	for nm in ["CampusFloor", "FallReset"]:
		var b := level.get_node_or_null(nm) as CollisionObject3D
		if b != null:
			b.collision_layer = 0

	var prev := level.get_node_or_null("Campus/CampusPreview")
	var mi: MeshInstance3D = null
	if prev != null:
		for c in prev.get_children():
			if c is MeshInstance3D:
				mi = c
				break
	if mi == null or mi.mesh == null:
		print("[fit] 找不到 CampusPreview 网格")
		quit(1)
		return
	var arrays := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var xf := mi.global_transform
	print("[fit] 预览点 %d 个（世界坐标）" % verts.size())

	var buckets := {}
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for v in verts:
		var p := xf * v
		var k := Vector2i(int(floor(p.x / STEP)), int(floor(p.z / STEP)))
		var arr = buckets.get(k)
		if arr == null:
			buckets[k] = [p.y]
		else:
			arr.append(p.y)
		lo.x = minf(lo.x, p.x); lo.z = minf(lo.z, p.z)
		hi.x = maxf(hi.x, p.x); hi.z = maxf(hi.z, p.z)

	await physics_frame
	var space: PhysicsDirectSpaceState3D = level.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = 1

	var hit := 0
	var miss := 0
	var no_pts := 0
	var errs: Array[float] = []
	var truths: Array[float] = []
	var worst: Array = []
	var sum := 0.0
	var cell_n := 0
	var keys := buckets.keys()
	keys.sort_custom(func(a, b): return a.x < b.x if a.x != b.x else a.z < b.z)
	for key in keys:
		var cx: float = (key.x + 0.5) * STEP
		var cz: float = (key.y + 0.5) * STEP
		cell_n += 1
		# ── 真值：附近 3×3 桶内、y<5 的点，按 0.25 m 分箱取最密箱 ──
		var hist := {}
		var total := 0
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var arr = buckets.get(Vector2i(key.x + dx, key.y + dz))
				if arr == null:
					continue
				for y in arr:
					if y >= FLOOR_CAP:
						continue
					var b := int(floor(y / BIN))
					hist[b] = int(hist.get(b, 0)) + 1
					total += 1
		if total < MIN_PTS or hist.is_empty():
			no_pts += 1
			continue
		var best_bin := 0
		var best_n := -1
		for b in hist:
			if int(hist[b]) > best_n:
				best_n = int(hist[b])
				best_bin = int(b)
		var truth: float = (best_bin + 0.5) * BIN
		truths.append(truth)

		q.from = Vector3(cx, truth + 1.5, cz)
		q.to = Vector3(cx, truth - 3.0, cz)
		var r: Dictionary = space.intersect_ray(q)
		if r.is_empty():
			miss += 1
			worst.append([0.0, cx, cz, truth, -999.0])
			continue
		var hy: float = (r["position"] as Vector3).y
		var e := hy - truth
		hit += 1
		errs.append(e)
		sum += e
		worst.append([e, cx, cz, truth, hy])

	if hit == 0:
		print("[fit] 一条射线都没命中")
		quit(1)
		return
	errs.sort()
	var mean := sum / hit
	var abs_sum := 0.0
	for e in errs:
		abs_sum += absf(e)
	var abs_mean := abs_sum / hit
	var med := errs[hit / 2]
	var p05 := errs[int(0.05 * (hit - 1))]
	var p95 := errs[int(0.95 * (hit - 1))]
	var good := 0
	var up := 0
	var down := 0
	for e in errs:
		if absf(e) <= 0.2:
			good += 1
		if e > 0.3:
			up += 1
		if e < -0.3:
			down += 1

	truths.sort()
	var tsum := 0.0
	for t in truths:
		tsum += t
	var tmean := tsum / truths.size()
	var tvar := 0.0
	for t in truths:
		tvar += (t - tmean) * (t - tmean)
	print("[fit] 地面真值：均值 %+.2f  标准差 %.2f  最小 %+.2f  最大 %+.2f"
		% [tmean, sqrt(tvar / truths.size()), truths[0], truths[truths.size() - 1]])
	print("[fit] 柱子 %d 个（其中 %d 个点太少跳过）；命中 %d，没碰撞 %d" % [cell_n, no_pts, hit, miss])
	print("[fit] 误差（碰撞面 y − 点云地面 y）：均值 %+.3f  绝对均值 %.3f  中位 %+.3f  P5 %+.3f  P95 %+.3f"
		% [mean, abs_mean, med, p05, p95])
	print("[fit] |误差| ≤ 0.2 m：%.1f%%   高于地面 > 0.3 m：%.1f%%   低于地面 > 0.3 m：%.1f%%"
		% [100.0 * good / hit, 100.0 * up / hit, 100.0 * down / hit])
	worst.sort_custom(func(a, b): return absf(a[0]) > absf(b[0]))
	print("[fit] 偏差最大的 10 个位置（误差 / x,z / 点云地面 / 碰撞面）：")
	for i in mini(10, worst.size()):
		var w = worst[i]
		print("       %+.2f m  @ (%.0f, %.0f)  真值 %.2f  碰撞 %.2f" % [w[0], w[1], w[2], w[3], w[4]])
	print("[fit] 总耗时 %d ms" % (Time.get_ticks_msec() - t0))
	quit(0)
