extends SceneTree
## 出图：开场标题卡的几个关键帧。
##
##   _tools/run_shot.sh res://scripts/_probe_title_shot.gd
##   → _arisu_captures/_title/00_start.png … 05_after.png
##
## ── ⚠️ 两条必须照做的规矩 ──
##   ① 不抢用户前台：`project.godot` 的 `window/size/mode=2`（最大化）会被
##      `RenderEnv.apply_window_mode()` 在载入关卡时重新应用，把窗口从屏幕外**拉回**
##      (0,34) 并最大化（2026-11-11 实测翻车一次）。所以**载入前**先把
##      `GameSettings` 的 `window_mode` 改成 `"windowed"`，跑完写回。
##   ② 标题卡的动画靠 Tween 真实时间推进，不能靠 `await` 固定帧数拍 ——
##      这里按**时间点**取样（0.18 / 0.55 / 1.1 / 2.2 / 3.0 s）。

const OffWin := preload("res://scripts/offscreen_window.gd")
const GameSettingsScript := preload("res://scripts/game_settings.gd")
const TitleIntroScript := preload("res://scripts/title_intro.gd")

const OUT_DIR := "_arisu_captures/_title"
## 取样时刻（秒，从标题卡开始播算起）→ 文件名
const SAMPLES := [
	[0.18, "00_start"],
	[0.55, "01_tag_in"],
	[1.05, "02_rule"],
	[2.10, "03_hold"],
	[2.95, "04_fading"],
	[4.20, "05_after"],
]

var _intro: Node
var _t0 := 0.0


func _initialize() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _out(name: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join(OUT_DIR).path_join(name + ".png")


func _shot(name: String) -> void:
	await process_frame
	# 真窗口才有 `frame_post_draw`；这个探针本来就只能走 run_shot.sh，
	# 但留个守卫免得有人在 headless 下试然后以为卡死了。
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := _out(name)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("[截图] %s（窗口 %s）" % [path, str(DisplayServer.window_get_position())])


func _pin_window() -> void:
	for attempt in 3:
		await OffWin.apply(self, Vector2i(1600, 900))
		var safe: Array = OffWin.is_safe()
		print("[title] 第 %d 次挪窗口：位置 %s  mouse_mode=%d  安全=%s" % [
			attempt + 1, str(DisplayServer.window_get_position()),
			Input.mouse_mode, str(safe)])
		if bool(safe[0]):
			return


func _run() -> void:
	await _pin_window()
	# ⚠️ 必须**在载入关卡之前**把窗口模式改掉，否则 RenderEnv 会把它拉回最大化
	var old_mode := String(GameSettingsScript.value("window_mode", "maximized"))
	GameSettingsScript.set_value("window_mode", "windowed")
	print("[title] window_mode %s → windowed（只为出图，跑完写回）" % old_mode)

	# 只为出图：光线/后处理全关会让标题卡对比更清楚？不 —— 保持原样，看的就是真实观感。
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	# ⚠️ 必须让它**不自己播**开场（否则会多出一张标题卡抢镜头）：
	#    game.gd 认 `--script`（我们是 --script 跑的，所以它本来就不会自动播）。
	root.add_child(game)
	for _i in 30:
		await process_frame
	await _pin_window()

	_intro = TitleIntroScript.new() as Node
	_intro.name = "TitleIntro"
	game.add_child(_intro)
	# 世界就算没就绪也不等（出图只要标题卡本身）—— 给一个永远 true 的 Callable
	_t0 = float(Time.get_ticks_msec()) / 1000.0
	_intro.call("play", Callable(self, "_always_ready"))

	var shot_i := 0
	while shot_i < SAMPLES.size():
		var t: float = float(SAMPLES[shot_i][0])
		while float(Time.get_ticks_msec()) / 1000.0 - _t0 < t:
			await process_frame
		await _shot(String(SAMPLES[shot_i][1]))
		shot_i += 1

	GameSettingsScript.set_value("window_mode", old_mode)
	print("[title] 出图完成，window_mode 写回 %s" % old_mode)
	quit(0)


func _always_ready() -> bool:
	return true
