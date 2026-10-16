extends SceneTree
## 最小探针：站在**平台地面**上按一次跳，看 `velocity.y` 到底变不变。
##
## 目的只有一个：把「按跳不生效」这件事**归因**到「合成输入 / 场景环境」还是「跑酷板上特有」。
## 什么都不设（不隐藏 HUD、不 set_process_input、不 _pk.enabled=false、不瞬移）。
##
## 用法：godot --path <工程> --script res://scripts/_probe_jump_min.gd -- --splat=off

var _p: Player


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 30:
		await process_frame
	_p = game.get_node_or_null("Player") as Player
	if _p == null:
		print("!! 没有 Player")
		quit(1)
		return
	print("[min] 站定：y = %.2f  floor = %s  v.y = %+.2f"
		% [_p.global_position.y, _p.is_on_floor(), _p.velocity.y])

	# ① 原始写法（各套件都在用的那种）
	Input.action_press("jump")
	await process_frame
	await process_frame
	print("[min] ① action_press 两帧：v.y = %+.2f  floor = %s  y = %.2f"
		% [_p.velocity.y, _p.is_on_floor(), _p.global_position.y])
	Input.action_release("jump")
	var peak := _p.global_position.y
	for _i in 40:
		await process_frame
		peak = maxf(peak, _p.global_position.y)
	print("[min] ① 峰值涨了 %.3f m" % (peak - 0.05))

	# ② 合成事件
	await _wait(20)
	var ev := InputEventAction.new()
	ev.action = "jump"
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	await process_frame
	print("[min] ② 合成事件两帧：v.y = %+.2f  floor = %s  y = %.2f"
		% [_p.velocity.y, _p.is_on_floor(), _p.global_position.y])
	ev = InputEventAction.new()
	ev.action = "jump"
	ev.pressed = false
	Input.parse_input_event(ev)
	await _wait(20)

	# ③ 真·键盘事件（空格 keycode 32 / physical 32）
	var ke := InputEventKey.new()
	ke.physical_keycode = KEY_SPACE
	ke.pressed = true
	Input.parse_input_event(ke)
	await process_frame
	await process_frame
	print("[min] ③ 合成键盘(空格)两帧：v.y = %+.2f  floor = %s  y = %.2f"
		% [_p.velocity.y, _p.is_on_floor(), _p.global_position.y])
	var ku := InputEventKey.new()
	ku.physical_keycode = KEY_SPACE
	ku.pressed = false
	Input.parse_input_event(ku)

	print("[min] 结论写在上面三行：哪一行的 v.y 跳到 +7.10 附近，哪种按法就是对的")
	quit(0)


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
