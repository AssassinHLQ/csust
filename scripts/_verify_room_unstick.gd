extends SceneTree
## 验：开发部桌子/椅子之间的窄口袋 + 卡角自救。
##   _tools/run_probe.sh res://scripts/_verify_room_unstick.gd -- --splat=off --story=off

func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(100)
	var player := game.get_node_or_null("Player") as CharacterBody3D
	if player == null:
		quit(1); return
	var col := game.get_node_or_null("GameDevRoom/Model/Collision/Mesh") as CollisionShape3D
	print("[unstick] 开发部碰撞 = %s" % (col.shape.get_class() if col and col.shape else "missing"))
	player.global_position = Vector3(52.70, 0.80, 4.30)
	player.velocity = Vector3.ZERO
	player.set("_yaw", PI)
	player.set("_pitch", 0.0)
	await _wait(20)
	var start := player.global_position
	Input.action_press("move_forward")
	for _f in 180:
		await process_frame
	Input.action_release("move_forward")
	await _wait(10)
	var moved := player.global_position - start
	print("[unstick] 起点 %s 终点 %s 水平位移 %.2f" % [
		str(start.snappedf(0.01)), str(player.global_position.snappedf(0.01)),
		Vector2(moved.x, moved.z).length()])
	quit(0)
