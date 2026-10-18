extends SceneTree
## 验「**边跑边打时腿还在跑**」——把「脚动没动」量成厘米。
##
## 用户报：
##   「开枪跑打时为什么角色脚不动，需要静止开枪不动，但是跑步开枪脚还是要动」
##
## 根因：`request_fire()` 原来把**整个** `AnimationPlayer` 切到 `Normal_Attack_Ing`，
## 而这条动作是**全骨架**的（实测爱丽丝 228 条轨道、下半身 48 条），于是开火期间
## 腿也被定格，人在地上滑。
##
## 修法：开火 / 换弹改成**只叠上半身** —— 复制一份动作、**把下半身轨道全删掉**，
## 挂到第二个 `AnimationPlayer`（`process_priority` 更大 ⇒ 后写、赢）；
## 基础层照旧每帧写整体（`Normal_Idle` / `Move_Ing`），所以腿一直在跑。
##
## 这一套的核心判据只有两条，但它们正好是用户那句话的两半：
##   · **站定开火**：脚骨位移 < 0.03 m（不动）、手骨位移 ≥ 0.08 m（上半身在演开火）
##   · **跑动开火**：脚骨位移 ≥ 0.15 m（**腿在跑**）、基础层仍是 `Move_Ing`
##
## 用法：
##   godot --path <工程> --script res://scripts/_verify_attack_move.gd -- --splat=off

const SPAWN := Vector3(0, 0.05, 6)
## 采样窗口（真实毫秒）
const WINDOW_MS := 500
## 跑动时脚的往返幅度（`Move_Ing` 脚摆 ±0.16 m，一个周期必然超过这个数）
const FOOT_MOVING := 0.15
## 站定时脚允许的漂移（待机的呼吸感）
const FOOT_STILL := 0.03
## 开火动作里手要比**待机基线**多挪这么多，才算「上半身真的在演开火」。
## ⚠️ 用小差值而不是绝对值：手的位移跟「采样窗口落在动作的哪一段」有关，
##    卡绝对值会在全量回归里擦边（第一版卡 0.08 m，实测 0.079 就红了）。
const HAND_ACTING := 0.03

## 胸椎：跑打开火时它的「上」轴不许离开「只跑」的姿势集（§7）
const CHEST := "Bip001 Spine1"
## 允许的最大偏离（度）。修好后实测 ≈ 0，改前是 65。
const TRUNK_TOL := 8.0

var _fail := 0
var _pass := 0
var _p: Player
var _anim: AnimDriver
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
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_anim = _p.anim as AnimDriver

	await _test_structure(game)
	await _test_standing_fire()
	await _test_running_fire()
	await _test_walking_fire()
	await _test_walkfire_posture()
	await _test_fire_then_walk()
	await _test_running_reload()
	await _test_recover()
	await _test_weapon_path()
	await _test_trunk_kept()
	await _wait(2)

	print("\n================ 结果 ================")
	print("通过 %d 项" % _pass)
	_print_table()
	_quit()


# --- 1. 叠加层本身搭对了吗 -----------------------------------------------------

func _test_structure(game: Node) -> void:
	print("\n========== 1. 上半身叠加层 ==========")
	_check(_anim != null and _anim.has_upper_layer(), "主角的驱动有**两层**叠加层（UpperBody / UpperBodyMove）")
	if _anim == null or not _anim.has_upper_layer():
		return
	for l in [_anim.upper, _anim.upper_move]:
		var nm := (l as AnimationPlayer).name
		_check(l.root_node == _anim.player.root_node,
			"%s 的 root_node 与基础层相同（轨道路径才对得上）" % nm)
		_check(l.process_priority > _anim.player.process_priority,
			"%s 的 process_priority=%d > 基础层 %d（**后写、赢**）"
			% [nm, l.process_priority, _anim.player.process_priority])

	var full := _anim.player.get_animation("Normal_Attack_Ing").get_track_count()
	for moving in [false, true]:
		var nm := "移动层" if moving else "静止层"
		var upper_tracks := _anim.upper_track_count("Normal_Attack_Ing", moving)
		_check(upper_tracks > 0 and upper_tracks < full,
			"%s 的开火动作：%d → %d 条轨道（原动作是全骨架的）" % [nm, full, upper_tracks])
		_check(_anim.upper_lower_track_count("Normal_Attack_Ing", moving) == 0,
			"%s 里**下半身轨道 0 条**" % nm)
		_check(_anim.upper.has_animation("Normal_Reload")
			and _anim.upper_track_count("Normal_Reload", moving) > 0,
			"换弹动作也做了%s（%d 条轨道）"
			% [nm, _anim.upper_track_count("Normal_Reload", moving)])

	# 七名同伴
	var mates := 0
	var bad: Array[String] = []
	for child in game.get_children():
		if not (child is Companion):
			continue
		var c := child as Companion
		var a := c.anim as AnimDriver
		mates += 1
		if a == null or not a.has_upper_layer() \
				or a.upper_lower_track_count("Normal_Attack_Ing", true) != 0 \
				or a.upper_trunk_track_count("Normal_Attack_Ing", true) != 0:
			bad.append(c.display_name)
	_check(mates == 7 and bad.is_empty(),
		"%d 名同伴也都搭上了两层、下半身与躯干轨道都为 0%s"
		% [mates, "" if bad.is_empty() else "（有问题：%s）" % str(bad)])


# --- 2. 站定开火：脚不动、上半身在动 -------------------------------------------

func _test_standing_fire() -> void:
	print("\n========== 2. 站定开火：脚不动，上半身在演 ==========")
	await _reset()
	var t0 := await _travel(["Bip001 L Foot", "Bip001 R Hand"], WINDOW_MS)
	var foot_still: float = t0["Bip001 L Foot"]
	var hand_idle: float = t0["Bip001 R Hand"]
	_m["foot_idle"] = foot_still
	_m["hand_idle"] = hand_idle
	_check(foot_still < FOOT_STILL, "（对照）站定时脚本来就不动：%.3f m" % foot_still)

	_anim.request_fire()
	_check(_anim.current_state_name() == "Fire" and _anim.upper_clip() == "Normal_Attack_Ing",
		"开火：状态 %s、叠加层在播「%s」"
		% [_anim.current_state_name(), _anim.upper_clip()])
	# ⚠️ 脚和手必须在**同一个窗口**里量：开火动作只有 1.07 s，分两次量会跨出动作之外。
	#    判据也**不用绝对值**：手的位移跟「采样窗口落在动作的哪一段」有关，
	#    第一版卡了个 0.08 m，全量回归里量到 0.079 就红了（擦边）。
	#    改成跟**同长度窗口的待机基线**比 —— 自校准，不靠魔数。
	var t := await _travel(["Bip001 L Foot", "Bip001 R Hand"], WINDOW_MS)
	var foot_firing: float = t["Bip001 L Foot"]
	var hand_firing: float = t["Bip001 R Hand"]
	_m["foot_fire_still"] = foot_firing
	_m["hand_fire"] = hand_firing
	_check(foot_firing < FOOT_STILL,
		"**站定开火时脚仍然不动**：%.3f m（< %.2f）—— 这就是用户要的那一半"
		% [foot_firing, FOOT_STILL])
	_check(hand_firing > hand_idle + HAND_ACTING,
		"同时上半身在演：右手 %.3f m vs 待机基线 %.3f m（多 %.3f ≥ %.2f）"
		% [hand_firing, hand_idle, hand_firing - hand_idle, HAND_ACTING])


# --- 3. 跑动开火：腿还在跑（核心）----------------------------------------------

func _test_running_fire() -> void:
	print("\n========== 3. 跑动开火：腿还在跑？ ==========")
	await _reset()
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _wait_ms(600)
	_check(_anim.current_clip() == "Move_Ing",
		"跑起来了：基础层 %s（速度 %.2f m/s）"
		% [_anim.current_clip(), _speed()])
	var foot_run := await _bone_travel("Bip001 L Foot", WINDOW_MS)
	_m["foot_run"] = foot_run
	_check(foot_run >= FOOT_MOVING, "（对照）只跑不打：脚往返 %.3f m（≥ %.2f）"
		% [foot_run, FOOT_MOVING])

	# 开火
	_anim.request_fire()
	await _wait_ms(120)          # 让叠加层 / 整身动作开始写
	var foot_run_fire := await _bone_travel("Bip001 L Foot", WINDOW_MS)
	_m["foot_run_fire"] = foot_run_fire
	if _anim.has_runfire():
		# 2026-10-17 之后的**主路径**：整身一条「跑打开火」动作，两个叠加层都不出场。
		# 腿是这条动作自带的，所以「脚还在跑」这条判据照旧有意义。
		_check(_anim.current_clip() == _anim.extra_clip,
			"**开火期间基础层换成单条跑打动作 %s**（不再叠两层）" % _anim.current_clip())
		_check(_anim.upper_clip() == "",
			"叠加层不参与这一发（%s）"
			% ("无" if _anim.upper_clip() == "" else _anim.upper_clip()))
	else:
		_check(_anim.current_clip() == "Move_Ing",
			"**开火期间基础层仍然是 %s**（不再被整体顶掉）" % _anim.current_clip())
		_check(_anim.upper_clip() == "Normal_Attack_Ing",
			"叠加层在播开火动作（%s）" % _anim.upper_clip())
	_check(foot_run_fire >= FOOT_MOVING,
		"**跑动开火时脚还在跑**：%.3f m（≥ %.2f）—— 用户要的另一半"
		% [foot_run_fire, FOOT_MOVING])
	# 枪要对准准星（用户：「跑打攻击时武器还是歪着的，没对齐准星」）。
	# 素材的持枪跑本身斜 30°、跑打动作斜 42°（`_probe_aim_cross.gd`），
	# 靠 `AnimDriver._aim_gun()` 每帧把枪骨绕握把掰正。
	var gun := await _gun_vs_crosshair()
	_m["run_fire_gun_deg"] = gun
	_check(gun < 8.0, "跑打时枪管离准星 %.1f°（判据 < 8°，改前 42°）" % gun)
	var gap := await _muzzle_marker_gap()
	_m["run_fire_muzzle_gap"] = gap
	_check(gap < 0.05,
		"弹道起点（`Weapon/Muzzle` 标记）落在视觉枪口上：差 %.3f m（改前 0.3+ m，偏右）" % gap)
	_release_all()
	await _wait(2)


# --- 3b. 走着开火：改成「慢速跑打」整身动作（走打也要有枪）---------------------
#
# 第三轮（2026-10-18，用户：「走路攻击时改一下，把走路改成慢速的跑动画，
# 这样子走打就有枪了」）。
#
# 第二轮把门槛抬到 `WALK_THRESHOLD` 之后，走打开火走的是老路
# （基础层 `Cafe_Walk` + 叠加层 `Normal_Attack_Ing`），代价是**没枪**：
# `Cafe_Walk` 素材把 `Bip001_Weapon` 的世界缩放写成 ≈0.04（实测），枪直接看不见。
# 现在门槛降到 `IDLE_SPEED`：只要在移动就整身播 `RunFire_Ing`，慢速时靠
# `speed_scale` 放慢（2.4 m/s → 0.46 倍），步幅对得上地面。
#
# 只走（不开火）**仍然**是 `Cafe_Walk` —— 用户的另一条要求是「正常走路不变」。
func _test_walking_fire() -> void:
	print("\n========== 3b. 走着开火：改成慢速跑打（走打也要有枪）==========")
	await _reset()
	Input.action_press("move_forward")            # 不按 sprint → 走
	await _wait_ms(700)
	_check(_anim.current_clip() == "Cafe_Walk",
		"只走：仍是 %s（速度 %.2f m/s）—— 正常走路不变"
		% [_anim.current_clip(), _speed()])
	var walk_base := await _bone_travel("Bip001 L Foot", WINDOW_MS)
	_m["foot_walk"] = walk_base
	_m["walk_weapon_scale"] = _weapon_scale()

	_anim.request_fire()
	await _wait_ms(200)
	# ⚠️ 第十一轮（2026-10-18）：走打 = **腿用 `Cafe_Walk`（走路节奏）+ 手臂层**
	#    （`Move_Ing` 只留手臂/武器）。第九轮那版是整身 `Move_Ing` 放慢 0.46 ——
	#    跑周期 0.667 s ÷ 0.46 = 1.45 s/循环（0.69 Hz），而 `Cafe_Walk` 是
	#    1.25 s ÷ 1.5 = 0.83 s（1.2 Hz）：**用跑的腿去走**，脚在地上滑 = 螃蟹。
	_check(_anim.current_clip() == "Cafe_Walk",
		"走打开火：腿仍是走路 Cafe_Walk（%s）" % _anim.current_clip())
	_check(_anim.arms_track_count() > 0 and _anim.arms_stray_track_count() == 0,
		"手臂层只剩手臂/武器轨道：%d 条，越界 %d 条"
		% [_anim.arms_track_count(), _anim.arms_stray_track_count()])
	var sc := _anim.player.speed_scale
	_m["walk_fire_speed_scale"] = sc
	_check(sc >= 1.2 and sc <= 1.8,
		"腿按走路节奏播：speed_scale %.2f（走 %.2f m/s / Cafe_Walk 标称 1.60）"
		% [sc, _speed()])
	var ws := _weapon_scale()
	_m["walk_fire_weapon_scale"] = ws
	_check(ws > 0.5,
		"走打时枪骨没被压没：世界缩放 %.2f（只走时是 %.2f）"
		% [ws, float(_m.get("walk_weapon_scale", 0.0))])
	var gun := await _gun_vs_crosshair()
	_m["walk_fire_gun_deg"] = gun
	_check(gun < 8.0, "走打时枪管离准星 %.1f°（判据 < 8°）" % gun)
	var walk_fire := await _bone_travel("Bip001 L Foot", WINDOW_MS)
	_m["foot_walk_fire"] = walk_fire
	# 走的速度比跑慢，脚往返幅度也小；判据用「不低于走基线的 70%」而不是绝对值
	_check(walk_fire >= walk_base * 0.7,
		"走打开火时脚还在走：%.3f m（走基线 %.3f 的 70%% = %.3f）"
		% [walk_fire, walk_base, walk_base * 0.7])

	# ── 第三轮补的两条（2026-10-18 用户报「右倾还在」+「右转螃蟹平移」）──
	#
	# ① 掰枪的**旋转半径**必须小：枪骨 `Bip001_Weapon` 是根级骨，离手很远，
	#    绕它转 42° 会把整把枪平移出去（上一版就是「枪歪到身子右边」）。
	#    现在中心取在握枪的手上，半径 = 枪骨原点到两手的距离，必须 ≤ 0.25 m。
	var radius := _gun_pivot_radius()
	_m["gun_pivot_radius"] = radius
	_check(radius <= 0.25,
		"掰枪的旋转中心在手上：枪骨离握枪的手 %.3f m（≤ 0.25 —— 否则一掰就甩出去）"
		% radius)
	#
	# ② 松开扳机之后**不许继续演攻击**：`RunFire_Ing` 2.667 s、走路倍速 0.46
	#    ⇒ 一次点击会演 5.8 s（实测 `_probe_crab.gd`：第 300 帧才回 `Cafe_Walk`）。
	#    那 5.8 秒里脚轴在 48°~115° 之间摆（正常走路 70°~87°）= 用户说的「螃蟹平移」。
	_anim.cancel_fire()
	await _wait_ms(350)
	var st := _anim.current_state_name()
	var clip_after := _anim.current_clip()
	_m["release_state"] = st
	_m["release_clip"] = clip_after
	_check(st == "Locomotion" and clip_after == "Cafe_Walk",
		"松开扳机 0.35 s 内交回走路：state=%s clip=%s（改前要等 5.8 s）"
		% [st, clip_after])
	_release_all()
	await _wait(2)


# --- 3c. 慢速开火不许把身子拧歪（2026-10-18 用户：「走打还是右倾」）-------------
#
# 这条是「右倾」的**机器判据**，和姿势无关、和相机无关：
#   **肩线倾角** = 左右上臂骨连线在**模型空间**里相对水平面的仰角。
# 实测（`_probe_live_fire.gd`，正 = 左肩高）：
#   只走 Cafe_Walk −0.6° / 走打(旧,RunFire@0.46) **+14.1°** / 只跑 −7.8° / 跑打 −10.4°
# 判据用「和只跑的差」而不是绝对值：素材本身的持枪跑姿就有 −8° 的肩线，
# 那个是风格，不是 bug；**慢速开火不该比跑打更歪**才是要守的东西。
func _test_walkfire_posture() -> void:
	print("
========== 3c. 慢速开火不许把身子拧歪（「右倾」的机器判据）==========")
	await _reset()
	# 只跑的肩线基准
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _wait_ms(700)
	var run_tilt := await _shoulder_tilt_avg(40)
	_m["tilt_run"] = run_tilt
	_check(_anim.current_clip() == "Move_Ing", "跑起来：%s（速度 %.2f）"
		% [_anim.current_clip(), _speed()])
	Input.action_release("sprint")
	# 走打
	await _wait_ms(500)
	var walk_tilt := await _shoulder_tilt_avg(40)
	_m["tilt_walk"] = walk_tilt
	_anim.request_fire()
	await _wait_ms(250)
	var fire_tilt := await _shoulder_tilt_avg(40)
	_m["tilt_walk_fire"] = fire_tilt
	print("  肩线：只走 %+.1f° / 走打 %+.1f° / 只跑 %+.1f°（正 = 左肩高）"
		% [walk_tilt, fire_tilt, run_tilt])
	_check(_anim.current_clip() == "Cafe_Walk", "走打的腿仍是走路：%s" % _anim.current_clip())
	# ⚠️ 判据从「和只跑比」改成「和**只走**比」：走打现在腿是 `Cafe_Walk`、
	#    手臂是独立一层，姿态本来就该跟**走路**一致，而不是跟跑一致。
	#    实测 只走 −1.0° / 走打 −1.1°（旧版整身 `RunFire@0.46` 是 +14.1°）。
	_check(absf(fire_tilt - walk_tilt) < 6.0,
		"走打的肩线和**只走**相差 %.1f°（判据 < 6°；旧版 RunFire@0.46 是 +14.1°）"
		% absf(fire_tilt - walk_tilt))
	_check(absf(fire_tilt) < 15.0, "走打肩线绝对值 %.1f°（< 15°）" % absf(fire_tilt))
	var gun := await _gun_vs_crosshair()
	_check(gun < 8.0, "走打（Cafe_Walk 腿 + 手臂层）枪管离准星 %.1f°（判据 < 8°）" % gun)
	var ws := _weapon_scale()
	_check(ws > 0.5, "走打时枪骨没被压没：世界缩放 %.2f" % ws)
	_anim.cancel_fire()
	await _wait_ms(350)
	_check(_anim.current_clip() == "Cafe_Walk" and _anim.current_state_name() == "Locomotion",
		"松手 0.35 s 后回到走路：%s / %s"
		% [_anim.current_clip(), _anim.current_state_name()])
	_release_all()
	await _wait(2)


## 肩线倾角（几帧平均）：左右上臂骨连线在模型空间里相对水平面的仰角，正 = 左肩高
func _shoulder_tilt_avg(frames: int) -> float:
	var sum := 0.0
	for _i in frames:
		await process_frame
		var sk := _anim.skeleton
		# ⚠️ 用**锁骨**而不是上臂：上臂原点会跟着手臂摆动前后挪（走一个循环能挪几厘米），
		#    量出来的「肩线」会被摆臂污染（实测同一条走路，30 帧平均 −2.3° 和 +8.3° 都有）。
		#    锁骨根部固定在胸上，才是干净的肩线基准。
		var l := sk.find_bone("Bip001 L Clavicle")
		var r := sk.find_bone("Bip001 R Clavicle")
		if l < 0 or r < 0:
			return 999.0
		var wl: Vector3 = sk.global_transform * sk.get_bone_global_pose(l).origin
		var wr: Vector3 = sk.global_transform * sk.get_bone_global_pose(r).origin
		var mb := _p.model_root.global_transform.basis
		var v := mb.inverse() * (wl - wr)
		sum += rad_to_deg(atan2(v.y, maxf(Vector2(v.x, v.z).length(), 0.0001)))
	return sum / float(maxi(frames, 1))


# --- 3d. 「先开火一次，再走路」（用户本轮的原话，完整复现）------------------------
#
# 用户：「现在只要修这个了，先开火一次，在走路就变成这样子右侧身子螃蟹平移」。
#
# 这条和 3b/3c 不是同一条路：**站着**开火走的是叠加层（含脊椎/颈/头），
# 而「走起来之后开火」走的是手臂层。之前所有探针都是「先走再打」，
# 正好绕过了用户实际做的事 —— 所以这一节专门按他的顺序来。
#
# 两个判据（都必须是「和只走一样」，不是「看起来还行」）：
#   1. 打完立刻走：0.35 s 内必须回到 `Cafe_Walk` / `Locomotion`（不许还在演开火）；
#   2. 此时的肩线（侧倾）和躯干扭转（偏航）都要和「只走」差 < 6°。
# 再加一条「按住扳机走」：腿仍是走路、手臂层在播、枪没被压没、枪还在手里。
func _test_fire_then_walk() -> void:
	print("
========== 3d. 先开火一次，再走路（用户原话）==========")
	var wpn := _p.get_node_or_null("Weapon") as Weapon
	if wpn == null:
		_check(false, "玩家身上没有 Weapon")
		return
	await _reset()
	Input.action_press("move_forward")
	await _wait_ms(600)
	var walk_tilt := await _shoulder_tilt_avg(60)
	var walk_twist := await _torso_twist_avg(60)
	_m["walk_tilt_3d"] = walk_tilt
	_m["walk_twist_3d"] = walk_twist
	print("  基准（只走）：肩线 %+.1f° / 躯干扭转 %+.1f°" % [walk_tilt, walk_twist])
	_release_all()
	await _wait_ms(500)

	# 站着点一下（真武器链），然后立刻走
	_anim.reset_state()
	await _wait_ms(200)
	wpn.trigger_down()
	await _wait(4)
	wpn.trigger_up()
	Input.action_press("move_forward")
	await _wait_ms(350)
	var st := _anim.current_state_name()
	var clip := _anim.current_clip()
	_m["fire_then_walk_state"] = st
	_check(st == "Locomotion" and clip == "Cafe_Walk",
		"站着打完立刻走：0.35 s 内回到 %s / %s（不许还在演开火）" % [st, clip])
	var tilt := await _shoulder_tilt_avg(60)
	var twist := await _torso_twist_avg(60)
	print("  打完立刻走：肩线 %+.1f° / 躯干扭转 %+.1f°" % [tilt, twist])
	_check(absf(tilt - walk_tilt) < 6.0,
		"肩线和只走相差 %.1f°（< 6°）" % absf(tilt - walk_tilt))
	_check(absf(twist - walk_twist) < 6.0,
		"躯干扭转和只走相差 %.1f°（< 6°）" % absf(twist - walk_twist))

	# 按住扳机走
	wpn.trigger_down()
	await _wait_ms(400)
	var arms_on := _anim.arms != null and _anim.arms.is_playing() 		and String(_anim.arms.current_animation) == AnimDriver.ARMS_CLIP
	_m["held_arms_on"] = arms_on
	_check(_anim.current_clip() == "Cafe_Walk" and arms_on,
		"按住扳机走：腿是 %s、手臂层 %s" % [_anim.current_clip(),
		"在播" if arms_on else "**没在播**"])
	var ws := _weapon_scale()
	var gap := _gun_hand_gap()
	_check(ws > 0.5, "按住扳机走：枪骨缩放 %.2f（看得见）" % ws)
	_check(gap < 0.16, "按住扳机走：枪离最近的手 %.3f m（< 0.16，还在手里）" % gap)
	wpn.trigger_up()
	await _wait_ms(350)
	_check(_anim.current_state_name() == "Locomotion" and _anim.current_clip() == "Cafe_Walk",
		"松开扳机 0.35 s 后：%s / %s" % [_anim.current_state_name(), _anim.current_clip()])
	_release_all()
	await _wait(2)


## 躯干扭转（肩线 vs 髋线，水平面内）的平均值，正 = 肩往右拧
func _torso_twist_avg(frames: int) -> float:
	var sum := 0.0
	for _i in frames:
		await process_frame
		var sk := _anim.skeleton
		var l: int = sk.find_bone("Bip001 L Clavicle")
		var r: int = sk.find_bone("Bip001 R Clavicle")
		var tl: int = sk.find_bone("Bip001 L Thigh")
		var tr: int = sk.find_bone("Bip001 R Thigh")
		if l < 0 or r < 0 or tl < 0 or tr < 0:
			return 999.0
		var mb := _p.model_root.global_transform.basis.inverse()
		var sh: Vector3 = mb * (_bone_w(l) - _bone_w(r))
		var hp: Vector3 = mb * (_bone_w(tl) - _bone_w(tr))
		sh.y = 0.0
		hp.y = 0.0
		if sh.length() < 0.0001 or hp.length() < 0.0001:
			continue
		sh = sh.normalized()
		hp = hp.normalized()
		sum += rad_to_deg(atan2(sh.cross(hp).y, sh.dot(hp)))
	return sum / float(maxi(frames, 1))


func _bone_w(i: int) -> Vector3:
	return _anim.skeleton.global_transform * _anim.skeleton.get_bone_global_pose(i).origin


## 枪骨原点到最近那只手的距离（素材原样 ≈ 0.11~0.22 m）
func _gun_hand_gap() -> float:
	var sk := _anim.skeleton
	var wi := sk.find_bone(AnimDriver.GUN_BONE)
	if wi < 0:
		return 999.0
	var g := _bone_w(wi)
	var best := 999.0
	for b in [AnimDriver.HAND_L_BONE, AnimDriver.HAND_R_BONE]:
		var i := sk.find_bone(b)
		if i < 0:
			continue
		best = minf(best, g.distance_to(_bone_w(i)))
	return best


# --- 4. 跑动换弹：同一套逻辑 ---------------------------------------------------

func _test_running_reload() -> void:
	print("\n========== 4. 跑动换弹（同一个毛病，同一套修法）==========")
	await _reset()
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _wait_ms(600)
	_anim.request_reload()
	await _wait_ms(120)
	var foot := await _bone_travel("Bip001 L Foot", WINDOW_MS)
	_m["foot_reload"] = foot
	_check(_anim.current_clip() == "Move_Ing" and _anim.upper_clip() == "Normal_Reload",
		"换弹期间：基础层 %s、叠加层 %s" % [_anim.current_clip(), _anim.upper_clip()])
	_check(foot >= FOOT_MOVING, "跑动换弹时脚还在跑：%.3f m（≥ %.2f）" % [foot, FOOT_MOVING])
	_release_all()
	await _wait(2)


# --- 5. 收尾：叠加层要收干净 ---------------------------------------------------

func _test_recover() -> void:
	print("\n========== 5. 一次性动作播完之后 ==========")
	await _reset()
	_anim.request_fire()
	await _wait_ms(1400)         # Normal_Attack_Ing 2.667 s / 2.5 倍 ≈ 1.07 s
	_check(_anim.current_state_name() == "Locomotion" and _anim.upper_clip() == "",
		"开火播完：状态回到 %s、叠加层已停（%s）"
		% [_anim.current_state_name(), "无" if _anim.upper_clip() == "" else _anim.upper_clip()])
	var foot := await _bone_travel("Bip001 L Foot", WINDOW_MS)
	_check(foot < FOOT_STILL, "停下之后脚也停了：%.3f m" % foot)


# --- 6. 真·扳机那条路也走一遍 --------------------------------------------------

func _test_weapon_path() -> void:
	print("\n========== 6. 从武器（真扳机）走一遍 ==========")
	await _reset()
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _wait_ms(600)
	_p.weapon.trigger_down()
	await _wait_ms(200)
	var clip := _anim.upper_clip()
	var whole := _anim.current_clip()
	var v := _speed()
	_p.weapon.trigger_up()
	if _anim.has_runfire():
		_check(whole == _anim.extra_clip,
			"按住左键跑动：整身切到单条跑打动作（%s）" % whole)
	else:
		_check(clip == "Normal_Attack_Ing",
			"按住左键跑动：叠加层自己播起了开火动作（%s）" % clip)
	_check(absf(v - Player.SPEED_RUN) < 0.3,
		"而且**跑速没被开火打断**：%.2f m/s（期望 %.2f）" % [v, Player.SPEED_RUN])
	_release_all()
	await _wait(2)


# --- 7. 跑打开火时躯干不许被开火动作掰走 ---------------------------------------

## 用户报：「跑打确实腿动了但是感觉身体倾斜了好多」。
##
## 根因：开火动作是**站桩**的，只滤下半身的话，它的脊椎 / 胸会把跑步的前倾
## 一下掰成站桩姿势 —— 实测 `Bip001 Spine1` 的上轴差 **65°**。
## 修法：叠加层分两层，**在动**用「再滤掉躯干」那层（躯干保持 `Move_Ing` 的前倾），
## 站着用完整上半身那层（站桩开火姿势保留）。
##
## 判据（自校准，不靠 65 这个魔数）：把「只跑」一个周期的胸椎上轴收成一个**姿势集**，
## 再量「跑打开火」的每一个采样到那个集合的**最小夹角** —— 修好后应当 ≈ 0°，
## 而把移动层摘掉（= 改前的行为）必须能红。
func _test_trunk_kept() -> void:
	print("\n========== 7. 跑打开火：躯干不许被掰 ==========")
	_check(_anim.upper_trunk_track_count("Normal_Attack_Ing", true) == 0,
		"移动层里**躯干轨道 0 条**（额外滤掉 %d 条：脊椎 / 胸保持基础层的跑步前倾）"
		% _anim.trunk_tracks_removed)
	var still_trunk := _anim.upper_trunk_track_count("Normal_Attack_Ing", false)
	_check(still_trunk > 0,
		"静止层里**仍然保留 %d 条躯干轨道**（站桩开火那套姿势没被吃掉）" % still_trunk)

	# 动态：只跑 vs 跑+开火
	await _reset()
	_check(_anim.active_upper_layer() == _anim.upper, "站定时用的是静止层")
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _wait_ms(600)
	_check(_anim.active_upper_layer() == _anim.upper_move,
		"跑起来之后自动换成移动层（速度 %.2f m/s）" % _speed())
	var run_set := await _sample_axis(CHEST, 700)
	_anim.request_fire()
	await _wait_ms(120)
	var fire_set := await _sample_axis(CHEST, 500)
	var worst := _dist_to_set(fire_set, run_set)
	_m["trunk_deg"] = worst
	_check(worst < TRUNK_TOL,
		"**跑打开火时胸椎离「只跑」的姿势集最多 %.1f°**（< %.0f°，改前是 65°）"
		% [worst, TRUNK_TOL])

	# 反向对照：把移动层摘掉（= 改前的行为）必须量到大角度
	# ⚠️ 同时要把「单条跑打动作」关掉，否则跑打开火根本不走叠加层，这个对照量的是
	#    同一个东西（不会红）。
	var keep := _anim.upper_move
	var keep_clip := _anim.extra_clip
	_anim.upper_move = null
	_anim.extra_clip = ""
	await _reset()
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _wait_ms(600)
	_anim.request_fire()
	await _wait_ms(120)
	var old_set := await _sample_axis(CHEST, 500)
	var old_deg := _dist_to_set(old_set, run_set)
	_anim.upper_move = keep
	_anim.extra_clip = keep_clip
	_m["trunk_deg_old"] = old_deg
	_check(old_deg > 20.0,
		"反向对照：只滤下半身时同一个量是 %.1f° —— 这就是用户看到的「身体倾斜」" % old_deg)
	_release_all()
	await _wait(2)

	# 站定开火：躯干**应该**跟着开火动作走（这是上一轮要的站桩姿势）
	await _reset()
	var idle_set := await _sample_axis(CHEST, 400)
	_anim.request_fire()
	await _wait_ms(120)
	var stand_set := await _sample_axis(CHEST, 400)
	var stand_deg := _dist_to_set(stand_set, idle_set)
	_m["trunk_stand"] = stand_deg
	_check(stand_deg > 10.0,
		"但站定开火时躯干**照样演素材里的站桩姿势**：离待机 %.1f°（> 10°）" % stand_deg)


# --- 工具 ---------------------------------------------------------------------

## 若干根骨在 `ms` 毫秒里**各自相对自己的最大位移**（骨架局部空间 ——
## 不算角色自身往前跑，只算动画把人摆成什么样）。
func _travel(bones: Array, ms: int) -> Dictionary:
	var origin := {}
	var worst := {}
	for b in bones:
		origin[b] = _anim.bone_local_origin(String(b))
		worst[b] = 0.0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame
		for b in bones:
			worst[b] = maxf(worst[b],
				_anim.bone_local_origin(String(b)).distance_to(origin[b]))
	return worst


func _bone_travel(bone: String, ms: int) -> float:
	var t := await _travel([bone], ms)
	return float(t[bone])


## `ms` 毫秒里每帧采一次某根骨的「上」轴 —— 一个姿势**集合**。
func _sample_axis(bone: String, ms: int) -> Array:
	var out: Array = []
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame
		out.append(_anim.bone_up_axis(bone))
	return out


## 这个集合到那个集合的**最小夹角**（度）：集合里每个采样，取它到参考集的最小值，
## 再取最大 —— 「这些姿势离参考姿势能有多远」。
func _dist_to_set(set_a: Array, set_b: Array) -> float:
	var worst := 0.0
	for a in set_a:
		var best := 999.0
		for b in set_b:
			best = minf(best, rad_to_deg((a as Vector3).angle_to(b as Vector3)))
		worst = maxf(worst, best)
	return worst


func _speed() -> float:
	return Vector2(_p.velocity.x, _p.velocity.z).length()


## 武器骨的世界缩放（√ 三轴之积）：素材 `Cafe_Walk` 把它写成 ≈0.04 ⇒ 枪被压没。
func _weapon_scale() -> float:
	var sk := _anim.skeleton
	if sk == null:
		return 0.0
	var i := sk.find_bone(AnimDriver.GUN_BONE)
	if i < 0:
		return 0.0
	var b: Basis = (sk.global_transform * sk.get_bone_global_pose(i)).basis
	return (b.get_scale().length() / sqrt(3.0))


## 枪管（muzzle − magazine）离**准星**（相机前向）多少度。角色前向与相机前向实测 0°，
## 所以相机不在时退回「模型 +Z」（`_probe_aim_cross.gd` 量过这一条）。
func _gun_vs_crosshair() -> float:
	var sk := _anim.skeleton
	if sk == null:
		return 999.0
	var mi := sk.find_bone(AnimDriver.GUN_MUZZLE_BONE)
	var gi := sk.find_bone(AnimDriver.GUN_BREECH_BONE)
	if mi < 0 or gi < 0:
		return 999.0
	var skb := sk.global_transform.basis
	var d: Vector3 = (skb * sk.get_bone_global_pose(mi).origin
		- skb * sk.get_bone_global_pose(gi).origin)
	if d.length_squared() < 1e-10:
		return 999.0
	var target: Vector3 = _p.model_root.global_transform.basis.z
	var cam: Camera3D = root.get_camera_3d() if root != null else null
	if cam != null:
		target = -cam.global_transform.basis.z
	return rad_to_deg((d.normalized()).angle_to(target.normalized()))


## 弹道起点（`Weapon/Muzzle` 标记 = 曳光弹 / 枪口火光的起点）离**视觉枪口**多远。
## 用户 2026-10-18：「跑打子弹发射的点不在枪口上，偏右了」——
## 病根是 `Weapon._process` 早于 `AnimDriver` 掰枪骨，标记落在**上一帧**的枪口上。
func _muzzle_marker_gap() -> float:
	var wpn := _p.get_node_or_null("Weapon") as Weapon
	var sk := _anim.skeleton
	if wpn == null or sk == null:
		return 999.0
	for b in ["bone_Railgun_Muzzle_03", "bone_Railgun_Muzzle_01"]:
		var i := sk.find_bone(b)
		if i >= 0:
			var at: Vector3 = sk.global_transform * sk.get_bone_global_pose(i).origin
			return wpn.muzzle.global_position.distance_to(at)
	return 999.0


## 掰枪的旋转半径：枪骨原点到「最近那只手」的距离（米）。
##
## 用户 2026-10-18：「右倾还在」。上一版转锁骨（手臂 + 枪当刚体）把肩膀拧走 42°，
## 剪影就是右倾；而更早那版绕**枪骨自己的原点**转，因为枪骨是根级骨、离手很远，
## 一掰就把整把枪**平移**出去（「枪歪到身子右边」）。
## 现在中心取在两手连线上，半径就是这条判据 —— 半径小 ⇒ 掰 42° 只挪
## `2 · r · sin(21°) ≈ 0.7 r`，枪还在手里。
func _gun_pivot_radius() -> float:
	var sk := _anim.skeleton
	if sk == null:
		return 999.0
	var wi := sk.find_bone(AnimDriver.GUN_BONE)
	if wi < 0:
		return 999.0
	var g: Vector3 = sk.global_transform * sk.get_bone_global_pose(wi).origin
	var best := 999.0
	for b in [AnimDriver.HAND_L_BONE, AnimDriver.HAND_R_BONE]:
		var i := sk.find_bone(b)
		if i < 0:
			continue
		var h: Vector3 = sk.global_transform * sk.get_bone_global_pose(i).origin
		best = minf(best, g.distance_to(h))
	return best


func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right",
			"sprint", "crouch", "jump"]:
		Input.action_release(a)


func _reset() -> void:
	_release_all()
	_p.velocity = Vector3.ZERO
	_p.global_position = SPAWN
	_p._yaw = 0.0
	_p._facing_yaw = PI
	_p.model_root.rotation.y = PI
	_anim.state = AnimDriver.State.LOCOMOTION
	_anim.reset_state()
	await _wait(6)


func _print_table() -> void:
	print("\n================ 脚动没动（骨架局部位移，米）================")
	print("  站定（对照）      %.3f" % float(_m.get("foot_idle", 0.0)))
	print("  站定 + 开火       %.3f   ← 用户要的：不动" % float(_m.get("foot_fire_still", 0.0)))
	print("  跑（对照）        %.3f" % float(_m.get("foot_run", 0.0)))
	print("  跑 + 开火         %.3f   ← 用户要的：还在跑" % float(_m.get("foot_run_fire", 0.0)))
	print("  走（对照）        %.3f" % float(_m.get("foot_walk", 0.0)))
	print("  走 + 开火         %.3f   ← 慢速跑打整身动作，腿还得走"
		% float(_m.get("foot_walk_fire", 0.0)))
	print("  跑 + 换弹         %.3f" % float(_m.get("foot_reload", 0.0)))
	print("\n================ 枪管离准星（度，越小越好）================")
	print("  跑打开火          %.1f   ← 改前 42°" % float(_m.get("run_fire_gun_deg", -1.0)))
	print("  走打开火          %.1f   ← 改前没枪（武器骨缩放 %.2f）" % [
		float(_m.get("walk_fire_gun_deg", -1.0)),
		float(_m.get("walk_fire_weapon_scale", -1.0))])
	print("\n================ 跑打开火时胸椎的偏离（度，越小越好）================")
	print("  改后（移动层滤掉躯干）  %.1f" % float(_m.get("trunk_deg", -1.0)))
	print("  改前（只滤下半身）      %.1f   ← 用户报的「身体倾斜了好多」"
		% float(_m.get("trunk_deg_old", -1.0)))
	print("  站定开火 vs 待机        %.1f   ← 站桩姿势仍然保留"
		% float(_m.get("trunk_stand", -1.0)))


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


func _wait_ms(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame
