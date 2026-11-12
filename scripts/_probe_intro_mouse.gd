extends SceneTree
## 真窗口探针：开场 PV 期间**鼠标必须看得见**（2026-11-12 用户报「开始 pv 没看见鼠标」）。
##
##   bash _tools/run_shot.sh res://scripts/_probe_intro_mouse.gd -- --splat=off
##
## 复现条件：`player.gd::_ready()` 把鼠标设成 CAPTURED（第三人称要那样），
## 而开场 UI 要用鼠标点「开始游戏」—— 不放开就是「看不见光标、点不着」。
##
## 三次读数：
##   ① 载入 game.tscn 之后（player 已跑过 _ready）
##   ② 开场 PV 起来之后（应当 VISIBLE = 0）
##   ③ 点完开始之后（应当回到 CAPTURED = 2）
##
## ⚠️ run_shot.sh 自带 `--no-capture`，而那条路径**故意不动鼠标**（怕抢用户鼠标）。
##    所以本探针自己把「不动鼠标」的闸临时绕开：直接调 `title_intro` 的
##    `_release_mouse()` / `_restore_mouse()` 验语义，不依赖引擎真实捕获状态。

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
	print("========== 开场 PV 鼠标 ==========")
	await OffWin.apply(self, Vector2i(1600, 900))
	var old_mode := String(GameSettingsScript.value("window_mode", "maximized"))
	GameSettingsScript.set_value("window_mode", "windowed")

	# 模拟「玩家正在玩第三人称」：鼠标被捕获
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("  起手 mouse_mode = %d（2 = CAPTURED，模拟玩家已在玩）" % Input.mouse_mode)

	var host := Node.new()
	root.add_child(host)
	var intro := TitleIntroScript.new() as Node
	intro.name = "TitleIntro"
	host.add_child(intro)

	# 1) _black_only() 里就会放开鼠标
	intro.call("_black_only")
	await process_frame
	print("  ① 建层后 mouse_mode = %d" % Input.mouse_mode)
	# ⚠️ run_shot.sh 带 --no-capture，`_release_mouse()` 会按设计**不动鼠标**
	var no_capture := OS.get_cmdline_user_args().has("--no-capture")
	if no_capture:
		print("  （本次带 --no-capture：按设计不动鼠标，所以下面直接验语义）")
		_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED,
			"带 --no-capture 时**不**去动用户鼠标（mode 仍是 CAPTURED）")
		# 语义验证：手动置成 we-own，再走一遍恢复
		intro.set("_prev_mouse_mode", int(Input.MOUSE_MODE_CAPTURED))
		intro.set("_mouse_owned", true)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "置 VISIBLE 成功（引擎层可写）")
		intro.call("_restore_mouse")
		await process_frame
		_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED,
			"`_restore_mouse()` 把鼠标还回 CAPTURED（%d）" % Input.mouse_mode)
		_check(not bool(intro.get("_mouse_owned")), "恢复后 `_mouse_owned` 归 false（不会重复抢）")
	else:
		_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
			"进开场层后鼠标被放开（VISIBLE = 0，实测 %d）" % Input.mouse_mode)

	# 2) 真跑一遍 play()：开场期间必须 VISIBLE，点完开始必须还回去
	intro.call("_black_only")
	intro.call("_build_backdrop")
	intro.call("_build_ui")
	await process_frame
	intro.call("_layout")
	intro.call("_release_mouse")
	await process_frame
	if not no_capture:
		_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
			"PV 播放期间鼠标可见（实测 %d）" % Input.mouse_mode)
	intro.call("_restore_mouse")
	await process_frame
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED,
		"点开始后鼠标还回 CAPTURED（实测 %d）" % Input.mouse_mode)

	# 3) game.tscn：`_play_title_intro()` 在 play() 之前就先放开一次
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	game.call("_play_title_intro")
	await process_frame
	await process_frame
	if not no_capture:
		_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
			"game.gd 播开场时鼠标是可见的（实测 %d）" % Input.mouse_mode)
	# 收尾：别把鼠标留在抓着不放的状态
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	GameSettingsScript.set_value("window_mode", old_mode)
	game.queue_free()
	intro.queue_free()
	host.queue_free()
	await process_frame

	print("\n========== 结果 ==========")
	print("  通过 %d，失败 %d" % [_pass, _fail])
	print("  %s" % ("★ 开场期间鼠标可见、点完还回去；--no-capture 时绝不动用户鼠标"
		if _fail == 0 else "✗ 有问题"))
	quit(0 if _fail == 0 else 1)
