extends SceneTree
## 复现并锁定「开场 PV 里看不见鼠标」的真实链路（2026-11-12）。
##
##   bash _tools/run_shot_direct.sh res://scripts/_probe_intro_mouse_race.gd -- --splat=off
##
## 真实链路（本喵第二次踩坑后查清楚的）：
##   ① `player.gd::_ready()` → CAPTURED
##   ② `game.gd::_play_title_intro()` → VISIBLE
##   ③ **窗口获焦 → `player._notification(FOCUS_IN)` → 又 CAPTURED**  ← 这里把光标抢走
##   ④ 用户看到「PV 里没鼠标」
##
## 本探针模拟 ③：在 PV 播着的时候造一次 FOCUS_IN / FOCUS_OUT / FOCUS_IN，
## 看鼠标最终是不是还**可见**。

const OffWin := preload("res://scripts/offscreen_window.gd")
const GameSettingsScript := preload("res://scripts/game_settings.gd")
const TitleIntroScript := preload("res://scripts/title_intro.gd")

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


func _mm() -> String:
	match Input.mouse_mode:
		0: return "VISIBLE(0)"
		1: return "HIDDEN(1)"
		2: return "CAPTURED(2)"
		3: return "CONFINED(3)"
	return "?%d" % Input.mouse_mode


func _run() -> void:
	print("========== 开场 PV：鼠标被谁抢走 ==========")
	await OffWin.apply(self, Vector2i(1600, 900))
	var old_mode := String(GameSettingsScript.value("window_mode", "maximized"))
	GameSettingsScript.set_value("window_mode", "windowed")

	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	for _i in 12:
		await process_frame

	var player := game.get_node_or_null("Player")
	# ⚠️ `--script`（也就是本探针）下 `game.gd` **故意不自动播开场**
	#    （见 `_play_title_intro()` 里的三条「不播」），所以这里直接手工建一层，
	#    和 `game.gd` 一样的搭法 —— 要验的正是「PV 在播的时候鼠标归谁」。
	var intro := TitleIntroScript.new() as Node
	intro.name = "TitleIntro"
	game.add_child(intro)
	var t_start := Time.get_ticks_msec()
	intro.call("play", func() -> Dictionary:
		return {"ratio": 1.0, "ready": float(Time.get_ticks_msec() - t_start) / 1000.0 >= 1.5,
			"names": []})
	for _i in 6:
		await process_frame
	_check(intro != null and bool(intro.call("is_playing")), "开场 PV 在播（探针手工建的）")
	print("  载入后 mouse_mode = %s" % _mm())

	# ① PV 期间：鼠标可见
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
		"① PV 播放期间鼠标可见（实测 %s）" % _mm())

	# ② 模拟「窗口获焦」（玩家 _notification 会在这里抢鼠标）
	if player != null:
		player.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
		await process_frame
		print("  模拟 FOCUS_IN 之后 mouse_mode = %s" % _mm())
		_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
			"② ★ 窗口获焦后鼠标**仍然可见**（实测 %s）—— 之前就是这里被抢走" % _mm())

	# ③ 失焦再获焦，也不能把它抢回去
	if player != null:
		player.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		await process_frame
		player.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
		await process_frame
		print("  失焦+获焦后 mouse_mode = %s" % _mm())
		_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
			"③ ★ 失焦再来一次仍然可见（实测 %s）" % _mm())

	# ④ `_may_capture()` 在 PV 期间就该是 false
	if player != null:
		var may := bool(player.call("_may_capture"))
		_check(not may, "④ `player._may_capture()` 在 PV 期间 = false（实测 %s）" % str(may))

	# ④b ★ 第三处凶手：`game.gd::_report_input()` 每秒那把「自动收回」
	#     （用户实测「一开始有鼠标但是加载完不见了」就是这个）
	if game.has_method("_report_input"):
		# 点开始之前它不该收；直接调一次等价的分支判断来验
		var would_steal := bool(game.call("_title_intro_playing"))
		_check(would_steal,
			"④b `game._title_intro_playing()` 在 PV 期间 = true（自愈分支会跳过它）")
	# 额外：真的等它跑满 1 秒自愈周期，确认鼠标没被收走
	print("  等 1.2 s 让 `_report_input()` 跑过一次自愈…")
	var t_w := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t_w) / 1000.0 < 1.2:
		await process_frame
	print("  自愈周期过后 mouse_mode = %s" % _mm())
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
		"④c ★ 自愈跑过一轮后鼠标**仍然可见**（实测 %s）—— 这就是「加载完不见了」那个坑" % _mm())

	# ⑤ 点开始之后：鼠标要收回去（第三人称）
	if intro != null:
		var waited := 0.0
		while waited < 40.0 and not bool(intro.call("is_start_ready")):
			await process_frame
			waited += 1.0 / 60.0
		print("  等开始按钮 %.1f s，ready=%s" % [
			waited, str(bool(intro.call("is_start_ready")))])
		intro.call("press_start")
		var t0 := Time.get_ticks_msec()
		while float(Time.get_ticks_msec() - t0) / 1000.0 < 5.0 and bool(intro.call("is_playing")):
			await process_frame
		await process_frame
		print("  点开始后 mouse_mode = %s" % _mm())
		_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED,
			"⑤ 进游戏后鼠标收回（实测 %s）" % _mm())
		# ⑥ 这一下才该允许抢回来
		if player != null:
			_check(bool(player.call("_may_capture")),
				"⑥ PV 结束后 `_may_capture()` 恢复 true")

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameSettingsScript.set_value("window_mode", old_mode)
	print("\n========== 结果 ==========")
	print("  通过 %d，失败 %d" % [_pass, _fail])
	print("  %s" % ("★ 开场期间鼠标不再被玩家抢走，点完开始才收回" if _fail == 0
		else "✗ 还有地方在抢"))
	quit(0 if _fail == 0 else 1)
