extends SceneTree
## 出图：普通攻击的**发光光点**长什么样（2026-11-11）。
##
##   _tools/run_shot.sh res://scripts/_probe_bolt_shot.gd
##   → _arisu_captures/_bolt/01_bolts_full.png、02_bolts_zoom.png
##
## 为什么要真窗口：`--headless` 下 `get_texture().get_image()` 拿不到内容。
## 窗口必须挪到屏幕外、不收鼠标、跑完自己关（见 `offscreen_window.gd`）。
##
## ⚠️ 2026-11-11 实测教训：`OffWin.apply()` **不能在 `_initialize()` 里 await**。
##    引擎把 `project.godot` 的 `window/size/mode=2`（最大化）应用得比那更晚，
##    于是 apply 干完又被顶回去 —— 这一次窗口真的开在 (0, 34) 抢了前台。
##    现在改成：`_initialize()` 里同步设一次，`_run()` 里**再 apply 并复查**
##    （`is_safe()` 假就重试），跑完把窗口位置打出来，出了事日志里看得见。
##
## ── 为什么要动 `tracer_speed` ──
## 弹丸默认 260 m/s：一帧飞 4.3 m，出膛那一帧就已经在十米外，**根本拍不到**。
## 这里临时压到 14 m/s，画面里才会同时挂着一串光点。
## ⚠️ 这只是**出图用**的临时值，跑完会写回去；游戏里的手感不受影响。
##
## ⚠️ 不要带 `--splat=off`：那会把 609 的碰撞一起关掉（见 `splat_scene.gd`），
##    弹丸永远打不到东西、命中火花也就永远不出现。

const OffWin := preload("res://scripts/offscreen_window.gd")
const GameSettingsScript := preload("res://scripts/game_settings.gd")

const SHOTS := 5
const SLOW_SPEED := 6.0
## 两发之间隔几帧。间隔要小到「最后一发还在画面里」，又大到能看出流。
const GAP_FRAMES := 4


func _initialize() -> void:
	# 同步先设一次（能挡住一部分时序），真正的确认放在 `_run()` 里
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _out(name: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_bolt").path_join(name)


func _shot(name: String, zoom: bool) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if zoom:
		var c := Vector2i(root.size) / 2
		var w := mini(360, c.x)
		var h := mini(270, c.y)
		img = img.get_region(Rect2i(c - Vector2i(w / 2, h / 2), Vector2i(w, h)))
		img.resize(w * 3, h * 3, Image.INTERPOLATE_NEAREST)
	var path := _out(name)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("[截图] %s（%d×%d，窗口 %s，安全=%s）" % [
		path, img.get_width(), img.get_height(),
		str(DisplayServer.window_get_position()), str(OffWin.is_safe())])


## 把窗口钉在屏幕外；最多试 3 轮，每轮都读回来确认。
func _pin_window() -> void:
	for attempt in 3:
		await OffWin.apply(self, Vector2i(1600, 900))
		var safe: Array = OffWin.is_safe()
		print("[bolt-shot] 第 %d 次挪窗口：位置 %s  mouse_mode=%d  安全=%s" % [
			attempt + 1, str(DisplayServer.window_get_position()),
			Input.mouse_mode, str(safe)])
		if bool(safe[0]):
			return
	push_warning("[bolt-shot] 窗口没能挪出屏幕（Windows 会在显示窗口那一刻给焦点，见 offscreen_window.gd）")


func _run() -> void:
	await _pin_window()
	# ⚠️ **必须先把窗口模式改成 windowed**（2026-11-11 实测翻车一次）：
	#    `project.godot` 的 `window/size/mode=2` 和 `GameSettings` 的
	#    `window_mode` 默认都是 **maximized**，`RenderEnv.apply_window_mode()`
	#    在关卡载入时会照着它把窗口最大化 —— 于是本探针前面刚挪到屏幕外的窗口
	#    被**拉回 (0, 34) 挡在用户脸上**，而且之后再 `window_set_mode(WINDOWED)`
	#    也压不住它（连试 3 次都回到 (0,34)）。
	var old_mode := String(GameSettingsScript.value("window_mode", "maximized"))
	GameSettingsScript.set_value("window_mode", "windowed")
	print("[bolt-shot] window_mode %s → windowed（只为出图，跑完写回）" % old_mode)

	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 60:
		await process_frame
	# 载入期间引擎还会动窗口，开拍前再钉一次
	await _pin_window()

	var player := game.get_node_or_null("Player")
	var wpn := player.get_node_or_null("Weapon") if player else null
	if wpn == null:
		print("[bolt-shot] 没有 Weapon")
		quit(1)
		return

	var old_speed := float(wpn.get("tracer_speed"))
	wpn.set("spread_hip", 0.0)
	wpn.set("spread_aim", 0.0)
	wpn.set("tracer_speed", SLOW_SPEED)
	print("[bolt-shot] tracer_speed %.1f → %.1f（只为出图）" % [old_speed, SLOW_SPEED])

	# 连打 SHOTS 发：每发清掉冷却，隔 GAP_FRAMES 帧，让子弹在弹道上排开
	var fired := 0
	for i in SHOTS:
		wpn.set("_cooldown", 0.0)
		if bool(wpn.call("shoot")):
			fired += 1
		for _j in GAP_FRAMES:
			await process_frame
	# ⚠️ 打完**马上**取数/截图：弹丸一直在往前飞，等太久就全撞墙回收了
	#    （上一版等了 8 帧，在最大化窗口下帧率更低、每帧飞得更远，最后一颗都不剩）。
	await process_frame
	var flight: Array = wpn.get("_in_flight")
	print("[bolt-shot] 打出 %d 发，此刻在飞 %d 个" % [fired, flight.size()])
	for it in flight:
		print("   弹丸：已飞 %.2f / 全程 %.2f m（%.1f m/s）" % [
			float(it[3]), float(it[1]), float(wpn.get("tracer_speed"))])

	# 按材质认子弹（**不能**按网格类型：子弹是 CapsuleMesh，球/柱都不是它）
	var bolt_mat: Variant = wpn.get("_bolt_mat")
	var bolts := 0
	var others := 0
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.material_override == bolt_mat:
			bolts += 1
		elif mi.mesh is SphereMesh or mi.mesh is CylinderMesh:
			others += 1
	print("  画面里：子弹 %d 个（应该 = 在飞的 %d）；其它球/柱 %d 个（光柱/爆闪若出现会算在这里）"
		% [bolts, flight.size(), others])
	if flight.size() > 0:
		var item: Array = flight[0]
		var mi2 := item[0] as MeshInstance3D
		print("  最老那颗子弹：位置 %s  局部缩放 %s（稳态应 ≈ (1, 1, 1)）" % [
			str(mi2.global_position.snappedf(0.01)), str(mi2.scale.snappedf(0.001))])

	await _shot("01_bolts_full.png", false)
	await _shot("02_bolts_zoom.png", true)

	wpn.set("tracer_speed", old_speed)
	GameSettingsScript.set_value("window_mode", old_mode)
	quit(0)
