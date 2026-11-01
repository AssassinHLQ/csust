extends SceneTree
## 出图：选项面板（箭头 + 呼吸边框）长什么样。
##   _tools/run_shot.sh res://scripts/_probe_choice_shot.gd
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var bg := CanvasLayer.new()
	bg.layer = 0
	root.add_child(bg)
	var rect := ColorRect.new()
	rect.color = Color(0.10, 0.11, 0.13, 1.0)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.add_child(rect)

	var box := DialogueBox.new()
	root.add_child(box)
	await process_frame
	box.set_cps(100000.0)
	box.play_steps([
		{"kind": "say", "who": "芹香", "text": "你配电脑吗?"},
		{"kind": "choice", "options": [
			{"text": "商人啊!我正是为此而来!", "disabled": true,
				"disabled_hint": "银行卡余额不足：还差 ¥20.0 万（卡上 ¥30.0 万）"},
			{"text": "观察了银行卡的余额,摇了摇头"},
		]},
	], "shot")
	for _i in 30:
		await process_frame
	box.advance()
	for _i in 40:
		await process_frame

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_choice")
	DirAccess.make_dir_recursive_absolute(out)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/01_choice.png" % out)
	var e := InputEventKey.new()
	e.keycode = KEY_S
	e.pressed = true
	Input.parse_input_event(e)
	for _i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/02_choice_second.png" % out)
	print("[shot] 输出到 %s" % out)
	quit(0)
