extends SceneTree
## 验：画室家具碰撞**真的挡人**，且不会挡得太远（空气墙）。
##   godot --path . --headless --script res://scripts/_verify_art_desk.gd
##
## 用户 2026-10-26：「老师左边桌子那里还没有加碰撞体吗?」
## → 「需要在 godot 编辑器也看得见，因为这样子我好微调」
## 盒子写在 `scenes/game.tscn` 的 `Room609/RoomCollision` 下（ArtDesk / ArtChairA / ArtChairB）。
##
## 判据：
##   ① 三个节点都在，尺寸为正；
##   ② 玩家从桌子**南侧**往北走，被挡在桌前 `胶囊半径(0.30) + 桌子南沿` 附近
##      —— 偏差超过 0.15 m 就算「空气墙 / 仍能穿」；
##   ③ 绕开桌子（往西偏 2 m）能一直走到老师旁边 —— 证明挡的只是桌子，不是整间屋子；
##   ④ 桌子**上面**（y = 0.9 处）没有碰撞 —— 碰撞盒顶面就在 0.78，别挡住跳过去的人。

const ROOM := "Room609/RoomCollision"
const DESK := "ArtDesk"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var fails := 0
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 120:
		await process_frame
	paused = false

	# ① 节点
	print("=== 1. 碰撞盒存在 ===")
	var body := game.get_node_or_null(ROOM) as Node3D
	if body == null:
		print("  [FAIL] 没有 %s" % ROOM)
		quit(1)
		return
	var desk_cs := body.get_node_or_null(DESK) as CollisionShape3D
	var boxes := {}
	for nm in [DESK, "ArtChairA", "ArtChairB"]:
		var cs := body.get_node_or_null(nm) as CollisionShape3D
		if cs == null:
			print("  [FAIL] 缺 %s" % nm)
			fails += 1
			continue
		var b := cs.shape as BoxShape3D
		if b == null or b.size.x <= 0 or b.size.y <= 0 or b.size.z <= 0:
			print("  [FAIL] %s 的 shape 不是正数 BoxShape3D" % nm)
			fails += 1
			continue
		boxes[nm] = {"c": cs.global_position, "s": b.size}
		print("  [PASS] %-11s 尺寸 %.2f×%.2f×%.2f  世界中心 %s"
			% [nm, b.size.x, b.size.y, b.size.z, str(cs.global_position.snappedf(0.01))])

	if not boxes.has(DESK):
		print("\n失败 %d 项" % fails)
		quit(1)
		return
	var dc: Vector3 = boxes[DESK]["c"]
	var ds: Vector3 = boxes[DESK]["s"]
	var desk_south := dc.z + ds.z * 0.5
	print("  桌子：x %.2f~%.2f  z %.2f~%.2f  顶面 y = %.2f"
		% [dc.x - ds.x * 0.5, dc.x + ds.x * 0.5, dc.z - ds.z * 0.5, desk_south,
			dc.y + ds.y * 0.5])

	# ② 从南往北走，应被挡在桌前
	print("\n=== 2. 从南侧走向桌子（应被挡住）===")
	var player := game.get_node_or_null("Player") as CharacterBody3D
	if player == null:
		print("  [FAIL] 没有 Player")
		quit(1)
		return
	var cap_r := 0.30
	for c in player.get_children():
		var cs := c as CollisionShape3D
		if cs != null and cs.shape is CapsuleShape3D:
			cap_r = (cs.shape as CapsuleShape3D).radius
			break
	var start_z := desk_south + 2.0
	player.global_position = Vector3(dc.x, 0.10, start_z)
	player.velocity = Vector3.ZERO
	for _f in 30:
		await process_frame
	Input.action_press("move_forward")     # W → -Z
	for _f in 150:
		await process_frame
	Input.action_release("move_forward")
	for _f in 20:
		await process_frame
	var p := player.global_position
	var want := desk_south + cap_r            # 理想：胶囊贴着桌面南沿停下
	var diff := p.z - want
	print("  起点 z=%.2f → 终点 (%.2f, %.3f, %.2f)" % [start_z, p.x, p.y, p.z])
	print("  被挡在 z = %.3f；桌子南沿 %.3f + 胶囊半径 %.2f = 理想 %.3f（差 %+.3f m）"
		% [p.z, desk_south, cap_r, want, diff])
	if absf(diff) <= 0.15:
		print("  [PASS] 挡在桌前（偏差 %.3f m ≤ 0.15）" % absf(diff))
	else:
		print("  [FAIL] %s（偏差 %.3f m）"
			% ["空气墙：离桌太远就停了" if diff > 0 else "没挡住：穿过去了", absf(diff)])
		fails += 1

	# ③ 绕开桌子能走过去
	print("\n=== 3. 绕开桌子往北走（应能一直走到老师附近）===")
	var sx := dc.x - ds.x * 0.5 - 1.2
	player.global_position = Vector3(sx, 0.10, start_z)
	player.velocity = Vector3.ZERO
	for _f in 30:
		await process_frame
	Input.action_press("move_forward")
	for _f in 150:
		await process_frame
	Input.action_release("move_forward")
	for _f in 20:
		await process_frame
	var p2 := player.global_position
	var went := start_z - p2.z
	print("  x=%.2f 起：走了 %.2f m，终点 z=%.2f" % [sx, went, p2.z])
	if went > 2.5:
		print("  [PASS] 绕得过去（走了 %.2f m，没被车成整面墙）" % went)
	else:
		print("  [FAIL] 只走了 %.2f m —— 碰撞盒围成一面墙了" % went)
		fails += 1

	# ④ 桌面之上不该有碰撞
	print("\n=== 4. 桌面上方 1.0 m 处没有碰撞 ===")
	var space := (root.get_world_3d() as World3D).direct_space_state
	var from := Vector3(dc.x, dc.y + ds.y * 0.5 + 0.20, dc.z)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
		from, from + Vector3.DOWN * 0.18))
	print("  从 y=%.2f 往下打 0.18 m：%s"
		% [from.y, "打空（好）" if hit.is_empty() else
			"打到 %s（碰撞盒比桌子高）" % (hit["collider"] as Node).name])
	if not hit.is_empty():
		fails += 1

	print("\n========== 结果 ==========")
	print("失败 %d 项" % fails)
	quit(0 if fails == 0 else 1)
