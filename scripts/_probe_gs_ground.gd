extends SceneTree
## 验收「分块 GDGS 碰撞」：全校园按网格打向下射线，统计
##   ① 洞（打不到 / 打到兜底板以下）
##   ② 相邻 8 m 采样点的高差（> 0.45 m 就是玩家可能卡住的台阶）
## 不加载泼溅（`--campus-splat=off`），秒出。
##
##   godot --headless --path . --script res://scripts/_probe_gs_ground.gd -- --campus-splat=off

const STEP := 8.0
const X0 := -288.0
const X1 := 288.0
const Z0 := -560.0
const Z1 := -76.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var lvl := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(lvl)
	for _i in 5:
		await process_frame
	var space: PhysicsDirectSpaceState3D = (lvl as Node3D).get_world_3d().direct_space_state
	var floor_body := lvl.get_node_or_null("CampusFloor") as CollisionObject3D
	var exclude: Array[RID] = []
	if floor_body != null:
		exclude.append(floor_body.get_rid())
	var nx := int((X1 - X0) / STEP) + 1
	var nz := int((Z1 - Z0) / STEP) + 1
	var grid := PackedFloat32Array()
	grid.resize(nx * nz)
	var holes := 0
	var plate := 0
	var lo := INF
	var hi := -INF
	for iz in nz:
		for ix in nx:
			var x := X0 + float(ix) * STEP
			var z := Z0 + float(iz) * STEP
			var q := PhysicsRayQueryParameters3D.create(
				Vector3(x, 120.0, z), Vector3(x, -40.0, z))
			q.collision_mask = 1
			q.exclude = exclude
			var hit: Dictionary = space.intersect_ray(q)
			var y := -9999.0
			if not hit.is_empty():
				y = (hit["position"] as Vector3).y
			if y < -50.0:
				holes += 1
			elif is_equal_approx(y, -0.02):
				plate += 1
			else:
				lo = minf(lo, y)
				hi = maxf(hi, y)
			grid[iz * nx + ix] = y
	var total := nx * nz
	var max_step := 0.0
	var steps := 0
	for iz in nz:
		for ix in nx:
			var y := grid[iz * nx + ix]
			if y < -50.0:
				continue
			if ix + 1 < nx:
				var y2 := grid[iz * nx + ix + 1]
				if y2 > -50.0:
					var d := absf(y2 - y)
					max_step = maxf(max_step, d)
					if d > 0.45:
						steps += 1
			if iz + 1 < nz:
				var y3 := grid[(iz + 1) * nx + ix]
				if y3 > -50.0:
					var d2 := absf(y3 - y)
					max_step = maxf(max_step, d2)
					if d2 > 0.45:
						steps += 1
	print("[gsground] 采样 %d 点（%.0f m 网格，**已排除 CampusFloor**）：洞 %d（%.1f%%）、-0.02 面 %d、碰撞面 %d" % [
		total, STEP, holes, 100.0 * float(holes) / float(total), plate,
		total - holes - plate])
	print("[gsground] 碰撞面高度 %.2f ~ %.2f；相邻高差 > 0.45 m 的边 %d 条，最大 %.2f m" % [
		lo, hi, steps, max_step])
	quit(0 if holes == 0 else 1)