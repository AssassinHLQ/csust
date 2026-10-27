extends SceneTree
## 出图：确认三个靶子在墙上看得见、位置正确。
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
	for n in ["Target1", "Target2", "Target3"]:
		var t := level.get_node_or_null(n) as Node3D
		if t != null:
			print("[target] %s 世界位置 %s  可见 %s" % [n,
				str(t.global_position.snappedf(0.01)), str(t.visible)])
	var cam := Camera3D.new()
	cam.fov = 66.0
	level.add_child(cam)
	cam.current = true
	cam.global_position = Vector3(6.0, 4.2, 0.0)
	cam.look_at(Vector3(10.0, 3.6, -8.8))
	await _shot("_constructivist_targets.png")
	cam.global_position = Vector3(6.0, 4.0, -1.5)
	cam.look_at(Vector3(13.8, 4.0, 2.0))
	await _shot("_constructivist_target_east.png")
	quit(0)
