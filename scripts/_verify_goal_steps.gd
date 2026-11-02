extends SceneTree
## 验：从三层地面沿新增的五级台阶走上红色终点台（11.3），不再要直跳 2.1 m。
##   _tools/run_probe.sh res://scripts/_verify_goal_steps.gd -- --splat=off --story=off

func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	await _wait(90)
	var player := level.get_node("Player") as CharacterBody3D
	player.global_position = Vector3(2.6, 9.35, -0.8)
	player.velocity = Vector3.ZERO
	player.set("_yaw", 0.0)
	player.set("_pitch", 0.0)
	await _wait(20)
	var start := player.global_position
	Input.action_press("move_forward")
	var best := start.y
	for i in 360:
		await process_frame
		if i % 36 == 0:
			Input.action_press("jump")
		elif i % 36 == 4:
			Input.action_release("jump")
		best = maxf(best, player.global_position.y)
	Input.action_release("move_forward")
	Input.action_release("jump")
	await _wait(20)
	var e := player.global_position
	print("[goal] 起点 %s 终点 %s 最高 y=%.2f %s" % [
		str(start.snappedf(0.01)), str(e.snappedf(0.01)), best,
		"OK" if e.y >= 11.15 and e.z < -3.8 else "STUCK"])
	quit(0)
