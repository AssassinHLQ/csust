extends SceneTree
## 验证 F3 浮层能画出来：开浮层 → 截图 → 打印文本。
##   _tools/run_shot.sh res://scripts/_probe_perf_overlay_shot.gd -- --splat=off --story=off


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(120)

	# 走真实入口：模拟一次 F3 按下
	var ev := InputEventKey.new()
	ev.keycode = KEY_F3
	ev.physical_keycode = KEY_F3
	ev.pressed = true
	Input.parse_input_event(ev)
	await _wait(40)

	var layer := game.get_node_or_null("PerfOverlay") as CanvasLayer
	if layer == null:
		print("[perfshot] 浮层没建出来（_input 没收到 F3？keys_seen=%d）" % int(game.get("_keys_seen")))
		quit(1)
		return
	var labels := layer.find_children("*", "Label", true, false)
	var label := (labels[0] as Label) if not labels.is_empty() else null
	if label == null:
		print("[perfshot] 浮层里没有 Label")
		quit(1)
		return
	print("[perfshot] 可见=%s" % str(layer.visible))
	print("[perfshot] ---- 文本 ----")
	print(label.text)

	await _wait(20)
	var img := root.get_texture().get_image()
	var path := "res://_log/perf_overlay.png"
	img.save_png(ProjectSettings.globalize_path(path))
	print("[perfshot] 截图 → %s" % path)

	# 再按一次应该关掉
	Input.parse_input_event(ev)
	await _wait(5)
	print("[perfshot] 再按一次后可见=%s" % str(layer.visible))
	quit(0)