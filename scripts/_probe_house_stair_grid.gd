extends SceneTree
## 网格测试：小屋楼梯在不同 x 上能不能上来 / 下去，找「被堵住」的落点。
##   _tools/run_probe.sh res://scripts/_probe_house_stair_grid.gd -- --splat=off --story=off
const O := Vector3(27.3, 0.0, 13.5)


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(90)
	var player := game.get_node_or_null("Player") as CharacterBody3D
	if player == null:
		quit(1)
		return

	for x in [-7.3, -7.1, -6.95, -6.8, -6.65, -6.5]:
		player.global_position = O + Vector3(x, 0.25, -5.1)
		player.velocity = Vector3.ZERO
		player.set("_yaw", PI)
		player.set("_pitch", -0.1)
		await _wait(20)
		Input.action_press("move_forward")
		var best := 0.0
		for _f in 480:
			await process_frame
			best = maxf(best, player.global_position.y)
		Input.action_release("move_forward")
		await _wait(10)
		print("[grid] 上 x=%.2f → (%.2f, %.2f) 最高 y=%.2f %s" % [
			x, player.global_position.z, player.global_position.y, best,
			"OK" if player.global_position.y > 3.9 else "STUCK"])

	for x in [-7.3, -7.1, -6.95, -6.8, -6.65, -6.5]:
		player.global_position = O + Vector3(x, 4.35, 3.3)
		player.velocity = Vector3.ZERO
		player.set("_yaw", 0.0)
		player.set("_pitch", -0.1)
		await _wait(20)
		Input.action_press("move_forward")
		var low := 99.0
		for _f in 480:
			await process_frame
			low = minf(low, player.global_position.y)
		Input.action_release("move_forward")
		await _wait(10)
		print("[grid] 下 x=%.2f → (%.2f, %.2f) 最低 y=%.2f %s" % [
			x, player.global_position.z, player.global_position.y, low,
			"OK" if low < 0.4 else "STUCK"])
	quit(0)
