extends SceneTree
## 出图：第二关两段斜坡井，从井口上/下看，检查外壳楼板有没有把井盖住。
##   _tools/run_shot.sh res://scripts/_probe_hall_well_shot.gd
func _initialize() -> void:
	# 不抢用户前台（AGENTS.md 硬要求，2026-11-09）：取消最大化 + 禁止聚焦 + 挪出屏幕
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(cam: Camera3D, p: Vector3, target: Vector3, nm: String) -> void:
	cam.global_position = p
	cam.look_at(target, Vector3.UP)
	cam.make_current()
	await _wait(4)
	await RenderingServer.frame_post_draw
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_mondrian_hall")
	DirAccess.make_dir_recursive_absolute(out)
	root.get_texture().get_image().save_png(out.path_join(nm + ".png"))
	print("[well] ", nm, " ", p, " -> ", target)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(level)
	await _wait(120)
	for c in level.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false
	var cam := Camera3D.new()
	cam.fov = 75.0
	cam.near = 0.05
	cam.far = 600.0
	root.add_child(cam)
	await _shot(cam, Vector3(-6.25, 1.50, 4.30), Vector3(-6.25, 4.60, -2.0), "w1_l1_up")
	await _shot(cam, Vector3(-6.25, 5.60, -1.20), Vector3(-6.25, 1.20, 3.2), "w2_l2_down")
	await _shot(cam, Vector3(4.25, 5.60, 4.20), Vector3(4.25, 8.60, -2.0), "w3_l2_up")
	await _shot(cam, Vector3(4.25, 9.90, -2.20), Vector3(4.25, 5.20, 2.6), "w4_l3_down")
	quit(0)
