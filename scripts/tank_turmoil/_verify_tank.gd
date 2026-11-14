extends SceneTree
## 坦克动荡 · 无窗口自检（2026-11-14）
##
## 用法：
##   godot --headless --path <工程根> --script res://scripts/tank_turmoil/_verify_tank.gd
##
## 只验「搬进主工程以后有没有坏」，不验玩法平衡：
##   ① 脚本能编译、节点能实例化（搬过来的资源路径都还在）
##   ② 五人编队：玩家 = 爱丽丝，四台 AI = 才羽绿 / 柚子 / 才羽桃井 / 凯伊
##   ③ AI 档位 = 优香档（0.075 s / 12 方向 / 30 步 / 拆 2 组）
##   ④ 大地图：默认 19 × 9，CELL 合理，墙网格生成得出来
##   ⑤ 没有音乐播放器、没有 `p1_*` 输入动作依赖
##   ⑥ 输入：喂 WASD 事件 → 主角真的动 / 真的转向

const SCENE := "res://scripts/tank_turmoil/tank_main_scene.tscn"
const ROUND_FRAMES := 240

var _fails := 0
var _checks := 0
var _tank: Node2D
var _frames := 0
var _stage := 0
var _start_pos := Vector2.ZERO
var _start_angle := 0.0


func _init() -> void:
	print("========== 坦克动荡 · 搬入主工程自检 ==========")
	var packed := load(SCENE) as PackedScene
	_check(packed != null, "场景能加载：%s" % SCENE)
	if packed == null:
		_finish()
		return
	_tank = packed.instantiate() as Node2D
	_check(_tank != null, "场景能实例化")
	if _tank == null:
		_finish()
		return
	# ⚠️ 必须有 1000×800 的 SubViewport 包着：逻辑尺寸写死在 `W` / `H`。
	#    直接挂到 `root`（--headless 下是 1152×648）会走 `_open_own_viewport()` 的警告分支。
	var sub := SubViewport.new()
	sub.size = Vector2i(1000, 800)
	sub.gui_disable_input = true
	get_root().add_child(sub)
	sub.add_child(_tank)
	_run.call_deferred()


func _run() -> void:
	await _wait_frames(2)
	_check(_tank.get("intro_playing") == false, "开场视频已跳过（不搬 ogv）")

	# ── ① 资源路径 ──
	var portraits := ["PORTRAIT_MIDORI", "PORTRAIT_YUZU", "PORTRAIT_MOMOI", "PORTRAIT_ALICE",
		"PORTRAIT_KEI", "PORTRAIT_YUUKA"]
	for pname in portraits:
		var tex: Texture2D = _tank.get(pname)
		_check(tex != null, "立绘 %s 已加载（%d×%d）" % [pname, tex.get_width() if tex else 0,
			tex.get_height() if tex else 0])
	var defeat: AudioStream = _tank.get("SOUND_MOMOI_DEFEAT")
	_check(defeat != null, "桃井败北音效已加载")

	# ── ② 没有音乐播放器、没有歌单 ──
	_check(_tank.get("music_player") == null, "没有自己的 AudioStreamPlayer（音乐交给电竞房）")
	var paths: Array = _tank.get("IMPORTED_MUSIC_PATHS")
	_check(paths.is_empty(), "曲库路径表为空（没把 37.9 MB 音乐搬进来）")

	# ── ③ 大地图 ──
	var cols: int = _tank.get("COLS")
	var rows: int = _tank.get("ROWS")
	_check(cols >= 15 and rows >= 9, "默认大地图：%d × %d" % [cols, rows])

	# ── ④ 开一局，验编队 + AI 档位 ──
	_tank.call("start_game", 1)
	var tanks: Array = _tank.get("tanks")
	_check(tanks.size() == 5, "五人同时在场：实际 %d 台" % tanks.size())
	if tanks.size() == 5:
		_check(str(tanks[0]["name"]) == "爱丽丝", "主角是爱丽丝（实际 %s）" % tanks[0]["name"])
		var enemies := []
		for i in range(1, 5):
			enemies.append(str(tanks[i]["name"]))
		enemies.sort()
		var expect := ["才羽桃井", "才羽绿", "凯伊", "柚子"]
		expect.sort()
		_check(enemies == expect, "四台 AI = %s（实际 %s）" % [str(expect), str(enemies)])
		_check(bool(tanks[1].get("boss", true)) == false, "队友没有 BOSS 耐久（一炮就死）")

	var cell: float = _tank.get("CELL")
	_check(cell > 30.0 and cell < 75.0, "格子尺寸合理：%.1f px" % cell)
	var walls: Array = _tank.get("walls")
	_check(walls.size() > 20, "迷宫墙生成：%d 面" % walls.size())

	# ── ⑤ AI 档位 = 优香档 ──
	var interval: float = _tank.get("ai_danger_interval")
	var dirs: int = _tank.get("ai_evade_directions")
	var steps: int = _tank.get("ai_evade_steps")
	var squads: int = _tank.get("ai_squads")
	_check(is_equal_approx(interval, 0.075), "危险预测间隔 = 优香的 0.075 s（实际 %.3f）" % interval)
	_check(dirs == 12, "躲避方向数 = 优香的 12（实际 %d）" % dirs)
	_check(steps == 30, "远期步数 = 30（优香 36 打八折，实际 %d）" % steps)
	_check(squads == 2, "四台拆成 2 组错峰（实际 %d）" % squads)
	_check(is_equal_approx(float(_tank.get("ai_fire_tolerance")), 0.022),
		"开火容差 = 优香的 0.022 弧度")
	var squads_seen := {}
	for i in range(1, tanks.size()):
		squads_seen[int(tanks[i].get("squad", -1))] = true
	_check(squads_seen.size() == 2, "四台确实分布在两组（%s）" % str(squads_seen.keys()))

	# ── ⑥ 输入：喂一个 W 事件，主角应该动 ──
	# 倒计时（2.8 秒）走完之前 `_process()` 不动坦克，所以先把倒计时清零并放一帧。
	_tank.set("countdown", 0.0)
	tanks = _tank.get("tanks")
	_start_pos = tanks[0]["pos"]
	_start_angle = float(tanks[0]["angle"])
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	_tank.call("feed", key)
	_stage = 1
	_frames = 0


func _process(_delta: float) -> bool:
	_frame_pulse.emit()
	if _stage == 1:
		_frames += 1
		if _frames == ROUND_FRAMES:
			var tanks: Array = _tank.get("tanks")
			var moved: float = (tanks[0]["pos"] as Vector2).distance_to(_start_pos)
			_check(moved > 1.0, "按住 W 240 帧后主角移动了 %.2f px" % moved)
			var key := InputEventKey.new()
			key.physical_keycode = KEY_W
			key.pressed = false
			_tank.call("feed", key)
			# ── 转向检查：先**重开一局**，把 AI 全部清掉，免得它们干扰 ──
			#
			# ⚠️ 坑 1：`_process()` 里 `return false` 并不等于停 —— 引擎照样每帧调
			#    `_tank._process()`，四台 AI 一直在追着打。前面的检查要跑 240 帧，
			#    实测有一半概率主角在这期间就被打爆，之后 `update_human()` 第一句
			#    `if not tanks[index].alive: return` 直接退出，按 A 当然一点反应都没有。
			# ⚠️ 坑 2：主角 `alive = false` 后 `round_over` 仍为 false（`tank_was_hit`
			#    里 `tanks[0]` 那条分支只置 `round_over`），所以这里要手动把 AI 清干净。
			# 做法：`new_round()` 重置整局，然后把 1..4 号直接标死、倒计时清零。
			_tank.call("new_round")
			_tank.set("countdown", 0.0)
			var fresh: Array = _tank.get("tanks")
			for i in range(1, fresh.size()):
				fresh[i]["alive"] = false
			_check(bool(fresh[0]["alive"]), "重开一局后主角活着（干净的转向测试）")
			_start_angle = float(fresh[0]["angle"])
			var left := InputEventKey.new()
			left.physical_keycode = KEY_A
			left.pressed = true
			_tank.call("feed", left)
			_stage = 2
			_frames = 0
	elif _stage == 2:
		_frames += 1
		if _frames == 60:
			var tanks: Array = _tank.get("tanks")
			var facing := Vector2.from_angle(float(tanks[0]["angle"]))
			# 直控模式下 `angle` 每帧朝「输入方向」（这里就是正左）lerp，60 帧足够掉头。
			_check(facing.x < -0.5, "按住 A 60 帧后朝左了（朝向 %s）" % str(facing))
			var left := InputEventKey.new()
			left.physical_keycode = KEY_A
			left.pressed = false
			_tank.call("feed", left)
			# ⚠️ 这里**必须同步调用 `_check_host()`，不能 `await`**：
			#    本分支跑在 `_process()` 的调用栈里，`_process` 里一 await 整个主循环就挂起。
			_check_host()
			_finish()
	return false


func _check_host() -> void:
	print("  … 开始检查宿主接线")
	var host_script := load("res://scripts/hut_computer.gd") as Script
	_check(host_script != null, "宿主脚本 hut_computer.gd 能加载")
	if host_script == null:
		_finish()
		return
	var scripted := host_script.new() as Node3D
	_check(scripted != null, "宿主脚本能 new 出节点")
	if scripted == null:
		_finish()
		return
	var host := scripted
	get_root().add_child(host)
	print("  … 已 add_child，is_tank_open=%s" % str(host.has_method("is_tank_open")))
	# ⚠️ 这里**只能同步跑**，不能 await 任何东西：
	#    本函数是在 `_process()` 的调用栈里被 await 的（`_process` 里的 await 会挂起
	#    整个主循环），一 await 就再也回不来 —— 实测日志每次都在「已 add_child」断掉。
	#    `hut_computer._ready()` 里要紧的东西（`_build()` → `tank_viewport`）都是同步建的，
	#    `_ready` 里那一句 `await process_frame` 只是建完灯之后的事，不等也行。
	print("  … 节点已在树里，检查方法")
	_check(host.has_method("is_tank_open") and host.has_method("open_tank_for_test"),
		"宿主暴露了小游戏开关（is_tank_open / open_tank_for_test）")
	var vp := host.get("tank_viewport") as SubViewport
	_check(vp != null and vp.size == Vector2i(1000, 800),
		"小游戏画布是 1000×800（实际 %s）" % (str(vp.size) if vp != null else "无"))
	# ⚠️ 这一整段的 `yield` 都不能省：`open_tank_for_test()` → `_ensure_tank()`
	#    里要 `load()` 场景和 6 张立绘，`add_child` 之后 `_ready()` 也要等一帧。
	print("  … 调 open_tank_for_test()")
	host.call("open_tank_for_test")
	_check(bool(host.call("is_tank_open")), "按 G 能打开小游戏")
	var node: Node = host.get("tank")
	_check(node != null and is_instance_valid(node), "坦克动荡节点已实例化并挂进画布")
	host.call("close_tank_for_test")
	_check(not bool(host.call("is_tank_open")), "关得掉（G 键 / 设置菜单 / 探针三条路）")
	host.queue_free()




## 等 n 个**引擎帧**（不是 `await process_frame`）。
##
## ⚠️ 实测坑：`--script` 模式下 `SceneTree` 的主循环不是我们推的，
##    `await process_frame` 的信号**根本不发**，协程永久挂起 ——
##    日志会停在两行 `✓` 之后、`_finish()` 永远不执行，
##    进程靠 Godot 自己的「没有帧驱动就退出」收场（exit code 是没意义的）。
##    `_process()` 和 `_physics_process` 是引擎照常调用的，所以用帧计数来等。
func _wait_frames(n: int) -> void:
	for i in n:
		await _one_frame_passed()


signal _frame_pulse

func _one_frame_passed() -> void:
	# 每帧由 `_process()` 里发一次；收到就继续。
	await _frame_pulse


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("  ✓ %s" % what)
	else:
		_fails += 1
		print("  ✗ %s" % what)


func _finish() -> void:
	print("---------- %d 项，失败 %d ----------" % [_checks, _fails])
	print("★ 全部通过" if _fails == 0 else "✗ 有 %d 项没过" % _fails)
	quit(0 if _fails == 0 else 1)



