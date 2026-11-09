extends SceneTree
## 出图：小屋新招牌「临时服务器据点」、柴关电脑城发光招牌。
##   _tools/run_shot.sh res://scripts/_probe_fix_batch_shot.gd -- --splat=off --story=off
const OUT := "res://_arisu_captures/_fixes"


func _initialize() -> void:
	# 不抢用户前台（AGENTS.md 硬要求，2026-11-09）：取消最大化 + 禁止聚焦 + 挪出屏幕
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(cam: Camera3D, pos: Vector3, target: Vector3, name: String, fov: float) -> void:
	cam.fov = fov
	cam.global_position = pos
	cam.look_at(target, Vector3.UP)
	await _wait(10)
	root.get_texture().get_image().save_png(OUT + "/" + name)
	print("[fix-shot] ", name)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(120)
	for c in game.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false
	var cam := Camera3D.new()
	cam.far = 300.0
	cam.near = 0.05
	root.add_child(cam)
	cam.current = true
	# 小屋西门（世界 x=10.7，门朝西）
	await _shot(cam, Vector3(8.6, 2.7, -15.5), Vector3(10.68, 2.85, -15.5), "01_hut_sign.png", 45.0)
	# 柴关电脑城招牌（门上方、朝南）
	await _shot(cam, Vector3(27.3, 3.6, -7.5), Vector3(27.3, 5.55, -12.6), "02_shop_sign.png", 55.0)
	quit(0)
