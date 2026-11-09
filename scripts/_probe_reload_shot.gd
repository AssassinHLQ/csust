extends SceneTree
## 出图：**跑** vs **跑着换弹**，同一机位、同一时刻，看身体有没有歪。
##
##   _tools/run_shot.sh res://scripts/_probe_reload_shot.gd
##
## 输出 `_log/reload_run_only.png` 与 `_log/reload_run_reload.png`。
## 机位放在角色**斜后方 3 m**：正后方看不清左右歪，正前方被枪挡住。

const OUT_A := "res://_log/reload_run_only.png"
const OUT_B := "res://_log/reload_run_reload.png"
const SPAWN := Vector3(0, 0.05, 6)


func _initialize() -> void:
	# 不抢用户前台（AGENTS.md 硬要求，2026-11-09）：取消最大化 + 禁止聚焦 + 挪出屏幕
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(12)

	var p := game.get_node_or_null("Player") as Player
	var anim := p.anim as AnimDriver
	if p == null or anim == null:
		print("!! 没有 Player / AnimDriver")
		quit(1)
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	await _shoot(p, anim, false, OUT_A)
	await _shoot(p, anim, true, OUT_B)
	quit(0)


func _shoot(p: Player, anim: AnimDriver, do_reload: bool, out: String) -> void:
	_release()
	p.velocity = Vector3.ZERO
	p.global_position = SPAWN
	p._yaw = 0.0
	p._facing_yaw = PI
	p.model_root.rotation.y = PI
	anim.state = AnimDriver.State.LOCOMOTION
	anim.stop_upper_layer()
	await _wait(8)

	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _wait_ms(700)

	if do_reload:
		anim.request_reload()
		await _wait_ms(300)      # 换弹播到 0.3 s 左右（2.0 s ÷ 1.9 = 1.05 s 的一半前段）
	else:
		await _wait_ms(300)

	# 机位：角色斜后方 3 m、高 1.6 m，看向角色胸口
	var eye := p.global_position + Vector3(-2.1, 1.6, 2.1)
	var cam := Camera3D.new()
	cam.fov = 50.0
	root.add_child(cam)
	cam.global_position = eye
	cam.look_at(p.global_position + Vector3(0, 1.0, 0), Vector3.UP)
	cam.current = true

	await _wait(3)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var abs_path := ProjectSettings.globalize_path(out)
	var err := img.save_png(abs_path)
	print("[reloadshot] %s -> %s err=%d" % [
		"跑+换弹" if do_reload else "只跑", out, err])
	print("    层=%s  基础clip=%s  状态=%s  速度=%.2f  位置=%s  on_floor=%s" % [
		String(anim.active_upper_layer().name), anim.current_clip(), anim.current_state_name(),
		p.velocity.length(), str(p.global_position.snappedf(0.01)), str(p.is_on_floor())])

	root.remove_child(cam)
	cam.free()
	_release()
	await _wait(2)


func _release() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right",
			"sprint", "crouch", "jump"]:
		Input.action_release(a)


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame


func _wait_ms(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame
