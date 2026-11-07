extends SceneTree
## 浮层自身的开销：同一次运行里「关着」和「开着」各采样 180 帧，对比主线程耗时。
##   _tools/run_shot.sh res://scripts/_probe_perf_overlay_cost.gd -- --splat=off --story=off


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _sample(tag: String, frames: int) -> void:
	var samples: Array = []
	var t0 := Time.get_ticks_usec()
	for _i in frames:
		await process_frame
		samples.append(float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0)
	var fps := float(frames) / maxf(float(Time.get_ticks_usec() - t0) / 1000000.0, 0.0001)
	samples.sort()
	var n := samples.size()
	var sum := 0.0
	for s in samples:
		sum += float(s)
	print("[cost] %-4s %d 帧：真实 fps %6.1f  主线程均值 %.2f ms  中位 %.2f ms" % [
		tag, n, fps, sum / float(n), float(samples[n / 2])])


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(150)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	await _sample("关", 180)

	var ev := InputEventKey.new()
	ev.keycode = KEY_F3
	ev.physical_keycode = KEY_F3
	ev.pressed = true
	Input.parse_input_event(ev)
	await _wait(30)
	await _sample("开", 180)
	quit(0)