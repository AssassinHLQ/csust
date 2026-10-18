extends SceneTree
## 探针：**「先开火一次，再走路」——按用户的原话复现**。
##
## 目标（本轮）：`先开火一次，在走路就变成这样子右侧身子螃蟹平移`
##
## 之前所有探针都是「先走路、再开火」，而用户的操作是相反的：
##   **站着 → 点一下开火 → 再开始走**。
## 这两条路在代码里完全不是一条：
##   · 走着开火 → `_fire_while_walking()`（基础层留在 `Move_Ing`，走的是 `_walk_fire`）
##   · 站着开火 → `_play_once("Normal_Attack_Ing")`（**叠加层** `UpperBody`），
##     中途起步还会被 `_migrate_upper_layer()` 搬到 `UpperBodyMove`
## 所以必须按「站 → 开火 → 走」的顺序量。
##
## 每行打：状态机全部内部标志 + 基础层 clip + 叠加层 clip + 姿态读数。
## 只要出现「state=Fire 却已经不该在开火」，或者「clip=Move_Ing 停不下来」，
## 就是用户看到的那个「一直螃蟹」。
##
## 用法：
##   godot --path <工程> --headless --script res://scripts/_probe_fire_then_walk.gd -- --splat=off

const SPOT := Vector3(-14.0, 0.1, -12.0)

var _p: Player
var _anim: AnimDriver
var _wpn: Weapon
var _sk: Skeleton3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 14:
		await process_frame
	paused = false
	_p = game.get_node_or_null("Player") as Player
	_anim = _p.anim as AnimDriver
	_sk = _anim.skeleton
	_wpn = game.get_node_or_null("Player/Weapon") as Weapon
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("[probe] mouse_mode 设成 CAPTURED 后读回 = %d（3 = CAPTURED）" % Input.mouse_mode)
	_p.global_position = SPOT
	await _frames(10)

	print("\n========== A. 站着点一下 → 再走路（用户原话）==========")
	await _seq(false)

	print("\n========== B. 走着点一下 → 继续走（对照组）==========")
	await _seq(true)

	quit(0)


func _seq(walk_first: bool) -> void:
	_anim.reset_state()
	_p.velocity = Vector3.ZERO
	_release_walk()
	await _frames(30)
	if walk_first:
		Input.action_press("move_forward")
		await _frames(60)
	_row(0, "起手")
	# 点一下：按下 6 帧再松开（≈0.1 s，一发的量）
	_click(true)
	await _frames(6)
	_row(6, "按下中")
	_click(false)
	_row(7, "刚松开")
	# 松开之后就**走路**（站着开火的话这里是「攻击演到一半开始走」）
	for i in 6:
		if i == 0 and not walk_first:
			Input.action_press("move_forward")
		await _frames(15)
		_pin()
		_row((i + 1) * 15 + 7, "松手后")
	# 再走 3 秒，看会不会永远停在某个状态
	for i in 6:
		await _frames(30)
		_pin()
		_row(97 + (i + 1) * 30, "继续走")
	_release_walk()
	await _frames(20)
	_row(999, "停下")


func _click(down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = down
	ev.position = Vector2(640, 360)
	Input.parse_input_event(ev)
	# 兜底：万一 `_input` 因为 mouse_mode 没拿到事件，直接走玩家那两条同样的路径
	if down:
		if not _p.get("_fire_held"):
			_p.set("_fire_held", true)
			_wpn.trigger_down()
	else:
		_p.set("_fire_held", false)
		_wpn.trigger_up()


func _row(f: int, tag: String) -> void:
	var tilt := _shoulder_tilt()
	var lyr := _anim.active_upper_layer()
	var lname := "无" if lyr == null else String(lyr.name)
	print("  [%3s 帧] %-8s state=%-10s base=%-13s upper=%-18s walk_fire=%s runfire=%s "
		% [str(f), tag, _anim.current_state_name(), _anim.current_clip(),
		"%s@%s" % ["无" if _anim.upper_clip() == "" else _anim.upper_clip(), lname],
		str(_anim.get("_walk_fire")), str(_anim.get("_runfire_playing"))] +
		"auto=%s trig=%s held=%s ss=%.2f spd=%.2f 肩线 %+5.1f° 枪骨缩 %.2f" % [
		str(_anim.get("_auto_return")), str(_wpn.get("_trigger")), str(_p.get("_fire_held")),
		_anim.player.speed_scale, _speed(), tilt, _weapon_scale()] +
		" migr=%d" % int(_anim.migrations))


func _shoulder_tilt() -> float:
	var l := _sk.find_bone("Bip001 L UpperArm")
	var r := _sk.find_bone("Bip001 R UpperArm")
	if l < 0 or r < 0:
		return 999.0
	var wl: Vector3 = _sk.global_transform * _sk.get_bone_global_pose(l).origin
	var wr: Vector3 = _sk.global_transform * _sk.get_bone_global_pose(r).origin
	var v := _p.model_root.global_transform.basis.inverse() * (wl - wr)
	return rad_to_deg(atan2(v.y, maxf(Vector2(v.x, v.z).length(), 0.0001)))


func _weapon_scale() -> float:
	var i := _sk.find_bone(AnimDriver.GUN_BONE)
	if i < 0:
		return 0.0
	var b: Basis = (_sk.global_transform * _sk.get_bone_global_pose(i)).basis
	return b.get_scale().length() / sqrt(3.0)


func _speed() -> float:
	return Vector2(_p.velocity.x, _p.velocity.z).length()


func _pin() -> void:
	if _p == null or not _p.is_inside_tree():
		return
	if _p.global_position.y < SPOT.y:
		_p.global_position = SPOT
	else:
		_p.global_position = Vector3(SPOT.x, _p.global_position.y, SPOT.z)


func _release_walk() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "sprint", "crouch"]:
		Input.action_release(a)


func _frames(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
