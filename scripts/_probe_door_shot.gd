extends SceneTree
## 出图：机关没破时东门关着 / 破完下沉后打开。
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
	for _i in 40:
		await process_frame
	for c in level.find_children("*", "CanvasLayer", true, false):
		var cl := c as CanvasLayer
		if cl != null:
			cl.visible = false
	var cam := Camera3D.new()
	cam.fov = 66.0
	level.add_child(cam)
	cam.current = true
	cam.global_position = Vector3(7.0, 2.2, 3.0)
	cam.look_at(Vector3(14.0, 2.6, 3.0))
	await _shot("_exit_door_closed.png")
	for c in level.get_children():
		if c is Target:
			c.take_damage(10000.0)
	await create_timer(2.6, true).timeout
	cam.global_position = Vector3(7.0, 2.2, 3.0)
	cam.look_at(Vector3(20.0, 1.2, 3.0))
	await _shot("_exit_door_open.png")
	print("[door] y=%.2f" % (level.get_node("ExitDoor") as Node3D).position.y)
	quit(0)
