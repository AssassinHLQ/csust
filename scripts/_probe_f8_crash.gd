extends SceneTree
## 复现用户那条「按 F8 就闪退」的路径，并**精确定位死在哪一步**。
##
##   bash _tools/run_shot_direct.sh res://scripts/_probe_f8_crash.gd
##
## ── 为什么要这个探针 ──
## 用户报「f8 怎么还是闪退」，日志 `godot.log` 最后一行是
##   `[FreeCam] 开：WASD 平移 / ...`
## 之后一行都没有 —— 这是 `start()` 的最后一行，说明**激活已经跑完**，
## 死在之后的帧里或 `capture_4k()` 内部。以前两个探针都是 1600×900 窗口化，
## 而用户是**最大化 2560×1334**，所以一直复现不出来。本探针按用户尺寸起步。
##
## ── 落盘心跳 ──
## Vulkan 硬崩时进程直接没了 GDScript 报错都留不下，但**已经写到文件里的字节还在**。
## 所以每迈一步就 `FileAccess` 写一次并 close（每次 open/close，不吃缓冲），
## 崩了以后读 `_f8_hb.txt` 就知道最后一步是什么。
##
## ── 顺带量的东西 ──
## 视口 msaa / ssaa / taa / 3D 缩放 —— 4K 离屏如果继承了 4× MSAA + TAA，
## 显存会翻好几倍（3840×2000 单张 color 就 30 MB，MSAA 4× 再叠深度缓冲）。

const OffWin := preload("res://scripts/offscreen_window.gd")
const GameSettingsScript := preload("res://scripts/game_settings.gd")
const DevMode := preload("res://scripts/dev_mode.gd")

const SHOTS_REL := "_arisu_captures/_shots"
## 用户最大化时的客户区尺寸（用户机器 2560×1440 屏，去掉标题栏后约这个）
const USER_SIZE := Vector2i(2560, 1334)

var _game: Node
var _hb_path := ""
var _steps: Array[String] = []


func _initialize() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(USER_SIZE)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_hb_path = ProjectSettings.globalize_path("res://").path_join(SHOTS_REL) \
		.path_join("_f8_hb.txt")
	_hb("00 启动")
	var wd := create_timer(300.0, true)
	wd.timeout.connect(func() -> void:
		_hb("!! 看门狗超时")
		print("[f8] !! 看门狗超时")
		quit(2))
	_run.call_deferred()


## 落盘心跳：每次 open/write/close，保证崩掉之后文件里是最新那一步。
func _hb(step: String) -> void:
	_steps.append(step)
	var f := FileAccess.open(_hb_path, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_steps) + "\n")
		f.close()
	print("[f8] · %s" % step)


func _run() -> void:
	await OffWin.apply(self, USER_SIZE)
	_hb("01 窗口挪到屏幕外 %s" % str(DisplayServer.window_get_size()))
	var old_mode := String(GameSettingsScript.value("window_mode", "maximized"))
	GameSettingsScript.set_value("window_mode", "windowed")

	_game = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(_game)
	current_scene = _game
	_hb("02 game.tscn 已加载")
	for _i in 25:
		await process_frame

	var room := _game.get_node_or_null("Room609")
	var t0 := Time.get_ticks_msec()
	while room != null and not bool(room.call("is_ready")) \
			and float(Time.get_ticks_msec() - t0) / 1000.0 < 60.0:
		await process_frame
	for _i in 30:
		await process_frame
	_hb("03 画室就绪=%s" % ("-" if room == null else str(room.call("is_ready"))))

	# 视口渲染参数：4K 离屏是按这些值复制的，先知道原样
	var vp := root
	print("[f8] 视口：%s  msaa_3d=%d  ssaa=%d  taa=%s  3D缩放=%.2f  窗口=%s" % [
		str(vp.get_visible_rect().size), vp.msaa_3d, vp.screen_space_aa,
		str(vp.use_taa), vp.scaling_3d_scale, str(DisplayServer.window_get_size())])

	DevMode.set_on(true)
	_hb("04 准备按 F7")
	_game.call("_input", _key(KEY_F7))
	await _wait(0.3)
	var fc: Camera3D = _game.call("free_camera")
	var active := fc != null and bool(fc.call("is_active"))
	_hb("05 F7 之后 自由摄像头=%s" % str(active))
	if not active:
		print("[f8] ✗ 自由摄像头没开，后面没意义")
		quit(1)
		return

	# 打开逐步追踪，跑到控制台
	fc.set("debug_trace", true)
	fc.global_position = Vector3(0.0, 1.6, 3.0)
	fc.rotation_degrees = Vector3(-6.0, 0.0, 0.0)
	await _wait(0.3)

	# 让相机在看得到东西的地方真的渲几帧（用户按 F8 之前也是这样）
	for _i in 8:
		await process_frame
	_hb("06 前方 8 帧渲完，开始截图")

	for round_i in 3:
		_hb("07 第 %d 次 capture_4k 调用前" % (round_i + 1))
		fc.call("capture_4k")
		var t1 := Time.get_ticks_msec()
		while bool(fc.call("is_capturing")) \
				and float(Time.get_ticks_msec() - t1) / 1000.0 < 60.0:
			await process_frame
		_hb("08 第 %d 次 capture_4k 返回（%.1f s）" % [
			round_i + 1, float(Time.get_ticks_msec() - t1) / 1000.0])
		await _wait(0.3)

	# ── A/B：把相机上的 Compositor 摘掉再拍 ──
	# 如果「摘掉能拍、不摘就崩」，那真凶就是 GDGS 的全局 manager 被两个视口
	# 用不同尺寸同时调用（`gaussian_compositor_effect.gd` 的
	# `MANAGER_SCRIPT.get_instance().render_for_compositor(size, ...)`）。
	var cam := root.get_camera_3d()
	if cam != null:
		var saved_comp: Compositor = cam.compositor
		_hb("09 A/B 开始：当前相机「%s」compositor=%s" % [
			cam.name, "有" if saved_comp != null else "无"])
		cam.compositor = null
		await process_frame
		fc.call("capture_4k")
		var t2 := Time.get_ticks_msec()
		while bool(fc.call("is_capturing")) \
				and float(Time.get_ticks_msec() - t2) / 1000.0 < 60.0:
			await process_frame
		_hb("10 A/B：摘掉 Compositor 后拍完（会没有泼溅，只看会不会崩）")
		if is_instance_valid(cam):
			cam.compositor = saved_comp
		await _wait(0.2)
		_hb("11 A/B：Compositor 已还回去")

	# 最新 4K 图校验
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
		_hb("12 ✗ 没有 4K 图")
	else:
		var img := Image.new()
		if img.load(newest) == OK:
			var p1 := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
			var p2 := img.get_pixel(img.get_width() / 4, img.get_height() / 4)
			print("[f8] 最新 4K：%s（%d×%d）中心 %s / 左上 %s → %s" % [
				newest.get_file(), img.get_width(), img.get_height(),
				str(p1), str(p2), "有内容 ✓" if p1 != p2 else "疑似纯色 ✗"])
			_hb("12 ✓ 4K 图 %d×%d" % [img.get_width(), img.get_height()])
		else:
			_hb("12 ✗ 4K 图读不出来")

	# ── 验证新截图键 P（绕开编辑器的 F8=Stop）──
	_hb("15 开始验证 P 键截图")
	var before_ms := _newest_4k_ms()
	fc.call("_input", _key(KEY_P))
	await _wait(0.2)
	var t3 := Time.get_ticks_msec()
	while bool(fc.call("is_capturing")) \
			and float(Time.get_ticks_msec() - t3) / 1000.0 < 60.0:
		await process_frame
	var after_ms := _newest_4k_ms()
	print("[f8] P 键截图：最新 4K 时间戳 %d → %d → %s" % [
		before_ms, after_ms, "P 键生效 ✓" if after_ms > before_ms else "P 键没反应 ✗"])
	_hb("16 P 键截图 %s" % ("生效 ✓" if after_ms > before_ms else "没反应 ✗"))

	fc.call("_input", _key(KEY_F7))
	await _wait(0.3)
	_hb("13 自由摄像头已关=%s" % str(not bool(fc.call("is_active"))))
	DevMode.set_on(false)
	GameSettingsScript.set_value("window_mode", old_mode)
	_hb("14 全部完成，正常退出")
	quit(0)


## 最新一张 4K 图的修改时间（秒级），用来判断「刚刚是不是又存了一张」。
func _newest_4k_ms() -> int:
	var dir := ProjectSettings.globalize_path("res://").path_join(SHOTS_REL)
	var newest := 0
	var da := DirAccess.open(dir)
	if da == null:
		return 0
	for f in da.get_files():
		if f.begins_with("4k_") and f.ends_with(".png"):
			newest = maxi(newest, int(FileAccess.get_modified_time(dir.path_join(f))))
	return newest


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
