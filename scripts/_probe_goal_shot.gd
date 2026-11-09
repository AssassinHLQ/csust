extends SceneTree
## 出图：三层终点台阶 + 红垫 + 提示牌。
##   _tools/run_shot.sh res://scripts/_probe_goal_shot.gd -- --splat=off

func _initialize() -> void:
	# 不抢用户前台（AGENTS.md 硬要求，2026-11-09）：取消最大化 + 禁止聚焦 + 挪出屏幕
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(cam: Camera3D, p: Vector3, t: Vector3, nm: String, fov := 60.0) -> void:
	cam.fov = fov
	cam.global_position = p
	cam.look_at(t, Vector3.UP)
	await _wait(8)
	await RenderingServer.frame_post_draw
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_mondrian_hall")
	root.get_texture().get_image().save_png(out.path_join(nm + ".png"))
	print("[goal-shot] ", nm)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	await _wait(90)
	for c in level.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false
	var cam := Camera3D.new()
	cam.near = 0.05
	cam.far = 400.0
	root.add_child(cam)
	cam.current = true
	await _shot(cam, Vector3(2.6, 10.9, 1.6), Vector3(2.6, 10.2, -4.6), "g1_steps", 62.0)
	await _shot(cam, Vector3(2.6, 10.5, -0.4), Vector3(2.6, 11.2, -4.9), "g2_steps_close", 55.0)
	quit(0)
