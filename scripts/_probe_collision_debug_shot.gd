extends SceneTree
## 打开「可见碰撞形状」调试，把两个候选房间各拍一张，和用户那张图对认。
##   _tools/run_shot.sh res://scripts/_probe_collision_debug_shot.gd -- --splat=off --story=off


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await _wait(20)
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("[cdbg] → %s" % path)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(150)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	debug_collisions_hint = true
	print("[cdbg] debug_collisions_hint = %s" % str(debug_collisions_hint))

	var cam := Camera3D.new()
	cam.far = 400.0
	cam.near = 0.05
	cam.fov = 70.0
	root.add_child(cam)
	cam.current = true

	# ① 部室：站在门外西侧往里看（用户那张图能看见「游戏开发部」招牌 + 机箱）
	cam.global_position = Vector3(45.5, 1.8, 2.0)
	cam.look_at(Vector3(53.0, 1.5, 3.0), Vector3.UP)
	await _shot("res://_log/cdbg_gamedev.png")

	# ② 电竞房：(52, 0.01, 13)，门朝西
	cam.global_position = Vector3(44.0, 1.8, 13.0)
	cam.look_at(Vector3(52.0, 1.2, 13.0), Vector3.UP)
	await _shot("res://_log/cdbg_esports.png")

	# ③ 再退远一点看两个房间所在的地块
	cam.global_position = Vector3(30.0, 8.0, 6.0)
	cam.look_at(Vector3(55.0, 1.0, 8.0), Vector3.UP)
	await _shot("res://_log/cdbg_lot.png")
	quit(0)