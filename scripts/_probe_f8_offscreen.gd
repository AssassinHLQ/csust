extends SceneTree
## 真窗口探针：F8 新版「离屏 4K 截图」—— 验窗口完全不动、连拍两次都成功、
## 泼溅在画面里（与 `_probe_subviewport_4k.gd` 的结论对齐）。
##
##   bash _tools/run_shot_direct.sh res://scripts/_probe_f8_offscreen.gd
##   （可加 -- --splat=off 跑快版）

const OffWin := preload("res://scripts/offscreen_window.gd")
const GameSettingsScript := preload("res://scripts/game_settings.gd")
const DevMode := preload("res://scripts/dev_mode.gd")

const SHOTS_REL := "_arisu_captures/_shots"

var _game: Node


func _initialize() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	var wd := create_timer(150.0, true)
	wd.timeout.connect(func() -> void:
		print("[f8] !! 看门狗超时")
		quit(2))
	_run.call_deferred()


func _run() -> void:
	await OffWin.apply(self, Vector2i(1600, 900))
	var old_mode := String(GameSettingsScript.value("window_mode", "maximized"))
	GameSettingsScript.set_value("window_mode", "windowed")

	_game = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(_game)
	current_scene = _game
	for _i in 25:
		await process_frame
	var room := _game.get_node_or_null("Room609")
	var t0 := Time.get_ticks_msec()
	while room != null and not bool(room.call("is_ready")) \
			and float(Time.get_ticks_msec() - t0) / 1000.0 < 45.0:
		await process_frame
	for _i in 20:
		await process_frame
	print("[f8] 画室就绪=%s，窗口 %s" % [
		"-" if room == null else str(room.call("is_ready")),
		str(DisplayServer.window_get_size())])

	DevMode.set_on(true)
	_game.call("_input", _key(KEY_F7))
	await _wait(0.2)
	var fc: Camera3D = _game.call("free_camera")
	if fc == null or not bool(fc.call("is_active")):
		print("[f8] ✗ 自由摄像头没开")
		quit(1)
		return
	# 挪到能看到画室的角度（往左前方走一点、稍微低头）
	fc.global_position = Vector3(0.0, 1.6, 3.0)
	fc.rotation_degrees = Vector3(-6.0, 0.0, 0.0)
	await _wait(0.2)

	var win_before := DisplayServer.window_get_size()
	var mode_before := DisplayServer.window_get_mode()
	print("[f8] 截图前窗口 %s / 模式 %d" % [str(win_before), mode_before])

	for round_i in 2:
		fc.call("capture_4k")
		var t1 := Time.get_ticks_msec()
		while bool(fc.call("is_capturing")) \
				and float(Time.get_ticks_msec() - t1) / 1000.0 < 30.0:
			await process_frame
		var took := float(Time.get_ticks_msec() - t1) / 1000.0
		var after := DisplayServer.window_get_size()
		var after_mode := DisplayServer.window_get_mode()
		print("[f8] 第 %d 次：耗时 %.1f s，窗口 %s（原 %s）/ 模式 %d（原 %d）→ %s" % [
			round_i + 1, took, str(after), str(win_before), after_mode, mode_before,
			"窗口未变 ✓" if after == win_before and after_mode == mode_before else "窗口被改了 ✗"])
		await _wait(0.15)

	# 找最新的 4K 图并校验尺寸
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
		print("[f8] ✗ 没有 4K 图")
	else:
		var img := Image.new()
		if img.load(newest) == OK:
			print("[f8] 最新 4K 图：%s（%d×%d）%s" % [
				newest, img.get_width(), img.get_height(),
				"✓" if img.get_width() >= 3800 else "✗ 不是 4K"])
			# 抽查非单色（说明泼溅/场景真的渲进去了）
			var p1 := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
			var p2 := img.get_pixel(img.get_width() / 4, img.get_height() / 4)
			print("[f8] 采样：中心 %s / 左上 %s → %s" % [
				str(p1), str(p2),
				"有内容 ✓" if p1 != p2 else "疑似纯色 ✗"])
		else:
			print("[f8] ✗ 4K 图读不出来")

	fc.call("_input", _key(KEY_F7))
	await _wait(0.15)
	print("[f8] 自由摄像头已关：%s" % str(not bool(fc.call("is_active"))))
	DevMode.set_on(false)
	GameSettingsScript.set_value("window_mode", old_mode)
	print("[f8] 完成")
	quit(0)


func _key(k: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = k
	ev.physical_keycode = k
	ev.pressed = true
	return ev


func _wait(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < sec:
		await process_frame
