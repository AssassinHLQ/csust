extends SceneTree
## 出图：开场 PV 的几个关键帧（真窗口、屏幕外、不抢前台）。
##
##   bash _tools/run_shot.sh res://scripts/_probe_title_shot.gd -- --splat=off
##   → _arisu_captures/_title_pv/00_first.png … 05_transition.png
##
## ── 为什么要 `--splat=off` ──
## 这个探针只拍 PV 本身（PV 会把 3D 世界完全盖住），关掉泼溅省掉解码与 1.28 GB 显存。
##
## ── ⚠️ 两条必须照做的规矩 ──
##   ① 不抢用户前台：`project.godot` 的 `window/size/mode=2`（最大化）会被
##      `RenderEnv` 在载入关卡时重新应用，把窗口拉回屏幕内。所以**载入前**先把
##      `GameSettings` 的 `window_mode` 改成 `"windowed"`，跑完写回。
##   ② PV 的动画靠真实时间推进，不能数帧 —— 这里按时间点取样。

const OffWin := preload("res://scripts/offscreen_window.gd")
const GameSettingsScript := preload("res://scripts/game_settings.gd")
const TitleIntroScript := preload("res://scripts/title_intro.gd")

const OUT_DIR := "_arisu_captures/_title_pv"
## 取样时刻（秒，从 PV 开始算起）→ 文件名
const SAMPLES := [
	[0.90, "00_first"],
	[2.90, "01_pan_later"],
	[3.40, "02_progress"],
	[4.70, "03_start_button"],
	[6.10, "04_after_click"],
	[6.90, "05_transition"],
]
## 世界「就绪」的时刻（秒）：之前进度条在涨、按钮藏着；到点后弹出按钮
const READY_AT := 4.0

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
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	# 调试读数：界面淡入/淡出时亮度会变，出图时顺手记一笔
	var root_ctrl := _intro.get_node_or_null("TitleIntro/Root") as Control
	var btn := _intro.get_node_or_null("TitleIntro/Root/Ui/StartButton") as Button
	if root_ctrl != null and btn != null:
		print("[title-pv] %s：root.a=%.2f btn.a=%.2f btn.disabled=%s" % [
			name, root_ctrl.modulate.a, btn.modulate.a, str(btn.disabled)])
	var img := root.get_texture().get_image()
	var path := _out(name)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("[截图] %s（窗口 %s）" % [path, str(DisplayServer.window_get_position())])


func _pin_window() -> void:
	for attempt in 3:
		await OffWin.apply(self, Vector2i(1600, 900))
		var safe: Array = OffWin.is_safe()
		print("[title-pv] 第 %d 次挪窗口：位置 %s  mouse_mode=%d  安全=%s" % [
			attempt + 1, str(DisplayServer.window_get_position()),
			Input.mouse_mode, str(safe)])
		if bool(safe[0]):
			return


func _run() -> void:
	await _pin_window()
	var old_mode := String(GameSettingsScript.value("window_mode", "maximized"))
	GameSettingsScript.set_value("window_mode", "windowed")
	print("[title-pv] window_mode %s → windowed（只为出图，跑完写回）" % old_mode)

	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 30:
		await process_frame
	await _pin_window()

	_intro = TitleIntroScript.new() as Node
	_intro.name = "TitleIntro"
	game.add_child(_intro)
	_t0 = float(Time.get_ticks_msec()) / 1000.0
	# 假 poll：进度在前 4 s 内爬升，4 s 后宣布就绪（真实加载太快/太慢都不好取景）
	var poll := Callable(self, "_poll")
	_intro.call("play", poll)

	var click_at := 5.6
	var clicked := false
	for sample in SAMPLES:
		var t: float = float(sample[0])
		await _wait_until(t)
		if not clicked and _elapsed() >= click_at:
			clicked = true
			print("[title-pv] 点「开始游戏」（%.2f s）" % _elapsed())
			_intro.call("press_start")
		await _shot(String(sample[1]))

	GameSettingsScript.set_value("window_mode", old_mode)
	print("[title-pv] 出图完成，window_mode 写回 %s" % old_mode)
	quit(0)


func _poll() -> Dictionary:
	var el := _elapsed()
	return {
		"ratio": clampf(el / READY_AT, 0.0, 0.95),
		"ready": el >= READY_AT,
		"names": [] if el >= READY_AT else ["画室609"],
	}


func _elapsed() -> float:
	return float(Time.get_ticks_msec()) / 1000.0 - _t0


func _wait_until(t: float) -> void:
	while _elapsed() < t:
		await process_frame
