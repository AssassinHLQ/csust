extends SceneTree
## 真窗口探针：**不带 `--no-capture`** 地跑一遍开场，验「鼠标真的看得见」。
## （`_probe_intro_mouse.gd` 是语义验证；这个是真的让引擎去放光标。）
##
##   bash _tools/run_shot_direct.sh res://scripts/_probe_intro_mouse_real.gd -- --splat=off

const TitleIntroScript := preload("res://scripts/title_intro.gd")
const OffWin := preload("res://scripts/offscreen_window.gd")
const GameSettingsScript := preload("res://scripts/game_settings.gd")

var _pass := 0
var _fail := 0


func _initialize() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  %s" % what)
	else:
		_fail += 1
		print("  FAIL  %s" % what)


func _run() -> void:
	print("========== 开场 PV 鼠标（真窗口，真放开）==========")
	await OffWin.apply(self, Vector2i(1600, 900))
	var old_mode := String(GameSettingsScript.value("window_mode", "maximized"))
	GameSettingsScript.set_value("window_mode", "windowed")

	# 模拟「玩家已经在玩」：先捕获
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await process_frame
	print("  起手 mouse_mode = %d（2 = CAPTURED）" % Input.mouse_mode)

	# 走真正的 game.tscn 路径（它自己会放开鼠标）
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	for _i in 12:
		await process_frame

	var intro := game.get_node_or_null("TitleIntro")
	_check(intro != null, "开场 PV 节点在场上")
	print("  PV 起来后 mouse_mode = %d（0 = VISIBLE 才对）" % Input.mouse_mode)
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
		"★ 开场期间鼠标可见（实测 %d）" % Input.mouse_mode)

	# 等开始按钮出现
	var waited := 0.0
	while waited < 30.0 and intro != null and not bool(intro.call("is_start_ready")):
		await process_frame
		waited += float(1.0) / 60.0
	_check(intro != null and bool(intro.call("is_start_ready")), "开始按钮出现")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
		"★ 等点击的整个过程鼠标都可见（实测 %d）" % Input.mouse_mode)

	# 点开始
	if intro != null:
		intro.call("press_start")
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < 4.0 and bool(intro.call("is_playing")):
		await process_frame
	await process_frame
	print("  点开始后 mouse_mode = %d（2 = CAPTURED 才对）" % Input.mouse_mode)
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED,
		"★ 进游戏后鼠标收回（实测 %d）" % Input.mouse_mode)

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameSettingsScript.set_value("window_mode", old_mode)
	print("\n========== 结果 ==========")
	print("  通过 %d，失败 %d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
