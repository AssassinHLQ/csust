extends SceneTree
## 拍：成交后（东侧三块现身）从玩家视角看东西两侧，对比「游戏开发部」和「蒙德里安小屋」。
##
## 出图：`_arisu_captures/_east_look/`
##   01_at_gamedev   站在开发部门口往里看
##   02_above_east   高处俯视东侧
##   03_mondrian     看蒙德里安小屋

const ShopClerkScript := preload("res://scripts/shop_clerk.gd")
const OUT := "res://_arisu_captures/_east_look"


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(cam: Camera3D, p: Vector3, t: Vector3, nm: String) -> void:
	cam.global_position = p
	if p.distance_to(t) > 0.01:
		cam.look_at(t, Vector3.UP)
	await _wait(6)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var img: Image = root.get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT, nm])
	print("[look] shot %s  from=%s to=%s" % [nm, str(p), str(t)])


func _run() -> void:
	await _wait(3)
	ShopClerkScript._bought = true
	var game: Node = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	for _i in 40:
		await process_frame

	var cam := Camera3D.new()
	cam.fov = 75.0
	cam.far = 800.0
	root.add_child(cam)
	current_scene = null

	# 开发部在 (52, 0.01, 0)，蒙德里安在 (27.3, 0, 13.5)
	await _shot(cam, Vector3(52, 2.0, -12.0), Vector3(52, 2.0, 0), "01_gamedev_front")
	await _shot(cam, Vector3(52, 2.0, 0), Vector3(52, 2.0, -10), "02_gamedev_inside")
	await _shot(cam, Vector3(52, 42.0, -18.0), Vector3(52, 0.0, 4.0), "03_east_above")
	await _shot(cam, Vector3(27.3, 2.0, -2.0), Vector3(27.3, 2.0, 13.5), "04_mondrian")

	print("[look] DONE")
	quit(0)
