extends SceneTree
## 真窗口探针：验 F7 自由摄像头 + F8 4K 截图（屏幕外窗口，不抢前台）。
##
##   bash _tools/run_shot.sh res://scripts/_probe_freecam_shot.gd
##   → _arisu_captures/_shots/4k_*.png（+ 同机位参数 txt）
##
## 默认**带泼溅**跑（这样 4K 图才有参考价值）；想快就加 `-- --splat=off`。
##
## ⚠️ 窗口全程在屏幕外；拍照时窗口会临时变大到 4K（仍在屏幕外），
##    拍完立刻恢复 —— 用户看不到、也不会抢焦点。

const OffWin := preload("res://scripts/offscreen_window.gd")
const GameSettingsScript := preload("res://scripts/game_settings.gd")
const DevMode := preload("res://scripts/dev_mode.gd")

const SHOTS_REL := "_arisu_captures/_shots"

var _game: Node
var _fc: Camera3D


func _initialize() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _run() -> void:
	await _pin_window()
	var old_mode := String(GameSettingsScript.value("window_mode", "maximized"))
	GameSettingsScript.set_value("window_mode", "windowed")

	_game = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(_game)
	current_scene = _game
	for _i in 25:
		await process_frame
	await _pin_window()

	# 等泼溅就绪（带 --splat=off 时这一步立即通过）
	var room := _game.get_node_or_null("Room609")
	var t0 := Time.get_ticks_msec()
	while room != null and not bool(room.call("is_ready")) \
			and float(Time.get_ticks_msec() - t0) / 1000.0 < 40.0:
		await process_frame
	print("[freecam-shot] 画室就绪=%s（等了 %.1f s）" % [
		"-" if room == null else str(room.call("is_ready")),
		float(Time.get_ticks_msec() - t0) / 1000.0])
	# 让泼溅合成多跑几帧
	for _i in 30:
		await process_frame

	# ── F7 进自由摄像头（走真键盘事件）──
	DevMode.set_on(true)
	_game.call("_input", _key(KEY_F7))
	await _wait_sec(0.2)
	_fc = _game.call("free_camera")
	if _fc == null or not bool(_fc.call("is_active")):
		print("[freecam-shot] ✗ 自由摄像头没打开")
		GameSettingsScript.set_value("window_mode", old_mode)
		quit(1)
		return
	print("[freecam-shot] 自由摄像头已开，机位 %s" % str(_fc.global_position.snappedf(0.01)))
	await _pin_window()

	# 先存一张窗口分辨率的干净图（HUD 已被自由摄像头藏掉）
	await _shot_viewport(ProjectSettings.globalize_path("res://").path_join(SHOTS_REL)
		.path_join("freecam_1600x900.png"))

	# ── F8 4K 截图 ──
	var before_size := DisplayServer.window_get_size()
	var before_mode := DisplayServer.window_get_mode()
	_fc.call("capture_4k")
	var t1 := Time.get_ticks_msec()
	while bool(_fc.call("is_capturing")) \
			and float(Time.get_ticks_msec() - t1) / 1000.0 < 30.0:
		await process_frame
	var cap_sec := float(Time.get_ticks_msec() - t1) / 1000.0
	print("[freecam-shot] 4K 截图耗时 %.1f s；窗口 %s → %s" % [
		cap_sec, str(before_size), str(DisplayServer.window_get_size())])
	print("[freecam-shot] 窗口模式恢复：%s（应为 %s）" % [
		str(DisplayServer.window_get_mode()), str(before_mode)])

	# 找刚保存的 4K 图
	var dir := ProjectSettings.globalize_path("res://").path_join(SHOTS_REL)
	var newest := ""
	var newest_ms := 0
	var da := DirAccess.open(dir)
	if da != null:
		for f in da.get_files():
			if not f.begins_with("4k_") or not f.ends_with(".png"):
				continue
			var full := dir.path_join(f)
			var ms := int(FileAccess.get_modified_time(full))
			if ms >= newest_ms:
				newest_ms = ms
				newest = full
	if newest.is_empty():
		print("[freecam-shot] ✗ 没找到 4K 截图")
	else:
		var img := Image.new()
		if img.load(newest) == OK:
			print("[freecam-shot] 4K 图 %s：%d×%d" % [
				newest, img.get_width(), img.get_height()])
			var ok := img.get_width() >= 3800
			print("[freecam-shot] %s" % ("✓ 真 4K" if ok else "✗ 分辨率不对"))
			print("[freecam-shot] 机位参数：%s" % newest.get_basename() + "_meta.txt")
		else:
			print("[freecam-shot] ✗ 4K 图读不出来：%s" % newest)

	# HUD 应该恢复
	var hud := _game.get_node_or_null("HUD")
	print("[freecam-shot] HUD 恢复=%s" % (str(hud.get("visible")) if hud != null else "-"))
	# 退出自由摄像头
	_fc.call("_input", _key(KEY_F7))
	await _wait_sec(0.15)
	print("[freecam-shot] 自由摄像头已关：%s" % str(not bool(_fc.call("is_active"))))

	var safe: Array = OffWin.is_safe()
	print("[freecam-shot] 窗口安全：%s" % str(safe))
	GameSettingsScript.set_value("window_mode", old_mode)
	DevMode.set_on(false)
	quit(0)


func _shot_viewport(path: String) -> void:
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := img.save_png(path)
	print("[freecam-shot] 窗口图 %s（%d×%d，错误 %d）" % [
		path, img.get_width(), img.get_height(), err])


func _pin_window() -> void:
	for attempt in 3:
		await OffWin.apply(self, Vector2i(1600, 900))
		var safe: Array = OffWin.is_safe()
		if bool(safe[0]):
			return


func _key(k: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = k
	ev.physical_keycode = k
	ev.pressed = true
	return ev


func _wait_sec(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < sec:
		await process_frame
