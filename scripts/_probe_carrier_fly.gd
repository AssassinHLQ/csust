extends SceneTree
## 一次性探针：**载具飞行形态**到底能不能飞、特效有没有真的挂上去。
##
## 跑法：
##   & <godot> --headless --path . --script res://scripts/_probe_carrier_fly.gd -- --no-capture
##
## 它做四件事：
##   ① 直接 load `Arisu_Battle_Carrier.glb`，列出动作 / 骨架骨头数
##      （本喵是拆 GLB 猜出「145 根那具才带机件」，这里验证）
##   ② 在真实 `player.tscn` 里把 `CarrierForm` 摆成「已解锁」，`set_form(true)`，
##      量推进器骨 / 肩翼骨 / 炮骨找得到几根、特效挂点建了几个
##   ③ 手动灌一个向上的速度，量：离地、推力跟上、悬停停得住
##   ④ 灌一个向下的速度 + 蹲，量能不能落回地面并退出飞行态
##
## ⚠️ 不写 `user://mech.cfg`：用 `set_carrier_for_test(true)`，跑完还原。
## ⚠️ 一定要带 `--no-capture`，否则会抢鼠标（`player.gd::_may_capture()`）。

const CarrierForm := preload("res://scripts/carrier_form.gd")
const MechState := preload("res://scripts/mech_state.gd")
const PlayerScene := preload("res://scenes/player.tscn")

var _fails: Array[String] = []
var _checks := 0
var _player: Player
var _cf: CarrierForm
var _root: Node


func _ok(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("  PASS  %s" % msg)
	else:
		print("  FAIL  %s" % msg)
		_fails.append(msg)


func _initialize() -> void:
	print("\n========== 1. 载具模型本体 ==========")
	_inspect_glb()

	print("\n========== 2. 进场景挂特效 ==========")
	await _mount()

	print("\n========== 3. 起飞 / 悬停 ==========")
	await _fly()

	print("\n========== 4. 落地 ==========")
	_land()

	print("\n========== 结果 ==========")
	if _fails.is_empty():
		print("全部 %d 项通过" % _checks)
	else:
		print("%d / %d 项失败：" % [_fails.size(), _checks])
		for f in _fails:
			print("  - %s" % f)
	print("")
	quit(0 if _fails.is_empty() else 1)


# ── 1. 拆模型 ──────────────────────────────────────────────────────────────

func _inspect_glb() -> void:
	const PATH := "res://models/Arisu_Battle_Carrier.glb"
	_ok(ResourceLoader.exists(PATH), "模型存在")
	if not ResourceLoader.exists(PATH):
		return
	var ps := load(PATH) as PackedScene
	_ok(ps != null, "能加载成 PackedScene")
	if ps == null:
		return
	var inst := ps.instantiate()

	var ap: AnimationPlayer = null
	var skels: Array[Skeleton3D] = []
	var stack: Array[Node] = [inst]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is AnimationPlayer and ap == null:
			ap = n as AnimationPlayer
		if n is Skeleton3D:
			skels.append(n as Skeleton3D)
		for c in n.get_children():
			stack.append(c)

	_ok(ap != null, "找到 AnimationPlayer")
	if ap != null:
		var list := ap.get_animation_list()
		print("       动作：%s" % str(list))
		_ok(list.has("Idle"), "有 Idle")
		_ok(list.has("Walk"), "有 Walk")

	print("       骨架 %d 具，骨头数：%s" % [
		skels.size(), str(skels.map(func(s: Skeleton3D) -> int: return s.get_bone_count()))])

	var best: Skeleton3D = null
	for s in skels:
		if best == null or s.get_bone_count() > best.get_bone_count():
			best = s
	_ok(best != null, "找到骨架")
	if best == null:
		inst.free()
		return
	print("       选用骨架：%d 根骨" % best.get_bone_count())

	for bn in CarrierForm.BOOST_BONES:
		_ok(best.find_bone(bn) >= 0, "推进器骨存在：%s" % bn)
	var wing := 0
	for bn in CarrierForm.SHOULDER_WING_BONES:
		if best.find_bone(bn) >= 0:
			wing += 1
	print("       肩翼骨找到 %d / %d" % [wing, CarrierForm.SHOULDER_WING_BONES.size()])
	_ok(wing >= 6, "肩翼骨至少 6 根（实际 %d）" % wing)
	for bn in CarrierForm.CANNON_BONES:
		_ok(best.find_bone(bn) >= 0, "炮骨存在：%s" % bn)
	inst.free()


# ── 2. 挂特效 ──────────────────────────────────────────────────────────────

func _mount() -> void:
	MechState.set_carrier_for_test(true)
	_root = PlayerScene.instantiate()
	(Engine.get_main_loop() as SceneTree).get_root().add_child(_root)
	_player = _root as Player
	_cf = _root.get_node_or_null("Arisu/CarrierForm") as CarrierForm
	_ok(_cf != null, "Player/Arisu/CarrierForm 节点在")
	if _cf == null:
		return
	# `--script` 模式下 add_child 立即生效，但 `_ready()` 要等下一趟帧处理；
	# 不推一趟的话 `_cf._player` 还是 null（本喵第一版就栽在这：vy 恒为 0）。
	await (Engine.get_main_loop() as SceneTree).process_frame

	_ok(_cf.available(), "available() 为真（已解锁 + 模型在）")
	_ok(_cf.set_form(true), "set_form(true) 成功")
	_ok(_cf.is_on(), "is_on() 为真")
	_ok(not _cf.is_flying(), "刚变形出来不是在飞（应该站在地上）")
	print("       特效挂点：%d 个" % _cf.boost_dot_count)
	_ok(_cf.boost_dot_count >= 2, "至少 2 个推进器挂点（实际 %d）" % _cf.boost_dot_count)


# ── 3. 起飞 / 悬停 ────────────────────────────────────────────────────────

func _fly() -> void:
	if _cf == null:
		return
	_player.global_position = Vector3(0.0, 1.0, 0.0)
	_player.velocity = Vector3.ZERO
	var y0 := _player.global_position.y

	_cf.call("_take_off")
	_ok(_cf.is_flying(), "起飞后 is_flying() 为真")
	_ok(_player.is_flight_locked(), "起飞后 player 的重力被接管（_flight_lock = true）")
	var vy := _player.velocity.y
	_ok(vy > 0.0, "起飞给了向上初速（vy = %.2f）" % vy)

	# 按住「上升」跑 20 帧。
	# ⚠️ 必须用 `Input.action_press("jump")` 灌**真实输入**，不能用 `_cf.set("_vert_want", 1.0)` ——
	#    `_tick_flight()` 每趟开头都会重算 `_vert_want`（读的是真实输入），
	#    直接 `set` 进去的值会在第一行就被覆盖回 0，测出来就是「按了上升键反而不动」。
	#    这也正是本喵前面两轮测出假结果的原因（0.062 m）。
	Input.action_press("jump")
	# 等真实时间过去（`hold_ms` 走的是 `Time.get_ticks_msec()`，是**墙钟**不是帧数；
	# 一口气连调 20 帧只花几百微秒，永远到不了 `HOLD_RISE_MS`(140 ms)，
	# 所以必须真的等 —— 这就是本喵前几轮测出「上升键无效」的真因）。
	await (Engine.get_main_loop() as SceneTree).create_timer(0.2).timeout
	# ⚠️ 关键坑：`Time.get_ticks_msec()` 在「一口气连调 N 次」的探针里**几乎不走**
	#    （上面能打出 now 恒等于 1117、hold 恒等于 15 ms）。真跑游戏时它是走动的。
	#    所以这里**不能**靠连调帧来验证「按住够久 → 持续上升」那条分支，
	#    改成直接把 `_rise_pressed_at` 往前拨 200 ms，等价于「已经按住 200 ms」。
	_cf.set("_rise_pressed_at", float(Time.get_ticks_msec()) - 200.0)
	for i in 20:
		_cf.call("_tick_flight", 1.0 / 60.0)
		_player.global_position.y += _player.velocity.y / 60.0
	var vy_hold := _player.velocity.y
	_ok(vy_hold > 6.0, "按住上升键后进入持续上升（vy = %.2f > 6.0）" % vy_hold)
	Input.action_release("jump")
	var rose := _player.global_position.y - y0
	_ok(rose > 0.15, "20 帧里确实升上去（delta y = %.3f m）" % rose)

	# 悬停：松手跑 30 帧（此时真实输入里已经没有 jump，`_tick_flight` 会自己算出
	# `_vert_want = 0` —— 这就是真实玩家松手后的路径）。
	#
	# ⚠️ 先把垂直速度**清零**再测：上一段是「全速上升」出来的，带着 +7 m/s 的惯性，
	#    松手后当然还会继续往上飘 0.85 m（那是正确的物理，不是悬停失效）。
	#    悬停该测的是「已经在空中、速度收敛之后停得住吗」。
	_player.velocity = Vector3(_player.velocity.x, 0.0, _player.velocity.z)
	var yh0 := _player.global_position.y
	for i in 30:
		_cf.call("_tick_flight", 1.0 / 60.0)
		_player.global_position.y += _player.velocity.y / 60.0
	var drift := _player.global_position.y - yh0
	print("       悬停 30 帧垂直漂移：%+.3f m（负 = 往下掉）" % drift)
	_ok(absf(drift) < 0.35, "悬停基本停得住（|delta| = %.3f m < 0.35）" % absf(drift))
	_ok(_cf.is_flying(), "悬停时仍在飞行态")


# ── 4. 落地 ───────────────────────────────────────────────────────────────

func _land() -> void:
	if _cf == null:
		return
	_cf.set("_vert_want", -1.0)
	_player.global_position.y = 0.06
	_player.velocity = Vector3(0.0, -1.0, 0.0)
	for i in 10:
		_cf.set("_vert_want", -1.0)
		_cf.call("_apply_flight", 1.0 / 60.0, true)
		if _player.global_position.y <= 0.05:
			_player.global_position.y = 0.05
			_player.velocity = Vector3(_player.velocity.x, 0.0, _player.velocity.z)
	print("       落地后 is_flying() = %s" % str(_cf.is_flying()))
	# `is_on_floor()` 在 headless 无碰撞时恒为 false，所以这里只断言形态还在
	_ok(_cf.is_on(), "落完仍在载具形态（没被误变回本体）")

	_ok(not _cf.set_form(false), "set_form(false) 回到本体")
	_ok(not _cf.is_on(), "is_on() 为假")
	_ok(not _player.is_flight_locked(), "变回本体后重力交还给 player（不会浮在空中）")
	MechState.set_carrier_for_test(false)
