extends SceneTree
## 对比三种天空在「同一时刻」的样子，看哪种适合做全天动态。
##
##   _tools/run_shot.sh res://scripts/_probe_sky_ab.gd
##
## 三种（运行时换 `Environment.sky` 的材质，**不改场景**）：
##   A PhysicalSkyMaterial  —— Godot 4.3+ 自带，真实大气散射（Rayleigh/Mie），跟方向光自动联动
##   B ProceduralSkyMaterial —— 工程现在 game.tscn 用的那种，四色渐变
##   C PanoramaSkyMaterial  —— 照片全景（现在看到的粉云就是这个），**天生固定时刻**
##
## 每种在 08:00 / 12:00 / 18:00 各出一张，输出到 _log/sky_<字母>_<小时>.png

const OUT := "res://_log/sky_%s_%02d.png"
const HOURS := [8.0, 12.0, 18.0]
const EYE := Vector3(-0.5, 5.0, 20.0)
const LOOK := Vector3(-0.5, 9.0, 48.0)


func _initialize() -> void:
	# 不抢用户前台（AGENTS.md 硬要求，2026-11-09）：取消最大化 + 禁止聚焦 + 挪出屏幕
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1100, 620)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(20)

	var tod := root.get_node_or_null("TimeOfDay")
	if tod != null:
		tod.set_process(false)

	var we := game.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we == null or we.environment == null:
		print("!! 没有 WorldEnvironment")
		quit(1)
		return
	var env := we.environment

	var cam := Camera3D.new()
	cam.fov = 70.0
	root.add_child(cam)
	cam.global_position = EYE
	cam.look_at(LOOK, Vector3.UP)
	cam.current = true

	for pair in [["A", _physical()], ["B", _procedural()], ["C", _panorama()]]:
		var tag: String = pair[0]
		var mat: Material = pair[1]
		if mat == null:
			print("[skyab] %s 造不出来，跳过" % tag)
			continue
		var sky := Sky.new()
		sky.sky_material = mat
		env.sky = sky
		for h in HOURS:
			if tod != null:
				tod.set_hours(float(h))
			await _wait(12)
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			var path := OUT % [tag, int(h)]
			var err := img.save_png(ProjectSettings.globalize_path(path))
			print("[skyab] %s %02d:00 (%s) -> %s err=%d" % [
				tag, int(h), mat.get_class(), path, err])

	quit(0)


## A 真实大气
func _physical() -> Material:
	if not ClassDB.class_exists("PhysicalSkyMaterial"):
		return null
	var m := PhysicalSkyMaterial.new()
	m.rayleigh_coefficient = 2.0
	m.mie_coefficient = 0.005
	m.turbidity = 3.0
	m.ground_color = Color(0.16, 0.17, 0.20)
	return m


## B 工程现在那种四色渐变
func _procedural() -> Material:
	var m := ProceduralSkyMaterial.new()
	m.sky_top_color = Color(0.22, 0.28, 0.42)
	m.sky_horizon_color = Color(0.52, 0.56, 0.64)
	m.ground_bottom_color = Color(0.12, 0.13, 0.16)
	m.ground_horizon_color = Color(0.34, 0.36, 0.42)
	m.sun_angle_max = 12.0
	return m


## C 照片全景（拿现成的那张粉云）
func _panorama() -> Material:
	var tex := load("res://assets/sky/sky_pink.jpg") as Texture2D
	if tex == null:
		return null
	var m := PanoramaSkyMaterial.new()
	m.panorama = tex
	m.filter = true
	return m


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
