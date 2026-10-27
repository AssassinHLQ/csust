extends SceneTree
## 玩家站在校园里、眼睛高度的视角（判断挨着走的时候能不能看）。
func _initialize() -> void:
	_run.call_deferred()

func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(name)
	root.get_texture().get_image().save_png(out)
	print("[截图] %s" % out)

func _run() -> void:
	root.size = Vector2i(1600, 900)
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	for _i in 30:
		await process_frame
	var campus := level.get_node("Campus")
	var t0 := Time.get_ticks_msec()
	while not bool(campus.call("is_ready")) and Time.get_ticks_msec() - t0 < 240000:
		await process_frame
	var player := level.get_node("Player") as CharacterBody3D
	player.global_position = Vector3(0.0, 0.3, -150.0)
	for _i in 30:
		await physics_frame
	for _i in 30:
		await process_frame
	await _shot("_campus_eye_level.png")
	print("[eye] 玩家 %s" % str(player.global_position.snappedf(0.1)))
	quit(0)
