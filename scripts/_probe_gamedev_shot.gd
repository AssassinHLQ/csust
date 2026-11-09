extends SceneTree
## 出图：商店东侧新地块 + 游戏开发部部室。
##   _tools/run_shot.sh res://scripts/_probe_gamedev_shot.gd -- --splat=off --story=off
const OUT := "res://_arisu_captures/_gamedev"


func _initialize() -> void:
	# 不抢用户前台（AGENTS.md 硬要求，2026-11-09）：取消最大化 + 禁止聚焦 + 挪出屏幕
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(cam: Camera3D, pos: Vector3, target: Vector3, name: String, fov := 55.0) -> void:
	cam.fov = fov
	cam.global_position = pos
	cam.look_at(target, Vector3.UP)
	await _wait(10)
	root.get_texture().get_image().save_png(OUT + "/" + name)
	print("[gamedev-shot] ", name)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))

	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(90)

	var cam := Camera3D.new()
	cam.far = 400.0
	cam.near = 0.05
	root.add_child(cam)
	cam.current = true

	# ⚠️ 2026-11-08：以下坐标原本**写死**成 x≈52（房间旧原点）。
	#    后来房间左移到 x=47.89，全部相机就偏了 4.11 m，拍出来的都是墙外。
	#    现在统一从房间实际原点算偏移量，房间再挪也不用改这里。
	var ox := 47.89
	if game.get_node_or_null("GameDevRoom") != null:
		ox = (game.get_node("GameDevRoom") as Node3D).global_position.x
	print("[gamedev-shot] 房间原点 x = %.2f" % ox)

	# 1) 从商店门口往东看：新地块 + 部室外观
	await _shot(cam, Vector3(ox - 26.0, 2.2, -6.5), Vector3(ox - 2.0, 3.2, 0.0), "01_from_shop.png", 60.0)
	# 2) 侧面俯视：地块接缝、部室位置
	await _shot(cam, Vector3(ox - 18.0, 22.0, 22.0), Vector3(ox - 2.0, 0.0, 0.0), "02_aerial.png", 50.0)
	# 3) 走到门口
	await _shot(cam, Vector3(ox - 8.6, 1.7, 3.5), Vector3(ox + 2.0, 2.2, 1.5), "03_door.png", 62.0)
	# 4) 室内
	await _shot(cam, Vector3(ox - 3.5, 2.0, 4.5), Vector3(ox + 3.0, 1.4, 0.0), "04_inside.png", 66.0)
	# 5) 字牌近景（看字体是否糊）
	await _shot(cam, Vector3(ox - 9.6, 3.5, 3.5), Vector3(ox - 6.85, 3.5, 3.5), "05_sign.png", 45.0)
	# 6) 掠射角（之前墙会映出天空，看着像通透）
	await _shot(cam, Vector3(ox - 9.7, 1.1, -6.2), Vector3(ox - 6.83, 6.0, 3.6), "06_graze.png", 62.0)
	# 7) 地上那台手持游戏机的屏幕（查重叠面）
	await _shot(cam, Vector3(ox + 0.7, 1.45, -0.9), Vector3(ox + 1.29, 0.38, -2.76), "07_handheld.png", 45.0)
	# 8) 屋顶两盏实体灯
	await _shot(cam, Vector3(ox, 2.2, 4.6), Vector3(ox, 5.85, 0.0), "08_lamps.png", 70.0)
	# 9) 手持游戏机本体（用户截图里屏幕左下角那台）
	await _shot(cam, Vector3(ox, 1.25, -0.7), Vector3(ox + 0.75, 0.38, -2.0), "09_handheld2.png", 42.0)
	await _shot(cam, Vector3(ox + 0.6, 6.2, 1.2), Vector3(ox + 0.6, 0.0, -2.2), "10_cluster_top.png", 58.0)
	await _shot(cam, Vector3(ox + 0.65, 1.05, -1.35), Vector3(ox + 0.78, 0.36, -2.15), "11_handheld_close.png", 38.0)
	await _shot(cam, Vector3(ox - 0.07, 2.2, 2.8), Vector3(ox - 0.07, 0.2, 0.6), "12_rug_handheld.png", 42.0)
	await _shot(cam, Vector3(ox - 0.85, 0.95, 2.85), Vector3(ox - 0.75, 0.30, 1.65), "13_pink_handheld.png", 40.0)
	print("[gamedev-shot] fps=", Engine.get_frames_per_second())
	quit(0)
