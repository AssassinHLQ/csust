extends SceneTree
## 自检：开发者模式 F7 自由摄像头（2026-11-12 用户：「f3 模式新增 f7，
## 切换自由摄像头 WASD QE 方便拍摄」）。
##
## 用法：
##   bash _tools/run_probe.sh res://scripts/_verify_free_camera.gd -- --splat=off
##
## ⚠️ headless 下只验**逻辑**（开/关、状态接管/还原、WASD 能平移、F8 不炸）；
##    真 4K 截图必须真窗口，见 `_probe_freecam_shot.gd`。

const DevMode := preload("res://scripts/dev_mode.gd")
const GAME := "res://scenes/game.tscn"

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  %s" % what)
	else:
		_fail += 1
		print("  FAIL  %s" % what)


func _wait_sec(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < sec:
		await process_frame


func _key(k: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = k
	ev.physical_keycode = k
	ev.pressed = true
	return ev


func _run() -> void:
	print("========== F7 自由摄像头 ==========")
	DevMode.set_on(false)

	# ── ① 开发者模式没开时，F7 不该动 ──
	print("\n── ① 没开开发者模式 ──")
	var game := (load(GAME) as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	for _i in 20:
		await process_frame
	_check(not DevMode.is_on(), "开发者模式默认关")
	game.call("_input", _key(KEY_F7))
	await _wait_sec(0.1)
	var fc0 = game.call("free_camera")
	_check(fc0 == null or not bool(fc0.call("is_active")), "关着开发者模式时 F7 不开自由摄像头")

	# ── ② 开发者模式开着：F7 开，状态接管 ──
	print("\n── ② F7 开：HUD 藏起、玩家停手、相机接管 ──")
	DevMode.set_on(true)
	game.call("_input", _key(KEY_F7))
	await _wait_sec(0.15)
	var fc = game.call("free_camera")
	_check(fc != null, "自由摄像头节点被懒创建")
	_check(fc != null and bool(fc.call("is_active")), "F7 之后处于激活态")
	var hud := game.get_node_or_null("HUD")
	_check(hud != null and not bool(hud.get("visible")), "HUD 被藏起来（拍摄画面干净）")
	var player := game.get_node_or_null("Player")
	_check(player != null and not player.is_processing_input(), "玩家输入被关掉（鼠标不会带角色转头 / 不会开枪）")
	_check(player != null and not player.is_physics_processing(), "玩家物理被关掉（人停在原地）")
	# ⚠️ 2026-11-12 改：自由摄像头**自己不当前相机**（那是 F8 崩溃的根因 ——
	#    第二台相机会让 SplatCompositor 挂第二份 Compositor）。
	#    现在它是「拿着**玩家那台相机**飞的支架」，所以要验两件事：
	#    ① 玩家相机被临时挂到了本节点下；② 视口里当前相机就是那一台。
	var borrowed := fc.get_node_or_null("Camera3D") as Camera3D if fc != null else null
	if borrowed == null and fc != null:
		for n in fc.find_children("*", "Camera3D", true, false):
			borrowed = n as Camera3D
			break
	_check(borrowed != null, "玩家相机被借到自由摄像头节点下（没有第二台相机）")
	_check(borrowed != null and root.get_camera_3d() == borrowed,
		"当前相机 = 借来的那台玩家相机")
	_check(player != null and bool(player.get_node("Arisu").visible), "角色网格**没有**被藏（构图需要）")
	var help: Label = null
	if fc != null:
		for n in fc.find_children("*", "Label", true, false):
			if String((n as Label).text).contains("自由摄像头"):
				help = n as Label
				break
	_check(help != null, "屏幕上有帮助条")
	if help != null:
		var txt := help.text
		_check(txt.contains("WASD") and txt.contains("Q") and txt.contains("E"),
			"帮助条写了 WASD / Q / E 键位")
		# 2026-11-13：截图键加了 P（编辑器里 F8 = 停止运行项目，会被编辑器接走）。
		# 从编辑器起跑时帮助条只写 P，从导出包起跑时写「P / F8」——两种都算过。
		_check(txt.contains("4K") and (txt.contains("P") or txt.contains("F8")),
			"帮助条写了截图键（P / F8）+ 4K")

	# ── ③ WASD / QE 能平移 ──
	print("\n── ③ WASD 平移 / QE 升降 ──")
	var p0: Vector3 = fc.global_position
	Input.action_press("move_forward")
	await _wait_sec(0.35)
	Input.action_release("move_forward")
	await process_frame
	var moved: float = fc.global_position.distance_to(p0)
	print("  前进位移 %.3f m" % moved)
	_check(moved > 0.05, "按 W 能沿视线前进（%.3f m）" % moved)
	# Shift 加速
	var p1: Vector3 = fc.global_position
	Input.action_press("move_forward")
	Input.action_press("freecam_fast")
	await _wait_sec(0.35)
	Input.action_release("freecam_fast")
	Input.action_release("move_forward")
	await process_frame
	var moved_shift: float = fc.global_position.distance_to(p1)
	print("  Shift 前进位移 %.3f m（应 > 普通 %.3f m）" % [moved_shift, moved])
	_check(moved_shift > moved, "Shift 能加速（%.3f > %.3f m）" % [moved_shift, moved])
	# E 升 / Q 降
	var y0: float = fc.global_position.y
	Input.action_press("freecam_up")
	await _wait_sec(0.35)
	Input.action_release("freecam_up")
	await process_frame
	var rose: float = fc.global_position.y - y0
	print("  E 上升 %.3f m" % rose)
	_check(rose > 0.05, "E 能上升（%.3f m）" % rose)
	var y1: float = fc.global_position.y
	Input.action_press("freecam_down")
	await _wait_sec(0.35)
	Input.action_release("freecam_down")
	await process_frame
	var fell: float = y1 - fc.global_position.y
	print("  Q 下降 %.3f m" % fell)
	_check(fell > 0.05, "Q 能下降（%.3f m）" % fell)

	# ── ④ F8 在 headless 不炸、不误改窗口 ──
	print("\n── ④ F8 在 headless ──")
	var size_before := DisplayServer.window_get_size()
	fc.call("capture_4k")
	await _wait_sec(0.2)
	_check(not bool(fc.call("is_capturing")), "headless 下 F8 直接返回，不卡在 capturing")
	_check(DisplayServer.window_get_size() == size_before, "headless 下窗口尺寸没被乱改")

	# ── ⑤ F7 / Esc 退出并还原 ──
	print("\n── ⑤ 退出：状态全部还原 ──")
	fc.call("_input", _key(KEY_F7))
	await _wait_sec(0.15)
	_check(not bool(fc.call("is_active")), "F7 再按一次：退出自由摄像头")
	_check(hud != null and bool(hud.get("visible")), "HUD 恢复显示")
	_check(player != null and player.is_processing_input(), "玩家输入恢复")
	_check(player != null and player.is_physics_processing(), "玩家物理恢复")
	# 相机应当归还到弹簧臂下面
	var player_cam := player.get_node_or_null("CameraRig/SpringArm3D/Camera3D") if player != null else null
	_check(player_cam != null, "玩家相机已挂回 CameraRig/SpringArm3D/Camera3D")
	_check(root.get_camera_3d() == player_cam, "相机交还玩家（视口当前相机 = 玩家相机）")
	_check(fc.get_node_or_null("FreeCamHelp") == null, "帮助条已释放")
	# Esc 也能退出
	fc.call("toggle")
	await _wait_sec(0.1)
	_check(bool(fc.call("is_active")), "再次 F7：重新进入")
	fc.call("_input", _key(KEY_ESCAPE))
	await _wait_sec(0.1)
	_check(not bool(fc.call("is_active")), "Esc 也能退出自由摄像头")

	DevMode.set_on(false)
	game.queue_free()
	for _i in 3:
		await process_frame

	print("\n========== 结果 ==========")
	print("  通过 %d，失败 %d" % [_pass, _fail])
	print("  %s" % ("★ F7 自由摄像头：开/关、接管/还原、WASD 平移、帮助条都对"
		if _fail == 0 else "✗ 有问题"))
	quit(0 if _fail == 0 else 1)
