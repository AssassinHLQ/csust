extends SceneTree
## 出图：机甲能量条 HUD 换成 BA 皮肤之后的样子（2026-11-11）。
##
##   _tools/run_shot.sh res://scripts/_probe_carrier_hud_shot.gd
##   → _arisu_captures/_carrier_hud/01_empty.png（0 条，空槽）
##      _arisu_captures/_carrier_hud/02_mid.png  （3 条 + 进度）
##      _arisu_captures/_carrier_hud/03_active.png（有生效条 + 巡航文案）
##
## ⚠️ 要出图必须：解锁机甲（否则 `set_form` 被静默拒掉）+ 把窗口模式改 windowed
##    （否则 `RenderEnv` 把窗口拉回 (0,34) 最大化，见 §14.1.4）。

const OffWin := preload("res://scripts/offscreen_window.gd")
const GameSettingsScript := preload("res://scripts/game_settings.gd")

const OUT_DIR := "_arisu_captures/_carrier_hud"


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

	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 40:
		await process_frame
	await _pin()

	var MechStateScript := load("res://scripts/mech_state.gd") as GDScript
	MechStateScript.call("set_carrier_for_test", true)
	var cf := game.get_node_or_null("Player/Arisu/CarrierForm")
	if cf == null:
		print("[hud-shot] 没有 CarrierForm")
		quit(1)
		return
	var ok := bool(cf.call("set_form", true))
	print("[hud-shot] 变形 = %s" % str(ok))
	for _i in 30:
		await process_frame

	# ① 空槽（0 条、进度 0%）
	cf.set("energy_bars", 0)
	cf.set("fly_distance_m", 0.0)
	cf.set("_bar_timers", [])
	for _i in 6:
		await process_frame
	await _shot("01_empty")

	# ② 攒了 3 条、进度 62%
	cf.set("energy_bars", 3)
	cf.set("fly_distance_m", 185.0)
	for _i in 6:
		await process_frame
	await _shot("02_mid")

	# ③ 有 2 条生效中（攻速 ×3）+ 巡航文案
	cf.set("energy_bars", 2)
	cf.call("use_energy_bar")
	cf.call("use_energy_bar")
	for _i in 6:
		await process_frame
	await _shot("03_active")

	print("[hud-shot] 攻速 = ×%.1f，生效 %d 条" % [
		float(cf.get("rate_scale")), (cf.get("_bar_timers") as Array).size()])

	GameSettingsScript.set_value("window_mode", old_mode)
	print("[hud-shot] 出图完成")
	quit(0)
