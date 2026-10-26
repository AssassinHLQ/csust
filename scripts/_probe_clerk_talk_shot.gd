extends SceneTree
## 判图：① 走近显示「按 F 说话」 ② 按 F 弹出对话「你配电脑吗?」
##   godot --path . --script res://scripts/_probe_clerk_talk_shot.gd -- --splat=off
func _initialize() -> void:
	_run.call_deferred()


func _shoot(cam: Camera3D, out: String, nm: String) -> void:
	cam.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, nm])


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 130:
		await process_frame
	paused = false
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_clerkview")
	DirAccess.make_dir_recursive_absolute(out)
	var clerk := game.get_node_or_null("Shop/ClerkSerika") as Node3D
	var player := game.get("_player") as CharacterBody3D
	var box := game.get_node_or_null("DialogueBox") as DialogueBox
	var base := clerk.global_position

	player.global_position = Vector3(base.x - 2.0, 0.10, base.z)
	player.velocity = Vector3.ZERO
	for _f in 30:
		await process_frame

	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.near = 0.05
	cam.far = 400.0
	root.add_child(cam)
	cam.global_position = Vector3(base.x - 3.5, 1.45, base.z + 0.1)
	cam.look_at(Vector3(base.x, 1.05, base.z), Vector3.UP)
	await _shoot(cam, out, "talk_hint")

	_key(KEY_F)
	for _f in 40:
		await process_frame
	print("对话 active = %s  文本 = 「%s」" % [box.is_active(), box.current_text()])
	await _shoot(cam, out, "talk_box")
	print("[截图] %s" % out)
	quit(0)
