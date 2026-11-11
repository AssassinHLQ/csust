extends SceneTree
## 出图：从高处俯拍整个「场地」，看边界加宽之后各建筑还剩多少空地（2026-11-11）。
##
## 用户（附两张俯视图）：
##   「边界扩大蒙德里安都快挨到边上了,场地长方形加宽」
##   → 定的是 **Z 方向 40 → 52**（每边 +6 m）。
##
##   _tools/run_shot.sh res://scripts/_probe_lot_shot.gd
##   → _arisu_captures/_lot/01_overview.png（俯视全景）
##      _arisu_captures/_lot/02_mondrian.png（蒙德里安 + 南边界特写）
##
## ⚠️ 载入前必须把 `window_mode` 改成 `"windowed"`，否则 `RenderEnv`
##    会把窗口从屏幕外拉回 (0,34) 最大化（§14.1.4 那次翻车）。

const OffWin := preload("res://scripts/offscreen_window.gd")
const GameSettingsScript := preload("res://scripts/game_settings.gd")

const OUT_DIR := "_arisu_captures/_lot"


func _initialize() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 1000))
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _out(name: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join(OUT_DIR).path_join(name + ".png")


func _shot(name: String) -> void:
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := _out(name)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("[截图] %s" % path)


func _pin() -> void:
	for _i in 3:
		await OffWin.apply(self, Vector2i(1600, 1000))
		if bool(OffWin.is_safe()[0]):
			return


## 造一台自由相机（不用玩家的弹簧臂，免得被弹簧臂拉回角色身边）
func _cam(pos: Vector3, look_at: Vector3, fov: float) -> Camera3D:
	var c := Camera3D.new()
	c.fov = fov
	c.far = 600.0
	root.add_child(c)
	c.global_position = pos
	c.look_at(look_at, Vector3.UP)
	c.current = true
	return c


func _run() -> void:
	await _pin()
	var old_mode := String(GameSettingsScript.value("window_mode", "maximized"))
	GameSettingsScript.set_value("window_mode", "windowed")

	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 40:
		await process_frame
	await _pin()

	# ⚠️ 场地中心：x −20~64、z −26~26 的几何中心 ≈ (22, 0, 0)。
	#    下面三台相机的机位都是照着这个范围和 FOV 反推的，改尺寸要一起改。

	print("\n── ① 俯视全景（正上方，看清整块边界）──")
	# 场地范围 x −20~64（84 宽）、z −26~26（52 深）。要一屏装下 84×52，
	# 相机高度按 FOV 反推：竖直方向要容纳 52 m ⇒ 高 ≈ 52/2/tan(fov/2)。
	# 直接给 60° + 70 m 高，再把宽屏当成横向用（16:10 屏横向更宽）。
	var c1 := _cam(Vector3(22.0, 78.0, 0.5), Vector3(22.0, 0.0, 0.5), 60.0)
	for _i in 6:
		await process_frame
	await _shot("01_overview")

	print("\n── ② 蒙德里安 + 南边界（原来的问题点）──")
	var c2 := _cam(Vector3(6.0, 26.0, 44.0), Vector3(27.0, 3.0, 14.0), 60.0)
	for _i in 6:
		await process_frame
	await _shot("02_mondrian")

	print("\n── ③ 站在南边缘往里看（确认地是连的、不是悬空）──")
	# ⚠️ 第一版机位在 (22, 6, 24) 朝北看 —— 那个点**在蒙德里安的房子里面**
	#    （它在 x 18.6~36、z 6.8~20.8），拍出来是一面白墙。
	#    改到平台东南角外、抬高一点，沿南边界斜着往里看，才能同时看到
	#    「地砖边缘 + 蒙德里安 + 电竞房」三样。
	var c3 := _cam(Vector3(66.0, 18.0, 40.0), Vector3(40.0, 2.0, 12.0), 70.0)
	for _i in 6:
		await process_frame
	await _shot("03_edge")

	if is_instance_valid(c1):
		c1.queue_free()
	if is_instance_valid(c2):
		c2.queue_free()
	if is_instance_valid(c3):
		c3.queue_free()

	GameSettingsScript.set_value("window_mode", old_mode)
	print("[lot] 出图完成")
	quit(0)
