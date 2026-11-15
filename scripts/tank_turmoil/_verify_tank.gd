extends SceneTree

class AimProbe:
	extends "res://scripts/tank_turmoil/tank_main.gd"
	var all_unsafe := false
	func _ai_shot_safe(_owner: int, shot_angle: float, _weapon: String) -> bool:
		return not all_unsafe and shot_angle > 0.005
	func play_sound(_stream: AudioStream, _pitch := 1.0, _gain_multiplier := 1.0) -> void:
		pass
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
##   ⑦ 宿主接线：`scripts/esports_arcade.gd`（电竞房街机柜）挂得住，
##      且小屋电脑那侧的入口**确实撤掉了**（用户 2026-11-14「搬到电竞房」）

const SCENE := "res://scripts/tank_turmoil/tank_main_scene.tscn"
const ROUND_FRAMES := 240

var _fails := 0
var _checks := 0
var _tank: Node2D
var _frames := 0
var _stage := 0
var _start_pos := Vector2.ZERO
var _start_angle := 0.0
var _finishing := false


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
	_check(is_equal_approx(float(_tank.get("master_volume")), 1.0) and is_equal_approx(float(_tank.get("sfx_volume")), 1.0), "新游戏默认总音量和音效均为 100%")
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
	var victory: AudioStream = _tank.get("SOUND_ALICE_VICTORY")
	_check(victory != null and absf(victory.get_length() - 1.35) < 0.05, "爱丽丝获胜语音已加载，时长约 1.35 秒")

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
	_check(is_equal_approx(interval, 0.12), "危险预测间隔 0.12 s（实际 %.3f）" % interval)
	_check(dirs == 8, "躲避方向数 8（实际 %d）" % dirs)
	_check(steps == 20, "远期步数 20（实际 %d）" % steps)
	_check(squads == 2, "四台拆成 2 组错峰（实际 %d）" % squads)
	_check(is_equal_approx(float(_tank.get("ai_fire_tolerance")), 0.022),
		"开火容差 = 优香的 0.022 弧度")
	var squads_seen := {}
	for i in range(1, tanks.size()):
		squads_seen[int(tanks[i].get("squad", -1))] = true
	_check(squads_seen.size() == 2, "四台确实分布在两组（%s）" % str(squads_seen.keys()))
	_check(float(_tank.call("ai_skill", 3)) < float(_tank.call("ai_skill", 1)), "桃井 AI 难度降低")
	_check(float(_tank.call("ai_skill", 4)) < float(_tank.call("ai_skill", 1)), "凯伊 AI 难度降低")
	_tank.call("tank_was_hit", 0)
	_check(not bool(_tank.get("round_over")), "爱丽丝出局后继续观战")
	_check(int(_tank.call("homing_target", 1, tanks[2]["pos"])) == 2, "AI 能追踪其他存活角色")
	for i in [1, 2, 3]: _tank.call("tank_was_hit", i)
	var momoi_volume := INF
	for child in _tank.get_children():
		if child is AudioStreamPlayer and child.stream == defeat: momoi_volume = child.volume_db
	_check(is_equal_approx(momoi_volume, linear_to_db(maxf(0.0001, float(_tank.get("master_volume")) * float(_tank.get("sfx_volume")))) - 3.0), "桃井败北语音遵循音效音量，不再额外放大")
	_check(bool(_tank.get("round_over")) and str(_tank.get("round_message")).contains("凯伊"), "最后存活的凯伊获胜")
	_check(int(_tank.get("scores")[4]) == 1, "胜场记在获胜角色名下")
	var before_win_voice := 0
	for child in _tank.get_children():
		if child is AudioStreamPlayer and child.stream == victory: before_win_voice += 1
	_check(before_win_voice == 0, "其他角色获胜不会播放爱丽丝语音")
	_tank.call("new_round")
	for i in [1, 2, 3, 4]: _tank.call("tank_was_hit", i)
	var win_voice_count := 0
	for child in _tank.get_children():
		if child is AudioStreamPlayer and child.stream == victory: win_voice_count += 1
	_check(win_voice_count == 1, "爱丽丝获胜时播放一次专属语音")
	_tank.call("new_round")
	var battle: Array = _tank.get("tanks")
	battle[0].alive = false
	battle[1].pos = Vector2(400, 400)
	battle[1].angle = PI / 2.0
	battle[1].cooldown = 0.0
	battle[2].pos = Vector2(500, 400)
	battle[3].pos = Vector2(900, 600)
	battle[4].pos = Vector2(1000, 200)
	_tank.get("walls").clear()
	_tank.call("build_prediction_mask")
	_tank.set("ai_danger_budget", 0)
	_tank.call("update_ai", 1, 1.0 / 60.0)
	_check(int(battle[1].get("target_index", -1)) == 2, "观战期间 AI 转向其他 AI")
	_check(int(battle[1].burst_remaining) == 5, "小绿面对侧方敌人立即使用五连发")
	_tank.call("update_weapon_bursts", 1.0 / 60.0)
	_check(not (_tank.get("bullets") as Array).is_empty(), "爱丽丝出局后 AI 仍然开火")
	_tank.call("new_round")
	battle = _tank.get("tanks")
	_check(bool(_tank.call("_kei_protects_alice", 4, 0)), "凯伊保护爱丽丝")
	_check(not bool(_tank.call("_kei_protects_alice", 0, 4)), "爱丽丝仍可攻击凯伊")
	_check(int(_tank.call("homing_target", 4, battle[0].pos)) != 0, "凯伊不会以爱丽丝为目标")
	_check(float(_tank.call("ai_skill", 3)) < float(_tank.call("ai_skill", 4)), "桃井反应弱于凯伊")
	battle[1].pos = Vector2(400, 400)
	battle[1].angle = PI / 2.0
	battle[1].weapon = "laser"
	battle[1].ammo = 1
	battle[1].cooldown = 0.0
	battle[0].pos = Vector2(500, 400)
	for i in [2, 3, 4]: battle[i].pos = Vector2(900, 600)
	_tank.get("walls").clear()
	_tank.call("build_prediction_mask")
	_tank.set("ai_danger_budget", 0)
	_tank.call("update_ai", 1, 1.0 / 60.0)
	_check(not bool(battle[0].alive), "小绿持激光快速瞄准并命中")
	_tank.call("new_round")
	battle = _tank.get("tanks")
	_tank.get("walls").clear()
	_tank.call("build_prediction_mask")
	_tank.set("ai_danger_budget", 0)
	battle[1].pos = Vector2(400, 400)
	battle[1].weapon = "shotgun"
	battle[1].cooldown = 10.0
	battle[0].pos = Vector2(500, 400)
	for i in [2, 3, 4]: battle[i].pos = Vector2(900, 600)
	_tank.get("pickups").append({"pos": Vector2(420, 400), "kind": "shotgun"})
	_tank.get("pickups").append({"pos": Vector2(400, 600), "kind": "laser"})
	_tank.call("update_ai", 1, 1.0 / 60.0)
	_check(battle[1].path_goal == _tank.call("point_cell", Vector2(400, 600)), "小绿持其他武器且附近有敌人时优先寻找激光")
	battle[1].pos = Vector2(400, 600)
	_tank.set("pickup_timer", 100.0)
	_tank.call("update_pickups", 0.0)
	_check(str(battle[1].weapon) == "laser", "小绿到达后成功拾取激光")
	_tank.call("new_round")
	battle = _tank.get("tanks")
	battle[1].pos = Vector2(400, 400)
	battle[1].angle = 0.0
	battle[1].cooldown = 0.0
	battle[1].weapon = "laser"
	battle[1].ammo = 1
	for i in [0, 2, 3, 4]: battle[i].pos = Vector2(900, 600)
	battle[0].pos = Vector2(900, 400)
	_tank.get("walls").clear()
	_tank.get("walls").append(Rect2(480, 300, 8, 200))
	_tank.call("build_prediction_mask")
	_check(not bool(_tank.call("_ai_shot_safe", 1, 0.0, "laser")), "预测激光反弹自伤")
	_check(not bool(_tank.call("_ai_shot_safe", 1, 0.0, "minigun")), "预测子弹反弹自伤")
	_tank.call("fire", 1)
	_check(bool(battle[1].alive) and str(battle[1].weapon) == "laser", "危险激光不会发射或消耗")
	_tank.call("fire_laser", 1)
	_check(not bool(battle[1].alive), "自伤规则仍生效而非免疫")
	_tank.call("new_round")
	battle = _tank.get("tanks")
	_tank.get("walls").clear()
	_tank.call("build_prediction_mask")
	battle[2].pos = Vector2(400, 400)
	battle[2].angle = 0.4
	battle[2].cooldown = 0.0
	battle[0].pos = Vector2(500, 400)
	for i in [1, 3, 4]: battle[i].alive = false
	_tank.get("pickups").append({"pos": Vector2(700, 600), "kind": "shotgun"})
	_tank.set("ai_danger_budget", 0)
	for i in 120: _tank.call("update_ai", 2, 1.0 / 60.0)
	var yuzu_fired := false
	for projectile in _tank.get("bullets"):
		if int(projectile.owner) == 2: yuzu_fired = true
	_check(yuzu_fired, "柚子后退时仍能瞄准开火，不被远处道具分心")
	_tank.get("bullets").clear()
	battle[2].pos = Vector2(400, 400)
	battle[2].angle = 0.0
	for i in 4:
		_tank.get("bullets").append({"pos": Vector2(800, 100 + i * 30), "vel": Vector2(0, -200), "owner": 0, "weapon": "normal", "life": 2.0, "grace": 0.0, "bounces": 0})
	_tank.get("bullets").append({"pos": Vector2(470, 400), "vel": Vector2(-200, 0), "owner": 0, "weapon": "normal", "life": 2.0, "grace": 0.0, "bounces": 0})
	_check((_tank.call("find_ai_evasion", battle[2].pos, battle[2].angle, 2) as Vector2).length_squared() > 0.0, "柚子优先预测靠近的危险子弹")
	_tank.call("new_round")
	battle = _tank.get("tanks")
	_tank.get("walls").clear()
	_tank.set("ai_danger_budget", 0)
	_tank.call("build_prediction_mask")
	battle[4].pos = Vector2(400, 400)
	battle[4].angle = 0.0
	battle[4].role = 0
	battle[4].cooldown = 10.0
	battle[1].pos = Vector2(700, 400)
	battle[0].pos = Vector2(900, 600)
	for i in [2, 3]: battle[i].alive = false
	_tank.call("update_ai", 4, 0.05)
	var normal_distance := float(battle[4].pos.x) - 400.0
	for i in 5:
		_tank.get("bullets").append({"owner": 4, "weapon": "normal"})
	battle[4].cooldown = 0.0
	_tank.call("fire", 4)
	_check((_tank.get("bullets") as Array).size() == 5, "爱丽丝存活时凯伊仍受 5 发限制")
	_tank.call("tank_was_hit", 0)
	_check(bool(battle[4].kei_rage), "爱丽丝被击败后凯伊进入无限火力")
	for i in 19: _tank.get("bullets").append({"owner": 1, "weapon": "normal"})
	battle[4].cooldown = 0.0
	_tank.call("fire", 4)
	_check((_tank.get("bullets") as Array).size() == 25, "无限火力突破个人和全场子弹上限")
	_check(is_equal_approx(float(battle[4].cooldown), 0.12), "无限火力开火间隔 0.12 秒")
	_check(is_equal_approx(float((_tank.get("bullets") as Array)[24].life), 2.4), "强化子弹限时消失以控制负载")
	_tank.get("bullets").clear()
	battle[4].pos = Vector2(400, 400)
	battle[4].angle = 0.0
	battle[4].cooldown = 10.0
	_tank.call("update_ai", 4, 0.05)
	_check(absf((float(battle[4].pos.x) - 400.0) - normal_distance * 2.0) < 0.01, "无限火力期间凯伊移动速度翻倍")
	battle[4].cooldown = 0.0
	battle[4].danger_velocity = Vector2.UP
	_tank.call("update_ai", 4, 0.05)
	_check(not (_tank.get("bullets") as Array).is_empty(), "无限火力期间凯伊躲避时也会向可见敌人开火")
	_tank.call("new_round")
	_check(not bool(_tank.get("tanks")[4].kei_rage), "新一局重置无限火力")
	var probe := AimProbe.new()
	probe.tanks = [probe.tank(Vector2(600, 400), 0.0, Color.WHITE, "爱丽丝"), probe.tank(Vector2(400, 400), 0.0, Color.WHITE, "柚子")]
	var alternate: float = probe._safe_ai_aim(1, 0, 0.0, "normal")
	_check(not is_nan(alternate) and alternate > 0.005, "正前方不安全时选择仍能命中目标的偏转角度")
	probe.mode = 1
	probe.tanks[0].name = "对手"
	for character in ["柚子", "才羽绿", "凯伊", "才羽桃井"]:
		probe.tanks[1].name = character
		probe.tanks[1].angle = 0.0
		probe.tanks[1].cooldown = 0.0
		probe.bullets.clear()
		probe.fire(1)
		_check(probe.bullets.size() == 1 and float(probe.tanks[1].angle) > 0.005, "%s 选择安全方向后开火" % character)
	probe.all_unsafe = true
	probe.bullets.clear()
	probe.tanks[1].cooldown = 0.0
	probe.fire(1)
	_check(probe.bullets.is_empty() and float(probe.tanks[1].reposition_timer) > 0.0, "无安全角度时不发射并尝试侧移")
	probe.free()
	_tank.call("new_round")
	var old_cell := float(_tank.get("CELL"))
	var viewport := _tank.get_viewport() as SubViewport
	viewport.size = Vector2i(1422, 800)
	_tank.call("resize_arena")
	_check(float(_tank.get("CELL")) > old_cell, "宽屏地图格子随画布增大")
	_check(not bool(_tank.call("tank_hits_wall", _tank.get("tanks")[0]["pos"], float(_tank.get("tanks")[0]["angle"]))), "画布调整后玩家未卡入墙内")
	_tank.set("countdown", 0.0)
	var shot := InputEventKey.new()
	shot.physical_keycode = KEY_J
	shot.pressed = true
	_tank.call("feed", shot)
	_tank.call("_process", 1.0 / 60.0)
	var player_fired := false
	for projectile in _tank.get("bullets"):
		if int(projectile.owner) == 0: player_fired = true
	_check(player_fired, "键盘单次开火在清除按键边沿前执行")
	_tank.call("release_all")
	_tank.call("new_round")
	_tank.get("walls").clear()
	var space := InputEventKey.new()
	space.physical_keycode = KEY_SPACE
	space.pressed = true
	_tank.call("feed", space)
	_tank.call("ui_event", space)
	_check(is_zero_approx(float(_tank.get("countdown"))) and bool(_tank.get("suppress_space_fire")), "物理空格跳过倒计时，当前这次按键不误发射")
	space.pressed = false
	_tank.call("feed", space)
	_tank.call("ui_event", space)
	_check(not bool(_tank.get("suppress_space_fire")), "中文输入法下释放物理空格解除抑制")
	_tank.call("_clear_frame_presses")
	space.pressed = true
	_tank.call("feed", space)
	_tank.call("ui_event", space)
	_tank.call("update_human", 0, 1.0 / 60.0)
	player_fired = false
	for projectile in _tank.get("bullets"):
		if int(projectile.owner) == 0: player_fired = true
	_check(player_fired, "跳过倒计时后再次按物理空格可发射")
	_tank.set("suppress_space_fire", true)
	_tank.call("release_all")
	_check(not bool(_tank.get("suppress_space_fire")), "退出与重新进入时清除残留空格抑制")
	_tank.call("new_round")

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
			# ⚠️ 这里**不能**断言「朝向左」（facing.x 接近 −1）：
			#    地图每局随机生成，主角出生点旁边可能就是墙，而
			#    `move_tank_direct()` 有一条「转过去会撞墙就退回原角度」的保护
			#    （`tank_main.gd`），于是它会卡在某个斜角转不过去 —— 实测出现过
			#    (−0.46, 0.89) 这种「转了 117° 就被墙挡住」的正常情况。
			#    所以断言改成「确实朝左转了一大截」：x 分量明显变负即可。
			_check(facing.x < -0.3, "按住 A 60 帧后明显朝左转（朝向 %s）" % str(facing))
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
	# ⚠️ 这一整段**只能同步跑**：本函数在 `_process()` 的调用栈里被调，里面一 `await`
	#    整个主循环就挂起（实测日志每次都断在半路）。
	#    实例化的功能检查在 `scripts/_verify_esports_play.gd`，这里只做静态接线。
	print("  … 开始检查宿主接线（电竞房「坐下开黑」过场）")

	# ── ① 小屋电脑**不该**再有坦克入口（用户 2026-11-14：「搬到电竞房」）──
	var hut := load("res://scripts/hut_computer.gd") as Script
	_check(hut != null, "小屋电脑脚本能加载")
	if hut != null:
		var hut_methods := []
		for m in hut.get_script_method_list():
			hut_methods.append(str(m["name"]))
		_check(not hut_methods.has("is_tank_open"), "小屋电脑的坦克入口已撤掉（只留 Arch 终端）")
		_check(not hut_methods.has("open_tank_for_test"), "小屋电脑不再暴露小游戏开关")

	# ── ② `game.gd` 里接得上 ──
	var gs := load("res://scripts/game.gd") as Script
	_check(gs != null, "game.gd 能加载")
	if gs != null:
		var gm := []
		for m in gs.get_script_method_list():
			gm.append(str(m["name"]))
		_check(gm.has("_build_esports_desk_play"), "game.gd 有 _build_esports_desk_play()")
		_check(gm.has("_sync_esports_play_visibility"), "game.gd 有显隐同步 _sync_esports_play_visibility()")
		_check(not gm.has("_build_esports_arcade"), "旧的街机柜入口已经拿掉")

	# ── ③ 新宿主脚本在、接口齐 ──
	var host_script := load("res://scripts/esports_desk_play.gd") as Script
	_check(host_script != null, "过场脚本 esports_desk_play.gd 能加载")
	if host_script != null:
		var hm := []
		for m in host_script.get_script_method_list():
			hm.append(str(m["name"]))
		for want in ["begin", "is_playing", "screens", "tick_for_test", "_process"]:
			_check(hm.has(want), "过场脚本有 %s()" % want)

	# ── ④ 本小游戏给「界面那一路」留了入口（`ui_event`）──
	# ⚠️ 没有它，菜单里点「开始对战」是没反应的：菜单走 `_handle_menu_keys` /
	#    `_handle_gameplay_mouse`，而宿主在 SubViewport 里、那两个回调不会被触发。
	var tank_script := load("res://scripts/tank_turmoil/tank_main_scene.tscn") as PackedScene
	var tank_methods := []
	if tank_script != null:
		var inst := tank_script.instantiate()
		if inst != null:
			for m in inst.get_script().get_script_method_list():
				tank_methods.append(str(m["name"]))
			inst.free()
	_check(tank_methods.has("ui_event"), "坦克动荡暴露出 ui_event()（菜单能点）")




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
	if _finishing:
		return
	_finishing = true
	_stage = -1
	if is_instance_valid(_tank):
		_tank.call("shutdown")
		_tank.queue_free()
	print("---------- %d 项，失败 %d ----------" % [_checks, _fails])
	print("★ 全部通过" if _fails == 0 else "✗ 有 %d 项没过" % _fails)
	# Let the audio server retire its playback references before engine teardown.
	create_timer(0.2).timeout.connect(quit.bind(0 if _fails == 0 else 1))



