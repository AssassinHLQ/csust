extends SceneTree
## 验跑酷 v2（4 段 / 33 站 / 30 跳 + 2 段独木桥 / 206 m）。
##
## 和别的自检不一样：这一套的主体是**用真输入开一个真玩家，把 30 跳挨个跳过去**。
## 几何对不对可以算，但「人到底跳不跳得过去」只有一个可信的判据：跳给他看。
##
## 七节：
##   1. 结构与几何 —— 站数/顺序、网格↔碰撞 AABB、0.05 网格、碰撞层、分段数据、灯与牌子
##   2. 胶囊与台面 —— 站在板上是台面 +0.000；**挂边容忍**；0.80 m 窄梁的横向余量
##   3. 实测跳跃能力 —— 空域二分法量「平跳最远」「抬升 0.80 最远」，再拿它核对每一跳
##   4. 逐跳回放 —— 每一跳单独跳一次；最后**一口气通一次关**（不重置、不停顿）
##   5. 反例 —— 不跳过不去；摔下去回**本段起点**；传送台；**计时器起停与最好成绩**
##   6. 与平台既有东西不打架
##   7. 终点区域
##
## 用法：
##   godot --path <工程> --script res://scripts/_verify_parkour.gd -- --splat=off
##
## ⚠️ 四条纪律：
##   · **等真实毫秒**，不等帧数（真窗口能跑到 1000+ fps）
##   · 开局把鼠标设成 VISIBLE（有人碰鼠标不会把视角带歪）
##   · 每一节自己摆好人和检查点状态，不靠上一节的残留
##   · 全程**不截图**（截图是无界等待的重灾区，别的套件已经踩过）
##
## ⚠️ 时间预算：本套跑完约 2 分钟（运行器有 6 分钟看门狗）。
##    所以「紧张的跳」全部真输入跑，「余量大的跳」也跑（30 跳 × ~1.2 s 还负担得起），
##    连续通关再跑一遍 —— 加起来仍远低于看门狗。

const SPAWN := Vector3(0, 0.05, 6)
## 「离边缘还有多少米就按跳」。跑速 6.8 m/s、物理 60 Hz ⇒ 一格 0.113 m，
## 所以 0.15 大致等于「踩着边起跳」。这个数会直接从余量里扣掉。
const JUMP_LEAD := 0.15
## 起跳前的助跑距离。0.89 m 就能从静止加到满速（v²/2a = 6.8²/52），给 1.6 m 很宽裕
const RUNUP := 1.6
## 助跑短于这个距离时，干脆按「从上一跳冲进来的速度」起步
## （小石台放不下 1.6 m 助跑，而真实玩法里人本来就是带着速度落上去的）
const RUNUP_MIN := 0.9
## 标定台的空域（远离平台和跑酷，免得互相干扰）
const RIG := Vector3(200, 0, 0)
## 实测系数：`实测射程 / 解析射程`（v1 二分法量的 1.054）。第 3 节会重新量一遍。
const K_REF := 1.054
const MARGIN_MIN := 0.40

var _fail := 0
var _pass := 0
var _p: Player
var _pk: Parkour
var _space: PhysicsDirectSpaceState3D
var _m := {}
var _t0 := 0
## 套件开跑前备份的「最好成绩」存档 —— 测完原样还回去
var _best_backup := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_t0 = Time.get_ticks_msec()
	root.size = Vector2i(1280, 720)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(10)
	_p = game.get_node_or_null("Player") as Player
	_pk = game.get_node_or_null("Parkour") as Parkour
	if _p == null or _pk == null:
		print("!! 场景里缺 Player 或 Parkour")
		quit(1)
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_space = _p.get_world_3d().direct_space_state
	_pk._build_route()
	# ⚠️ 这一套会**真的跑完一次全程**，于是 `parkour.gd` 会把那次用时写进
	#    `user://parkour_best.cfg` —— 那是玩家真实存档。开跑前备份、收尾时还回去
	#    （和 `_verify_settings` 测音量时的做法一样）。
	_best_backup = _read_best_file()

	await _test_structure(game)
	await _test_capsule()
	await _test_calibration()
	await _test_hops()
	await _test_negative()
	await _test_clash(game)
	await _test_island()
	await _wait(2)

	print("\n================ 结果 ================")
	print("通过 %d 项" % _pass)
	_print_table()
	_quit()


# --- 1. 结构与几何 -------------------------------------------------------------

func _test_structure(game: Node) -> void:
	print("\n========== 1. 结构与几何 ==========")
	var n := _pk.node_count()
	_check(n == 33, "路线有 %d 站（期望 33：跑道 + 30 块板 + 2 段独木桥 + 岛）" % n)
	var want := ["Launch", "P1", "P2", "P3", "P4", "P5", "P6", "P7", "C1",
		"B1", "BA", "S1", "BB", "T1", "T2", "T3", "T4", "T5", "T6", "C2",
		"U1", "U2", "U3", "U4", "U5", "U6", "C3", "D1", "D2", "D3", "D4", "D5", "Island"]
	var got: Array[String] = []
	for i in n:
		got.append(_pk.label_at(i))
	_check(got == want, "顺序正确（%d 站）：%s" % [got.size(), " → ".join(PackedStringArray(got))])

	# 分段数据：升序、首项为 0、段名对得上
	var segs: Array = _pk.segments
	var sorted_ok := not segs.is_empty() and int(segs[0]) == 0
	for i in range(1, segs.size()):
		if int(segs[i]) <= int(segs[i - 1]):
			sorted_ok = false
	_check(sorted_ok and _pk.segment_count() == 4 and segs.size() == _pk.seg_names.size(),
		"分段数据：segments=%s（升序、首项 0、4 段），seg_names %d 个「%s」"
		% [str(segs), _pk.seg_names.size(), " / ".join(PackedStringArray(_pk.seg_names))])
	# 段起点必须是段落里**第一站**、而且每段都非空
	var span_ok := true
	for s in _pk.segment_count():
		var st := _pk.segment_start(s)
		var en: int = _pk.segment_start(s + 1) if s + 1 < _pk.segment_count() else n
		if en <= st or st < 0 or en > n:
			span_ok = false
	_check(span_ok, "四段的站号区间都不空：%s"
		% str(Array(range(0, 4)).map(func(s): return "%s[%d]" % [
			_pk.segment_name(s), _pk.segment_start(s)])))

	# 网格与碰撞必须指着同一块体积
	var worst := 0.0
	var worst_name := ""
	var mismatched: Array[String] = []
	for i in n:
		var node := _pk.get_node_or_null(NodePath(String(_pk.route[i])))
		if node == null:
			continue
		var mesh := node.get_node_or_null("Mesh") as MeshInstance3D
		var col := node.get_node_or_null("Col") as CollisionShape3D
		if mesh == null or col == null:
			continue          # 跑道标记本来就没有碰撞
		var a := mesh.global_transform * mesh.get_aabb()
		var b := _shape_aabb(col)
		var d := maxf(maxf(absf(a.position.x - b.position.x), absf(a.position.y - b.position.y)),
			maxf(absf(a.position.z - b.position.z), (a.size - b.size).length()))
		if d > worst:
			worst = d
			worst_name = String(node.name)
		if d > 0.001:
			mismatched.append("%s(%.4f)" % [node.name, d])
	_check(mismatched.is_empty(), "每一站「网格 AABB == 碰撞 AABB」（最大偏差 %.4f m @ %s）%s"
		% [worst, worst_name, "" if mismatched.is_empty() else str(mismatched)])

	var runway := _pk.get_node_or_null("Launch") as MeshInstance3D
	var pads_without_col: Array[String] = []
	for i in range(1, n):
		var node := _pk.get_node_or_null(NodePath(String(_pk.route[i])))
		if node != null and node.get_node_or_null("Col") == null:
			pads_without_col.append(String(node.name))
	_check(runway != null and runway.mesh != null and _pk.get_node_or_null("Launch/Col") == null
		and pads_without_col.is_empty(),
		"跑道标记有外观、没碰撞体；其余 %d 站都有碰撞体%s"
		% [n - 1, "" if pads_without_col.is_empty() else "（缺：%s）" % str(pads_without_col)])

	var off: Array[String] = []
	for node in _walk(_pk):
		if not (node is Node3D) or node is Light3D or node is Label3D or node is Area3D:
			continue
		var xf := (node as Node3D).transform
		for v in [xf.origin, xf.basis.get_scale()]:
			for c in 3:
				var q: float = absf(v[c]) / 0.05
				if absf(q - roundf(q)) > 0.001:
					off.append("%s %s=%.3f" % [node.name, "xyz"[c], v[c]])
	_check(off.is_empty(), "所有 position / scale 都落在 0.05 m 网格上%s"
		% ("" if off.is_empty() else "（越界：%s）" % str(off.slice(0, 4))))

	var bad_layer: Array[String] = []
	for node in _walk(_pk):
		if node is StaticBody3D and (node as StaticBody3D).collision_layer != 1:
			bad_layer.append("%s(%d)" % [node.name, (node as StaticBody3D).collision_layer])
	_check(bad_layer.is_empty(), "所有 StaticBody3D 都在碰撞层 1 上（相机 SpringArm 才挡得住）%s"
		% ("" if bad_layer.is_empty() else str(bad_layer)))

	var st := _stats(_pk)
	var shadowed := 0
	for node in _walk(_pk):
		if node is Light3D and (node as Light3D).shadow_enabled:
			shadowed += 1
	_check(st["lights"] <= 2 and shadowed == 0,
		"整条路线只有 %d 盏灯、且全部关阴影（省电：地标用自发光材质，不占灯）"
		% st["lights"])
	_check(st["labels"] >= 6 and _pk.get_node_or_null("ParkourHUD/Timer") != null
		and _pk.get_node_or_null("ParkourHUD/Seg") != null,
		"指路牌 %d 块 + 计时 HUD 两个 Label 都在" % st["labels"])
	print("  小结：%d 个节点，%d 个网格，%d 个碰撞形状，%d 盏灯，%d 个 Label3D"
		% [st["nodes"], st["meshes"], st["shapes"], st["lights"], st["labels"]])


# --- 2. 胶囊与台面（真物理）----------------------------------------------------

func _test_capsule() -> void:
	print("\n========== 2. 胶囊与台面（真物理量的两个数）==========")
	_pk.enabled = false          # 这一节故意要摔下去，别让检查点把人捞回来
	var big := _pk.box_at(8)     # C1：4 × 4 m，段终点的休息台
	var top := _pk.top_at(8)
	var x_mid := big.position.x + big.size.x * 0.5

	for probe in [
		{"label": "板正中", "dx": 0.0, "want": top},
		{"label": "板内沿（距边 0.10）", "dx": -1.90, "want": top},
	]:
		_put(x_mid + float(probe["dx"]), top + 1.0, big.position.z + big.size.z * 0.5)
		await _wait_ms(700)
		_check(absf(_p.global_position.y - float(probe["want"])) < 0.02,
			"%s：站在 y = %.3f（台面 %.2f）" % [probe["label"], _p.global_position.y, top])

	# 挂边：站在板外多远还托得住。
	#
	# ⚠️ 两件事都会把这个数搞错，都踩过：
	#   1. **不能拿「某条边上贴着另一块板」的那一侧测** —— 人不是「挂在边上」，
	#      是**站在旁边那块板上**（v1 量到 +0.40 就是这么来的）。C1 的**南**边缘
	#      外面什么都没有，所以测南边。
	#   2. 几何极限是**胶囊半径**（floor_max_angle 45° ⇒ 0.30 × tan45° = 0.30），
	#      但临界点上掉不掉跟落地那一下的动能有关，所以断言给区间、不给单点。
	var hang := -99.0
	for over in [0.10, 0.20, 0.30, 0.40]:
		_put(x_mid, top + 1.0, big.position.z + big.size.z + float(over))
		await _wait_ms(700)
		if _p.is_on_floor() and _p.global_position.y > top - 0.5:
			hang = float(over)
	_check(hang >= 0.15 and hang <= 0.35,
		"挂边容忍（C1 南边缘）：站到板外 **+%.2f m** 还托得住、+0.40 就掉"
		% hang + "（胶囊半径 0.30 = 几何极限）")
	_m["hang"] = hang

	# 窄梁：横向站多远还站得住 —— 这就是「0.80 m 独木桥」的量化
	var beam := _pk.box_at(10)   # BA：0.80 × 3.50 的独木桥前段
	var bx := beam.position.x + beam.size.x * 0.5
	var bz := beam.position.z + beam.size.z * 0.5
	var btop := _pk.top_at(10)
	var wide := -99.0
	for off in [0.0, 0.20, 0.40, 0.50, 0.60, 0.70]:
		_put(bx, btop + 0.6, bz + float(off))
		await _wait_ms(700)
		if _p.is_on_floor() and _p.global_position.y > btop - 0.5:
			wide = float(off)
	_m["beam_wide"] = wide
	_check(wide >= 0.45 and wide <= 0.75,
		"0.80 m 宽的独木桥：**中心**偏 %.2f m 还站得住、再远就掉（梁半宽 0.40 + 挂边）" % wide)
	_pk.enabled = true
	_release_all()


# --- 3. 实测跳跃能力（标定）+ 逐跳余量核对 -------------------------------------

func _test_calibration() -> void:
	print("\n========== 3. 实测跳跃能力（空域里二分法量）+ 逐跳余量核对 ==========")
	_pk.enabled = false
	var rig := _build_rig()
	var flat := await _bisect_gap(rig, 0.0, 1.5, 6.5)
	var rise := await _bisect_gap(rig, 0.8, 1.0, 5.5)
	rig.queue_free()
	await _wait(2)
	_pk.enabled = true

	var flat_theory := Player.SPEED_RUN * 2.0 * Player.JUMP_VELOCITY / Player.GRAVITY
	var rise_probe := Parkour.hop_analysis(
		AABB(Vector3.ZERO, Vector3(3, 0.5, 3)),
		AABB(Vector3(-4, 0.8, 0), Vector3(3, 0.5, 3)),
		Player.JUMP_VELOCITY, Player.GRAVITY, Player.SPEED_RUN)
	var rise_theory := float(rise_probe["reach"])
	_m["flat"] = flat
	_m["flat_theory"] = flat_theory
	_m["rise"] = rise
	print("  平跳：实测 %.2f m（解析 %.2f m）" % [flat, flat_theory])
	print("  抬升 0.80 m：实测 %.2f m（解析 %.2f m）" % [rise, rise_theory])
	_check(flat >= flat_theory - 0.45, "平跳实测 %.2f m 与解析 %.2f m 相差 ≤ 0.45 m"
		% [flat, flat_theory])
	_check(rise >= rise_theory - 0.45, "抬升 0.80 m 实测 %.2f m 与解析 %.2f m 相差 ≤ 0.45 m"
		% [rise, rise_theory])

	# 用实测系数核对**每一跳**：实测射程 = 解析射程 × k
	var k := flat / flat_theory
	_m["k"] = k
	_check(absf(rise - rise_theory * k) <= 0.45,
		"模型自洽：抬升 0.80 实测 %.2f m 与「解析 × %.3f」= %.2f m 相差 ≤ 0.45"
		% [rise, k, rise_theory * k])
	var worst := INF
	var worst_name := ""
	var bad: Array[String] = []
	var tight := 0
	var jumps := 0
	var gap_sum := 0.0
	for i in range(1, _pk.node_count()):
		var h := _hop(i - 1, i)
		if float(h["required"]) < 0.5:
			continue                       # 走过去（独木桥）
		jumps += 1
		gap_sum += float(h["required"])
		var margin := float(h["reach"]) * k - float(h["required"])
		var name := "%s→%s" % [_pk.label_at(i - 1), _pk.label_at(i)]
		if margin <= 0.90:
			tight += 1
		if margin < worst:
			worst = margin
			worst_name = name
		if margin < MARGIN_MIN:
			bad.append("%s 余量 %.2f" % [name, margin])
	_m["worst_margin"] = worst
	_m["worst_name"] = worst_name
	_m["gap_sum"] = gap_sum
	_m["jumps"] = jumps
	_m["tight"] = tight
	_check(bad.is_empty(), "按**实测**能力核对每一跳：跳 %d 个、跳距合计 %.1f m，最紧的是 %s，"
		% [jumps, gap_sum, worst_name] + "余量 %.2f m（要求 ≥ %.2f）%s"
		% [worst, MARGIN_MIN, "" if bad.is_empty() else str(bad)])
	_check(tight >= int(ceil(jumps / 3.0)),
		"紧张区间（余量 0.40~0.90）：**%d/%d = %.0f%%** ≥ 1/3（v2 的难度指标）"
		% [tight, jumps, 100.0 * tight / maxf(jumps, 1)])


## 在空域搭两组板（起跳板 + 目标板），二分法量「还能跨多远」。
func _build_rig() -> Node3D:
	var rig := Node3D.new()
	rig.name = "ParkourRig"
	root.add_child(rig)
	_add_slab(rig, Vector3(RIG.x, -0.25, 0), Vector3(3, 0.5, 3))
	return rig


func _bisect_gap(rig: Node3D, rise: float, lo: float, hi: float) -> float:
	var target := _add_slab(rig, Vector3(0, 0, 0), Vector3(3, 0.5, 3))
	var ok := lo
	for _step in 6:
		var mid := (lo + hi) * 0.5
		target.position = Vector3(RIG.x - 1.5 - mid - 1.5, rise - 0.25, 0)
		await _wait(2)
		if bool(await _try_rig_jump(target, rise, mid)):
			ok = mid
			lo = mid
		else:
			hi = mid
	return ok


func _try_rig_jump(target: Node3D, rise: float, _gap: float) -> bool:
	_release_all()
	_p.global_position = Vector3(RIG.x + 1.30, 0.05, 0)
	_p.velocity = Vector3.ZERO
	_aim(Vector2(-1, 0))
	await _wait(3)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	var t0 := Time.get_ticks_msec()
	var jumped := false
	while Time.get_ticks_msec() - t0 < 1500:
		await process_frame
		if _p.global_position.x <= RIG.x - 1.5 + JUMP_LEAD and _p.is_on_floor():
			await _jump()
			jumped = true
			break
	if not jumped:
		_release_all()
		return false
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 2000:
		await process_frame
		if _p.is_on_floor() and Time.get_ticks_msec() - t1 > 120:
			break
		if _p.global_position.y < rise - 3.0:
			break
	var good := _p.is_on_floor() \
		and absf(_p.global_position.y - rise) < 0.25 \
		and absf(_p.global_position.x - target.position.x) < 1.8
	_release_all()
	return good


func _add_slab(parent: Node3D, pos: Vector3, size: Vector3) -> Node3D:
	var body := StaticBody3D.new()
	body.position = pos
	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3.ONE
	col.shape = sh
	col.scale = size
	body.add_child(col)
	parent.add_child(body)
	return body


# --- 4. 逐跳回放 ---------------------------------------------------------------

func _test_hops() -> void:
	print("\n========== 4. 逐跳回放（真输入、真物理）==========")
	_pk.enabled = true
	_pk.reset_run()
	var rows: Array[String] = []
	var fails := 0
	var isolated := 0
	var skipped: Array[String] = []
	for i in range(1, _pk.node_count()):
		var h := _hop(i - 1, i)
		var walk := float(h["required"]) < 0.5
		var margin := float(h["reach"]) * K_REF - float(h["required"])
		var pair := "%s→%s" % [_pk.label_at(i - 1), _pk.label_at(i)]
		# 逐跳真跑：全部跑（33 站 × ~1.2 s 还负担得起），这样每一跳都有实测落点
		var res := await _run_hop(i - 1, i, walk)
		isolated += 1
		var ok: bool = bool(res["ok"])
		if not ok:
			fails += 1
		rows.append("%-13s %s 必须跨 %5.2f 抬升 %+5.2f 余量 %5.2f → 实落 (%7.2f,%7.2f) %s" % [
			pair, "走 " if walk else "跳 ", h["required"], h["rise"], margin,
			float(res["pos"].x), float(res["pos"].z), "✓" if ok else "**✗**"])
		_check(ok, "%s：落在 %s 上（y = %.2f，台面 %.2f）"
			% [pair, _pk.label_at(i), float(res["pos"].y), _pk.top_at(i)])
		if not walk:
			var pred: Vector3 = h["landing"]
			var d := Vector2(float(res["pos"].x) - pred.x, float(res["pos"].z) - pred.z).length()
			_check(d <= 0.90, "    解析预测落点与实际相差 %.2f m（≤ 0.90）" % d)
	_check(fails == 0, "33 站逐跳全部通过（真跑 %d 站，失败 %d）" % [isolated, fails])
	print("\n  " + "\n  ".join(PackedStringArray(rows)))
	_release_all()
	await _wait(2)

	# 一口气通一次关：不重置、不重摆、**带转向**（人就是看着下一块板按 W 的）
	print("\n  ── 连续通关（中途不重置、每帧朝目标转向）──")
	_pk.reset_run()
	var chain_ok := true
	var chain_log: Array[String] = []
	for i in range(1, _pk.node_count()):
		var walk := float(_hop(i - 1, i)["required"]) < 0.5
		var res := await _run_hop(i - 1, i, walk, i == 1, true)
		if not bool(res["ok"]):
			chain_ok = false
			chain_log.append("%s✗" % _pk.label_at(i))
			break
		chain_log.append(_pk.label_at(i))
	_check(chain_ok, "连续通关：%s（检查点 %d/%d）"
		% [" → ".join(PackedStringArray(chain_log)), _pk.checkpoint + 1, _pk.node_count()])
	_check(_pk.checkpoint == _pk.node_count() - 1,
		"到达终点站（检查点 = %d = 信号塔岛）" % _pk.checkpoint)
	_check(_pk.finished and not _pk.timer_running and _pk.elapsed_seconds() > 0.0,
		"连续通关顺带把计时器跑完：用时 %.2f s、最好 %.2f s（撞到终点自动停表）"
		% [_pk.elapsed_seconds(), _pk.best_seconds()])
	_release_all()


## 跑一站：把玩家摆到上一站、镜头对准下一站，按住 W+Shift 冲过去。
##
## `walk`  = 这一站是「走过去」的（相邻同高：独木桥），不按跳。
## `place` = 要不要把玩家先摆到上一站（否则用他当前站着的位置接着跑）。
## `steer` = 每帧把镜头转向目标中心（模拟「人看着下一块板按 W」）——
##           **绕角跳必须开**，否则人会笔直冲出板外。
func _run_hop(from_i: int, to_i: int, walk: bool, place := true, steer := false) -> Dictionary:
	var a := _pk.box_at(from_i)
	var b := _pk.box_at(to_i)
	var h := _hop(from_i, to_i)
	var takeoff: Vector3 = h["takeoff"]
	var center := b.position + b.size * 0.5
	var dir := Vector2(center.x - takeoff.x, center.z - takeoff.z).normalized()
	if place:
		_release_all()
		# 助跑能有多长取决于板有多大：从起跳点往回走，走到出板为止（再留 0.40 m）
		var back := _exit_dist(a, takeoff, Vector2(-dir.x, -dir.y))
		var run := clampf(back - 0.40, 0.50, RUNUP)
		_p.global_position = Vector3(takeoff.x - dir.x * run, _pk.top_at(from_i) + 0.05,
			takeoff.z - dir.y * run)
		_p.velocity = Vector3.ZERO
		if run < RUNUP_MIN:
			# 小板放不下助跑 → 按「从上一跳冲进来的速度」起步（真实玩法就是这样）
			_p.velocity = Vector3(dir.x, 0.0, dir.y) * Player.SPEED_RUN
	else:
		# 连续通关：**不松键、不停顿**，落地就接着跑（人就是这么跑的）。
		# 松一下键会吃 30 m/s² 的摩擦，在小石台上很容易滑到边缘外。
		await process_frame
	_aim(dir)
	if place:
		await _wait(3)

	Input.action_press("move_forward")
	Input.action_press("sprint")
	var t0 := Time.get_ticks_msec()
	var jumped := false
	if walk:
		while Time.get_ticks_msec() - t0 < 1800:
			await process_frame
			var wp := _p.global_position
			var past := -((takeoff.x - wp.x) * dir.x + (takeoff.z - wp.z) * dir.y)
			if past >= 1.0:
				break
			if wp.y < _pk.top_at(to_i) - 1.5:
				break
	else:
		while Time.get_ticks_msec() - t0 < 1800:
			await process_frame
			var pp := _p.global_position
			var d := dir
			if steer:
				var v := Vector2(center.x - pp.x, center.z - pp.z)
				if v.length() > 0.05:
					d = v.normalized()
				_aim(d)
			var remain := (takeoff.x - pp.x) * d.x + (takeoff.z - pp.z) * d.y
			if remain <= JUMP_LEAD and _p.is_on_floor():
				await _jump()
				jumped = true
				break
		if not jumped:
			_release_all()
			return {"ok": false, "pos": _p.global_position, "why": "没跑到边缘"}

	if not walk:
		var t1 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t1 < 2200:
			await process_frame
			if _p.is_on_floor() and Time.get_ticks_msec() - t1 > 140:
				break
			if _p.global_position.y < _pk.top_at(to_i) - 3.0:
				break
	var pos := _p.global_position
	var ok := _p.is_on_floor() \
		and absf(pos.y - _pk.top_at(to_i)) < 0.25 \
		and pos.x > b.position.x - 0.25 and pos.x < b.position.x + b.size.x + 0.25 \
		and pos.z > b.position.z - 0.25 and pos.z < b.position.z + b.size.z + 0.25
	return {"ok": ok, "pos": pos, "why": ""}


# --- 5. 反例 -------------------------------------------------------------------

func _test_negative() -> void:
	print("\n========== 5. 反例（过不去 / 摔下去回本段起点 / 计时 / 传送台）==========")
	_pk.enabled = true

	# ① 不按跳，直接跑出边缘 → 必然掉下去（同时证明「间距是真的」）
	var worst := _worst_jump()
	var from_i: int = worst["from"]
	var to_i: int = worst["to"]
	var h := _hop(from_i, to_i)
	var takeoff: Vector3 = h["takeoff"]
	var c := _pk.box_at(to_i)
	var dir := Vector2(c.position.x + c.size.x * 0.5 - takeoff.x,
		c.position.z + c.size.z * 0.5 - takeoff.z).normalized()
	_release_all()
	_pk.reset_run()
	_p.global_position = Vector3(takeoff.x - dir.x * RUNUP, _pk.top_at(from_i) + 0.05,
		takeoff.z - dir.y * RUNUP)
	_p.velocity = Vector3.ZERO
	_aim(dir)
	await _wait(3)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	var fell := false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2500:
		await process_frame
		if _p.global_position.y < _pk.top_at(from_i) - 2.0:
			fell = true
			break
	_release_all()
	_check(fell, "%s 这一段**不按跳**会掉下去（掉到 y = %.1f）—— 间距是真的"
		% ["%s→%s" % [_pk.label_at(from_i), _pk.label_at(to_i)], _p.global_position.y])

	# ② 摔落 → 回**本段起点**（这是 v2 的核心惩罚）
	for probe in [
		{"station": 13, "seg": 1, "what": "第 2 段中段（T1）"},
		{"station": 24, "seg": 2, "what": "第 3 段中段（U5）"},
		{"station": 30, "seg": 3, "what": "第 4 段中段（D4）"},
	]:
		var idx := int(probe["station"])
		_pk.reset_run()
		_pk.rescues = 0
		var b := _pk.box_at(idx)
		_put(b.position.x + b.size.x * 0.5, _pk.top_at(idx) + 0.05, b.position.z + b.size.z * 0.5)
		await _wait(4)
		var seg := _pk.segment_of(_pk.checkpoint)
		_p.global_position = Vector3(_p.global_position.x, -13.0, _p.global_position.z)
		await _wait(4)
		var back := _p.global_position
		var want := _pk.respawn_point(_pk.segment_start(int(probe["seg"])))
		_check(seg == int(probe["seg"]) and _pk.rescues == 1 and back.distance_to(want) < 0.30,
			"%s（第 %d 站）摔到 y = −13 → 送回**本段起点** %s（实落 %.2f,%.2f vs 期望 %.2f,%.2f，第 %d 次）"
			% [probe["what"], idx + 1, _pk.label_at(_pk.segment_start(int(probe["seg"]))),
				back.x, back.z, want.x, want.z, _pk.rescues])
	_check(_pk.FALL_Y > -60.0 and _pk.FALL_Y < -5.0,
		"跑酷的兜底线 %.0f m **高于** game.gd 的 −60 m，所以抢在它前面出手" % _pk.FALL_Y)

	# ③ 回到主平台 → 检查点清空、计时归零；此时再摔，归 game.gd 的兜底管
	_p.global_position = SPAWN
	_p.velocity = Vector3.ZERO
	await _wait(4)
	_check(_pk.checkpoint == -1 and not _pk.timer_running and _pk.elapsed_seconds() == 0.0,
		"站在主平台上 → 检查点清空、计时归零（免得路人被塞进跑酷中段）")
	_p.global_position = Vector3(0, -59.5, 6)
	await _wait_ms(400)
	_check(_p.global_position.distance_to(SPAWN) < 0.30,
		"不在跑酷里摔下去 → 还是 game.gd 送回出生点（y = %.2f）" % _p.global_position.y)

	# ④ 计时器：站跑道不计时 → 离开跑道开始 → 撞到终点停表 + 记最好成绩
	#    （存档的备份/还原在 `_run()` 与 `_quit()` 里统一做）
	_pk.reset_run()
	_put(-15.0, 0.05, 4.0)
	await _wait(4)
	var idle_time := _pk.elapsed_seconds()
	var started := _pk.timer_running
	var c1 := _pk.box_at(1)
	_put(c1.position.x + c1.size.x * 0.5, _pk.top_at(1) + 0.05, c1.position.z + c1.size.z * 0.5)
	await _wait_ms(300)
	var running := _pk.timer_running
	var t_mid := _pk.elapsed_seconds()
	var island := _pk.box_at(_pk.node_count() - 1)
	_put(island.position.x + island.size.x * 0.5, _pk.top_at(_pk.node_count() - 1) + 0.05,
		island.position.z + island.size.z * 0.5)
	await _wait(6)
	var hud := _pk.get_node_or_null("ParkourHUD/Seg") as Label
	_check(not started and idle_time == 0.0 and running and t_mid > 0.0
		and _pk.finished and not _pk.timer_running and _pk.best_seconds() > 0.0,
		"计时器：站跑道 %s → 离开后 %s（%.2f s）→ 撞岛停表 %s，最好成绩 %.2f s（存 user://）"
		% [str(started), str(running), t_mid, str(_pk.finished), _pk.best_seconds()])
	_check(hud != null and hud.text.contains("CLEAR"),
		"计时 HUD 文本跟着状态走：「%s」" % (hud.text if hud != null else "（没有 HUD）"))

	# ⑤ 岛上的传送台 → 回平台 + 复位
	var pad := _pk.get_node_or_null("Island/Props/ReturnPad") as Node3D
	_check(pad != null, "岛上有传送台节点（Island/Props/ReturnPad）")
	if pad != null:
		_p.global_position = pad.global_position + Vector3(0, 0.10, 0)
		_p.velocity = Vector3.ZERO
		await _wait_ms(500)
		_check(_p.global_position.distance_to(_pk.return_target) < 0.30 and _pk.checkpoint == -1
			and not _pk.timer_running,
			"踏上传送台 → 回到主平台 %s，检查点/计时清空（y = %.2f）"
			% [str(_pk.return_target), _p.global_position.y])


# --- 6. 与平台既有东西不打架 ---------------------------------------------------

func _test_clash(game: Node) -> void:
	print("\n========== 6. 与平台既有东西不打架 ==========")
	var mine: Array[AABB] = []
	var mine_names: Array[String] = []
	for n in _walk(_pk):
		if n is StaticBody3D:
			var b := _body_aabb(n)
			if b.size != Vector3.ZERO:
				mine.append(b)
				mine_names.append(String(n.name))
	# 落脚板之间不许互相压。
	#
	# ⚠️ **只查路线上的落脚板**：岛上的道具（四角柱/信号塔/掩体/货箱）各自是**复合实体**
	#    （一个 StaticBody3D 里塞了 3~4 个形状，铺满 14.8 m），合并出来的 AABB 会粗到
	#    覆盖整座岛 —— 拿它互相判重叠必然假阳性（第一版就是这么红的）。
	#    落脚板是单形状，比较是准的。
	var pads_b: Array[AABB] = []
	var pads_n: Array[String] = []
	for i in _pk.node_count():
		var pad_node := _pk.get_node_or_null(NodePath(String(_pk.route[i])))
		var pb := _body_aabb(pad_node)
		if pb.size != Vector3.ZERO:
			pads_b.append(pb)
			pads_n.append(String(pad_node.name))
	var self_hits: Array[String] = []
	for i in pads_b.size():
		for j in range(i + 1, pads_b.size()):
			if pads_b[i].intersects(pads_b[j]):
				self_hits.append("%s∩%s" % [pads_n[i], pads_n[j]])
	_check(self_hits.is_empty(), "%d 块落脚板互不重叠（相邻的独木桥贴面不算重叠）%s"
		% [pads_b.size(), "" if self_hits.is_empty() else "（重叠：%s）" % str(self_hits.slice(0, 4))])

	var others: Array = []
	for path in ["Boss", "BossPig", "Pillar1", "Pillar2", "Pillar3",
			"Target1", "Target2", "Target3", "Target4", "Target5"]:
		var node := game.get_node_or_null(path)
		if node != null:
			others.append({"b": _body_aabb(node), "n": path})
	var rc := game.get_node_or_null("Room609/RoomCollision")
	if rc != null:
		for c in rc.get_children():
			if c is CollisionShape3D:
				others.append({"b": _shape_aabb(c as CollisionShape3D), "n": "画室墙 %s" % c.name})
	var hut := game.get_node_or_null("MeshHut")
	if hut != null:
		for n in _walk(hut):
			if n is StaticBody3D:
				others.append({"b": _body_aabb(n), "n": "MeshHut/%s" % n.name})
	others.append({"b": AABB(Vector3(5.4, 0, -10.6), Vector3(1.2, 2.0, 6.6)),
		"n": "受保护弹道 玩家(6,−4)→靶1(6,−10)"})

	var hits: Array[String] = []
	for i in mine.size():
		for o in others:
			if mine[i].intersects(o["b"]):
				hits.append("%s ∩ %s" % [mine_names[i], o["n"]])
	_check(hits.is_empty(), "跑酷的实体与画室墙/柱子/靶子/两位 Boss/小屋/受保护弹道都不相交%s"
		% ("" if hits.is_empty() else "（撞上：%s）" % str(hits)))

	var island := _pk.box_at(_pk.node_count() - 1)
	_check(island.position.x + island.size.x <= -20.0,
		"终点岛整块在平台之外（x 最大 %.2f ≤ −20）" % (island.position.x + island.size.x))
	var east := -INF
	for b in mine:
		east = maxf(east, b.position.x + b.size.x)
	_check(east < 9.0, "跑酷最东边 x = %.2f，与东北角的网格小屋（x ≥ 9.25）隔着 %.2f m"
		% [east, 9.25 - east])

	# 跑道那道 2.5 cm 的标记板**不能挡人**（README §1.13 那个坎的复现测试）
	_pk.enabled = false
	_p.global_position = Vector3(-11.0, 0.05, 4.0)
	_p.velocity = Vector3.ZERO
	_p._yaw = PI * 0.5
	await _wait(3)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _wait_ms(600)
	_release_all()
	var dx := -11.0 - _p.global_position.x
	_check(dx >= 3.0 and absf(_p.global_position.y) < 0.30,
		"从跑道东端往西跑 0.6 s：前进 %.2f m、y = %.2f（理论 3.2 m；标记板没有挡人）"
		% [dx, _p.global_position.y])
	_pk.enabled = true


# --- 7. 终点区域 ---------------------------------------------------------------

func _test_island() -> void:
	print("\n========== 7. 终点区域（信号塔岛）==========")
	var n := _pk.node_count()
	var island := _pk.box_at(n - 1)
	var top := _pk.top_at(n - 1)
	_check(island.size.x >= 12.0 and island.size.z >= 12.0,
		"岛面 %.0f × %.0f m（≥ 12 × 12，装得下下一章要摆的东西）" % [island.size.x, island.size.z])
	_check(absf(top - 0.00) < 0.01, "岛面高度 y = %.2f（第 4 段下降链的最后一级落到平台同一层）" % top)

	var last := _hop(n - 2, n - 1)
	var land: Vector3 = last["landing"]
	var blocked: Array[String] = []
	for d in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var safe := _cast_safe(land + Vector3(0, 0.5, 0), d * 3.0)
		if safe < 0.999:
			blocked.append("%s %.2f" % [str(d), safe])
	_check(blocked.is_empty(), "落点 (%0.1f, %0.1f) 四周各 3 m 是净空的%s"
		% [land.x, land.z, "" if blocked.is_empty() else str(blocked)])

	var off := _cast_safe(land + Vector3(0, 0.5, 0), Vector3(1, 0, 0) * 9.0)
	_check(off < 0.999, "从落点往东走 9 m 会走到岛沿（safe = %.2f，岛东缘 x = %.2f）"
		% [off, island.position.x + island.size.x])

	var signs: Array[String] = []
	for node in _walk(_pk):
		if node is Label3D:
			signs.append((node as Label3D).text.replace("\n", " / "))
	_check(signs.size() >= 6, "指路牌 %d 块：%s" % [signs.size(), str(signs)])
	_m["signs"] = signs.size()


# --- 结果 ---------------------------------------------------------------------

func _print_table() -> void:
	var secs := (Time.get_ticks_msec() - _t0) / 1000.0
	print("\n================ 跑酷 v2 一览（实测）================")
	print("  平跳最远（实测）      %.2f m   ← 解析 %.2f m"
		% [float(_m.get("flat", 0.0)), float(_m.get("flat_theory", 0.0))])
	print("  抬升 0.80 m 最远      %.2f m" % float(_m.get("rise", 0.0)))
	print("  实测系数 k            %.3f（参考 %.3f）" % [float(_m.get("k", 0.0)), K_REF])
	print("  挂边容忍              +%.2f m（胶囊半径 0.30）" % float(_m.get("hang", 0.0)))
	print("  0.80 m 独木桥横向余量 ±%.2f m" % float(_m.get("beam_wide", 0.0)))
	print("  全线最紧的一跳        %s，余量 %.2f m"
		% [String(_m.get("worst_name", "")), float(_m.get("worst_margin", 0.0))])
	print("  紧张区间              %d/%d 跳" % [int(_m.get("tight", 0)), int(_m.get("jumps", 0))])
	print("  路线                  4 段 / 33 站 / 30 跳 + 2 段独木桥 / 跳距合计 %.1f m / x 跨度 206 m"
		% float(_m.get("gap_sum", 0.0)))
	print("  本套自检用时          %.1f s" % secs)


# --- 工具 ---------------------------------------------------------------------

## 取第 from_i → to_i 站的解析分析（自检和探针共用 parkour.gd 的实现）
func _hop(from_i: int, to_i: int) -> Dictionary:
	return Parkour.hop_analysis(_pk.box_at(from_i), _pk.box_at(to_i),
		Player.JUMP_VELOCITY, Player.GRAVITY, Player.SPEED_RUN)


## 实测余量最小的那一跳（用于反例：拿最难的跳去证明「不跳就过不去」）
func _worst_jump() -> Dictionary:
	var best := {"from": 1, "to": 2, "margin": INF}
	for i in range(1, _pk.node_count()):
		var h := _hop(i - 1, i)
		if float(h["required"]) < 0.5:
			continue
		var m := float(h["reach"]) * K_REF - float(h["required"])
		if m < float(best["margin"]):
			best = {"from": i - 1, "to": i, "margin": m}
	return best


## 把镜头对准某个水平方向：`move_forward` 正好朝它（推导见 parkour 的朝向约定）
func _aim(dir: Vector2) -> void:
	_p._yaw = atan2(-dir.x, -dir.y)
	_p._facing_yaw = _p._yaw + PI
	_p.model_root.rotation.y = _p._facing_yaw


## 按一次跳（两帧），和玩家真按键的时序一致
func _jump() -> void:
	Input.action_press("jump")
	await process_frame
	await process_frame
	Input.action_release("jump")


## 从 `from` 沿 `d`（水平）走多远离开盒子 —— 用来算「这块板上还能退多远助跑」
func _exit_dist(b: AABB, from: Vector3, d: Vector2) -> float:
	var t := INF
	if absf(d.x) > 1e-6:
		t = minf(t, ((b.position.x + b.size.x - from.x) / d.x) if d.x > 0.0
			else ((b.position.x - from.x) / d.x))
	if absf(d.y) > 1e-6:
		t = minf(t, ((b.position.z + b.size.z - from.z) / d.y) if d.y > 0.0
			else ((b.position.z - from.z) / d.y))
	return maxf(t, 0.0)


func _put(x: float, y: float, z: float) -> void:
	_release_all()
	_p.global_position = Vector3(x, y, z)
	_p.velocity = Vector3.ZERO


## 读一份原始的最好成绩存档（不存在 → 空串），测完还要还回去
func _read_best_file() -> String:
	if not FileAccess.file_exists(Parkour.BEST_PATH):
		return ""
	var f := FileAccess.open(Parkour.BEST_PATH, FileAccess.READ)
	return "" if f == null else f.get_as_text()


func _restore_best_file(backup: String) -> void:
	if backup.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Parkour.BEST_PATH))
		return
	var f := FileAccess.open(Parkour.BEST_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(backup)


## 用一枚和玩家同尺寸的胶囊做 cast_motion，返回 safe 比例（1.0 = 一路无阻）
func _cast_safe(from: Vector3, motion: Vector3) -> float:
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.30
	cap.height = 1.5
	q.shape = cap
	q.transform = Transform3D(Basis.IDENTITY, from + Vector3(0, 0.75, 0))
	q.motion = motion
	q.collision_mask = 1
	var res := _space.cast_motion(q)
	return float(res[0]) if res.size() > 0 else 1.0


func _body_aabb(node: Node) -> AABB:
	var out := AABB()
	var first := true
	for c in node.get_children():
		if c is CollisionShape3D:
			var b := _shape_aabb(c as CollisionShape3D)
			if b.size == Vector3.ZERO:
				continue
			out = b if first else out.merge(b)
			first = false
	if first and node is Node3D:
		out = AABB((node as Node3D).global_position, Vector3.ZERO)
	return out


func _shape_aabb(cs: CollisionShape3D) -> AABB:
	if cs == null or cs.shape == null:
		return AABB()
	var s := cs.shape
	var local := AABB()
	if s is BoxShape3D:
		local = AABB(-(s as BoxShape3D).size * 0.5, (s as BoxShape3D).size)
	elif s is CylinderShape3D:
		var cy := s as CylinderShape3D
		var r := cy.radius
		local = AABB(Vector3(-r, -cy.height * 0.5, -r), Vector3(r * 2.0, cy.height, r * 2.0))
	elif s is SphereShape3D:
		var rr := (s as SphereShape3D).radius
		local = AABB(Vector3(-rr, -rr, -rr), Vector3(rr * 2.0, rr * 2.0, rr * 2.0))
	return cs.global_transform * local


func _walk(root_node: Node) -> Array[Node]:
	var out: Array[Node] = []
	for c in root_node.get_children():
		out.append(c)
		out.append_array(_walk(c))
	return out


func _stats(root_node: Node) -> Dictionary:
	var st := {"nodes": 0, "meshes": 0, "shapes": 0, "lights": 0, "labels": 0}
	for n in _walk(root_node):
		st["nodes"] += 1
		if n is MeshInstance3D:
			st["meshes"] += 1
		elif n is CollisionShape3D:
			st["shapes"] += 1
		elif n is Light3D:
			st["lights"] += 1
		elif n is Label3D:
			st["labels"] += 1
	return st


func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right",
			"sprint", "crouch", "jump"]:
		Input.action_release(a)


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
	_restore_best_file(_best_backup)
	print("失败 %d 项" % _fail)
	quit(1 if _fail > 0 else 0)


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
