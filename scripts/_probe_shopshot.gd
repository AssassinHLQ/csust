extends SceneTree
## 验图：店外看整栋（墙角 / 幕墙有没有缝）
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 60:
		await process_frame
	paused = false
	var hud := game.get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		hud.visible = false
	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.far = 200.0
	root.add_child(cam)
	# 站在店面斜前方 12 m、2 m 高，能同时看到幕墙和两侧墙角
	cam.global_position = Vector3(24.0, 2.0, -6.0)
	cam.look_at(Vector3(27.0, 3.0, -13.5), Vector3.UP)
	cam.make_current()
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures")
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("_shop_after_fix.png"))
	print("[截图] %s/_shop_after_fix.png" % out)
	quit(0)
