extends SceneTree
## 时间系统**效果验证**：同一机位、同一个场景，只改太阳 / 天空 / 曝光，出三张图。
##
##   _tools/run_shot.sh res://scripts/_probe_time_of_day.gd
##
## 输出 `_log/tod_morning.png` / `tod_noon.png` / `tod_dusk.png`。
##
## ⚠️ 这个探针**不改游戏**，只是把结论摆出来给人看：
##    - 网格（家具 / 机箱 / 楼壳）会跟着太阳真变
##    - 泼溅不受光照，只能靠 `tonemap_exposure` 这种**整屏**后处理一起压暗/染色
##      这条路是引擎自带的（Environment.adjustment_*），不用写着色器
##
## 三档参数是手调的观感值，不是物理值。

const TIMES := [
	{
		"n": "morning", "out": "res://_log/tod_morning.png",
		"sun_rot": Vector3(-22.0, 75.0, 0.0),
		"sun_col": Color(1.0, 0.86, 0.70), "sun_energy": 1.05,
		"exposure": 1.05,
		"sky_top": Color(0.34, 0.44, 0.62), "sky_hor": Color(0.95, 0.75, 0.58),
		"gnd_bot": Color(0.18, 0.17, 0.19), "gnd_hor": Color(0.55, 0.48, 0.45),
		"amb": Color(0.55, 0.55, 0.65), "amb_e": 0.55,
	},
	{
		"n": "noon", "out": "res://_log/tod_noon.png",
		"sun_rot": Vector3(-58.0, 25.0, 0.0),
		"sun_col": Color(1.0, 0.97, 0.92), "sun_energy": 1.35,
		"exposure": 1.0,
		"sky_top": Color(0.22, 0.28, 0.42), "sky_hor": Color(0.52, 0.56, 0.64),
		"gnd_bot": Color(0.12, 0.13, 0.16), "gnd_hor": Color(0.34, 0.36, 0.42),
		"amb": Color(0.62, 0.66, 0.78), "amb_e": 0.75,
	},
	{
		"n": "dusk", "out": "res://_log/tod_dusk.png",
		"sun_rot": Vector3(-7.0, 112.0, 0.0),
		"sun_col": Color(1.0, 0.52, 0.32), "sun_energy": 0.85,
		"exposure": 0.82,
		"sky_top": Color(0.16, 0.14, 0.28), "sky_hor": Color(0.95, 0.44, 0.30),
		"gnd_bot": Color(0.08, 0.07, 0.10), "gnd_hor": Color(0.42, 0.28, 0.30),
		"amb": Color(0.42, 0.38, 0.50), "amb_e": 0.45,
	},
]


func _initialize() -> void:
	# 不抢用户前台（AGENTS.md 硬要求，2026-11-09）：取消最大化 + 禁止聚焦 + 挪出屏幕
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(14)

	var sun := game.get_node_or_null("Sun") as DirectionalLight3D
	var we := game.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if sun == null or we == null or we.environment == null:
		print("!! 找不到 Sun / WorldEnvironment")
		quit(1)
		return
	var env := we.environment
	var sky := env.sky
	var mat := sky.sky_material as ProceduralSkyMaterial if sky != null else null

	# 把玩家摆在能同时看到室内 + 窗外的一个位置
	var p := game.get_node_or_null("Player") as Player
	if p != null:
		p.global_position = Vector3(-4.0, 0.1, 6.0)
		await _wait(30)

	for c in TIMES:
		sun.rotation_degrees = c["sun_rot"]
		sun.light_color = c["sun_col"]
		sun.light_energy = c["sun_energy"]
		env.tonemap_exposure = c["exposure"]
		env.ambient_light_color = c["amb"]
		env.ambient_light_energy = c["amb_e"]
		if mat != null:
			mat.sky_top_color = c["sky_top"]
			mat.sky_horizon_color = c["sky_hor"]
			mat.ground_bottom_color = c["gnd_bot"]
			mat.ground_horizon_color = c["gnd_hor"]
			mat.sun_angle_max = 12.0
		await _wait(8)
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var abs_path := ProjectSettings.globalize_path(String(c["out"]))
		var err := img.save_png(abs_path)
		print("[tod] %-8s sun=%s energy=%.2f exposure=%.2f -> %s err=%d" % [
			c["n"], str(c["sun_rot"]), c["sun_energy"], c["exposure"],
			String(c["out"]), err])

	quit(0)


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
