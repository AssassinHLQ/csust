extends SceneTree
## 验：开发部换成凹面碰撞后，地面、门口、家具之间的空地不会穿模/绊住。
##   _tools/run_probe.sh res://scripts/_verify_room_trimesh.gd -- --splat=off --story=off

func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _walk(player: CharacterBody3D, start: Vector3, yaw: float, frames: int) -> Array:
	player.global_position = start
	player.velocity = Vector3.ZERO
	player.set("_yaw", yaw)
	player.set("_pitch", 0.0)
	await _wait(20)
	var s := player.global_position
	var lowest := s.y
	Input.action_press("move_forward")
	for _f in frames:
		await process_frame
		lowest = minf(lowest, player.global_position.y)
	Input.action_release("move_forward")
	await _wait(10)
	var e := player.global_position
	return [s, e, lowest]


func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(100)
	var player := game.get_node_or_null("Player") as CharacterBody3D
	if player == null:
		quit(1); return
	print("[tri] 玩家出生 ", player.global_position.snappedf(0.01))

	# 1) 从室内中心往西走出门（门在西墙 world x≈45.3）
	var r1 := await _walk(player, Vector3(52.0, 0.8, 3.0), PI * 0.5, 300)
	print("[tri] 出门 起=%s 终=%s 最低y=%.2f %s" % [
		str((r1[0] as Vector3).snappedf(0.01)), str((r1[1] as Vector3).snappedf(0.01)),
		r1[2], "OUT" if (r1[1] as Vector3).x < 45.0 else "STUCK"])

	# 2) 室内横穿：从东侧走到西侧（避开桌子，走南边走道）
	var r2 := await _walk(player, Vector3(57.0, 0.8, 3.6), PI * 0.5, 240)
	print("[tri] 横穿 起=%s 终=%s 最低y=%.2f" % [
		str((r2[0] as Vector3).snappedf(0.01)), str((r2[1] as Vector3).snappedf(0.01)), r2[2]])

	# 3) 往电视柜方向走（应该被家具挡住，但不能掉下去/穿过去）
	var r3 := await _walk(player, Vector3(53.0, 0.8, 0.2), 0.0, 180)
	print("[tri] 电视柜 起=%s 终=%s 最低y=%.2f" % [
		str((r3[0] as Vector3).snappedf(0.01)), str((r3[1] as Vector3).snappedf(0.01)), r3[2]])

	# 4) 站回室内中心，看有没有穿过地毯掉出地板
	await _wait(60)
	print("[tri] 收尾 y=%.3f fps=%d" % [player.global_position.y, Engine.get_frames_per_second()])
	quit(0)
