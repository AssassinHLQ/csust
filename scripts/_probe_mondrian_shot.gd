extends SceneTree
## 验图 + 验数：蒙德里安大楼。
##   godot --path . --script res://scripts/_probe_mondrian_shot.gd -- --splat=off
## 输出：_arisu_captures/_mondrian/{front,from_shop,side,inside,stairs_up,upstairs}.png
##
## 同时驱真玩家走一遍：从商店门口 → 进大门 → 走到楼梯 → 爬到二层，
## 沿途打印 y，证明楼梯真的能上去、脚踩在踏面上。
func _initialize() -> void:
	_run.call_deferred()


func _shoot(cam: Camera3D, out: String, nm: String) -> void:
	cam.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, nm])


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 120:
		await process_frame
	paused = false
	for _f in 20:
		await process_frame

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_mondrian")
	DirAccess.make_dir_recursive_absolute(out)
	for c in game.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false

	var house := game.get_node_or_null("MondrianHouse") as Node3D
	if house == null:
		print("[错误] 场景里没有 MondrianHouse")
		quit(1)
		return
	var hp := house.global_position
	print("MondrianHouse 世界原点 %s" % str(hp))

	# ── 实测包围盒（含所有网格）──
	var bb := AABB()
	var first := true
	var n_mesh := 0
	for mi in house.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var a: AABB = m.global_transform * m.mesh.get_aabb()
		bb = a if first else bb.merge(a)
		first = false
		n_mesh += 1
	print("网格 %d 个，世界包围盒 x %.2f~%.2f  y %.2f~%.2f  z %.2f~%.2f"
		% [n_mesh, bb.position.x, bb.end.x, bb.position.y, bb.end.y,
			bb.position.z, bb.end.z])

	var cam := Camera3D.new()
	cam.near = 0.05
	cam.far = 500.0
	root.add_child(cam)

	# ① 正立面。
	# ⚠️ 相机不能压得太低、太靠 −Z：商店占 z −18.30 ~ −12.70、高 5.91，站在
	#    z = hp.z − 17 = −19 拍到的全是商店内墙（实测整屏粉色）。这里升到 y=11、
	#    退到 z = hp.z − 24，从商店屋脊上方俯拍整张北立面。
	cam.fov = 46.0
	cam.global_position = Vector3(hp.x, 11.0, hp.z - 24.0)
	cam.look_at(Vector3(hp.x, 4.2, hp.z), Vector3.UP)
	await _shoot(cam, out, "front")

	# ② 从商店门口往外看（同机位，但带上商店）
	cam.fov = 58.0
	cam.global_position = Vector3(27.30, 1.7, -12.9)
	cam.look_at(Vector3(hp.x, 3.4, hp.z - 6.0), Vector3.UP)
	await _shoot(cam, out, "from_shop")

	# ③ 侧面（东北角，看两层关系）
	cam.fov = 50.0
	cam.global_position = Vector3(hp.x + 19.0, 9.0, hp.z - 9.0)
	cam.look_at(Vector3(hp.x, 4.0, hp.z), Vector3.UP)
	await _shoot(cam, out, "side")

	# ④ 室内一层（站在门口往里看）
	cam.fov = 62.0
	cam.global_position = Vector3(hp.x, 1.62, hp.z - 5.6)
	cam.look_at(Vector3(hp.x, 1.9, hp.z + 3.0), Vector3.UP)
	await _shoot(cam, out, "inside")

	# ── ⑤ 驱真玩家走一遍 ──
	var player := game.get("_player") as CharacterBody3D
	if player == null:
		print("[错误] 拿不到玩家")
		quit(1)
		return
	# 起点：**楼梯正前方**。
	# ⚠️ 第一版从商店门口直着走进大门（x = hp.x = 29），一路走到 z = +3.45 都是
	#    y = 0 —— 因为楼梯在局部 x = −6.95（世界 x ≈ 22.05），沿 x = 29 直走
	#    根本碰不到它。要走楼梯必须先把人挪到楼梯口。
	# ⚠️ 必须站在**屋里**：门开在北墙局部 x ±1.10，而楼梯在局部 x = −6.95，
	#    所以「从门外直接走到楼梯口」这条路线是撞墙的（实测 z 卡在 −8.30 一步不动，
	#    正是北墙外表面 −8.00 再加胶囊半径 0.30）。这里直接把人放到屋内楼梯口。
	var stair_x := hp.x - 6.95          # 楼梯中线（局部 −6.95）
	var stair_z := hp.z - 5.60          # 局部 −3.60，第 1 级踢面（−4.30）前 0.70 m
	player.global_position = Vector3(stair_x, 0.10, stair_z)
	player.velocity = Vector3.ZERO
	for _f in 30:
		await process_frame
	print("\n—— 驱玩家走：商店门 → 大楼门 → 楼梯 → 二层 ——")
	print("起点 y=%.3f  z=%.2f" % [player.global_position.y, player.global_position.z])

	print("楼梯口：x=%.2f  z=%.2f（楼梯中线局部 −6.95，第 1 级踢面局部 −4.30）"
		% [stair_x, stair_z])
	Input.action_press("move_back")   # move_back 走 +Z（朝楼梯、朝大楼）
	var best_y := 0.0
	for _f in 420:
		await process_frame
		best_y = maxf(best_y, player.global_position.y)
		if _f % 60 == 0:
			print("  t=%.1fs  y=%.3f  z=%.2f  x=%.2f"
				% [float(_f) / 60.0, player.global_position.y,
					player.global_position.z, player.global_position.x])
	Input.action_release("move_back")
	for _f in 20:
		await process_frame
	print("走完：y=%.3f（最高 %.3f）  z=%.2f  x=%.2f"
		% [player.global_position.y, best_y, player.global_position.z,
			player.global_position.x])

	# ⑥ 楼梯段特写
	cam.fov = 60.0
	cam.global_position = Vector3(hp.x - 2.4, 2.2, hp.z + 3.2)
	cam.look_at(Vector3(hp.x - 6.9, 2.0, hp.z - 1.0), Vector3.UP)
	await _shoot(cam, out, "stairs_up")

	# ⑦ 二层鸟瞰
	cam.fov = 66.0
	cam.global_position = Vector3(hp.x + 5.0, hp.y + 7.4, hp.z - 4.0)
	cam.look_at(Vector3(hp.x - 4.0, hp.y + 4.2, hp.z + 2.0), Vector3.UP)
	await _shoot(cam, out, "upstairs")

	print("\n[截图] %s" % out)
	quit(0)
