extends SceneTree
## 验：从东侧 / 南侧都钻不进楼梯底下（封板生效）。
##   _tools/run_probe.sh res://scripts/_probe_house_under_entry.gd -- --splat=off --story=off
const O := Vector3(27.3, 0.0, 13.5)


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _walk(player: CharacterBody3D, pos: Vector3, yaw: float, name: String) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO
	player.set("_yaw", yaw)
	player.set("_pitch", 0.0)
	await _wait(20)
	var start := player.global_position
	Input.action_press("move_forward")
	for _f in 240:
		await process_frame
	Input.action_release("move_forward")
	await _wait(10)
	var end := player.global_position
	var local_end := end - O
	print("[under] %s 起点 local=(%.2f,%.2f) 终点 local=(%.2f,%.2f) %s" % [
		name, start.x - O.x, start.z - O.z, local_end.x, local_end.z,
		"OK 被挡" if local_end.x > -6.2 or (name.contains("南") and local_end.z > 2.9) else "FAIL 钻进楼梯底"])


func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(90)
	var player := game.get_node_or_null("Player") as CharacterBody3D
	if player == null:
		quit(1)
		return
	await _walk(player, O + Vector3(-4.9, 0.25, 0.8), PI * 0.5, "东侧")
	await _walk(player, O + Vector3(-6.95, 0.25, 3.95), 0.0, "南侧")
	quit(0)
