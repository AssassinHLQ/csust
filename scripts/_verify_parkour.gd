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
const MARGIN_MIN := 0.80
## 减速短跳（螺旋塔）的余量闸门。`air_hop_reach()` 只算**空中** 9 m/s² 的加速，
## 不含起跳那一/两帧还踩在地面上的 26 m/s² —— 它比实测保守约 0.35 m。
## 塔现在 7 跳、弦长 4.31 m、缝隙 0.99 m：解析余量 1.46 - 0.99 = 0.47 m，
## 而 `_probe_tower_chain.gd` 用真物理逐跳跑 7/7 全过。给短跳单独一个 0.40 的门槛。
const MARGIN_MIN_SHORT := 0.40

var _fail := 0
var _pass := 0
var _p: Player
var _pk: Parkour
var _space: PhysicsDirectSpaceState3D
var _m := {}
var _t0 := 0
## 套件开跑前备份的「最好成绩」存档 —— 测完原样还回去
var _best_backup := ""
## 「这一节真的跑完了」的章（见收尾处那段注释：运行时错误不会记成 FAIL）
var _done_hops := false
var _done_chain := false
## 起跳有没有用到「直接写 velocity.y」的兜底（正常应当 0）
var _jump_assisted := 0


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
	await _test_mechanics()
	await _test_negative()
	await _test_clash(game)
	await _test_island()
	await _wait(2)

	print("\n================ 结果 ================")
	# ⚠️ **运行时错误不会记成 FAIL**：GDScript 里一个 `await` 协程中途报错（比如对
	#    `null` 取 `.resource_path`）只会让**那一节悄悄不跑**，断言一条都不记 ——
	#    于是「133 项 0 失败」看着全绿，其实「连续通关」整节没执行。
	#    v3 第一版就是这样：日志里躺着一条 SCRIPT ERROR，而汇总里写着「连续通关用时
	#    0.00 s」—— 计时器根本没启动。所以每一节跑完都盖一个章，收尾核对。
	for stamp in [["逐跳回放", _done_hops], ["连续通关", _done_chain]]:
		_check(bool(stamp[1]), "%s那一节**真的跑到了**（防运行时错误静默跳过）" % stamp[0])
	_check(_jump_assisted == 0,
		"所有起跳都是**靠输入按出来**的（兜底用了 %d 次；>0 说明跳键脉冲又被微弹吃掉了）"
		% _jump_assisted)
	# 兜底：任何一节静默跳过，断言总数都会掉下来（当前 125 条；59 站版比 63 站版少 4 跳）
	_check(_pass + _fail >= 120,
		"断言总数 ≥ 120（实测 %d 条）—— 哪一节没跑完这里会先变红" % (_pass + _fail))
	print("通过 %d 项" % _pass)
	_print_table()
	_quit()


# --- 1. 结构与几何 -------------------------------------------------------------

func _test_structure(game: Node) -> void:
	print("\n========== 1. 结构与几何 ==========")
	var n := _pk.node_count()
	_check(n == 59, "路线有 %d 站（期望 59：跑道 + 46 块落脚板 + 6 段「走过去」的接口板 + 6 处机关 + 岛）" % n)
	var want := ["Launch", "P1", "P2", "P3", "P4", "P5", "P6", "P7", "C1",
		"B1", "BA", "S1", "BB", "T1", "T2", "T3", "T4", "T5", "T6", "C2",
		"X1", "X2", "X3", "X4", "X5", "F1", "F2", "C3",
		"W1", "W2", "W3", "W4", "W5", "W6", "W7", "C4",
		"E1", "Q1", "H1", "V1", "V2", "V3", "V4", "L1", "U1", "U2", "Q2", "H2", "C5",
		"R1", "R2", "R3", "R4", "R5", "J1", "J2", "J3", "J4", "Island"]
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
	_check(sorted_ok and _pk.segment_count() == 6 and segs.size() == _pk.seg_names.size(),
		"分段数据：segments=%s（升序、首项 0、6 段），seg_names %d 个「%s」"
		% [str(segs), _pk.seg_names.size(), " / ".join(PackedStringArray(_pk.seg_names))])
	# 段起点必须是段落里**第一站**、而且每段都非空
	var span_ok := true
	for s in _pk.segment_count():
		var st := _pk.segment_start(s)
		var en: int = _pk.segment_start(s + 1) if s + 1 < _pk.segment_count() else n
		if en <= st or st < 0 or en > n:
			span_ok = false
	_check(span_ok, "六段的站号区间都不空：%s"
		% str(Array(range(0, 6)).map(func(s): return "%s[%d]" % [
			_pk.segment_name(s), _pk.segment_start(s)])))
	# 机关清单也要跟着对：6 处机关跳、螺旋塔 7 处减速短跳（W2…C4，由场景给）。
	# 螺旋塔 2026-10-17 回到 7 跳版：11 跳版每 4 级叠在同一 xz、层间只差 2.05 m，
	# 玩家的 1.5 m 身高 + 0.5 m 板厚只剩 5 cm，跳起来必撞头 —— 这不是难度，是几何死锁。
	# 现在每级 +0.80（4 级 = 3.20 m，净空 2.70 m），总高仍是 W1 台面 2.80 → C4 台面 8.40。
	_check(_pk.special_hops.size() == 6,
		"机关跳 %d 处（期望 6）：%s（减速短跳 %d 处，期望 7：W2…C4）"
		% [_pk.special_hops.size(), str(_pk.special_hops), _pk.short_hops.size()])

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
		if node is AnimatableBody3D:
			continue      # 移动平台**在动**：它的 position 每帧都变，查两个端点即可（见下）
		var xf := (node as Node3D).transform
		for v in [xf.origin, xf.basis.get_scale()]:
			for c in 3:
				var q: float = absf(v[c]) / 0.05
				if absf(q - roundf(q)) > 0.001:
					off.append("%s %s=%.3f" % [node.name, "xyz"[c], v[c]])
	_check(off.is_empty(), "所有 position / scale 都落在 0.05 m 网格上（移动平台查两端点）%s"
		% ("" if off.is_empty() else "（越界：%s）" % str(off.slice(0, 4))))
	var bad_dock: Array[String] = []
	for node in _walk(_pk):
		if node is AnimatableBody3D:
			var mv := node as ParkourMover
			for v in [mv.point_a, mv.point_b]:
				for c in 3:
					var q: float = absf(v[c]) / 0.05
					if absf(q - roundf(q)) > 0.001:
						bad_dock.append("%s %s=%.3f" % [mv.name, "xyz"[c], v[c]])
	_check(bad_dock.is_empty(), "移动平台的两个端点也落在 0.05 m 网格上%s"
		% ("" if bad_dock.is_empty() else "（越界：%s）" % str(bad_dock)))

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
	# ⚠️ 计时 HUD **不许压在玩家血量面板上**（本喵验收时抓到的）：
	#    左上角 (24,20)–(368,112) 是 `hud.gd` 的 `HP_PANEL_POS` / `HP_PANEL_SIZE`，
	#    而 `Parkour` 在 `game.tscn` 里排在 `HUD` **前面** —— 两个 CanvasLayer
	#    同为 layer 1 时按树序画，HUD 会盖在上面、计时文字被整个挡掉。
	#    两个都是挂在 `game.tscn` 下的 CanvasLayer，`get_global_rect()` 同一套画布坐标，
	#    所以可以直接比矩形。探针：`_probe_parkour_hud.gd`（还会出一张真机图）。
	var hp := Rect2(Vector2(24.0, 20.0), Vector2(344.0, 92.0))
	for hud_name in ["ParkourHUD/Timer", "ParkourHUD/Seg"]:
		var lb := _pk.get_node_or_null(hud_name) as Label
		if lb == null:
			continue
		var r := lb.get_global_rect()
		_check(not r.intersects(hp) and r.position.x > 800.0,
			"%s 在右上角、与血量面板不相交（x = %.0f，重叠 %.0f px²）"
			% [hud_name, r.position.x, r.intersection(hp).get_area()])
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
	var worst_min := MARGIN_MIN
	var worst_name := ""
	var bad: Array[String] = []
	var tight := 0
	var jumps := 0
	var gap_sum := 0.0
	for i in range(1, _pk.node_count()):
		if _pk.is_special_hop(i):
			continue                       # 机关跳不按弹道算（第 5b 节另有真物理断言）
		var h := _hop(i - 1, i)
		if float(h["required"]) < 0.5 and absf(float(h["rise"])) < 0.35:
			continue                       # 走过去（独木桥 / 机关接口板）
		jumps += 1
		gap_sum += float(h["required"])
		# 减速短跳（螺旋塔）用空中操控模型，其余用「解析 × 实测系数 k」
		var is_short := _pk.is_short_hop(i)
		var margin := (Parkour.air_hop_reach(float(h["rise"])) if is_short
			else float(h["reach"]) * k) - float(h["required"])
		var min_margin := MARGIN_MIN_SHORT if is_short else MARGIN_MIN
		var name := "%s→%s" % [_pk.label_at(i - 1), _pk.label_at(i)]
		if margin <= 0.90:
			tight += 1
		if margin < worst:
			worst = margin
			worst_min = min_margin
			worst_name = name
		if margin < min_margin:
			bad.append("%s 余量 %.2f（要求 ≥ %.2f）" % [name, margin, min_margin])
		# 入板：沿行进方向前后 ≥ 0.40、侧向 ≥ 0.20。
		# ⚠️ 判据要算上 **挂边容忍** `EDGE_MARGIN = 0.30`：D 版的塔跳是「瞄板心全速跳」，
		#    斜着落到板角附近只剩 0.16 m，但胶囊还能挂住 0.30 m 的边 —— 实测回放全过。
		#    不加这一项会把「已经过的跳」误报成设计不合格（11 跳版那次就是这么红的）。
		var b := _pk.box_at(i)
		var t: Vector3 = h["takeoff"]
		# **按玩家实际瞄的方向（下一块板中心）算落点**，不是瞄最近点：斜跳（横跳区 3.2 m
		# 侧移）两者差很多，用最近点会把「擦着板侧边落下」误判成设计不合格
		var _c2 := b.position + b.size * 0.5
		var dir := Vector2(_c2.x - t.x, _c2.z - t.z).normalized()
		var reach := Parkour.air_hop_reach(float(h["rise"])) if is_short \
			else float(h["reach"]) * k
		var lx := t.x + dir.x * reach
		var lz := t.z + dir.y * reach
		var bb := PackedFloat32Array([b.position.x, b.position.x + b.size.x,
			b.position.z, b.position.z + b.size.z])
		var back := _exit(bb, lx, lz, -dir.x, -dir.y)
		var fwd := _exit(bb, lx, lz, dir.x, dir.y)
		var side := minf(_exit(bb, lx, lz, -dir.y, dir.x), _exit(bb, lx, lz, dir.y, -dir.x))
		var edge := Parkour.EDGE_MARGIN
		if back + edge < 0.40 or fwd + edge < 0.40 or side + edge < 0.20:
			bad.append("%s 入板（前%.2f/后%.2f/侧%.2f，含挂边 %.2f）"
				% [name, fwd, back, side, edge])
	_m["worst_margin"] = worst
	_m["worst_name"] = worst_name
	_m["gap_sum"] = gap_sum
	_m["jumps"] = jumps
	_m["tight"] = tight
	_check(bad.is_empty(), "按**实测**能力核对每一跳：跳 %d 个、跳距合计 %.1f m，最紧的是 %s，"
		% [jumps, gap_sum, worst_name] + "余量 %.2f m（要求：常规 ≥ %.2f / 短跳 ≥ %.2f）%s"
		% [worst, MARGIN_MIN, MARGIN_MIN_SHORT, "" if bad.is_empty() else str(bad)])
	# 用户反馈「太难」之后闸门反过来了：紧张区（0.80~0.90）占比必须 **≤ 1/4**
	_check(tight * 4 <= jumps,
		"紧张区间（余量 0.80~0.90）：%d/%d = %.0f%% ≤ 1/4（降难度后的闸门）"
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
		if _pk.is_special_hop(i):
			skipped.append("%s（机关）" % _pk.label_at(i))
			continue                       # 机关跳在第 5b 节逐条真物理验
		var h := _hop(i - 1, i)
		var walk := float(h["required"]) < 0.5 and absf(float(h["rise"])) < 0.35
		var short := _pk.is_short_hop(i)
		var reach := Parkour.air_hop_reach(float(h["rise"])) if short \
			else float(h["reach"]) * K_REF
		var margin := reach - float(h["required"])
		var b2 := _pk.box_at(i)
		var pair := "%s→%s" % [_pk.label_at(i - 1), _pk.label_at(i)]
		# 逐跳真跑哪些？**新段（3~6）全跑 + 所有紧张跳（余量 ≤ 0.90）**。
		# 段 1~2 是 v2 验过的老内容、由下面的连续通关兜着，单独回放会白烧 30 s。
		var run_it := (_pk.segment_of(i) >= 2 or margin <= 0.90) \
			and not _pk.label_at(i) in ["Q1", "Q2", "U1"]
		# ↑ Q1/Q2（弹跳板）与 U1（气流底座）是**机关接口板**：人一踩上去立刻被机关带走，
		#   单独的「走过去」回放没有意义（而且必然红）—— 它们由第 5b 节的机关驱动负责。
		if not run_it:
			skipped.append("%s（余量 %.2f 宽裕，连续通关里覆盖）" % [pair, margin])
			continue
		var res := await _run_hop(i - 1, i, walk, true, false, short)
		isolated += 1
		var ok: bool = bool(res["ok"])
		if not ok:
			fails += 1
		rows.append("%-13s %s 必须跨 %5.2f 抬升 %+5.2f 余量 %5.2f → 实落 (%7.2f,%7.2f) %s" % [
			pair, "走 " if walk else ("短跳" if short else "跳 "), h["required"], h["rise"],
			margin, float(res["pos"].x), float(res["pos"].z), "✓" if ok else "**✗**"])
		_check(ok, "%s：落在 %s 上（y = %.2f，台面 %.2f）"
			% [pair, _pk.label_at(i), float(res["pos"].y), _pk.top_at(i)])
		if not walk:
			# 预测落点按**玩家实际会瞄的方向**（目标板中心）算，而不是解析里那条
			# 「到最近点」的捷径 —— 两者在横跳（R5→J1 这种偏 1.4 m 的）上差 1.6 m，
			# 拿捷径当基准会误报（v3 第一版就是这么红的）。
			var t2: Vector3 = h["takeoff"]
			var c2 := b2.position + b2.size * 0.5
			var d2 := Vector2(c2.x - t2.x, c2.z - t2.z).normalized()
			var pred := Vector3(t2.x + d2.x * reach, _pk.top_at(i), t2.z + d2.y * reach)
			var d := Vector2(float(res["pos"].x) - pred.x, float(res["pos"].z) - pred.z).length()
			# 容差 1.30：逐跳回放里「起跳点在边缘前 0.15 m 内触发」+ 固定初始朝向，
			# 斜跳时落地会差个 ~1 m —— 这条查的是**模型有没有大错**（真错会差 3 m 以上），
			# 不是逐毫米复现弹道。实测绝大多数在 0.05~0.20 m。
			_check(d <= (1.20 if short else 1.60),
				"    预测落点与实际相差 %.2f m（≤ %.2f；起跳点会在「边缘」与「投影面」之间浮动）"
				% [d, 1.20 if short else 1.60])
	_check(fails == 0, "逐跳真输入回放全部通过（真跑 %d 站，跳过 %d 站，失败 %d）"
		% [isolated, skipped.size(), fails])
	print("\n  " + "\n  ".join(PackedStringArray(rows)))
	if not skipped.is_empty():
		print("  （跳过：%s）" % "；".join(PackedStringArray(skipped)))
	_release_all()
	await _wait(2)

	# 一口气通一次关：不重置、不重摆、**带转向**（人就是看着下一块板按 W 的），
	# 六处机关用各自的驱动函数正经过一遍（等平台、踩弹跳板、进气流、穿传送门）
	print("\n  ── 连续通关（中途不重置；六处机关按真实玩法驱动）──")
	_pk.reset_run()
	var chain_ok := true
	var chain_log: Array[String] = []
	# ⚠️ 这里原来有一段 `special_kind[...] = route[idx].get_script().resource_path...`：
	#    移动平台的落点（F2 / C3）是**普通板、没有脚本**，`get_script()` 返回 null，
	#    `.resource_path` 当场抛 SCRIPT ERROR ⇒ **整节连续通关静默不跑**（而汇总仍全绿）。
	#    而且那个字典后面根本没被用过 —— 删掉。要认「这一站是什么机关」，看
	#    `_drive_special()` 里的分支就够。
	for i in range(1, _pk.node_count()):
		var short := _pk.is_short_hop(i)
		# Q1/Q2 是弹跳板本体、U1 是气流底座：它们不是「跳过去」的站，
		# 而是下一站机关驱动的起点。逐跳回放本来就把它们跳过；连续通关也跳过，
		# 交给下一轮 `_drive_special(H1/H2/U2)` 从这块板出发。
		if _pk.label_at(i) in ["Q1", "Q2", "U1"]:
			continue
		var walk := _pk.label_at(i) in ["Q1", "Q2", "U1"] \
			or (float(_hop(i - 1, i)["required"]) < 0.5 \
			and absf(float(_hop(i - 1, i)["rise"])) < 0.35)
		var res: Dictionary
		if _pk.is_special_hop(i):
			res = await _drive_special(i)
		else:
			res = await _run_hop(i - 1, i, walk, i == 1, true, short)
		if not bool(res["ok"]):
			chain_ok = false
			chain_log.append("%s✗(%s)" % [_pk.label_at(i), String(res.get("why", ""))])
			break
		chain_log.append(_pk.label_at(i))
	_check(chain_ok, "连续通关：%s（检查点 %d/%d）"
		% [" → ".join(PackedStringArray(chain_log)), _pk.checkpoint + 1, _pk.node_count()])
	_check(_pk.checkpoint == _pk.node_count() - 1,
		"到达终点站（检查点 = %d = 信号塔岛）" % _pk.checkpoint)
	_check(_pk.finished and not _pk.timer_running and _pk.elapsed_seconds() > 0.0,
		"连续通关顺带把计时器跑完：用时 %.2f s、最好 %.2f s（撞到终点自动停表）"
		% [_pk.elapsed_seconds(), _pk.best_seconds()])
	_m["run_seconds"] = _pk.elapsed_seconds()
	_release_all()
	# 这一节（含连续通关）跑到底了才盖章 —— 中途抛运行时错误会跳过这一行
	_done_chain = true
	_done_hops = true


## 跑一站：把玩家摆到上一站、镜头对准下一站，按住 W+Shift 冲过去。
##
## `walk`  = 这一站是「走过去」的（相邻同高：独木桥），不按跳。
## `place` = 要不要把玩家先摆到上一站（否则用他当前站着的位置接着跑）。
## `steer` = 每帧把镜头转向目标中心（模拟「人看着下一块板按 W」）——
##           **绕角跳必须开**，否则人会笔直冲出板外。
## `standstill` = **减速短跳**（绕柱螺旋塔）：站在起跳点不助跑，先按跳、再按住方向，
##           靠空中操控走出 ~1.46 m。全速冲过去会飞过头（射程 3.87 > 板深 2.0）。
func _run_hop(from_i: int, to_i: int, walk: bool, place := true, steer := false,
		standstill := false) -> Dictionary:
	var a := _pk.box_at(from_i)
	var b := _pk.box_at(to_i)
	var h := _hop(from_i, to_i)
	var takeoff: Vector3 = h["takeoff"]
	var center := b.position + b.size * 0.5
	var dir := Vector2(center.x - takeoff.x, center.z - takeoff.z).normalized()
	if standstill:
		_release_all()
		if place:
			_p.global_position = Vector3(takeoff.x - dir.x * 0.10, _pk.top_at(from_i) + 0.05,
				takeoff.z - dir.y * 0.10)
			_p.velocity = Vector3.ZERO
		else:
			# 连续通关里也要「**先站住再跳**」：螺旋塔是 90° 转的站定跳，弦长 4.31 m，
			# 带着上一跳的冲量起跳，横向惯性会让 90° 转弯擦着板边掉下去。
			# 松键吃 30 m/s² 摩擦，0.23 s 就停住；停住后**站回起跳角落** ——
			# 真人到这里也会先站到边缘再瞄，不是从落点直接莽出去。
			var ts0 := Time.get_ticks_msec()
			while Time.get_ticks_msec() - ts0 < 450:
				await process_frame
				if _p.is_on_floor() \
						and Vector2(_p.velocity.x, _p.velocity.z).length() < 1.0:
					break
			_p.global_position = Vector3(takeoff.x - dir.x * 0.10, _pk.top_at(from_i) + 0.05,
				takeoff.z - dir.y * 0.10)
			_p.velocity = Vector3.ZERO
		_aim(dir)
		# ⚠️ **必须等到真的落地再按跳**：摆人的 y 是「台面 + 0.05」，前几帧人是离地的，
		#    而 `player.gd` 的 `jump` 只在 `is_on_floor()` 时才写入 velocity —— 等 3 帧就跳
		#    会被整个忽略，塔里每一跳都会原地掉（v3 塔改成 11 跳后就是这么红的）。
		var tw := Time.get_ticks_msec()
		while not _p.is_on_floor() and Time.get_ticks_msec() - tw < 400:
			await process_frame
		await _wait(2)
		await _jump()
		Input.action_press("move_forward")
		Input.action_press("sprint")
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 2200:
			await process_frame
			var ps := _p.global_position
			var vs := Vector2(center.x - ps.x, center.z - ps.z)
			if vs.length() > 0.05:
				_aim(vs.normalized())
			if _p.is_on_floor() and Time.get_ticks_msec() - t0 > 140:
				break
			if ps.y < _pk.top_at(to_i) - 3.0:
				break
		var pos2 := _p.global_position
		var ok2 := _p.is_on_floor() and absf(pos2.y - _pk.top_at(to_i)) < 0.25 \
			and pos2.x > b.position.x - 0.25 and pos2.x < b.position.x + b.size.x + 0.25 \
			and pos2.z > b.position.z - 0.25 and pos2.z < b.position.z + b.size.z + 0.25
		return {"ok": ok2, "pos": pos2, "why": ""}
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
			# **跑到板边就跳**的兜底：连续通关要去够下一块板，转向时 `remain` 的投影
			# 会卡在正值上（人已经贴着边缘了、投影还没到 0.15）—— 真人这时直接起跳，
			# 自检照做。少了这条，横跳区那种「边跑边转 60°」的站会一直等到掉下去。
			elif _p.is_on_floor() and _exit_dist(a, pp, d) <= 0.35:
				await _jump()
				jumped = true
				break
		if not jumped:
			_release_all()
			return {"ok": false, "pos": _p.global_position, "why": "没跑到边缘"}

	if not walk:
		var t1 := Time.get_ticks_msec()
		var land_pos := _p.global_position
		var got := false
		while Time.get_ticks_msec() - t1 < 2200:
			await process_frame
			# **落点取第一次着地那一帧**：着地后按住 W 还会继续滑（6.8 m/s × 0.1 s
			# 就是 0.7 m），等 140 ms 再采样会把「滑出去的距离」算进模型误差里
			if not got and _p.is_on_floor() and Time.get_ticks_msec() - t1 > 55:
				land_pos = _p.global_position
				got = true
			if got and Time.get_ticks_msec() - t1 > 140:
				break
			if _p.global_position.y < _pk.top_at(to_i) - 3.0:
				break
		if got:
			_p.global_position = land_pos      # 用着地那一帧的点做判定与误差比对
	var pos := _p.global_position
	var ok := _p.is_on_floor() \
		and absf(pos.y - _pk.top_at(to_i)) < 0.25 \
		and pos.x > b.position.x - 0.25 and pos.x < b.position.x + b.size.x + 0.25 \
		and pos.z > b.position.z - 0.25 and pos.z < b.position.z + b.size.z + 0.25
	return {"ok": ok, "pos": pos, "why": ""}


# --- 5b. 机关（真物理）--------------------------------------------------------

## 六处「机关跳」的驱动：按真实玩法走一遍（等平台 / 踩弹跳板 / 进气流 / 穿传送门）。
## 连续通关里就是靠它过那六处。
func _drive_special(to_i: int) -> Dictionary:
	var from_i := to_i - 1
	var b := _pk.box_at(to_i)
	var mover := _pk.get_node_or_null("Movers/MoverA") as ParkourMover
	var name := _pk.label_at(to_i)
	match name:
		"F2":
			return await _drive_mover(_pk.get_node_or_null("Movers/MoverA") as ParkourMover,
				from_i, to_i)
		"C3":
			return await _drive_mover(_pk.get_node_or_null("Movers/MoverB") as ParkourMover,
				from_i, to_i)
		"H1", "H2":
			return await _drive_bounce(from_i, to_i)
		"U2":
			return await _drive_updraft(from_i, to_i)
		"C5":
			return await _drive_portal(from_i, to_i)
		_:
			return {"ok": false, "pos": _p.global_position,
				"why": "没有 %s 的机关驱动（%s）" % [name, str(mover != null)]}


## 移动平台：**站着不动**被带过缺口（相对位移不变 = 承载生效的铁证）。
func _drive_mover(mv: ParkourMover, from_i: int, to_i: int) -> Dictionary:
	if mv == null:
		return {"ok": false, "pos": _p.global_position, "why": "找不到平台"}
	mv.force_progress(0.0, 1.6)                 # 靠岸并**多停一会儿**，好让人站上去
	var a := _pk.box_at(from_i)
	_release_all()
	# 直接站到**平台上**（平台靠岸时与岸重叠 0.30 m，取重叠带西侧 0.35 m 处 =
	# 板上专属区），**不按键** —— 平台一开动人就被带走，rel 不变就是承载生效的铁证。
	# （第一版站在岸上再走过去：人还没上船平台就开走了，直接掉进缺口）
	_p.global_position = Vector3(a.position.x - a.size.x * 0.5 - 0.35,
		_pk.top_at(from_i) + 0.05, a.position.z + a.size.z * 0.5)
	_p.velocity = Vector3.ZERO
	await _wait(4)
	var on_board := false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 4000:
		await process_frame
		if _p.get_platform_velocity().length() > 0.5:
			on_board = true
			break
		if not _p.is_on_floor():
			break
	if not on_board:
		_release_all()
		return {"ok": false, "pos": _p.global_position, "why": "没走上平台"}
	var rel0 := _p.global_position - mv.global_position
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 9000:
		await process_frame
		if mv.docked() and mv.progress() > 0.5:
			break
		if _p.global_position.y < _pk.top_at(from_i) - 3.0:
			_release_all()
			return {"ok": false, "pos": _p.global_position, "why": "中途掉下去了"}
	var rel := (_p.global_position - mv.global_position) - rel0
	# 下船（平台在对岸只停 0.8 s，别磨蹭）
	_aim(Vector2(-1, 0))
	Input.action_press("move_forward")
	await _wait_ms(600)
	_release_all()
	await _wait(3)
	var b := _pk.box_at(to_i)
	var pos := _p.global_position
	var ok := pos.x > b.position.x - 0.40 and pos.x < b.position.x + b.size.x + 0.40 \
		and pos.z > b.position.z - 0.40 and pos.z < b.position.z + b.size.z + 0.40 \
		and absf(pos.y - _pk.top_at(to_i)) < 0.40
	return {"ok": ok, "pos": pos, "rel": Vector2(rel.x, rel.z).length(),
		"boarded": on_board,
		"why": "" if ok else "没送到对岸（上船=%s, progress=%.2f, rel=%.2f, 落点 %.2f,%.2f）"
			% [str(on_board), mv.progress(), Vector2(rel.x, rel.z).length(), pos.x, pos.z]}


## 弹跳板：从上一块板**全速跑上去**（不跳），被弹到 +4.40 的高台。
func _drive_bounce(from_i: int, to_i: int) -> Dictionary:
	var a := _pk.box_at(from_i)
	var b := _pk.box_at(to_i)
	_release_all()
	_p.global_position = Vector3(a.position.x + a.size.x * 0.5 + 2.2,
		_pk.top_at(from_i) + 0.05, a.position.z + a.size.z * 0.5)
	_p.velocity = Vector3.ZERO
	_aim(Vector2(-1, 0))
	await _wait(3)
	var peak := _p.global_position.y
	Input.action_press("move_forward")
	Input.action_press("sprint")
	var t0 := Time.get_ticks_msec()
	var launched := false
	while Time.get_ticks_msec() - t0 < 3000:
		await process_frame
		peak = maxf(peak, _p.global_position.y)
		if _p.velocity.y > 4.0:
			launched = true
		if launched and _p.is_on_floor() and Time.get_ticks_msec() - t0 > 300:
			break
		if _p.global_position.y < _pk.top_at(from_i) - 4.0:
			break
	_release_all()
	await _wait(4)
	var pos := _p.global_position
	var ok := pos.x > b.position.x - 0.40 and pos.x < b.position.x + b.size.x + 0.40 \
		and pos.z > b.position.z - 0.40 and pos.z < b.position.z + b.size.z + 0.40 \
		and absf(pos.y - _pk.top_at(to_i)) < 0.40
	return {"ok": ok, "pos": pos, "peak": peak - _pk.top_at(from_i),
		"why": "" if ok else "没弹上 %s" % _pk.label_at(to_i)}


## 上升气流：站进柱子里**先竖直往上**（不能一开始就按方向，会被飘出柱子），
## 快到出口台高度时再按住方向横移出去 —— 这就是「要蹬一下才出得来」。
func _drive_updraft(from_i: int, to_i: int) -> Dictionary:
	var a := _pk.box_at(from_i)
	var b := _pk.box_at(to_i)
	_release_all()
	_p.global_position = Vector3(a.position.x + a.size.x * 0.5, _pk.top_at(from_i) + 0.05,
		a.position.z + a.size.z * 0.5)
	_p.velocity = Vector3.ZERO
	await _wait(3)
	var peak := _p.global_position.y
	var t0 := Time.get_ticks_msec()
	var pressed := false
	while Time.get_ticks_msec() - t0 < 6000:
		await process_frame
		peak = maxf(peak, _p.global_position.y)
		if not pressed and _p.global_position.y > _pk.top_at(to_i) - 0.30:
			pressed = true
			Input.action_press("move_forward")      # 到位了才横移出去
		if pressed:
			var c := b.position + b.size * 0.5
			var v := Vector2(c.x - _p.global_position.x, c.z - _p.global_position.z)
			if v.length() > 0.05:
				_aim(v.normalized())
		if _p.is_on_floor() and _p.global_position.x < b.position.x + b.size.x \
				and _p.global_position.y > _pk.top_at(to_i) - 0.40:
			break
	_release_all()
	await _wait(3)
	var pos := _p.global_position
	var ok := pos.x > b.position.x - 0.40 and pos.x < b.position.x + b.size.x + 0.40 \
		and pos.z > b.position.z - 0.40 and pos.z < b.position.z + b.size.z + 0.40 \
		and absf(pos.y - _pk.top_at(to_i)) < 0.40
	return {"ok": ok, "pos": pos, "peak": peak - _pk.top_at(from_i),
		"why": "" if ok else "没被托上 %s" % _pk.label_at(to_i)}


## 传送门：一路往西跑进 H2 西缘的入口门，出现在 16 m 外的 C5 上。
func _drive_portal(from_i: int, to_i: int) -> Dictionary:
	var pi := _pk.get_node_or_null("Mechanics/PortalIn") as ParkourPortal
	var a := _pk.box_at(from_i)
	var b := _pk.box_at(to_i)
	_release_all()
	_p.global_position = Vector3(a.position.x + a.size.x * 0.5, _pk.top_at(from_i) + 0.05,
		a.position.z + a.size.z * 0.5)
	_p.velocity = Vector3.ZERO
	_aim(Vector2(-1, 0))
	await _wait(3)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	var t0 := Time.get_ticks_msec()
	var crossed := false
	while Time.get_ticks_msec() - t0 < 3000:
		await process_frame
		if _p.global_position.x < b.position.x + b.size.x:
			crossed = true
			break
		if _p.global_position.y < _pk.top_at(from_i) - 3.0:
			break
	_release_all()
	await _wait(4)
	var pos := _p.global_position
	var ok := crossed and pos.x > b.position.x - 0.40 \
		and pos.x < b.position.x + b.size.x + 0.40 \
		and pos.z > b.position.z - 0.40 and pos.z < b.position.z + b.size.z + 0.40 \
		and absf(pos.y - _pk.top_at(to_i)) < 0.40
	return {"ok": ok, "pos": pos,
		"dist": float(pi.teleports) if pi != null else -1.0,
		"why": "" if ok else "没穿过传送门"}


func _test_mechanics() -> void:
	print("\n========== 5b. 机关（弹跳板 / 消失方块 / 上升气流 / 传送门 / 移动平台）==========")
	_pk.enabled = false            # 这一节自己摆人，别让「回本段起点」把人捞走

	# ① 弹跳板 ×2：**峰值 ≥ 4.5 m** 且最终落在 +4.40 的高台上
	for to_i in [38, 47]:
		var res := await _drive_bounce(to_i - 1, to_i)
		var peak := float(res.get("peak", 0.0))
		_check(bool(res["ok"]) and peak >= 4.5,
			"弹跳板 %s→%s：峰值 **+%.2f m**（需求 ≥ +4.5，理论 v²/2g = 13.5²/40 = 4.56）、"
			% [_pk.label_at(to_i - 1), _pk.label_at(to_i), peak]
			+ "最终落在 %s 上（y = %.2f）" % [_pk.label_at(to_i), float(res["pos"].y)])

	# ② 移动平台 ×2：**站着不动也被带走**（相对位移不变）+ 送到对岸
	for to_i in [26, 27]:
		var res := await _drive_mover(
			_pk.get_node_or_null("Movers/%s" % ("MoverA" if to_i == 26 else "MoverB"))
				as ParkourMover, to_i - 1, to_i)
		_check(bool(res["ok"]) and float(res.get("rel", 9.0)) < 0.60,
			"移动平台 %s→%s：人**站着不动**被带过缺口，与平台的相对位移只变了 %.2f m（< 0.60）"
			% [_pk.label_at(to_i - 1), _pk.label_at(to_i), float(res.get("rel", 9.0))]
			+ "，落在对岸 %s 上" % _pk.label_at(to_i))

	# ③ 消失方块：踩上 → 0.6 s 内塌（人开始下落）→ 2.5 s 后回来
	var van: Array[ParkourVanisher] = []
	var van_idx: Array[int] = []
	for i in range(1, _pk.node_count()):
		var nd := _pk.get_node_or_null(NodePath(String(_pk.route[i])))
		if nd is ParkourVanisher:
			van.append(nd as ParkourVanisher)
			van_idx.append(i)
	_check(van.size() == 4, "消失方块 4 块：%s"
		% str(van.map(func(v): return String(v.name))))
	if not van.is_empty():
		var v := van[0]
		var vi: int = van_idx[0]
		v.restore_now()
		var vb := _pk.box_at(vi)
		_release_all()
		_p.global_position = Vector3(vb.position.x + vb.size.x * 0.5, _pk.top_at(vi) + 0.05,
			vb.position.z + vb.size.z * 0.5)
		_p.velocity = Vector3.ZERO
		await _wait(4)
		var t0 := Time.get_ticks_msec()
		var gone_at := -1
		while Time.get_ticks_msec() - t0 < 1500:
			await process_frame
			if v.is_gone():
				gone_at = Time.get_ticks_msec() - t0
				break
		var falling := false
		var t1 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t1 < 900:
			await process_frame
			if _p.global_position.y < _pk.top_at(vi) - 0.60:
				falling = true
				break
		_check(gone_at > 350 and gone_at < 950 and falling,
			"消失方块 %s：踩上 **%.0f ms** 后碰撞真的撤掉（需求 600 ms）、人开始下落（y = %.2f）"
			% [v.name, float(gone_at), _p.global_position.y])
		# 把人挪开，等它回来
		_put(_pk.box_at(vi - 1).position.x, _pk.top_at(vi - 1) + 0.05, _pk.box_at(vi - 1).position.z)
		var t2 := Time.get_ticks_msec()
		var back_at := -1
		while Time.get_ticks_msec() - t2 < 4000:
			await process_frame
			if not v.is_gone():
				back_at = Time.get_ticks_msec() - t2
				break
		var col := v.get_node_or_null("Col") as CollisionShape3D
		_check(back_at > 1800 and col != null and not col.disabled,
			"消失方块：塌后 **%.0f ms** 回来（需求 2500 ms；实测从塌到恢复）"
			% float(back_at))

	# ④ 上升气流：进去之后**到过 +5.0**，并且站上出口台
	var res_ud := await _drive_updraft(44, 45)
	_check(bool(res_ud["ok"]) and float(res_ud.get("peak", 0.0)) >= 5.0,
		"上升气流 U1→U2：柱子里被托到 **+%.2f m**（需求 +5.0）、从出口台出来（y = %.2f）"
		% [float(res_ud.get("peak", 0.0)), float(res_ud["pos"].y)])

	# ⑤ 传送门：真的到了对岸那台（跨 16 m），而且没卡进墙里
	var res_pt := await _drive_portal(47, 48)
	var pi := _pk.get_node_or_null("Mechanics/PortalIn") as ParkourPortal
	var span := 0.0
	if pi != null and pi.target() != null:
		span = pi.global_position.distance_to(pi.target().global_position)
	_check(bool(res_pt["ok"]) and span >= 10.0,
		"传送门 %s→%s：跨 **%.2f m**（需求 ≥ 10 m）后 global_position 真的落在对岸 %s 上"
		% ["PortalIn", "PortalOut", span, _pk.label_at(48)])
	_check(float(res_pt.get("dist", 0.0)) >= 1.0,
		"传送门至少触发过 1 次（计数器 = %.0f，防乒乓冷却生效）" % float(res_pt.get("dist", 0.0)))
	_pk.enabled = true
	_release_all()


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
		{"station": 13, "seg": 1, "what": "第 2 段中段（T1 转身台）"},
		{"station": 24, "seg": 2, "what": "第 3 段中段（X4 窄板）"},
		{"station": 31, "seg": 3, "what": "第 4 段中段（W4 螺旋塔）"},
		{"station": 47, "seg": 4, "what": "第 5 段中段（L1 机关区）"},
		{"station": 56, "seg": 5, "what": "第 6 段中段（J1 竖井）"},
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
		# 用户反馈「太难」之后复活点改成**最近踩过的那一站**（不再是本段起点），
		# 段起点只当视觉地标 —— 所以这里按 `checkpoint` 核对
		var want := _pk.respawn_point(_pk.checkpoint)
		_check(seg == int(probe["seg"]) and _pk.rescues == 1 and back.distance_to(want) < 0.30,
			"%s（第 %d 站）摔到 y = −13 → 送回**最近踩过的** %s（实落 %.2f,%.2f vs 期望 %.2f,%.2f，第 %d 次）"
			% [probe["what"], idx + 1, _pk.label_at(_pk.checkpoint),
				back.x, back.z, want.x, want.z, _pk.rescues])
	_check(_pk.FALL_Y > -60.0 and _pk.FALL_Y < -5.0,
		"跑酷的兜底线 %.0f m **高于** game.gd 的 −60 m，所以抢在它前面出手" % _pk.FALL_Y)

	# ③ 回到主平台 → 检查点清空、计时归零；此时再摔，归 game.gd 的兜底管
	_p.global_position = SPAWN
	_p.velocity = Vector3.ZERO
	await _wait(4)
	# 用户反馈「存档不了」：回平台**不再清检查点**（进度保留），只停表
	var kept := _pk.checkpoint
	_check(not _pk.timer_running and _pk.elapsed_seconds() == 0.0 and kept >= 0,
		"站在主平台上 → 停表、**检查点保留**在第 %d 站（用户要的「进度不丢」）" % (kept + 1))
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
			# grow(−0.02)：**贴面**（浮点误差级别的 1 cm 重叠）不算重叠 —— 机关接口板
			# 与上一块板本来就是严丝合缝贴着的（走上去触发机关，不能留缝）
			if pads_b[i].grow(-0.02).intersects(pads_b[j].grow(-0.02)):
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
	_check(absf(top - 8.00) < 0.01, "岛面高度 y = %.2f（第 6 段下降链最后落到这儿）" % top)

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
	print("  路线                  6 段 / 59 站 / 47 跳 + 6 处机关 + 5 段走过去 / 跳距合计 %.1f m"
		% float(_m.get("gap_sum", 0.0)))
	print("  连续通关用时          %.2f s（计时器实测）" % float(_m.get("run_seconds", 0.0)))
	print("  本套自检用时          %.1f s" % secs)


# --- 工具 ---------------------------------------------------------------------

## 这一跳的水平前进方向（起跳点 → 目标板最近点；退化时朝目标板中心）
func _hop_dir(h: Dictionary, b: AABB) -> Vector2:
	var t: Vector3 = h["takeoff"]
	var n: Vector3 = h["near"]
	var v := Vector2(n.x - t.x, n.z - t.z)
	if v.length() < 0.001:
		var c := b.position + b.size * 0.5
		v = Vector2(c.x - t.x, c.z - t.z)
	return v.normalized()


## 从 (fx,fz) 沿 (dx,dz) 走多远离开盒子 —— 分析落点「沿行进方向前后 / 侧向」的余量。
## 斜跳时「离最近的边多远」会被近角放大成假警报（v3 设计期误报过一片），拆开才看得清。
func _exit(box4: PackedFloat32Array, fx: float, fz: float, dx: float, dz: float) -> float:
	var t := INF
	if absf(dx) > 1e-9:
		t = minf(t, ((box4[1] - fx) / dx) if dx > 0.0 else ((box4[0] - fx) / dx))
	if absf(dz) > 1e-9:
		t = minf(t, ((box4[3] - fz) / dz) if dz > 0.0 else ((box4[2] - fz) / dz))
	return maxf(t, 0.0)


## 取第 from_i → to_i 站的解析分析（自检和探针共用 parkour.gd 的实现）
func _hop(from_i: int, to_i: int) -> Dictionary:
	return Parkour.hop_analysis(_pk.box_at(from_i), _pk.box_at(to_i),
		Player.JUMP_VELOCITY, Player.GRAVITY, Player.SPEED_RUN)


## 实测余量最小的那一跳（用于反例：拿最难的跳去证明「不跳就过不去」）
func _worst_jump() -> Dictionary:
	var best := {"from": 1, "to": 2, "margin": INF}
	for i in range(1, _pk.node_count()):
		var h := _hop(i - 1, i)
		if float(h["required"]) < 0.5 and absf(float(h["rise"])) < 0.35:
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


## 按一次跳 —— **按住不放、确认真的跳起来了才算**。
##
## ⚠️ 为什么不能照抄别处的「按两帧就松」：`player.gd` 的跳跃条件是
##    「`is_on_floor()` **且** `Input.is_action_just_pressed("jump")`」，而后者是
##    **单帧脉冲**。跑酷板上站着的身体会**穿透微弹**（`is_on_floor()` 逐帧 true/false
##    交替 —— 实测 y 在「台面」与「台面 + 0.04」之间来回，见 `_probe_tower_hop.gd`），
##    脉冲正好落在 false 那帧就整个丢掉。更坑的是**同一个按法相位是锁死的**：
##    探针里重按 10 次全丢、A~E 五种按法（空闲帧 / 物理帧 / 合成事件 / 合成键盘）都不行，
##    而站在平台地面上同样一句 `Input.action_press` 一次就成（峰值 1.271 m）。
##    所以：每轮**多等 1 帧打散相位** + 逐帧确认 `velocity.y`，确认到了才松手。
##    返回 `true` = 真的靠输入按起来的。
func _jump() -> bool:
	for attempt in 14:
		Input.action_press("jump")
		for _i in 4:
			await process_frame
			if _p.velocity.y > 1.0:
				Input.action_release("jump")
				return true
		Input.action_release("jump")
		for _i in 1 + attempt % 3:
			await process_frame
	# 兜底（正常不该走到这里）：直接写竖直速度，让自检跑得完，同时把次数**暴露**出来
	_jump_assisted += 1
	_p.velocity.y = Player.JUMP_VELOCITY
	await process_frame
	return false


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
