extends SceneTree
## 出图：CG 插槽在**真窗口**下到底能不能显示出画面（2026-11-11）。
##
## 为什么必须真窗口：`VideoStreamPlayer` 在 `--headless` 下**不会真的推进画面**
## （没有渲染/音频后端），所以 headless 只能验"能不能 load、能不能收尾"，
## 验不了"屏幕上有没有东西"。这个探针补的就是那一步。
##
##   _tools/run_shot.sh res://scripts/_probe_cg_shot.gd
##   → _arisu_captures/_cg/00_black.png（刚起，全黑）
##      _arisu_captures/_cg/01_cg.png   （视频在播）
##      _arisu_captures/_cg/02_after.png（播完、黑幕淡出、世界出现）
##
## ⚠️ 载入前必须把 `window_mode` 改成 `"windowed"`，否则 `RenderEnv` 会把窗口
##    从屏幕外拉回 (0,34) 最大化（§14.1.4 那次翻车）。

const OffWin := preload("res://scripts/offscreen_window.gd")
const GameSettingsScript := preload("res://scripts/game_settings.gd")
const TitleIntroScript := preload("res://scripts/title_intro.gd")

const OUT_DIR := "_arisu_captures/_cg"


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
	print("[cg] window_mode %s → windowed（只为出图，跑完写回）" % old_mode)

	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 40:
		await process_frame
	await _pin()

	var intro := TitleIntroScript.new() as Node
	intro.name = "TitleIntro"
	game.add_child(intro)
	print("[cg] 这一遍会播的正片 = %s" % String(intro.call("kind")))
	intro.call("play", func() -> bool: return true)

	# 0.15 s：黑幕刚起（CG 还没淡出来）
	await create_timer(0.15).timeout
	await _shot("00_black")
	# 1.0 s：CG 应该在播了
	await create_timer(0.85).timeout
	await _shot("01_cg")
	# 再等 4 s：2 s 的视频 + 淡出，应该已经回到世界
	await create_timer(4.0).timeout
	await _shot("02_after")

	GameSettingsScript.set_value("window_mode", old_mode)
	print("[cg] 出图完成，window_mode 写回 %s" % old_mode)
	quit(0)
