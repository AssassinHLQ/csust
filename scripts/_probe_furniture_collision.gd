extends SceneTree
## 验家具碰撞：直接往沙发/桌子上撞，看人会不会穿过去。
##   godot --path . --headless --script res://scripts/_probe_furniture_collision.gd

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(level)
	for _i in 40:
		await process_frame
	var p := level.get("_player") as CharacterBody3D

	# ① 三层红沙发：沙发在 x=-3.5（0.95 宽），东侧面 ≈ -3.02
	p.global_position = Vector3(-1.6, 9.35, -1.4)
	p.velocity = Vector3.ZERO
	for _i in 15:
		await process_frame
	Input.action_press("move_left")
	for _i in 90:
		await process_frame
	Input.action_release("move_left")
	for _i in 10:
		await process_frame
	print("[col] 撞沙发后 x=%.2f（沙发东面 −3.02，期望停在 −2.7 左右，< −3.0 就是穿过去了）"
		% p.global_position.x)

	# ② 三层小桌：桌子在 (-1.7, -1.4)，1.3×1.3，东侧面 ≈ -1.05
	p.global_position = Vector3(0.6, 9.35, -1.4)
	p.velocity = Vector3.ZERO
	for _i in 15:
		await process_frame
	Input.action_press("move_left")
	for _i in 90:
		await process_frame
	Input.action_release("move_left")
	for _i in 10:
		await process_frame
	print("[col] 撞桌子后 x=%.2f（桌面东沿 −1.05，期望 > −1.0）" % p.global_position.x)
	quit(0)
