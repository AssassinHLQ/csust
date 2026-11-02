extends SceneTree
## 自检：商店东侧延长地块 + 游戏开发部部室。
##   _tools/run_probe.sh res://scripts/_verify_gamedev_room.gd -- --splat=off --story=off
##
## 判据：
##   · 新地砖铺到 x = 64，顶面 y = 0，再往东是空的；
##   · 部室地板在 y ≈ 0.01，门洞能直着走进去，西墙挡人；
##   · 玩家从门前进屋后站在地板上，不会卡在 1 cm 门槛上。

var _fails: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, msg: String) -> void:
	print(("[ OK ] " if ok else "[FAIL] ") + msg)
	if not ok:
		_fails.append(msg)


func _wait(n: int) -> void:
	for _i in n:
		await physics_frame


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = false
	return root.world_3d.direct_space_state.intersect_ray(q)


func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(30)

	var lot := game.get_node_or_null("LotEast") as Node3D
	var room := game.get_node_or_null("GameDevRoom") as Node3D
	_check(lot != null, "LotEast 已挂进场景")
	_check(room != null, "GameDevRoom 已挂进场景")
	if lot == null or room == null:
		quit(1)
		return

	# 地块
	var lot_aabb := AABB(Vector3(lot.position.x - 12.0, -0.5, -20.0), Vector3(24.0, 0.5, 40.0))
	print("[lot] 理论范围 x %.2f ~ %.2f" % [lot_aabb.position.x, lot_aabb.end.x])
	for p in [Vector3(40.5, 8.0, 0.0), Vector3(52.0, 8.0, -18.0), Vector3(63.5, 8.0, 18.0)]:
		var hit := _ray(p, Vector3(p.x, -5.0, p.z))
		_check(hit and absf(hit.position.y) < 0.001,
			"地砖踩得到 %s → y=%s" % [str(p), str(hit.position.y) if hit else "没有碰撞"])
	var beyond := _ray(Vector3(65.0, 8.0, 0.0), Vector3(65.0, -5.0, 0.0))
	_check(beyond.is_empty(), "x=65 已经在空地外（没有地板）")

	# 部室范围
	var model := room.get_node_or_null("Model") as Node3D
	_check(model != null, "Model 节点存在")
	var aabb := AABB()
	var first := true
	for node in room.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var w := mi.global_transform * mi.mesh.get_aabb()
		aabb = w if first else aabb.merge(w)
		first = false
	print("[room] 世界包围盒 %s ~ %s" % [str(aabb.position.snappedf(0.01)), str(aabb.end.snappedf(0.01))])
	_check(aabb.position.x > 40.0 and aabb.end.x < 64.0, "部室整栋都在新地砖上")
	_check(aabb.end.z < 7.5 and aabb.position.z > -12.7,
		"部室没有压到商店（z 在 -12.7 ~ 7.5 之间）")

	# 地板 / 墙 / 门洞
	var mid := Vector3(52.0, 0.0, 0.0)
	# 门内侧没铺地毯，射线从这里往下量地板（屋子正中是圆地毯，会先打到毯子）
	var floor_hit := _ray(Vector3(46.2, 0.8, 3.48), Vector3(46.2, -3.0, 3.48))
	_check(floor_hit and absf(floor_hit.position.y - 0.01) < 0.02,
		"屋内地面 y=%.3f（期望 0.01）" % [floor_hit.position.y if floor_hit else 999.0])

	var wall_hit := _ray(Vector3(42.0, 1.5, -3.48), Vector3(49.0, 1.5, -3.48))
	_check(wall_hit and wall_hit.position.x > 44.5 and wall_hit.position.x < 46.0,
		"西墙挡人：x=%.2f（期望 ≈45.17）" % [wall_hit.position.x if wall_hit else 999.0])

	var door_hit := _ray(Vector3(42.0, 1.5, 3.48), Vector3(70.0, 1.5, 3.48))
	_check(door_hit and door_hit.position.x > 50.0,
		"门洞是通的：射线打到 x=%.2f（不该在门口 45 就停）" % [door_hit.position.x if door_hit else 999.0])

	# 玩家从门口走进去
	var player := game.get_node_or_null("Player") as CharacterBody3D
	_check(player != null, "Player 存在")
	if player == null:
		_report()
		return
	player.global_position = Vector3(43.2, 0.25, 3.48)
	player.velocity = Vector3.ZERO
	await _wait(40)
	_check(player.is_on_floor(), "门口站得住（on_floor=%s，y=%.3f）"
		% [str(player.is_on_floor()), player.global_position.y])
	_check(absf(player.global_position.x - 43.2) < 0.35, "玩家没被门口弹开")

	player.set("_yaw", -PI * 0.5)
	Input.action_press("move_forward")
	var start_x := player.global_position.x
	await _wait(150)
	Input.action_release("move_forward")
	await _wait(10)
	var end_x := player.global_position.x
	print("[walk] x %.2f → %.2f，y=%.3f，on_floor=%s" % [
		start_x, end_x, player.global_position.y, str(player.is_on_floor())])
	_check(end_x > start_x + 3.0, "能穿过门洞往屋里走（+%.2f m）" % (end_x - start_x))
	_check(player.is_on_floor() and absf(player.global_position.y - 0.01) < 0.12,
		"进屋后站在地板上（y=%.3f）" % player.global_position.y)

	_report()


func _report() -> void:
	if _fails.is_empty():
		print("[gamedev] 结论：OK")
		quit(0)
	else:
		print("[gamedev] 结论：FAIL %d 项" % _fails.size())
		quit(1)
