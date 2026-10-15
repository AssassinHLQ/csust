extends SceneTree
## 验「移动手感」：把用户报的六条主观感受**量成可以断言的数字**。
##
##   1. 速度      —— 四个方向的稳态速度
##   2. 加速度    —— 静止 → 90% 满速要多久；松开 → 停下要多久
##   3. 跳跃      —— 峰值高度与滞空时间
##   4. 机动性    —— 空中能不能修正落点（`ACCEL_AIR`）
##   5. **往后也能跑** —— 用户报的 bug：`move_back` 的 `input.y` 是 **+1**，
##                     被 `sprinting` 里一句 `input.y < 0.1` 挡掉了，按 S 永远拿不到跑速
##   6. 转向灵活性 —— 换向多久收到 5° 以内；而且**朝输入方向**转，不是等速度拐过去
##
## 用法：
##   godot --path <工程> --script res://scripts/_verify_move_feel.gd -- --splat=off
##
## ⚠️ 三条纪律：
##   · **等真实时间，不等帧数**：真渲染窗口能跑到 1000+ fps，「等 60 帧」可能只有
##     16 ms（README §1.11 那条坑）。这里所有等待都按 `Time.get_ticks_msec()`。
##   · 开局把鼠标设成 `VISIBLE`：`player._input` 只在 CAPTURED 时吃鼠标移动，
##     这样跑自检时有人碰鼠标也不会把视角带歪、把转向测量搞脏。
##   · 每节开始都 `_reset()` 把人和视角摆回出生点：不然十几项测下来会漂出平台。
##
## 结论会打一张「手感一览」表 —— 这张表才是这一套的主要产出，断言只是守门。

const SPAWN := Vector3(0, 0.05, 6)
## 稳态速度的容许误差（米/秒）
const SPEED_TOL := 0.15
## `anim_driver.gd` 的走路 / 跑步动画分界。**必须大于 SPEED_WALK**，否则走路会播跑。
## 这里写死复制一份是故意的：它跨文件，改动时两边都得看一眼（自检就是那个「看一眼」）。
const ANIM_WALK_THRESHOLD := 2.8

var _fail := 0
var _pass := 0
var _p: Player
## 量出来的手感数值，最后打表用
var _m := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(10)
	_p = game.get_node_or_null("Player") as Player
	if _p == null:
		print("!! 场景里没有 Player")
		quit(1)
		return
	# 见文件头第 2 条：别让人碰鼠标把视角带歪
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	await _test_speeds()
	await _test_accel_brake()
	await _test_jump()
	await _test_air_control()
	await _test_turning()
	await _test_relation()
	await _wait(2)

	print("\n================ 结果 ================")
	print("通过 %d 项" % _pass)
	_print_table()
	_quit()


# --- 1. 四个方向的稳态速度 ----------------------------------------------------

func _test_speeds() -> void:
	print("========== 1. 稳态速度（四个方向，都按住 Shift）==========")
	# 用户报的「往后走不能跑步」就在这里：以前 `move_back` 只有走路速度 2.0
	for a in [["move_forward", "前进"], ["move_back", "后退"],
			["move_left", "左移"], ["move_right", "右移"]]:
		var r := await _hold(String(a[0]), true, 500)
		_m["run_" + String(a[0])] = r["speed"]
		_check(bool(r["sprinting"]) and absf(float(r["speed"]) - Player.SPEED_RUN) < SPEED_TOL,
			"%s + Shift：sprinting=%s，速度 %.2f（期望 %.2f）"
			% [a[1], str(r["sprinting"]), r["speed"], Player.SPEED_RUN])
	# 后退是这一组的重点，单独再记一条（失败时一眼能看出是它）
	var back := float(_m["run_move_back"])
	_check(absf(back - Player.SPEED_RUN) < SPEED_TOL,
		"**后退确实拿到了跑速**（%.2f，以前这里恒为 %.2f）" % [back, Player.SPEED_WALK])

	print("\n── 不按 Shift（走路）──")
	for a in [["move_forward", "前进"], ["move_back", "后退"]]:
		var r := await _hold(String(a[0]), false, 500)
		_m["walk_" + String(a[0])] = r["speed"]
		_check(absf(float(r["speed"]) - Player.SPEED_WALK) < SPEED_TOL,
			"%s（不按 Shift）：速度 %.2f（期望 %.2f）" % [a[1], r["speed"], Player.SPEED_WALK])
	# 走路速度必须低于动画阈值，否则播的是跑步动画
	_check(Player.SPEED_WALK < ANIM_WALK_THRESHOLD,
		"走路 %.2f < 动画阈值 %.2f（否则走路会播 Move_Ing）"
		% [Player.SPEED_WALK, ANIM_WALK_THRESHOLD])


# --- 2. 加速度 / 刹车 ---------------------------------------------------------

func _test_accel_brake() -> void:
	print("\n========== 2. 加速度与刹车（按真实毫秒量）==========")
	await _reset()
	# 0 → 90% 满速
	var goal := Player.SPEED_RUN * 0.9
	Input.action_press("move_forward")
	Input.action_press("sprint")
	var t0 := Time.get_ticks_msec()
	var t_accel := -1
	while Time.get_ticks_msec() - t0 < 2000:
		await process_frame
		if _speed() >= goal:
			t_accel = Time.get_ticks_msec() - t0
			break
	_m["accel_ms"] = t_accel
	_check(t_accel >= 0 and t_accel < 400,
		"静止 → 90%% 满速（%.1f m/s）用了 %d ms（< 400）" % [goal, t_accel])

	# 满速 → 停
	var t1 := Time.get_ticks_msec()
	var t_brake := -1
	_release_all()
	while Time.get_ticks_msec() - t1 < 2000:
		await process_frame
		if _speed() < 0.1:
			t_brake = Time.get_ticks_msec() - t1
			break
	_m["brake_ms"] = t_brake
	_check(t_brake >= 0 and t_brake < 400, "松开 → 停住用了 %d ms（< 400）" % t_brake)


# --- 3. 跳跃 ------------------------------------------------------------------

func _test_jump() -> void:
	print("\n========== 3. 跳跃高度与滞空 ==========")
	await _reset()
	var y0 := _p.global_position.y
	Input.action_press("jump")
	await process_frame
	await process_frame
	Input.action_release("jump")
	var peak := y0
	var t0 := Time.get_ticks_msec()
	var landed := false
	var air_ms := 0
	while Time.get_ticks_msec() - t0 < 3000:
		await process_frame
		peak = maxf(peak, _p.global_position.y)
		var el := Time.get_ticks_msec() - t0
		if el > 250 and _p.is_on_floor():
			landed = true
			air_ms = el
			break
	var height := peak - y0
	# 理论值：v²/(2g) = 7.1²/40 = 1.26 m；滞空 2v/g = 0.71 s
	_m["jump_h"] = height
	_m["air_ms"] = air_ms
	_check(height >= 1.10, "跳跃峰值 %.2f m（≥ 1.10；理论 %.2f）"
		% [height, Player.JUMP_VELOCITY * Player.JUMP_VELOCITY / (2.0 * Player.GRAVITY)])
	_check(air_ms >= 600, "滞空 %d ms（≥ 600；理论 %d ms）"
		% [air_ms, int(2000.0 * Player.JUMP_VELOCITY / Player.GRAVITY)])
	_check(landed and absf(_p.global_position.y - y0) < 0.15,
		"落回地面（y = %.2f，出发时 %.2f）" % [_p.global_position.y, y0])


# --- 4. 空中机动 --------------------------------------------------------------

func _test_air_control() -> void:
	print("\n========== 4. 空中机动（跳起来能不能修正落点）==========")
	await _reset()
	Input.action_press("jump")
	await process_frame
	await process_frame
	Input.action_release("jump")
	await _wait_ms(220)          # 大约在上升中后段
	var vx0 := _p.velocity.x
	Input.action_press("move_left")
	await _wait_ms(200)
	var vx1 := _p.velocity.x
	_release_all()
	_m["air_vx"] = vx1
	# ACCEL_AIR=9 → 0.2 s 能改约 1.8 m/s；改之前只有 3，只能改 0.6
	_check(vx1 < -1.0, "空中按左，横向速度 %.2f → %.2f m/s（ACCEL_AIR = %.1f）"
		% [vx0, vx1, Player.ACCEL_AIR])


# --- 5. 转向灵活性 ------------------------------------------------------------

func _test_turning() -> void:
	print("\n========== 5. 转向灵活性 ==========")
	# 站定朝 −Z（_yaw = 0 → 朝向 _yaw + PI）
	await _reset()
	Input.action_press("move_right")
	var target := atan2(1.0, 0.0)             # 朝 +X：atan2(dir.x, dir.z) = PI/2
	var t0 := Time.get_ticks_msec()
	var need := -1
	while Time.get_ticks_msec() - t0 < 1000:
		await process_frame
		if _face_err_deg(target) < 5.0:
			need = Time.get_ticks_msec() - t0
			break
	_m["turn_ms"] = need
	_check(need >= 0 and need < 300, "从朝 −Z 换到朝 +X，收到 5° 以内用了 %d ms（< 300）" % need)
	_release_all()

	# 关键判据：**朝输入方向转，不是等速度拐过去**
	# 先朝 −Z 跑满速，再换 +X —— 那一刻「朝哪」和「往哪走」会分叉
	await _reset()
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _wait_ms(400)
	Input.action_release("move_forward")
	Input.action_press("move_right")
	await _wait_ms(30)
	var err_face := _face_err_deg(target)
	var vel := Vector2(_p.velocity.x, _p.velocity.z)
	var err_vel := rad_to_deg(absf(angle_difference(target, atan2(vel.x, vel.y))))
	_release_all()
	_m["lead_face"] = err_face
	_m["lead_vel"] = err_vel
	_check(err_face < err_vel - 15.0,
		"换向 30 ms 后：朝向离目标 %.0f°、速度方向还差 %.0f° → **朝向领先于速度**"
		% [err_face, err_vel])


# --- 6. 各档位速度的关系 ------------------------------------------------------

func _test_relation() -> void:
	print("\n========== 6. 蹲行 / 走路 / 开镜 / 跑步 的关系 ==========")
	var crouch := await _hold("move_forward", false, 400, "crouch")
	_m["crouch"] = crouch["speed"]
	_check(absf(float(crouch["speed"]) - Player.SPEED_CROUCH) < SPEED_TOL,
		"蹲行 %.2f（期望 %.2f）" % [crouch["speed"], Player.SPEED_CROUCH])

	await _reset()
	var aim := await _hold("move_forward", true, 400, "", true)
	_m["aim"] = aim["speed"]
	_check(absf(float(aim["speed"]) - Player.SPEED_AIM) < SPEED_TOL,
		"开镜时 %.2f（期望 %.2f；开镜时按住 Shift 也不跑）" % [aim["speed"], Player.SPEED_AIM])

	_check(Player.SPEED_CROUCH < Player.SPEED_AIM and Player.SPEED_AIM < Player.SPEED_WALK \
		and Player.SPEED_WALK < Player.SPEED_RUN,
		"档位是递增的：蹲 %.1f < 开镜 %.1f < 走 %.1f < 跑 %.1f"
		% [Player.SPEED_CROUCH, Player.SPEED_AIM, Player.SPEED_WALK, Player.SPEED_RUN])


# --- 手感一览表 ---------------------------------------------------------------

func _print_table() -> void:
	print("\n================ 手感一览（实测）================")
	print("  跑（任意方向）  %.2f m/s    ← 后退以前恒为 %.2f" % [
		float(_m.get("run_move_forward", 0.0)), Player.SPEED_WALK])
	print("    后退          %.2f m/s" % float(_m.get("run_move_back", 0.0)))
	print("    左移 / 右移   %.2f / %.2f m/s" % [
		float(_m.get("run_move_left", 0.0)), float(_m.get("run_move_right", 0.0))])
	print("  走              %.2f m/s" % float(_m.get("walk_move_forward", 0.0)))
	print("  蹲行            %.2f m/s" % float(_m.get("crouch", 0.0)))
	print("  开镜            %.2f m/s" % float(_m.get("aim", 0.0)))
	print("  0 → 90%% 满速    %d ms" % int(_m.get("accel_ms", -1)))
	print("  松开 → 停       %d ms" % int(_m.get("brake_ms", -1)))
	print("  跳跃峰值        %.2f m（滞空 %d ms）" % [
		float(_m.get("jump_h", 0.0)), int(_m.get("air_ms", 0))])
	print("  空中横改        %.2f m/s（0.2 s 内）" % float(_m.get("air_vx", 0.0)))
	print("  换向到 5°       %d ms" % int(_m.get("turn_ms", -1)))
	print("  换向 30 ms 后   朝向差 %.0f° / 速度差 %.0f°" % [
		float(_m.get("lead_face", 0.0)), float(_m.get("lead_vel", 0.0))])


# --- 工具 ---------------------------------------------------------------------

func _speed() -> float:
	return Vector2(_p.velocity.x, _p.velocity.z).length()


func _face_err_deg(target: float) -> float:
	return rad_to_deg(absf(angle_difference(target, _p.model_root.rotation.y)))


func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right",
			"sprint", "crouch", "jump"]:
		Input.action_release(a)


## 把人和视角摆回出生点，并等到真的站稳
func _reset() -> void:
	_release_all()
	_p.velocity = Vector3.ZERO
	_p.global_position = SPAWN
	_p._yaw = 0.0
	_p._facing_yaw = _p._yaw + PI
	_p.model_root.rotation.y = _p._facing_yaw
	_p._set_aiming(false)
	await _wait(3)


## 按住某个方向（可选再按住一个键 / 开镜）走 ms 毫秒，返回 {speed, sprinting}
##
## ⚠️ 开镜必须在 `_reset()` **之后**设：`_reset()` 里有一句 `_set_aiming(false)`，
##    先设会被它清掉（本喵第一版就是这样，量到「开镜 6.80 m/s」——等于没开镜）。
func _hold(action: String, sprint: bool, ms: int, extra := "", aim := false) -> Dictionary:
	await _reset()
	if aim:
		_p._set_aiming(true)
	Input.action_press(action)
	if sprint:
		Input.action_press("sprint")
	if extra != "":
		Input.action_press(extra)
	await _wait_ms(ms)
	var r := {"speed": _speed(), "sprinting": _p.sprinting}
	_release_all()
	if aim:
		_p._set_aiming(false)
	await _wait(2)
	return r


func _wait_ms(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame


func _check(cond: bool, label: String) -> void:
	print("  [%s] %s" % ["PASS" if cond else "FAIL", label])
	if cond:
		_pass += 1
	else:
		_fail += 1


func _quit() -> void:
	print("失败 %d 项" % _fail)
	quit(1 if _fail > 0 else 0)


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
