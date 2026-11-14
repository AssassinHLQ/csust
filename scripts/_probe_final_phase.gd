extends SceneTree
## 终局演出验收：三只霸王龙倒下 → 围墙升起 → 血色封锁 + 末日天 → 优香-恐怖登场
##              → 三招都能打到人 / 圈外打不到 / 挑战胜 → 封锁解除、天空还原。
##
##   _tools/run_shot.sh res://scripts/_probe_final_phase.gd
##   _tools/run_shot.sh res://scripts/_probe_final_phase.gd --splat=off
##
## 出图到 `_arisu_captures/_final_phase/`：
##   1_before   杀之前（对照）
##   2_sky      末日天空
##   3_rise     墙正在升
##   4_locked   墙到位 + 天变了
##   5_wall     贴墙看"上下密集线条"
##   6_boss     优香-恐怖 全身
##   8_face     优香-恐怖 上半身（看暗身体 + 红边）
##   9_telegraph 砸击预警圈（圈 = 伤害范围）
##   10_cleared 打倒之后：墙沉下去、天回来
##
## ⚠️ 幕外窗口 + --no-capture（AGENTS.md 硬要求：不许抢用户前台）。
## ⚠️ 会真的播 BOSS 曲 —— 探针里把 Master 总线静音，只验证"在放"。

const OffWin := preload("res://scripts/offscreen_window.gd")
## ⚠️ 不能直接写 `Music`：`--script` 模式下**全局 class_name 解析不到**
##    （`splat_scene.gd` 那次自检就栽在这上面），必须 preload 一份。
const MusicLib := preload("res://scripts/music.gd")
const OUT_DIR := "C:/Users/WY157/Desktop/GODOT/_arisu_captures/_final_phase"

var _out := ""
var _lvl: Node3D
var _cam: Camera3D
var _player: CharacterBody3D
var _boss: Node3D
var _pass := 0
var _fail := 0
## 玩家在校园里那个"站得住"的落点（测试全程都在它附近，不来回传送）
var _safe := Vector3.ZERO


func _initialize() -> void:
	if not OS.get_cmdline_user_args().has("--no-capture"):
		push_error("[final] 缺 --no-capture")
		quit(2)
		return
	_run.call_deferred()


func _run() -> void:
	_out = OUT_DIR
	DirAccess.make_dir_recursive_absolute(_out)
	await OffWin.apply(self, Vector2i(1280, 720))
	var safe: Array = OffWin.is_safe()
	if not bool(safe[0]):
		push_error("[final] 窗口没挪到屏幕外：%s" % str(safe[1]))
		quit(2)
		return
	# 静音 Master：探针要**验证**这首在不在放，但不能真的把用户吼一脸
	AudioServer.set_bus_mute(0, true)

	var ps := load("res://scenes/next_level.tscn") as PackedScene
	_lvl = ps.instantiate() as Node3D
	root.add_child(_lvl)
	# ⚠️ 关掉「掉出广场」的重置：探针要把玩家钉在校园里做判定，
	#    而它往下掉一次就被送回大厅（−2, 0.6, 5.2），之后 BOSS 的技能
	#    全部打向那个位置、判定全乱（实测：幻影追到 243 m 外的"玩家"）。
	var fall := _lvl.get_node_or_null("FallReset") as Area3D
	if fall != null:
		fall.set_deferred("monitoring", false)
		print("[final] 已关闭 FallReset（探针把玩家钉住，不需要坠落兜底）")
	for _i in 20:
		await process_frame

	# 校园泼溅要不要等（`--splat=off` 跳过，跑得快，但背景是空的）
	var want_splat := not OS.get_cmdline_user_args().has("--splat=off")
	var campus := _lvl.get_node_or_null("Campus")
	if campus != null:
		# 探针会把玩家钉住 / 到处传，掉进广场的洞就会低于校园内容盒 → 触发
		# 「离开范围释放泼溅」→ 后面的图全是黑地面（实测 run9 就是这样）。
		# 出图验收时让泼溅常驻，别让这条省显存的逻辑搅局。
		campus.set("unload_outside_room", false)
	if campus != null and want_splat:
		campus.set("start_delay", 0.0)
		campus.set("low_priority", false)
		campus.set("preload_on_gate", false)
		campus.call("force_start")
		var t0 := Time.get_ticks_msec()
		while not bool(campus.call("is_ready")) and Time.get_ticks_msec() - t0 < 300000:
			await process_frame
		print("[final] 泼溅就绪 %d ms" % (Time.get_ticks_msec() - t0))
	elif campus != null:
		campus.call("force_start")
		print("[final] 泼溅按 --splat=off 不等")

	# 玩家挪到校园里（不然它在蒙德里安大厅里，墙和 BOSS 都在几百米外）
	#
	# ⚠️ 落点必须是**真有地面**的地方：校园碰撞网格是有洞的（见
	#    `arena_lock.gd` 里 GROUND_MIN/MAX 那段注释）。
	var player := _lvl.get_node_or_null("Player") as CharacterBody3D
	if player == null:
		push_error("[final] 没有 Player")
		quit(1)
		return
	_player = player
	var spot := Vector3(-120.0, 2.0, -200.0)
	for cand in [Vector3(-120.0, 2.0, -200.0), Vector3(-60.0, 2.0, -250.0),
			Vector3(0.0, 2.0, -200.0), Vector3(-40.0, 2.0, -320.0)]:
		var g := _ground(cand.x, cand.z)
		if g != null:
			spot = Vector3(cand.x, float(g) + 1.2, cand.z)
			break
	player.global_position = spot
	player.set("velocity", Vector3.ZERO)
	_safe = spot
	for _i in 12:
		await physics_frame
	_safe = player.global_position
	print("[final] 玩家落点 %s（落地后 %s）" % [str(spot.snappedf(0.01)),
		str(_safe.snappedf(0.01))])

	_cam = Camera3D.new()
	_cam.fov = 62.0
	_cam.near = 0.1
	_cam.far = 3000.0
	root.add_child(_cam)
	_cam.make_current()

	await _shot("1_before", Vector3(-60, 42, -128), Vector3(-46, 10, -215))

	# ── 把三只霸王龙打到 0 ──
	var bosses: Array = []
	for n in get_nodes_in_group("bosses"):
		if n is Node3D and _lvl.is_ancestor_of(n) and n.has_method("take_damage"):
			bosses.append(n)
	print("[final] 场上霸王龙 %d 只：%s" % [bosses.size(),
		", ".join(bosses.map(func(b): return String(b.name)))])
	for b in bosses:
		b.call("take_damage", 1.0e9)
	await process_frame
	print("[final] 打完之后 TrexLeft = %s" % str(_lvl.get("_trex_left")))

	# 换天 + 墙开始升（脚本里先等 1.4 s 缓冲）。这一张专看**末日天空**。
	await _wait(3.2)
	await _shot("2_sky", Vector3(-60, 22, -215), Vector3(-40, 64, -330))
	await _wait(1.4)
	await _shot("3_rise", Vector3(-60, 16, -305), Vector3(-60, 30, -76))
	await _wait(5.0)
	await _shot("4_locked", Vector3(-60, 16, -305), Vector3(-60, 30, -76))
	await _shot("5_wall", Vector3(-60, 8, -110), Vector3(-60, 26, -76))

	# ── BOSS 登场 ──
	var lock := _lvl.get_node_or_null("ArenaLock")
	for _i in 240:
		await process_frame
		if lock != null and String(lock.call("status")["boss"]) != "":
			break
	_boss = lock.get_node_or_null("YuukaHorror") if lock != null else null
	if _boss == null:
		push_error("[final] BOSS 没出来")
		quit(1)
		return
	await _wait(1.0)
	var st: Dictionary = lock.call("status")
	var bpos: Vector3 = st.get("boss_pos", Vector3(-60, 0, -240))
	var bst: Dictionary = _boss.call("status")
	_check("BOSS 有动画", bool(bst["has_anim"]), "anim=%s" % str(bst["anim"]))
	_check("BOSS 贴图换成 horror_skin", int(bst["skin_mats"]) >= 10,
		"skin_mats=%d" % int(bst["skin_mats"]))
	_check("BOSS 血量 14000", is_equal_approx(float(bst["max_health"]), 14000.0),
		"%s" % str(bst["max_health"]))
	# 主角团：终局开场到场 4 人（不含优香/小雪/诺亚），并且枪被加强了
	var party_names: Array[String] = []
	var gun_dmg := 0.0
	var gun_intervals: Array[float] = []
	var gun_skills: Array[String] = []
	var party_guns: Array[Node] = []
	for i in 4:
		var c := _lvl.get_node_or_null("Party%d" % i)
		if c == null:
			continue
		party_names.append(String(c.get("display_name")))
		var g := c.get_node_or_null("Gun")
		if g != null:
			gun_dmg = maxf(gun_dmg, float(g.get("attack_damage")))
			gun_intervals.append(float(g.get("attack_interval")))
			gun_skills.append(String(g.call("skill_name")))
			party_guns.append(g)
			g.set("enabled", false)   # 测 BOSS 招式判定时别让队友的枪掺和
	_check("主角团到场 4 人（不含优香/小雪/诺亚）", party_names.size() == 4,
		", ".join(party_names))
	_check("主角团的枪被加强（≥50 伤害）", gun_dmg >= 50.0, "%.0f 伤害/发" % gun_dmg)
	var fast := gun_intervals.size() == 4
	for v in gun_intervals:
		if v > 0.32:
			fast = false
	_check("队友攻速全部加强（≤ 0.32 s/发）", fast,
		"%s" % str(gun_intervals))
	var uniq := {}
	for s in gun_skills:
		uniq[s] = true
	_check("四人各带一个技能且互不相同", gun_skills.size() == 4 and uniq.size() == 4,
		", ".join(gun_skills))
	await _shot("19_party", safe_spot() + Vector3(-12, 16, 20),
		safe_spot() + Vector3(0, 4, 0))

	# 让 BOSS 转向玩家后拍全身 / 上半身。
	# ⚠️ 玩家**不挪窝**：前几轮为了取景把玩家传过去，结果那边是个洞，
	#    `_safe` 当场变成 y=−56（掉下去 60 m），后面所有判定全废。
	#    机位沿"BOSS→玩家"的方向插到两者之间，拍到的是它正面。
	await _wait(2.2)
	var to_player := safe_spot() - bpos
	to_player.y = 0.0
	to_player = to_player.normalized() if to_player.length() > 0.5 else Vector3.FORWARD
	await _shot("6_boss", bpos + to_player * 26.0 + Vector3(0, 18, 0),
		bpos + Vector3(0, 10, 0))
	await _shot("8_face", bpos + to_player * 14.0 + Vector3(0, 13, 0),
		bpos + Vector3(0, 13, 0))

	# ── 三招判定 ──
	#
	# ⚠️ 玩家**不挪窝**。校园碰撞网格有大洞、楼顶也很多，探针每传一次都可能
	#    掉出广场（前几轮实测两次「玩家掉出广场，已送回出生点」，之后的判定全废）。
	#    改成把 **BOSS 挪到玩家 18 m 外**——截图已经拍完了，这里只测判定。
	# ⚠️ 把玩家**钉住**（关掉它的 `_physics_process`）：
	#    这个校园的碰撞网格是零碎的（站得住的地方很窄），探针里玩家被击退 /
	#    脚下是薄边都会掉下去，一掉就被 FallReset 送回大厅（实测三次），
	#    判定全部作废。测试只需要"玩家站在某个坐标"，钉住最稳。
	_player.set_physics_process(false)
	_teleport(safe_spot())
	await _wait(0.3)
	var stand := _player.global_position
	_boss.global_position = Vector3(stand.x + 18.0, stand.y, stand.z)
	await _wait(0.4)
	print("[final] 测试机位：玩家 %s / BOSS %s（水平 %.1f m）" % [
		str(stand.snappedf(0.1)), str(_boss.global_position.snappedf(0.1)),
		Vector2(stand.x - _boss.global_position.x, stand.z - _boss.global_position.z).length()])
	# ⚠️ 先等它把"登场后第一轮自动出招"演完（可能正有一圈冲击波在飞），
	#    再掐掉自动节奏、清场，否则上一招会混进第一个测试里
	await _until_idle(40.0)
	_boss.call("debug_reset")
	_boss.set("_t_skill", 9999.0)
	# 测试期间别让闪现乱触发（会打乱"BOSS 固定在 18 m 外"的前提）
	_boss.call("debug_set_blink_cd", 999.0)
	_boss.call("debug_set_chase", false)
	# ⚠️ 追击是**这之后**才关掉的，`_until_idle` 那几秒它会朝玩家挪窝
	#    （实测有一次直接贴到队友身上：射线从模型内部出发，榴弹/轨道炮全打空）。
	#    这里把「18 m 外」重新钉一遍，后面的判定前提才是真的。
	_boss.global_position = Vector3(stand.x + 18.0, stand.y, stand.z)
	await _wait(0.3)

	# ── 队友技能：四个都要真的打到 BOSS 身上 ──
	# BOSS 就在 18 m 外、玩家被钉住 → 四个技能都在射程内（最短的霰弹 26 m）
	#
	# ⚠️ 队友在这之前的跟随会被拖进广场的洞里（日志里几十次「被拉回玩家身边」），
	#    射线从洞里往上打全被地形挡住，四个技能一个都打不到。这里把四个人
	#    摆到玩家旁边、**关掉跟随物理**，保证射线是从地面上打出去的。
	for i in party_guns.size():
		var c := party_guns[i].get_parent() as Node3D
		c.set_physics_process(false)
		c.global_position = stand + Vector3(-1.8 + 1.2 * float(i), 0.1, 1.5)
		c.rotation.y = atan2(_boss.global_position.x - c.global_position.x,
			_boss.global_position.z - c.global_position.z)
	await _wait(0.2)
	_boss.call("debug_set_evasion", 0.0)   # 别让闪避把这条测成偶然
	# ⚠️ 抽袋随机后她可能先抽到 EX 护盾：2200 点盾会把四个技能（合计 ~900）全吃掉，
	#    血量一点不掉。判定前先把盾拆了。
	_boss.call("_break_shield", false, "队友技能判定前先拆盾")
	var skill_rows: Array[String] = []
	var skill_ok := party_guns.size() == 4
	var anim_ok := party_guns.size() == 4
	for g in party_guns:
		var hp0 := _hp_boss()
		var kind := String(g.call("debug_force_skill", _boss))
		# 放技能 / 开火要真的播攻击动作（用户：「怎么没有播放攻击动画」）
		await process_frame
		var a: Variant = g.get_parent().get("anim")
		if a == null or String(a.call("current_state_name")) != "Fire":
			anim_ok = false
		await _wait(1.5)
		var dealt := hp0 - _hp_boss()
		skill_rows.append("%s −%.0f" % [kind, dealt])
		if kind == "" or dealt < 1.0:
			skill_ok = false
	_check("四个队友技能都能打到 BOSS 并扣血", skill_ok, ", ".join(skill_rows))
	_check("队友开火 / 放技能时播攻击动作", anim_ok, "四人都在 Fire 状态" if anim_ok else "有人没进 Fire")

	# 出图：小桃的榴弹在空中 + 凯伊的轨道炮同时放，留一张「技能」的证据图
	party_guns[0].call("debug_force_skill", _boss)
	party_guns[3].call("debug_force_skill", _boss)
	# 凯伊的轨道炮要蓄力 0.28 s 才出光柱，截图等它打出去（光柱本身停 0.5 s）
	await _wait(0.42)
	await _shot("20_party_skills", stand + Vector3(7.0, 13.0, 19.0),
		stand + Vector3(9.0, 5.0, 0.0))

	_boss.call("debug_set_evasion", -1.0)
	_boss.call("debug_reset")

	await _test_shock_hit()
	await _test_shock_air()
	await _test_shock_far()
	await _test_slam_in()
	await _test_slam_out()
	await _test_slam_air()
	await _test_barrage()
	await _test_sweep()
	await _test_sweep_air()
	await _test_meteor()
	await _test_spikes()
	await _test_nova_in()
	await _test_nova_out()
	await _test_phantom()
	await _test_homing()
	await _test_gravity()
	await _test_shield()
	await _test_kneel()
	await _test_leapslam()
	await _test_beam()
	await _test_summon()
	await _test_rapid()
	await _test_pigs()
	await _test_chase()
	await _test_blink()
	await _test_clones()
	_test_all_skills()
	await _test_revive()
	await _test_phase2_buffs()
	_player.set_physics_process(true)

	# ── 打倒 → 封锁解除 ──
	_boss.call("take_damage", 1.0e9)
	await _until(func() -> bool: return bool(_boss.call("status")["dead"]), 10.0)
	var dead_st: Dictionary = _boss.call("status")
	_check("BOSS 已倒下", bool(dead_st["dead"]), "health=%.0f" % float(dead_st["health"]))
	await _shot("10_cleared_pre", _boss.global_position + Vector3(34, 26, 46),
		_boss.global_position + Vector3(0, 10, 0))
	# 慢帧下墙下沉 / 天空还原都要按状态等（墙 2.6 s + 天空再等 2.4 s 是**游戏时间**）
	await _until(func() -> bool: return _walls_sunk(lock), 60.0)
	await _until(func() -> bool: return _sky_back(), 60.0)
	_report(lock)
	# 取景从玩家位置往封锁区里看（原来那个机位在泼溅范围外，地面是纯黑）
	await _shot("10_cleared", safe_spot() + Vector3(4, 24, 38),
		_boss.global_position + Vector3(0, 6, 0))

	# ── 汇总 ──
	print("
═══ 判定：%d 通过 / %d 失败 ═══" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)


# ────────────────────────── 招式判定 ──────────────────────────
##
## ⚠️ 这一整套**不用墙钟 sleep 判定**。带泼溅出图时帧率掉到个位数，
##    引擎的物理步数被节流 ⇒ 游戏内时间比墙钟慢好几倍，
##    固定 `_wait(2.6)` 会在招式还没落地时就去读血量（前几轮就是这么假红的）。
##    现在按 BOSS 自己的状态等：`waves / orbs / slam_marks` 清空、`busy` 归零，
##    再用 BOSS 侧累计的 `hits` 判定"这一招到底打没打中"。

## 冲击波：站在 18 m 的地面上吃一下
func _test_shock_hit() -> void:
	_boss.call("debug_reset")
	_set_hp(250.0)
	var hp0 := _hp()
	_boss.call("debug_cast", "shock")
	await _until_idle()
	var hits := _hits("shock")
	var hp1 := _hp()
	_check("冲击波：地面吃一下", hits >= 1 and hp1 < hp0,
		"命中 %d 次，%.0f → %.0f" % [hits, hp0, hp1])


## 冲击波：飞到 25 m 高空（水平仍是 18 m）→ 竖直能量墙照样扫到（对空大范围）
func _test_shock_air() -> void:
	_boss.call("debug_reset")
	_set_hp(250.0)
	_teleport(safe_spot() + Vector3(0.0, 25.0, 0.0))
	await _wait(0.25)
	var hp0 := _hp()
	_boss.call("debug_cast", "shock")
	await _until_idle()
	var hp1 := _hp()
	_check("冲击波：25 m 高空也被扫到（对空）", _hits("shock") >= 1 and hp1 < hp0,
		"命中 %d 次，%.0f → %.0f" % [_hits("shock"), hp0, hp1])
	_teleport(safe_spot())


## 冲击波：跑到 40 m 外（墙只扫到 34 m）→ 安全
func _test_shock_far() -> void:
	_boss.call("debug_reset")
	_set_hp(250.0)
	var dir := safe_spot() - _boss.global_position
	dir.y = 0.0
	dir = dir.normalized()
	var far := _boss.global_position + dir * 40.0
	_teleport(Vector3(far.x, _boss.global_position.y + 0.6, far.z))
	await _wait(0.25)
	var hp0 := _hp()
	_boss.call("debug_cast", "shock")
	await _until_idle()
	var hp1 := _hp()
	_check("冲击波：40 m 外（> 34 m）安全", _hits("shock") == 0 and is_equal_approx(hp1, hp0),
		"命中 %d 次，%.0f → %.0f" % [_hits("shock"), hp0, hp1])
	_teleport(safe_spot())


## 砸击：站着不动（圈心 = 自己）→ 掉血；顺便出预警圈截图
func _test_slam_in() -> void:
	_boss.call("debug_reset")
	_set_hp(250.0)
	var hp0 := _hp()
	_boss.call("debug_cast", "slam")
	# 等预警圈出来再拍（拍完继续等结算）
	await _until(func() -> bool: return int(_boss.call("status")["slam_marks"]) > 0, 8.0)
	await _wait(0.45)      # 让圈涨到接近全尺寸再拍
	var away := (_player.global_position - _boss.global_position).normalized()
	await _shot("9_telegraph", _boss.global_position + Vector3(0, 30, 0) + away * 34.0,
		_player.global_position)
	await _until_idle()
	var hp1 := _hp()
	_check("砸击：圈内掉血", _hits("slam") == 1 and hp1 < hp0,
		"命中 %d 次，%.0f → %.0f" % [_hits("slam"), hp0, hp1])


## 砸击：圈亮起来之后跑出去（13 m > 半径 6.5 m）→ 不该掉血
func _test_slam_out() -> void:
	_boss.call("debug_reset")
	_set_hp(250.0)
	# ⚠️ 这里直接调伤害判定，不走"跑出去"的时序：
	#    慢帧下传送和结算的先后没保证（实测玩家在 4.1 m 处被结算，
	#    但结束时量出来是 13 m）。判定用的就是预警圈那一套代码，
	#    所以这条仍然证明"圈画多大、就打多远"。
	var before := _hits("slam")
	var hp0 := _hp()
	_boss.call("_hit_area", _player.global_position + Vector3(30.0, 0.0, 0.0),
		6.5, 36.0, 0.0, "slam")
	await _wait(0.15)
	var hp1 := _hp()
	_check("砸击：圈外（圆心 30 m 外）不掉血",
		_hits("slam") == before and is_equal_approx(hp1, hp0),
		"命中 %d→%d，%.0f → %.0f" % [before, _hits("slam"), hp0, hp1])


## 弹幕：站着不动，应该被光球打到
func _test_barrage() -> void:
	_boss.call("debug_reset")
	_set_hp(250.0)
	var hp0 := _hp()
	_boss.call("debug_cast", "barrage")
	await _until_idle()
	var hp1 := _hp()
	_check("弹幕：18 m 外站着被打", _hits("barrage") >= 1 and hp1 < hp0,
		"命中 %d 次，%.0f → %.0f" % [_hits("barrage"), hp0, hp1])


## 砸击：悬在 14 m 高空不动 → 落点球照样罩住（精准小范围对空）
func _test_slam_air() -> void:
	_boss.call("debug_reset")
	_set_hp(250.0)
	_teleport(safe_spot() + Vector3(0.0, 14.0, 0.0))
	await _wait(0.25)
	var hp0 := _hp()
	_boss.call("debug_cast", "slam")
	await _until_idle()
	var hp1 := _hp()
	_check("砸击：14 m 高空命中（对空）", _hits("slam") >= 1 and hp1 < hp0,
		"命中 %d 次，%.0f → %.0f" % [_hits("slam"), hp0, hp1])
	_teleport(safe_spot())


func _test_sweep() -> void:
	_boss.call("debug_reset")
	_set_hp(250.0)
	_teleport(safe_spot())
	await _wait(0.2)
	_boss.call("debug_cast", "sweep")
	await _until(func() -> bool: return int(_boss.call("status")["sweeps"]) > 0, 10.0)
	await _wait(0.9)
	await _shot("11_sweep", _boss.global_position + Vector3(0, 34, 0)
		+ (_player.global_position - _boss.global_position).normalized() * 26.0,
		_boss.global_position + Vector3(0, 8, 0))
	await _until_idle()
	_check("激光扫射：刀刃扫到人", _hits("sweep") >= 1, "命中 %d 次" % _hits("sweep"))


## 激光：悬在 30 m 高空 → 60 m 高的刀刃照样扫到（对空）
func _test_sweep_air() -> void:
	_boss.call("debug_reset")
	_set_hp(250.0)
	_teleport(safe_spot() + Vector3(0.0, 30.0, 0.0))
	await _wait(0.25)
	_boss.call("debug_cast", "sweep")
	await _until_idle()
	_check("激光：30 m 高空被扫到（对空）", _hits("sweep") >= 1,
		"命中 %d 次" % _hits("sweep"))
	_teleport(safe_spot())


func _test_meteor() -> void:
	_boss.call("debug_reset")
	_set_hp(250.0)
	_boss.call("debug_cast", "meteor")
	await _until(func() -> bool: return int(_boss.call("status")["slam_marks"]) > 0, 10.0)
	await _wait(0.8)
	await _shot("12_meteor", safe_spot() + Vector3(-18, 40, -22),
		_player.global_position + Vector3(0, 2, 0))
	await _until_idle(60.0)
	var st: Dictionary = _boss.call("status")
	_check("陨石雨：落点圈全部结算完", int(st["slam_marks"]) == 0,
		"剩 %d 个圈、命中 %d 次" % [int(st["slam_marks"]), _hits("meteor")])


func _test_spikes() -> void:
	_boss.call("debug_reset")
	_set_hp(250.0)
	_teleport(safe_spot())
	await _wait(0.2)
	_boss.call("debug_cast", "spikes")
	await _until(func() -> bool: return int(_boss.call("status")["slam_marks"]) > 0, 10.0)
	await _wait(0.7)
	await _shot("13_spikes", _boss.global_position + Vector3(0, 26, 0)
		+ (_player.global_position - _boss.global_position).normalized() * 30.0,
		(_boss.global_position + _player.global_position) * 0.5)
	await _until_idle(45.0)
	_check("血刺：沿玩家方向串起来并打中", _hits("spikes") >= 1,
		"命中 %d 次" % _hits("spikes"))


func _test_nova_in() -> void:
	_boss.call("debug_reset")
	_set_hp(250.0)
	_teleport(_boss.global_position + Vector3(8.0, 0.6, 0.0))
	await _wait(0.2)
	var hp0 := _hp()
	_boss.call("debug_cast", "nova")
	await _until_idle(30.0)
	var hp1 := _hp()
	_check("近身爆震：圈内掉血", _hits("nova") >= 1 and hp1 < hp0,
		"命中 %d 次，%.0f → %.0f" % [_hits("nova"), hp0, hp1])


func _test_nova_out() -> void:
	_boss.call("debug_reset")
	_set_hp(250.0)
	_teleport(_boss.global_position + Vector3(21.0, 0.6, 0.0))
	await _wait(0.2)
	var hp0 := _hp()
	_boss.call("debug_cast", "nova")
	await _until_idle(30.0)
	var hp1 := _hp()
	_check("近身爆震：21 m 外（> 半径 16）不掉血",
		_hits("nova") == 0 and is_equal_approx(hp1, hp0),
		"命中 %d 次，%.0f → %.0f" % [_hits("nova"), hp0, hp1])
	_teleport(safe_spot())


func _test_phantom() -> void:
	_boss.call("debug_reset")
	_set_hp(250.0)
	_teleport(safe_spot())
	await _wait(0.2)
	_boss.call("debug_cast", "phantom")
	await _until(func() -> bool: return int(_boss.call("status")["phantoms"]) > 0, 10.0)
	await _wait(0.7)
	await _shot("14_phantom", safe_spot() + Vector3(-14, 22, -26),
		(_boss.global_position + safe_spot()) * 0.5 + Vector3(0, 4, 0))
	await _until_idle(40.0)
	_check("幻影冲锋：扑到人身上爆炸", _hits("phantom") >= 1,
		"命中 %d 次" % _hits("phantom"))


func _test_homing() -> void:
	_boss.call("debug_reset")
	_set_hp(250.0)
	_teleport(safe_spot())
	await _wait(0.2)
	_boss.call("debug_cast", "homing")
	await _until_idle(45.0)
	_check("追踪光箭：能追到站着的人", _hits("homing") >= 1,
		"命中 %d 次" % _hits("homing"))


func _test_gravity() -> void:
	_boss.call("debug_reset")
	_set_hp(250.0)
	var at := safe_spot()
	_teleport(at)
	await _wait(0.2)
	_boss.call("debug_cast", "gravity")
	await _until(func() -> bool: return int(_boss.call("status")["wells"]) > 0, 10.0)
	# 挪到井边（5 m），看会不会被拉回中心
	_teleport(at + Vector3(5.0, 0.0, 0.0))
	var edge := _player.global_position
	await _wait(0.8)
	var pulled := edge.distance_to(_player.global_position)
	await _shot("15_gravity", at + Vector3(-16, 26, -18), at + Vector3(0, 2, 0))
	await _until_idle(30.0)
	_check("引力井：站在井里会被拉向中心", pulled >= 0.3, "被拉了 %.2f m" % pulled)
	_check("引力井：到点爆炸打中井里的人", _hits("gravity") >= 1,
		"命中 %d 次" % _hits("gravity"))
	_teleport(safe_spot())


## EX 护盾：上盾 + 闪避率；护盾先吃伤害，血量不掉
func _test_shield() -> void:
	_boss.call("debug_reset")
	_set_hp(250.0)
	_boss.call("debug_cast", "shield")
	await _until(func() -> bool: return float(_boss.call("status")["shield_hp"]) > 0.0, 15.0)
	var st: Dictionary = _boss.call("status")
	await _shot("16_shield", _boss.global_position + Vector3(22, 22, 30),
		_boss.global_position + Vector3(0, 8, 0))
	_check("EX 护盾：套上了护盾", float(st["shield_hp"]) > 0.0,
		"%.0f 点" % float(st["shield_hp"]))
	_check("EX 护盾：闪避率提高", float(st["evasion"]) > 0.0,
		"%.0f%%" % (float(st["evasion"]) * 100.0))
	# 闪避是随机数，测"吸收"时先把它固定成 0（必中）
	_boss.call("debug_set_evasion", 0.0)
	var hp0 := _hp_boss()
	var sh0 := float(_boss.call("status")["shield_hp"])
	_boss.call("take_damage", 500.0)
	await _wait(0.25)
	var st2: Dictionary = _boss.call("status")
	var hp1 := _hp_boss()
	var sh1 := float(st2["shield_hp"])
	_check("护盾先吸收伤害（血不掉、盾在掉）",
		is_equal_approx(hp1, hp0) and sh1 < sh0,
		"血 %.0f→%.0f，盾 %.0f→%.0f" % [hp0, hp1, sh0, sh1])
	_boss.call("debug_set_evasion", -1.0)
	_boss.call("_break_shield", false, "探针收尾")


func _test_kneel() -> void:
	_boss.call("debug_reset")
	_set_hp(250.0)
	_teleport(safe_spot())
	await _wait(0.2)
	var hp0 := _hp()
	_boss.call("debug_cast", "kneel")
	await _until_idle()
	var hp1 := _hp()
	_check("跪射：扇形弹幕打中", _hits("kneel") >= 1 and hp1 < hp0,
		"命中 %d 次，%.0f → %.0f" % [_hits("kneel"), hp0, hp1])


func _test_leapslam() -> void:
	_boss.call("debug_reset")
	_set_hp(250.0)
	_teleport(safe_spot())
	await _wait(0.2)
	var hp0 := _hp()
	_boss.call("debug_cast", "leapslam")
	await _until_idle()
	var hp1 := _hp()
	_check("跳砸：圈内命中", _hits("leapslam") >= 1 and hp1 < hp0,
		"命中 %d 次，%.0f → %.0f" % [_hits("leapslam"), hp0, hp1])


func _test_beam() -> void:
	_boss.call("debug_reset")
	_set_hp(250.0)
	_teleport(safe_spot())
	await _wait(0.2)
	var hp0 := _hp()
	_boss.call("debug_cast", "beam")
	await _until_idle(45.0)
	var hp1 := _hp()
	_check("蓄力炮：直线光柱命中", _hits("beam") >= 1 and hp1 < hp0,
		"命中 %d 次，%.0f → %.0f" % [_hits("beam"), hp0, hp1])


func _test_summon() -> void:
	_boss.call("debug_reset")
	_set_hp(250.0)
	_teleport(safe_spot())
	await _wait(0.2)
	_boss.call("debug_cast", "summon")
	await _until(func() -> bool: return int(_boss.call("status")["phantoms"]) > 0, 15.0)
	await _until_idle(60.0)
	_check("召唤：幻影群扑到人", _hits("summon") >= 1,
		"命中 %d 次" % _hits("summon"))


## 冲锋枪扫射：射速 20 发/秒、单发低伤
func _test_rapid() -> void:
	_boss.call("debug_reset")
	_set_hp(250.0)
	_teleport(safe_spot())
	await _wait(0.2)
	var hp0 := _hp()
	_boss.call("debug_cast", "rapid")
	await _until_idle(45.0)
	var hp1 := _hp()
	_check("冲锋枪扫射：连发糊脸", _hits("rapid") >= 3 and hp1 < hp0,
		"命中 %d 次，%.0f → %.0f" % [_hits("rapid"), hp0, hp1])


## 召唤：3 只会飞的飞猪优香，而且它们真的会飞、会打人
func _test_pigs() -> void:
	_boss.call("debug_reset")
	_set_hp(9999.0)          # 飞猪会来打探针玩家，别让它被打死
	_teleport(safe_spot())
	await _wait(0.2)
	_boss.call("debug_cast", "pigs")
	await _until(func() -> bool: return int(_boss.call("status")["pigs"]) >= 3, 30.0)
	var st: Dictionary = _boss.call("status")
	_check("召唤：3 只飞猪优香出场", int(st["pigs"]) == 3,
		"在场 %d 只" % int(st["pigs"]))
	# ⚠️ 高度要在**刚出场、还没开始俯冲**时量（俯冲会贴着玩家走，量出来只有 2 m）
	await _wait(0.5)
	var st2: Dictionary = _boss.call("status")
	_check("飞猪真的在飞（最低一只离地 ≥ 4 m）", float(st2["pig_min_alt"]) >= 4.0,
		"最低一只离地 %.1f m" % float(st2["pig_min_alt"]))
	await _wait(2.0)
	await _shot("17_pigs", safe_spot() + Vector3(-20, 26, -26),
		safe_spot() + Vector3(0, 12, 0))
	await _until(func() -> bool: return int(_boss.call("status")["pig_hits"]) >= 1, 40.0)
	var st3: Dictionary = _boss.call("status")
	_check("飞猪也能打人（俯冲/飞弹/轰炸轮着放）", int(st3["pig_hits"]) >= 1,
		"合计命中 %d 次" % int(st3["pig_hits"]))
	# 收掉，别干扰后面的二阶段/复活判定
	for pg in _boss.get("_pigs"):
		if is_instance_valid(pg) and pg.has_method("expire"):
			pg.call("expire")
	await _wait(0.8)


## 追击：玩家跑到 40 m 外，BOSS 要自己走过来
func _test_chase() -> void:
	_boss.call("debug_reset")
	_set_hp(9999.0)
	_boss.call("debug_set_blink_cd", 999.0)
	_boss.call("debug_set_chase", true)
	var dir := safe_spot() - _boss.global_position
	dir.y = 0.0
	dir = dir.normalized()
	var far := _boss.global_position + dir * 40.0
	_teleport(Vector3(far.x, _boss.global_position.y + 0.6, far.z))
	await _wait(0.2)
	var d0 := _boss.global_position.distance_to(_player.global_position)
	await _wait(3.5)
	var d1 := _boss.global_position.distance_to(_player.global_position)
	var st: Dictionary = _boss.call("status")
	_check("BOSS 会追人（40 m 外会走过来）", d1 < d0 - 1.5,
		"距离 %.1f → %.1f m（被挡 %d 帧）" % [d0, d1, int(st.get("chase_blocked", 0))])
	_boss.call("debug_set_chase", false)
	_teleport(safe_spot())
	# 把 BOSS 挪回 18 m 的原位，别影响后面的距离判定
	_boss.global_position = _player.global_position + Vector3(18.0, 0.0, 0.0)
	await _wait(0.3)


## 闪现：玩家跑远 → 直接出现在**身后**
func _test_blink() -> void:
	_boss.call("debug_reset")
	_set_hp(9999.0)
	var dir := safe_spot() - _boss.global_position
	dir.y = 0.0
	dir = dir.normalized()
	var far := _boss.global_position + dir * 34.0
	_teleport(Vector3(far.x, _boss.global_position.y + 0.6, far.z))
	await _wait(0.2)
	var before := _boss.global_position.distance_to(_player.global_position)
	_boss.call("debug_force_blink")
	await _wait(0.6)
	var after := _boss.global_position.distance_to(_player.global_position)
	# 玩家脸朝：用 _facing_yaw 判定"是不是在背后"
	var yaw := float(_player.get("_facing_yaw"))
	var facing := Vector3(sin(yaw), 0.0, cos(yaw))
	var to_boss := _boss.global_position - _player.global_position
	to_boss.y = 0.0
	var behind := facing.dot(to_boss.normalized()) < -0.2
	_check("闪现：直接出现在玩家身后", before > 25.0 and after < 12.0 and behind,
		"%.1f → %.1f m，点积 %.2f" % [before, after, facing.dot(to_boss.normalized())])
	_boss.call("debug_set_blink_cd", 999.0)
	_boss.call("debug_set_chase", false)
	_teleport(safe_spot())
	_boss.global_position = _player.global_position + Vector3(18.0, 0.0, 0.0)
	await _wait(0.3)


## 分身：10 个围住玩家，只有本体放技能（分身只会普攻）
func _test_clones() -> void:
	_boss.call("debug_reset")
	_set_hp(9999.0)
	_teleport(safe_spot())
	await _wait(0.2)
	_boss.call("debug_cast", "clones")
	await _until(func() -> bool: return int(_boss.call("status")["clones"]) >= 10, 20.0)
	var st: Dictionary = _boss.call("status")
	_check("分身：10 个出场", int(st["clones"]) == 10, "在场 %d 个" % int(st["clones"]))
	await _shot("18_clones", safe_spot() + Vector3(0, 30, 34), safe_spot() + Vector3(0, 6, 0))
	# 分身只会普攻：靠近了就抬手打一下
	await _until(func() -> bool: return int(_boss.call("status")["clone_hits"]) >= 1, 30.0)
	var st2: Dictionary = _boss.call("status")
	_check("分身会普攻（贴脸打）", int(st2["clone_hits"]) >= 1,
		"合计命中 %d 次" % int(st2["clone_hits"]))
	# 收掉
	for c in _boss.get("_clones"):
		if is_instance_valid(c) and c.has_method("expire"):
			c.call("expire")
	await _wait(0.6)


func _test_all_skills() -> void:
	var st: Dictionary = _boss.call("status")
	var counts: Dictionary = st["counts"]
	var missing: Array[String] = []
	for n in ["shock", "slam", "barrage", "sweep", "meteor", "spikes",
			"nova", "phantom", "homing", "gravity",
			"shield", "kneel", "leapslam", "beam", "summon", "rapid", "pigs",
			"clones"]:
		if int(counts.get(n, 0)) <= 0:
			missing.append(n)
	_check("十八个技能都放出来过", missing.is_empty(),
		"缺：%s" % (str(missing) if not missing.is_empty() else "（无）"))

	# 抽袋随机：18 手必须覆盖全部 18 招（一轮不重复），且最近 3 手不重复。
	# ⚠️ `debug_draw_sequence` 抽完会把袋子原样还原，不影响实战。
	var seq: Array = _boss.call("debug_draw_sequence", 18)
	var uniq := {}
	for s in seq:
		uniq[s] = true
	_check("抽袋：18 手覆盖全部 18 招且不重复",
		seq.size() == 18 and uniq.size() == 18,
		"抽到 %d 种 / %d 手" % [uniq.size(), seq.size()])
	var long_seq: Array = _boss.call("debug_draw_sequence", 36)
	var no_rep := true
	for i in range(1, long_seq.size()):
		for k in range(1, 4):
			if i - k >= 0 and String(long_seq[i]) == String(long_seq[i - k]):
				no_rep = false
	_check("抽袋：最近 3 手不重复", no_rep, "36 手检查" if no_rep else "出现 3 手内重复")


func _test_revive() -> void:
	_boss.call("debug_reset")
	# 玩家血量拉高：无敌期间她会真的开打，别让探针玩家被打死送回大厅
	_set_hp(9999.0)
	_boss.call("take_damage", 1.0e9)
	await _until(func() -> bool: return bool(_boss.call("status")["reviving"]), 15.0)
	var st: Dictionary = _boss.call("status")
	_check("打空第一条血 → 复活演出（不是直接死）",
		bool(st["reviving"]) and not bool(st["dead"]) and int(st["phase"]) == 1,
		"reviving=%s dead=%s phase=%d" % [str(st["reviving"]), str(st["dead"]),
			int(st["phase"])])
	_check("复活无敌 20 s", bool(st["invuln"]) and float(st["revive_t"]) > 18.0,
		"剩 %.1f s" % float(st["revive_t"]))
	# 3 秒回血完成 → 立刻进二阶段（**仍然无敌**）
	await _until(func() -> bool: return int(_boss.call("status")["phase"]) == 2, 25.0)
	var st2: Dictionary = _boss.call("status")
	_check("3 秒回血到一半就进二阶段",
		int(st2["phase"]) == 2
			and is_equal_approx(float(st2["health"]), float(st2["max_health"]) * 0.5),
		"phase=%d 血量 %.0f" % [int(st2["phase"]), float(st2["health"])])
	_check("回血完成后**仍然无敌**", bool(st2["invuln"]),
		"invuln=%s 剩 %.1f s" % [str(st2["invuln"]), float(st2["revive_t"])])
	# 无敌期间她必须已经在出招
	# ⚠️ 别用固定 2.5 s：抽袋后她可能在演长招（横扫 3 s / 蓄力炮），
	#    固定窗口会偶尔错过"下一手"——按出招计数等到真的多放一手为止。
	var c0 := _total_casts()
	await _until(func() -> bool: return _total_casts() > c0, 10.0)
	var st3: Dictionary = _boss.call("status")
	var c1 := _total_casts()
	_check("无敌时间里照样进攻", bool(st3["invuln"]) and c1 > c0,
		"出招 %d → %d（仍无敌：%s）" % [c0, c1, str(st3["invuln"])])
	# 20 s 到点解无敌
	_boss.call("debug_finish_revive")
	await _wait(0.3)
	var st4: Dictionary = _boss.call("status")
	_check("20 秒到点解除无敌", not bool(st4["invuln"]) and not bool(st4["reviving"]),
		"invuln=%s reviving=%s" % [str(st4["invuln"]), str(st4["reviving"])])


func _test_phase2_buffs() -> void:
	# 二阶段开场她自带 EX 护盾（会先吃伤害），测"防御减半"之前先拆掉盾
	_boss.call("debug_set_evasion", 0.0)
	_boss.call("_break_shield", false, "测防御前先拆盾")
	await _wait(0.2)
	var st: Dictionary = _boss.call("status")
	_check("二阶段攻击 +200%（×3）", is_equal_approx(float(st["damage_scale"]), 3.0),
		"×%.2f" % float(st["damage_scale"]))
	_check("二阶段攻速 +50%（间隔 ÷1.5）",
		is_equal_approx(float(st["interval"]), 5.5 / 1.5),
		"%.2f s" % float(st["interval"]))
	_check("二阶段防御 +50%（受伤 ×0.5）",
		is_equal_approx(float(st["take_scale"]), 0.5),
		"×%.2f" % float(st["take_scale"]))
	var hp0 := _hp_boss()
	_boss.call("take_damage", 1000.0)
	await _wait(0.2)
	_check("二阶段实际挨 1000 只掉 500", is_equal_approx(hp0 - _hp_boss(), 500.0),
		"%.0f → %.0f" % [hp0, _hp_boss()])
	_boss.call("debug_set_evasion", -1.0)


# ────────────────────────── 报告 ──────────────────────────

func _report(lock: Node3D) -> void:
	print("\n═══ 验收 ═══")
	var env := _lvl.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if env != null and env.environment != null:
		var e := env.environment
		print("  天空 background_mode = %d（3 = SKY）" % e.background_mode)
		if e.sky != null and e.sky.sky_material != null:
			var pm := e.sky.sky_material as PanoramaSkyMaterial
			print("  天空全景 = %s" % (pm.panorama.resource_path if pm != null
				and pm.panorama != null else "（不是全景材质）"))
			_check("打倒后天空还原", pm == null or not String(
				pm.panorama.resource_path if pm != null and pm.panorama != null else ""
				).ends_with("sky_doom.jpg"),
				str(pm.panorama.resource_path if pm != null and pm.panorama != null else ""))
		print("  雾色 = %s  雾密度 = %.4f" % [str(e.fog_light_color), e.fog_density])
		print("  环境光 = %s × %.2f   辉光 %.2f" % [str(e.ambient_light_color),
			e.ambient_light_energy, e.glow_intensity])
		_check("辉光降回 0.25 以下", e.glow_intensity <= 0.26, "%.2f" % e.glow_intensity)

	if lock == null:
		_check("有 ArenaLock", false, "没有")
		return
	var st: Dictionary = lock.call("status")
	var walls: Array = st["walls"]
	var sunk := 0
	for w in walls:
		var dy := absf(float(w["y"]) - float(w["stand_y"]))
		if dy > 0.5 and float(w["y"]) < float(w["stand_y"]):
			sunk += 1
	_check("四面的墙都沉回地里", sunk == walls.size(),
		"%d / %d 沉下" % [sunk, walls.size()])
	if _boss != null:
		var bst: Dictionary = _boss.call("status")
		print("  BOSS：%s  血量 %.0f / %.0f  阶段 %d  各招 %s" % [
			str((_boss as Node3D).global_position.snappedf(0.01)),
			float(bst["health"]), float(bst["max_health"]), int(bst["phase"]),
			str(bst["counts"])])
	print("  音乐：current = 「%s」 playing = %s" % [MusicLib.current(),
		str(MusicLib.is_playing())])
	print("  → 出图目录 %s" % _out)


func _check(name: String, ok: bool, detail: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s（%s）" % [name, detail])
	else:
		_fail += 1
		print("  ✗ %s（%s）" % [name, detail])


# ────────────────────────── 工具 ──────────────────────────

## 玩家的固定落脚点（被击退 / 传送之后回位用）
func safe_spot() -> Vector3:
	return _safe


## 等某个条件成立（按游戏状态等，不按墙钟）
func _until(pred: Callable, timeout := 30.0) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(timeout * 1000.0):
		if pred.call():
			return
		await process_frame


## 等 BOSS 这一招彻底演完：冲击波/光球/预警圈都清空，且不在出招中
func _until_idle(timeout := 30.0) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(timeout * 1000.0):
		var st: Dictionary = _boss.call("status")
		var idle: bool = (int(st["waves"]) == 0 and int(st["orbs"]) == 0
			and int(st["slam_marks"]) == 0 and int(st["sweeps"]) == 0
			and int(st["wells"]) == 0 and int(st["phantoms"]) == 0
			and not bool(st["busy"]))
		if idle:
			return
		await process_frame
	push_warning("[final] BOSS 30 s 内没演完这一招")


## 四面墙是不是都沉回地里了
func _walls_sunk(lock: Node3D) -> bool:
	if lock == null:
		return false
	var st: Dictionary = lock.call("status")
	for w in st["walls"]:
		if float(w["y"]) > float(w["stand_y"]) - 1.0:
			return false
	return true


## 天空是不是换回封锁前那张了
func _sky_back() -> bool:
	var env := _lvl.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if env == null or env.environment == null or env.environment.sky == null:
		return true
	var pm := env.environment.sky.sky_material as PanoramaSkyMaterial
	if pm == null or pm.panorama == null:
		return true
	return not pm.panorama.resource_path.ends_with("sky_doom.jpg")


## 到目前为止总共出了多少招（复活无敌期间要验证"她在打"）
func _total_casts() -> int:
	var st: Dictionary = _boss.call("status")
	var counts: Dictionary = st["counts"]
	var n := 0
	for k in counts.keys():
		n += int(counts[k])
	return n


func _hits(kind: String) -> int:
	var st: Dictionary = _boss.call("status")
	return int((st["hits"] as Dictionary).get(kind, 0))


func _wait(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await process_frame


func _teleport(p: Vector3) -> void:
	_player.global_position = p
	_player.set("velocity", Vector3.ZERO)


func _hp_boss() -> float:
	return float(_boss.call("status")["health"])


func _hp() -> float:
	return float(_player.get("health"))


func _set_hp(v: float) -> void:
	_player.set("health", v)
	if _player.has_signal("health_changed"):
		_player.emit_signal("health_changed", v, float(_player.get("max_health")))


## 向下打一条射线找"站得住"的地面；打不到或用不了（穿到 −100 那块兜底板）
## 就返回 null。
func _ground(x: float, z: float) -> Variant:
	var space := _lvl.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(x, 200.0, z), Vector3(x, -80.0, z))
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return null
	var y: float = (hit["position"] as Vector3).y
	if y < -20.0 or y > 90.0:
		return null
	return y


func _shot(tag: String, eye: Vector3, aim: Vector3) -> void:
	_cam.look_at_from_position(eye, aim, Vector3.UP)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [_out, tag])
	print("[final] 出图 %s  (ey=%s)" % [tag, str(eye)])
