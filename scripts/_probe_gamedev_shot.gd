extends SceneTree
## 出图：商店东侧新地块 + 游戏开发部部室。
##   _tools/run_shot.sh res://scripts/_probe_gamedev_shot.gd -- --splat=off --story=off
const OUT := "res://_arisu_captures/_gamedev"


func _initialize() -> void:
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

	# 1) 从商店门口往东看：新地块 + 部室外观
	await _shot(cam, Vector3(26.0, 2.2, -6.5), Vector3(50.0, 3.2, 0.0), "01_from_shop.png", 60.0)
	# 2) 侧面俯视：地块接缝、部室位置
	await _shot(cam, Vector3(34.0, 22.0, 22.0), Vector3(50.0, 0.0, 0.0), "02_aerial.png", 50.0)
	# 3) 走到门口
	await _shot(cam, Vector3(43.4, 1.7, 3.5), Vector3(54.0, 2.2, 1.5), "03_door.png", 62.0)
	# 4) 室内
	await _shot(cam, Vector3(48.5, 2.0, 4.5), Vector3(55.0, 1.4, 0.0), "04_inside.png", 66.0)
	# 5) 字牌近景（看字体是否糊）
	await _shot(cam, Vector3(42.4, 3.5, 3.5), Vector3(45.15, 3.5, 3.5), "05_sign.png", 45.0)
	# 6) 掠射角（之前墙会映出天空，看着像通透）
	await _shot(cam, Vector3(42.3, 1.1, -6.2), Vector3(45.17, 6.0, 3.6), "06_graze.png", 62.0)
	# 7) 地上那台手持游戏机的屏幕（查重叠面）
	await _shot(cam, Vector3(52.7, 1.45, -0.9), Vector3(53.29, 0.38, -2.76), "07_handheld.png", 45.0)
	# 8) 屋顶两盏实体灯
	await _shot(cam, Vector3(52.0, 2.2, 4.6), Vector3(52.0, 5.85, 0.0), "08_lamps.png", 70.0)
	# 9) 手持游戏机本体（用户截图里屏幕左下角那台）
	await _shot(cam, Vector3(52.0, 1.25, -0.7), Vector3(52.75, 0.38, -2.0), "09_handheld2.png", 42.0)
	await _shot(cam, Vector3(52.6, 6.2, 1.2), Vector3(52.6, 0.0, -2.2), "10_cluster_top.png", 58.0)
	await _shot(cam, Vector3(52.65, 1.05, -1.35), Vector3(52.78, 0.36, -2.15), "11_handheld_close.png", 38.0)
	await _shot(cam, Vector3(51.93, 2.2, 2.8), Vector3(51.93, 0.2, 0.6), "12_rug_handheld.png", 42.0)
	await _shot(cam, Vector3(51.15, 0.95, 2.85), Vector3(51.25, 0.30, 1.65), "13_pink_handheld.png", 40.0)
	print("[gamedev-shot] fps=", Engine.get_frames_per_second())
	quit(0)
