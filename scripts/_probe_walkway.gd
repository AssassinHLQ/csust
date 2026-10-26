extends SceneTree
## 验数：楼与商店之间的空地、楼大门是否正对商店门、玩家能不能从商店门口走到大楼门口。
##   godot --path . --headless --script res://scripts/_probe_walkway.gd -- --splat=off
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 120:
		await process_frame
	paused = false
	var house := game.get_node_or_null("MondrianHouse") as Node3D
	var shop := game.get_node_or_null("Shop") as Node3D
	if house == null or shop == null:
		print("[错误] 缺节点")
		quit(1)
		return
	var hp := house.global_position
	var sp := shop.global_position

	# 商店：长 13.20、进深 5.60 → 南墙 z = sp.z + 2.80；门在那面墙中心 x = sp.x
	var shop_south := sp.z + 2.80
	var house_north := hp.z - 6.00
	print("商店南墙 z = %.2f（门中心 x = %.2f）" % [shop_south, sp.x])
	print("大楼北墙 z = %.2f（门中心 x = %.2f）" % [house_north, hp.x])
	print("两楼间距（门前空场）= %.2f m" % (house_north - shop_south))
	print("两门中心横向偏移 = %.2f m" % absf(hp.x - sp.x))

	# 走道净宽里有没有障碍（在 x 取两门中点、z 从商店南墙到大楼北墙扫一遍）
	var space := (root.get_world_3d() as World3D).direct_space_state
	var mx := (sp.x + hp.x) * 0.5
	print("\n走道剖线 x=%.2f，从 z=%.2f 到 z=%.2f：" % [mx, shop_south + 0.1, house_north - 0.1])
	var blocked := 0
	var z := shop_south + 0.10
	while z < house_north - 0.10:
		var q := PhysicsRayQueryParameters3D.create(Vector3(mx, 1.0, z), Vector3(mx, 1.0, z + 0.05))
		var h := space.intersect_ray(q)
		if not h.is_empty():
			blocked += 1
			print("  挡住 @ z=%.2f → %s" % [z, (h["collider"] as Node).name])
		z += 0.10
	print("  被挡格点 %d 个 → %s" % [blocked, "走道通畅" if blocked == 0 else "有障碍"])

	# 真走一遍：从商店门口直着走向大楼门口。
	# ⚠️ 2026-10-26 楼退到 z = +13.50 之后，两门相距 20.16 m ——
	#    走路速度 2.4 m/s（`player.gd::SPEED_WALK`），4 秒只够走 9.6 m，
	#    所以从 240 帧加到 **660 帧（11 秒）**，并按每 2 秒打一次点。
	var player := game.get("_player") as CharacterBody3D
	player.global_position = Vector3(sp.x, 0.10, shop_south + 0.60)
	player.velocity = Vector3.ZERO
	for _f in 20:
		await process_frame
	print("\n真走一遍（起点 z=%.2f，朝 +Z 走 11 秒 / 2.4 m·s⁻¹）：" % player.global_position.z)
	Input.action_press("move_back")
	for _f in 660:
		await process_frame
		if _f % 120 == 0:
			print("  t=%.1fs  (%.2f, %.3f, %.2f)"
				% [float(_f) / 60.0, player.global_position.x,
					player.global_position.y, player.global_position.z])
	Input.action_release("move_back")
	for _f in 15:
		await process_frame
	var p := player.global_position
	print("  终点 (%.2f, %.3f, %.2f)" % [p.x, p.y, p.z])
	print("  进门了吗：%s（大门在 z = %.2f）"
		% ["是" if p.z > house_north - 0.15 and p.z < hp.z + 6.0 else "否", house_north])
	quit(0)
