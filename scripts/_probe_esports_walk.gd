extends SceneTree
## 探针：电竞房门**能不能走进去** —— 把玩家胶囊一步步挪，用真物理试（不靠射线猜）。
##
## 前一版 `_probe_esports_door_ray.gd` 的"可通"判据写错了：
## 它把"射线打到房间中心之后就算通"，结果**四面墙全被判成可通 10.4 m**，
## 完全不能用。教训：射线穿过墙 ≠ 人能过去。
##
## 这一版直接做玩家会做的事：
##   ① 把真玩家的胶囊放到门外 2 m；
##   ② 按 `move_and_slide` 一路往里推（真物理），记录每一帧位置；
##   ③ 卡住了就报**卡在哪一点**，并在该点做一次完整扫描，
##      列出挡住它的每一个 CollisionShape3D（名字 + 世界 AABB）。
##
## 用法：& <godot_console.exe> --headless --path . --script res://scripts/_probe_esports_walk.gd -- --splat=off --no-capture

const ROOM := "EsportsRoom"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 150:
		await process_frame
	paused = false
	for _f in 30:
		await process_frame

	var room := game.get_node_or_null(ROOM) as Node3D
	var player := game.get("_player") as CharacterBody3D
	if room == null or player == null:
		print("[错误] room=%s player=%s" % [str(room), str(player)])
		quit(1)
		return
	room.visible = true
	for _f in 10:
		await process_frame

	# 玩家胶囊尺寸
	var cap_r := 0.30
	var cap_h := 1.50
	for c in player.find_children("*", "CollisionShape3D", true, false):
		var sh := (c as CollisionShape3D).shape
		if sh is CapsuleShape3D:
			cap_r = (sh as CapsuleShape3D).radius
			cap_h = (sh as CapsuleShape3D).height
			break
	print("玩家胶囊：radius %.2f / height %.2f（总高 %.2f）"
		% [cap_r, cap_h, cap_h + cap_r * 2.0])

	# 房间范围
	var bb := AABB()
	var first := true
	for mi in room.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var a: AABB = m.global_transform * m.mesh.get_aabb()
		bb = a if first else bb.merge(a)
		first = false
	print("房间 x %.2f~%.2f  y %.2f~%.2f  z %.2f~%.2f"
		% [bb.position.x, bb.end.x, bb.position.y, bb.end.y, bb.position.z, bb.end.z])

	var cx := (bb.position.x + bb.end.x) * 0.5
	var cz := (bb.position.z + bb.end.z) * 0.5
	var floor_y := bb.position.y

	# ── 四面各试一次：从门外 3 m 往里走 8 m ──
	# 门应该在**哪一面**是未知的，所以四面都试，看哪一面能进去
	var trials := {
		"从 -Z 侧进（朝 +Z 走）": [Vector3(0, 0, -3.0), Vector3(0, 0, 1)],
		"从 +Z 侧进（朝 -Z 走）": [Vector3(0, 0, 3.0), Vector3(0, 0, -1)],
		"从 -X 侧进（朝 +X 走）": [Vector3(-3.0, 0, 0), Vector3(1, 0, 0)],
		"从 +X 侧进（朝 -X 走）": [Vector3(3.0, 0, 0), Vector3(-1, 0, 0)],
	}
	var horiz_half := {"z": bb.size.z * 0.5, "x": bb.size.x * 0.5}

	for label in trials:
		var spec: Array = trials[label]
		var off: Vector3 = spec[0]
		var dir: Vector3 = spec[1]
		# 起点：房间中心 + 偏移（偏移是"门外多远"），y 放在地面上 0.05
		var start: Vector3 = Vector3(cx + off.x * (horiz_half["x"] if off.x != 0.0 else 1.0),
			floor_y + 0.05,
			cz + off.z * (horiz_half["z"] if off.z != 0.0 else 1.0))
		# 偏移给的是倍数，改成"门外 3 m"
		if off.x != 0.0:
			start.x = cx + signf(off.x) * (bb.size.x * 0.5 + 3.0)
		if off.z != 0.0:
			start.z = cz + signf(off.z) * (bb.size.z * 0.5 + 3.0)

		player.global_position = start
		player.velocity = Vector3.ZERO
		for _f in 20:
			await process_frame

		# 用 physics 帧推，每帧给一个速度；用 move_and_slide 才会真正被挡
		var moved := 0.0
		var last := player.global_position
		var stuck_at: Vector3 = start
		var stuck_frames := 0
		for i in 240:
			# 直接给速度再让它自己 move_and_slide（玩家脚本在 _physics_process 里做，
			# 这里只是 `--script` 模式，所以手动调）
			player.velocity = dir * 3.0
			player.move_and_slide()
			await process_frame
			var now := player.global_position
			if now.distance_to(last) < 0.002:
				stuck_frames += 1
			else:
				stuck_frames = 0
			moved += now.distance_to(last)
			last = now
			if stuck_frames >= 30:
				stuck_at = now
				break
		player.velocity = Vector3.ZERO

		var end := player.global_position
		var inside := end.x > bb.position.x + 0.3 and end.x < bb.end.x - 0.3 \
			and end.z > bb.position.z + 0.3 and end.z < bb.end.z - 0.3
		print("\n%s" % label)
		print("   起点 %s → 终点 %s（移动 %.2f m）%s"
			% [str(start.round()), str(end.round()), moved,
				"  ★ 进到屋里了" if inside else "  ✗ 没进去"])
		if not inside:
			print("   卡住位置 %s（y=%.2f，地面 %.2f）"
				% [str(stuck_at.round()), stuck_at.y, floor_y])
			_report_blockers(room, stuck_at, cap_r, cap_h)


## 在某个位置列出挡住玩家的所有碰撞形状（世界 AABB）
func _report_blockers(room: Node3D, pos: Vector3, r: float, h: float) -> void:
	# 玩家占的竖直范围：脚底 pos.y 附近 → pos.y + 总高
	var lo := pos.y + 0.05
	var hi := pos.y + h + r * 2.0
	var count := 0
	for b in room.find_children("*", "StaticBody3D", true, false):
		for c in b.get_children():
			if not (c is CollisionShape3D):
				continue
			var cs := c as CollisionShape3D
			if cs.shape == null:
				continue
			if not (cs.shape is BoxShape3D) and not (cs.shape is CapsuleShape3D) \
					and not (cs.shape is SphereShape3D):
				continue
			var aabb := _shape_world_aabb(cs)
			# 水平距离
			var near_x := clampf(pos.x, aabb.position.x, aabb.end.x)
			var near_z := clampf(pos.z, aabb.position.z, aabb.end.z)
			var dx := pos.x - near_x
			var dz := pos.z - near_z
			var horiz := sqrt(dx * dx + dz * dz)
			# 竖直重叠
			var v_overlap := aabb.end.y > lo and aabb.position.y < hi
			if horiz < r + 0.02 and v_overlap:
				count += 1
				if count <= 12:
					print("     挡：%s/%s  AABB x[%.2f,%.2f] y[%.2f,%.2f] z[%.2f,%.2f]  (水平距 %.3f)"
						% [String(b.name), String(cs.name),
							aabb.position.x, aabb.end.x,
							aabb.position.y, aabb.end.y,
							aabb.position.z, aabb.end.z, horiz])
	if count == 0:
		print("     挡：**没有形状重叠** —— 卡住的不是碰撞体（可能是台阶/斜坡/地板高度问题）")
	else:
		print("     共 %d 个形状挡在这里" % count)


func _shape_world_aabb(cs: CollisionShape3D) -> AABB:
	var sh := cs.shape
	var local := AABB()
	if sh is BoxShape3D:
		var s := (sh as BoxShape3D).size
		local = AABB(-s * 0.5, s)
	elif sh is CapsuleShape3D:
		var c := sh as CapsuleShape3D
		local = AABB(Vector3(-c.radius, -(c.height * 0.5 + c.radius), -c.radius),
			Vector3(c.radius * 2.0, c.height + c.radius * 2.0, c.radius * 2.0))
	elif sh is SphereShape3D:
		var sp := sh as SphereShape3D
		local = AABB(Vector3(-sp.radius, -sp.radius, -sp.radius),
			Vector3(sp.radius * 2.0, sp.radius * 2.0, sp.radius * 2.0))
	return cs.global_transform * local
