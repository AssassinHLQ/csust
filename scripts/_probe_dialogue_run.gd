extends SceneTree
## 探针：对话期间角色是不是还在「原地跑步」。
##
## 用户报「对话时还在跑步」。机理怀疑：`dialogue_box.gd` 开播就 `get_tree().paused = true`，
## 玩家物理停了（位置冻住），但 `anim_driver.gd::_keep_alive_when_paused()` 把 AnimationPlayer
## 设成 ALWAYS（为了让待机呼吸继续播）——于是开播前正在播的 `Move_Ing` / `Cafe_Walk`
## 会**原地循环整段对话**，暂停期间没人调 `set_locomotion`，状态机切不回待机。
##
## 这里量四件事（跑动 / 走路两种起手各一遍）：
##   ① 对话期间世界确实暂停、玩家位置确实冻住（排除「真的在移动」）
##   ② 对话期间基础层播的是哪条 clip、speed_scale 多少
##   ③ 动画相位有没有继续推进（移动 clip + 相位推进 = 原地跑的铁证）
##   ④ 对话结束、松开键后能不能正常回待机
##
## 用法：_tools/run_probe.sh res://scripts/_probe_dialogue_run.gd -- --splat=off --story=off

const GAME := "res://scenes/game.tscn"
const SPAWN := Vector3(0, 0.05, 6)

var _fail := 0
var _pass := 0
var _p: Player
var _anim: Node
var _box: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game: Node = (load(GAME) as PackedScene).instantiate()
	root.add_child(game)
	await _wait(10)
	_p = game.get_node_or_null("Player") as Player
	_box = game.get_node_or_null("DialogueBox")
	if _p == null or _box == null:
		print("!! 场景里没有 Player / DialogueBox")
		quit(1)
		return
	_anim = _p.get_node_or_null("Arisu/Model/AnimDriver")
	if _anim == null:
		print("!! 找不到 AnimDriver")
		quit(1)
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	await _case("跑动起手", true)
	await _case("走路起手", false)

	print("\n================ 结果 ================")
	print("通过 %d 项 / 失败 %d 项" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


## 一种起手：先真的跑/走起来，再开对话，量对话期间的动画与位移。
func _case(label: String, sprint: bool) -> void:
	print("\n========== %s ==========" % label)
	await _reset()
	Input.action_press("move_forward")
	if sprint:
		Input.action_press("sprint")
	await _wait_ms(600)
	var speed0 := Vector2(_p.velocity.x, _p.velocity.z).length()
	var clip0 := String(_anim.current_clip())
	print("起手：速度 %.2f m/s  clip=%s  speed_scale=%.2f" % [
		speed0, clip0, _anim.player.speed_scale])
	_check(speed0 > 1.0, "起手真的在动（%.2f m/s）" % speed0)

	# 开对话（两步台词，够量 0.6 s）
	_box.call("play_steps", [
		{"kind": "say", "who": "爱丽丝", "text": "第一句话，用来量对话期间的动画状态。"},
		{"kind": "say", "who": "爱丽丝", "text": "第二句话。"},
	], "probe_dialogue_run")
	await _wait(3)
	_check(paused, "对话期间世界已暂停")

	var pos0 := _p.global_position
	var clip_during := String(_anim.current_clip())
	var scale_during := float(_anim.player.speed_scale)
	var apos0 := float(_anim.player.current_animation_position)
	var amode := int(_anim.player.process_mode)
	# 量 0.6 s：位置漂移 + 动画相位推进 + clip 是否变化
	var clip_changed := false
	await _measure_ms(600, func() -> void:
		if String(_anim.current_clip()) != clip_during:
			clip_changed = true)
	var drift := _p.global_position.distance_to(pos0)
	var apos1 := float(_anim.player.current_animation_position)
	var advanced := apos1 - apos0
	print("对话中：clip=%s  speed_scale=%.2f  位置漂移 %.4f m  clip变过=%s" % [
		clip_during, scale_during, drift, str(clip_changed)])
	print("        动画相位 %.3f → %.3f（推进 %.3f s）  播放器process_mode=%d（3=ALWAYS）" % [
		apos0, apos1, advanced, amode])
	_check(drift < 0.02, "对话期间位置冻住（漂移 %.4f m < 0.02）" % drift)
	# 核心断言：对话期间不该还在播移动动画
	_check(clip_during == "Normal_Idle",
		"对话期间播待机（实际 %s）%s" % [clip_during,
			"← **还在原地跑**" if clip_during != "Normal_Idle" else ""])
	# 移动动画 + 相位推进 = 原地跑的铁证（待机呼吸也会推进相位，所以只在移动 clip 下断言）
	if clip_during != "Normal_Idle":
		_check(advanced > 0.05, "移动动画相位仍在推进（%.3f s）= 原地跑" % advanced)

	# 结束对话、松键，看能不能正常回待机
	_box.call("finish")
	_release_all()
	await _wait_ms(400)
	_check(not paused, "对话结束后世界恢复")
	var clip_after := String(_anim.current_clip())
	var speed_after := Vector2(_p.velocity.x, _p.velocity.z).length()
	print("收尾：clip=%s  速度 %.2f m/s" % [clip_after, speed_after])
	_check(clip_after == "Normal_Idle", "松键后回待机（实际 %s）" % clip_after)
	_check(speed_after < 0.2, "松键后停下（%.2f m/s）" % speed_after)


func _measure_ms(ms: int, tick: Callable) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame
		tick.call()


func _reset() -> void:
	_release_all()
	_p.velocity = Vector3.ZERO
	_p.global_position = SPAWN
	_p._yaw = 0.0
	_p._facing_yaw = PI
	_p.model_root.rotation.y = PI
	await _wait(3)


func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "sprint", "crouch", "jump"]:
		Input.action_release(a)


func _check(cond: bool, label: String) -> void:
	print("  [%s] %s" % ["PASS" if cond else "FAIL", label])
	if cond:
		_pass += 1
	else:
		_fail += 1


func _wait_ms(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame