extends SceneTree
## 出图：霸王龙跑起来的样子（两级：腿摆到前、腿摆到后）。
##
##   _tools/run_shot.sh res://scripts/_probe_trex_run_shot.gd -- --splat=off
##   → _arisu_captures/_trex_run/01_stride.png、02_stride.png

const OffWin := preload("res://scripts/offscreen_window.gd")
const GameSettingsScript := preload("res://scripts/game_settings.gd")

const LEVEL := "res://scenes/next_level.tscn"
const BOSS := "TrexBossA"
const OUT_DIR := "_arisu_captures/_trex_run"


func _initialize() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
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
		await OffWin.apply(self, Vector2i(1280, 720))
		if bool(OffWin.is_safe()[0]):
			return


func _run() -> void:
	await _pin()
	var old_mode := String(GameSettingsScript.value("window_mode", "maximized"))
	GameSettingsScript.set_value("window_mode", "windowed")
	GameSettingsScript.set_value("boss_attack", false)

	var level := (load(LEVEL) as PackedScene).instantiate()
	root.add_child(level)
	for _i in 30:
		await process_frame
	var boss := level.get_node_or_null(BOSS)
	if boss == null:
		print("[run-shot] 找不到 %s" % BOSS)
		quit(1)
		return
	if not bool(boss.get("_booted")):
		boss.call("_boot")
	for _i in 30:
		await process_frame

	var player := level.get_tree().get_first_node_in_group("player") as Node3D
	# 玩家站在侧面 26 m 处：这样镜头能斜看一条腿的摆动
	var side: Vector3 = (boss as Node3D).global_position + Vector3(-26, 0, 6)
	if player != null:
		player.global_position = side

	# 机位：从玩家这一侧斜前方看，把整只龙框进去
	var cam := Camera3D.new()
	level.add_child(cam)
	var center: Vector3 = (boss as Node3D).global_position + Vector3(0, 5.0, 0)
	cam.global_position = center + Vector3(-24.0, 9.0, 20.0)
	cam.look_at(center, Vector3.UP)
	cam.fov = 55.0
	cam.current = true

	# 让它先跑起来（12 m/s，跑 40 帧 ≈ 8 m）
	for _i in 40:
		await process_frame
	# 抓两个不同步相位的瞬间（步频 1.15 Hz，半个周期约 0.43 s ≈ 26 帧）
	await _shot("01_stride")
	for _i in 13:
		await process_frame
	await _shot("02_stride")

	print("[run-shot] 出图完成（离出生点 %.1f m）" % Vector2(
		(boss as Node3D).global_position.x - float((boss.get("_home") as Vector3).x),
		(boss as Node3D).global_position.z - float((boss.get("_home") as Vector3).z)).length())
	GameSettingsScript.set_value("window_mode", old_mode)
	GameSettingsScript.set_value("boss_attack", true)
	quit(0)
