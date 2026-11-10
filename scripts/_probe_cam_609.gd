extends SceneTree
## 复现「初始 609 就抽动」：**不移动玩家**，在出生点逐帧记录相机臂长 + 每一条射线的命中。
##
## 用户 2026-11-10 第四轮：「还不对，初始609就抽动」。
##
## 目标：找出静止时到底是什么在每帧翻转。
##   - 打印 5 条探测射线的命中距离序列：如果某一条在"命中/未命中"之间来回翻，
##     就是它把 `blocked` 拉来拉去。
##   - 打印 `Room609/RoomCollision` 每个盒的世界 AABB：`_probe_room609_walls.gd`
##     的注释说「Y 全部是错的」，先确认几何本身对不对。
##
##   godot --headless --script res://scripts/_probe_cam_609.gd -- --splat=off --story=off --no-capture

const OffWin := preload("res://scripts/offscreen_window.gd")
const GAME := "res://scenes/game.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	await OffWin.apply(self, Vector2i(640, 360))
	await _wait(2)
	get_root().get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[c6] !! 超时强制退出")
		quit(2))
	var game: Node = load(GAME).instantiate()
	root.add_child(game)
	await _wait(90)

	var p := game.get_node_or_null("Player") as CharacterBody3D
	if p == null:
		print("[c6] !! 没找到 Player")
		quit(1)
		return
	var spring := p.get_node_or_null("CameraRig/SpringArm3D") as SpringArm3D
	var rig := p.get_node_or_null("CameraRig") as Node3D
	var cam := p.get_node_or_null("CameraRig/SpringArm3D/Camera3D") as Camera3D
	if spring == null or rig == null or cam == null:
		print("[c6] !! 相机节点缺失")
		quit(1)
		return

	print("[c6] 玩家出生点 %s   _yaw=%.3f  _pitch=%.3f"
		% [str(p.global_position.snappedf(0.01)), float(p.get("_yaw")), float(p.get("_pitch"))])
	print("[c6] rig.position=%s   spring.position=%s   spring_length=%.3f"
		% [str(rig.position.snappedf(0.01)), str(spring.position.snappedf(0.01)),
		   spring.spring_length])

	# ── A. Room609 的 5 个墙盒世界 AABB ──
	print("[c6] ── A. Room609/RoomCollision 的墙盒（世界 AABB）──")
	var col := game.get_node_or_null("Room609/RoomCollision") as Node3D
	if col == null:
		print("[c6]   没有 Room609/RoomCollision")
	else:
		for c in col.get_children():
			var cs := c as CollisionShape3D
			if cs == null or cs.shape == null:
				continue
			var sh := cs.shape as BoxShape3D
			if sh == null:
				print("[c6]   %s: 非 BoxShape" % cs.name)
				continue
			var xf := cs.global_transform
			var half := sh.size * 0.5
			var lo := Vector3(INF, INF, INF)
			var hi := Vector3(-INF, -INF, -INF)
			for i in 8:
				var lp := Vector3(
					half.x if (i & 1) != 0 else -half.x,
					half.y if (i & 2) != 0 else -half.y,
					half.z if (i & 4) != 0 else -half.z)
				var wp := xf * lp
				lo = Vector3(minf(lo.x, wp.x), minf(lo.y, wp.y), minf(lo.z, wp.z))
				hi = Vector3(maxf(hi.x, wp.x), maxf(hi.y, wp.y), maxf(hi.z, wp.z))
			print("[c6]   %-16s x[%.2f,%.2f] y[%.2f,%.2f] z[%.2f,%.2f]"
				% [cs.name, lo.x, hi.x, lo.y, hi.y, lo.z, hi.z])

	# ── B. 静止 180 帧：臂长 + 相机世界坐标 + is_on_floor ──
	print("[c6] ── B. 静止 180 帧（不移动、不转视角）──")
	var space := p.get_world_3d().direct_space_state
	var lens: Array[float] = []
	var cam_pos: Array[Vector3] = []
	var rig_y: Array[float] = []
	var ply_y: Array[float] = []
	var on_floor: Array[bool] = []
	var per_dir: Array[String] = []          # 每帧每条射线"沿轴距离 or 空"
	for i in 180:
		await physics_frame
		lens.append(spring.spring_length)
		cam_pos.append(cam.global_position)
		rig_y.append(rig.position.y)
		ply_y.append(p.global_position.y)
		on_floor.append(p.is_on_floor())

		var axis := spring.global_transform.basis.z.normalized()
		var origin := spring.global_position
		var want := spring.spring_length
		var reach := want + 0.18 + 0.25
		var row := PackedStringArray()
		for d: Vector3 in p.call("_camera_probe_dirs", axis, want):
			var q := PhysicsRayQueryParameters3D.create(
					origin, origin + d * reach, 1, [p.get_rid()])
			var h := space.intersect_ray(q)
			if h.is_empty():
				row.append("  ---")
			else:
				var n: Vector3 = h.get("normal", Vector3.UP)
				var along: float = origin.distance_to(h["position"]) * d.dot(axis)
				row.append("%5.2f%s" % [along, "" if absf(n.y) <= 0.85 else "(平)"])
		per_dir.append(", ".join(row))

	## 统计一个小统计器：区间宽度
	var span := func(arr: Array) -> String:
		var lo := INF
		var hi := -INF
		for v in arr:
			lo = minf(lo, float(v))
			hi = maxf(hi, float(v))
		return "宽 %.4f [%.4f, %.4f]" % [hi - lo, lo, hi]

	var rev_len := _reversals(lens, 0.01)
	var cx := cam_pos.map(func(v: Vector3) -> float: return v.x)
	var cy := cam_pos.map(func(v: Vector3) -> float: return v.y)
	var cz := cam_pos.map(func(v: Vector3) -> float: return v.z)
	var rev_y := _reversals(cy, 0.001)
	var floor_flips := 0
	for i in range(1, on_floor.size()):
		if on_floor[i] != on_floor[i - 1]:
			floor_flips += 1

	print("[c6]   臂长     : %s   反向 %d 次" % [span.call(lens), rev_len])
	print("[c6]   相机 y   : %s   反向 %d 次  ← 抽动就是这里" % [span.call(cy), rev_y])
	print("[c6]   相机 x/z : %s / %s" % [span.call(cx), span.call(cz)])
	print("[c6]   rig.y    : %s" % span.call(rig_y))
	print("[c6]   玩家 y   : %s" % span.call(ply_y))
	print("[c6]   is_on_floor 翻转 %d 次" % floor_flips)
	print("[c6]   前 10 帧臂长：%s" % str(lens.slice(0, 10).map(func(v: float) -> String:
		return "%.2f" % v)))
	print("[c6]   前 10 帧相机 y：%s" % str(cy.slice(0, 10).map(func(v: float) -> String:
		return "%.4f" % v)))
	print("[c6]   每帧各射线沿轴距离（前 12 帧，末尾 (平)=地板/天花板）──")
	for i in mini(12, per_dir.size()):
		print("[c6]     %3d  len=%.2f  | %s" % [i, lens[i], per_dir[i]])

	# ── C. 结论（静止）──
	print("[c6] ── C. 结论（静止）──")
	var bad := false
	if rev_len > 2:
		print("[c6]   [FAIL] 臂长在抖（反向 %d 次）" % rev_len)
		bad = true
	if rev_y > 2:
		print("[c6]   [FAIL] 相机高度在抖（反向 %d 次）—— 这就是「抽动」的直接来源" % rev_y)
		bad = true
	if floor_flips > 2:
		print("[c6]   [FAIL] is_on_floor 翻转 %d 次（玩家脚下在微弹）" % floor_flips)
		bad = true
	if not bad:
		print("[c6]   [PASS] 出生点静止时相机稳定")

	# ── D. 原地转视角 360°：609 里转一圈 ──
	print("[c6] ── D. 原地转视角 360° ──")
	# ⚠️ 必须 `await`：`_p_sweep()` 里有 await，不 await 它跑到第一个 await 就返回了，
	#    后面的 quit() 直接结束进程 —— 第一次跑这段时什么都没打印，就是踩了这个。
	await _p_sweep(p, spring, cam, 360, "转视角")

	# ── E. 走动：从出生点沿 -Z 走 6 m（经过桌子那一带）──
	print("[c6] ── E. 走动：从出生点沿 -Z 走 6 m ──")
	var start := Vector3(0, 0.0, 6.0)
	p.global_position = start
	await _wait(10)
	var wlens: Array[float] = []
	var wpos: Array[Vector3] = []
	for i in 200:
		p.global_position = start + Vector3(0, 0, -float(i) * 0.03)
		await physics_frame
		wlens.append(spring.spring_length)
		wpos.append(cam.global_position)
	var wrev := _reversals(wlens, 0.01)
	var wy := wpos.map(func(v: Vector3) -> float: return v.y)
	var wjerks := 0
	for i in range(1, wlens.size()):
		if absf(wlens[i] - wlens[i - 1]) > 0.25:
			wjerks += 1
	print("[c6]   臂长 宽 %.2f  反向 %d 次  跳变帧 %d"
		% [float(wlens.max()) - float(wlens.min()), wrev, wjerks])
	if wrev > 6 or wjerks > 6:
		print("[c6]   [FAIL] 走动时臂长抖（反向 %d、跳变 %d）" % [wrev, wjerks])
	else:
		print("[c6]   [PASS] 走动平稳")

	quit(0)


## 原地把视角转 `deg` 度，逐帧记臂长和相机位置，报告抖动。
func _p_sweep(p: CharacterBody3D, spring: SpringArm3D, cam: Camera3D,
		deg: float, tag: String) -> void:
	var base_yaw := float(p.get("_yaw"))
	var steps := int(deg)
	var lens: Array[float] = []
	var pos: Array[Vector3] = []
	var worst_i := -1
	var worst := 0.0
	for i in steps:
		p.set("_yaw", base_yaw + deg_to_rad(float(i)))
		await physics_frame
		var cur := spring.spring_length
		if lens.size() > 0 and absf(cur - lens[lens.size() - 1]) > worst:
			worst = absf(cur - lens[lens.size() - 1])
			worst_i = i
		lens.append(cur)
		pos.append(cam.global_position)
	var rev := _reversals(lens, 0.01)
	var lo := INF
	var hi := -INF
	for v in lens:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	print("[c6]   %s：臂长 [%.2f, %.2f] 宽 %.2f  反向 %d 次  单帧最大 %.3f（第 %d 帧）"
		% [tag, lo, hi, hi - lo, rev, worst, worst_i])
	if rev > 12 or worst > 0.55:
		print("[c6]   [FAIL] %s 时在抖" % tag)
	else:
		print("[c6]   [PASS] %s 平稳" % tag)


## 统计序列的符号翻转次数（deadband 外的相邻差分）。
func _reversals(seq: Array, dead: float) -> int:
	var rev := 0
	var prev_sign := 0
	for i in range(1, seq.size()):
		var dd := float(seq[i]) - float(seq[i - 1])
		if absf(dd) < dead:
			continue
		var s := 1 if dd > 0.0 else -1
		if prev_sign != 0 and s != prev_sign:
			rev += 1
		prev_sign = s
	return rev
