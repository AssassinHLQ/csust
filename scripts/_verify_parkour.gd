extends SceneTree
## 验跑酷 v8（12 段 / 99 站 / 84 跳 + 9 处机关 + 5 段「走过去」+ 期货通四机制 + 比特币三线 + 期权/A股/外汇 + 暗网比纳 / 571 m）。
##
## 和别的自检不一样：这一套的主体是**用真输入开一个真玩家，把 59 跳挨个跳过去**。
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
##    所以「紧张的跳」全部真输入跑，「余量大的跳」也跑（59 跳 × ~1.2 s 还负担得起），
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
	var fut0 := _pk.get_node_or_null("Futures") as ParkourFutures
	if fut0 != null:
		fut0.blue_live = 0.0          # 第 1~4 节只测跳；蓝块由 5c 自己打开
	# 第 8 段的比纳会朝人打激光/炮弹（带击退）：逐跳回放和连续通关不能被它打断。
	# 它现在**不在场景里**（玩家进黑市才由 `DarkGate` 生成），所以关的是闸门：
	# 闸门不触发 = 比纳不会出现；§5f 再打开测「延迟加载 + 开火」。
	var gate0 := _pk.get_node_or_null("Route/DarkGate") as DarkGate
	if gate0 != null:
		gate0.set_physics_process(false)
	# 第 9~10 段的「天降内存条」同理：逐跳回放 / 连续通关时关掉，§5g 单独开。
	var ram0 := _pk.get_node_or_null("RamMarket") as RamMarket
	if ram0 != null:
		ram0.rain_enabled = false
		ram0.loot_enabled = false       # 地上那几根也别捡：前面几节会把玩家到处瞬移
	# ⚠️ 这一套会**真的跑完一次全程**，于是 `parkour.gd` 会把那次用时写进
	#    `user://parkour_best.cfg` —— 那是玩家真实存档。开跑前备份、收尾时还回去
	#    （和 `_verify_settings` 测音量时的做法一样）。
	_best_backup = _read_best_file()

	await _test_structure(game)
	await _test_ready_zone()
	await _test_summon_pad()
	await _test_fund_lottery()
	await _test_capsule()
	await _test_calibration()
	await _test_hops()
	await _test_mechanics()
	await _test_futures()
	await _test_branch()
	await _test_dark_boss()
	await _test_ram_market()
	await _test_ram_loot()
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
	# 兜底：任何一节静默跳过，断言总数都会掉下来（当前 125 条；71 站版比 59 站版多 12 根 K 线的回放）
	_check(_pass + _fail >= 150,
		"断言总数 ≥ 120（实测 %d 条）—— 哪一节没跑完这里会先变红" % (_pass + _fail))
	print("通过 %d 项" % _pass)
	_print_table()
	_quit()


# --- 1. 结构与几何 -------------------------------------------------------------

func _test_structure(game: Node) -> void:
	print("\n========== 1. 结构与几何 ==========")
	var n := _pk.node_count()
	_check(n == 99, "路线有 %d 站（期望 99：跑道 + 57 块落脚板 + 13 块期货通板块 + 第 4 段 5 站 + 期权/A股/外汇 15 站 + 暗网 7 站 + 5 处接口板 + 6 处机关 + 岛）" % n)
	var want := ["Launch", "P1", "P2", "P3", "P4", "P5", "P6", "P7", "C1",
		"B1", "BA", "S1", "BB", "T1", "T2", "T3", "T4", "T5", "T6", "C2",
		"K1", "K2", "K3", "K4", "K5", "K6", "K7", "K8", "K9", "K10", "K11", "K12", "K13",
		"J0", "SP1", "SP2", "SP3", "M0",
		"OPT1", "OPT2", "OPT3", "OPT4", "AS1", "AS2", "AS3", "AS4",
		"FX1", "FX2", "FX3", "FX4", "FX5", "FX6", "FX7",
		"DK1", "DK2", "DK3", "DK4", "DK5", "DK6", "DK7",
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
	_check(sorted_ok and _pk.segment_count() == 12 and segs.size() == _pk.seg_names.size(),
		"分段数据：segments=%s（升序、首项 0、12 段），seg_names %d 个「%s」"
		% [str(segs), _pk.seg_names.size(), " / ".join(PackedStringArray(_pk.seg_names))])
	# 段起点必须是段落里**第一站**、而且每段都非空
	var span_ok := true
	for s in _pk.segment_count():
		var st := _pk.segment_start(s)
		var en: int = _pk.segment_start(s + 1) if s + 1 < _pk.segment_count() else n
		if en <= st or st < 0 or en > n:
			span_ok = false
	_check(span_ok, "十二段的站号区间都不空：%s"
		% str(Array(range(0, _pk.segment_count())).map(func(s): return "%s[%d]" % [
			_pk.segment_name(s), _pk.segment_start(s)])))
	# 机关清单也要跟着对：6 处机关跳、螺旋塔 7 处减速短跳（W2…C4，由场景给）。
	# 螺旋塔 2026-10-17 回到 7 跳版：11 跳版每 4 级叠在同一 xz、层间只差 2.05 m，
	# 玩家的 1.5 m 身高 + 0.5 m 板厚只剩 5 cm，跳起来必撞头 —— 这不是难度，是几何死锁。
	# 现在每级 +0.80（4 级 = 3.20 m，净空 2.70 m），总高仍是 W1 台面 2.80 → C4 台面 8.40。
	_check(_pk.special_hops.size() == 9,
		"机关跳 %d 处（期望 9 = 6 处机关 + 升降台 K6 + 平移台 K8 + 第 4 段现货道渡船 SP3）：%s（减速短跳 %d 处，期望 7：W2…C4）"
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
		if _inside_boss(node) or _inside_decor(node):
			continue      # Boss 的 FBX / 内存条市场的装饰件不在 0.05 m 网格上
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
		if node is ParkourMover:
			var mv := node as ParkourMover
			for v in [mv.point_a, mv.point_b]:
				for c in 3:
					var q: float = absf(v[c]) / 0.05
					if absf(q - roundf(q)) > 0.001:
						bad_dock.append("%s %s=%.3f" % [mv.name, "xyz"[c], v[c]])
	for node in _walk(_pk):
		if node is ParkourDrift and (node as ParkourDrift).mode != ParkourDrift.Mode.BROWNIAN:
			var dr := node as ParkourDrift
			for v in [dr.point_a, dr.point_b]:
				for c in 3:
					var q: float = absf(v[c]) / 0.05
					if absf(q - roundf(q)) > 0.001:
						bad_dock.append("%s %s=%.3f" % [dr.name, "xyz"[c], v[c]])
	_check(bad_dock.is_empty(), "移动平台 / 升降台 / 平移台的两个端点也落在 0.05 m 网格上%s"
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
	_check(st["labels"] >= 6, "指路牌 %d 块都在" % st["labels"])
	# 2026-10-18 用户：「还有这些 ui 太挡视线了不需要」→ 计时 HUD（原 `ParkourHUD`
	# 里那两个 Label）整个删掉了，所以这里反过来断言**它不在了** ——
	# 免得以后谁又把它加回来，在屏幕顶上挡视线。
	var gone := 0
	for hud_name in ["ParkourHUD", "ParkourHUD/Timer", "ParkourHUD/Seg"]:
		if _pk.get_node_or_null(hud_name) == null:
			gone += 1
	_check(gone == 3, "跑酷计时 HUD 已删除（用户要求，不挡视线）")
	print("  小结：%d 个节点，%d 个网格，%d 个碰撞形状，%d 盏灯，%d 个 Label3D"
		% [st["nodes"], st["meshes"], st["shapes"], st["lights"], st["labels"]])


## ── 1b. 跑酷准备区：踏进去同伴就原地待命 ─────────────────────────────────────
## 用户 2026-10-19：「现在跑酷第一段前，设置跑酷准备区，一旦进入，同伴就原地待命，
## 爱丽丝单枪匹马前去」。
func _test_ready_zone() -> void:
	print("\n========== 1b. 跑酷准备区（同伴原地待命）==========")
	var comps: Array[Companion] = []
	for c in _p.get_parent().get_children():
		if c is Companion:
			comps.append(c as Companion)
	_check(comps.size() >= 3, "场上有 %d 名同伴" % comps.size())
	var zone := _pk.get_node_or_null("ReadyZone") as ParkourReadyZone
	_check(zone != null, "第 1 段跑道东口摆着准备区 `ReadyZone`（金色垫子，x −20~−6、z 0~8）")
	if zone == null or comps.is_empty():
		return
	# ⓪ 尺寸：2026-10-20 用户「准备区短了，要延伸到平台边缘」+「没有覆盖到边缘」
	#    —— 6×4 → 13×8 → **14×8**（最西那 1 m 原来踩上去不触发）
	_check(absf(zone.zone_size.x - 14.0) < 0.01 and absf(zone.zone_size.z - 8.0) < 0.01,
		"垫子尺寸 %s（14×8：整条 10 m 跑道 + 西端 1 m 都在里面）" % str(zone.zone_size))
	var zb: AABB = AABB(Vector3(zone.global_position.x - zone.zone_size.x * 0.5, 0.0,
		zone.global_position.z - zone.zone_size.z * 0.5),
		Vector3(zone.zone_size.x, 3.0, zone.zone_size.z))
	_check(zb.position.x <= -20.0 and zb.end.x >= -6.0 and zb.position.z <= 0.0
			and zb.end.z >= 8.0,
		"覆盖范围 x %.1f ~ %.1f、z %.1f ~ %.1f（跑道 Launch 是 x −20~−10 / z 2.5~5.5）"
		% [zb.position.x, zb.end.x, zb.position.z, zb.end.z])
	# ⓪b 跑道上那块和台面共面的 `LaunchMark` 已删（用户：「边缘有一小块多余的
	#     黄色条要去掉不然会 z-fighting」—— 它顶面 y = 0.025 和跑道一模一样）
	_check(_pk.get_node_or_null("LaunchMark") == null,
		"跑道上没有和台面共面的多余金条（`LaunchMark` 已删，不会再 z-fighting）")
	# ① 进区之前：一个都不许待命
	_put(0.00, 0.10, 6.00)
	await _wait(6)
	var early := 0
	for c in comps:
		if c.is_standby():
			early += 1
	_check(early == 0, "踏进之前 %d 名同伴都还在跟随（待命 %d 名）" % [comps.size(), early])
	# ② 踏进垫子 → 全部原地待命
	_put(zone.global_position.x, 0.10, zone.global_position.z)
	await _wait(10)
	var n := 0
	for c in comps:
		if c.is_standby():
			n += 1
	_check(n == comps.size(), "踏入准备区 → **%d/%d 名同伴原地待命**" % [n, comps.size()])
	# ③ 玩家跑出 29 m（比 teleport_distance 26 还远）：同伴不许跟、也不许被拉回
	var homes: Array[Vector3] = []
	for c in comps:
		homes.append(c.global_position)
	var was := _pk.enabled
	_pk.enabled = false          # 别让掉下去触发检查点回送，把玩家拉回来
	_put(-38.00, 2.00, 6.00)
	await _wait_ms(1500)
	var moved := 0.0
	for i in comps.size():
		moved = maxf(moved, comps[i].global_position.distance_to(homes[i]))
	_check(moved < 1.0,
		"玩家跑到 29 m 外（> 拉回阈值 26 m），同伴最大位移只有 %.2f m —— 真的在待命"
		% moved)
	_pk.enabled = was

	# ④ 用户 2026-10-20：「召回所有人后再次跑酷，准备区用不了了」
	#    以前 `_fired` 一旦置真就永远不再触发。现在**离开垫子就重新武装**：
	#    先手动解除待命（等价于在小屋里按过召唤台），再走回垫子 —— 必须再触发一次。
	for c in comps:
		c.set_standby(false)
	_put(0.00, 0.10, 6.00)          # 离开垫子（x 0 在垫子东边之外）
	await _wait_ms(700)              # 等过 `rearm_delay`（0.45 s）
	var armed := not zone.fired()
	_put(zone.global_position.x, 0.10, zone.global_position.z)
	await _wait(10)
	var again := 0
	for c in comps:
		if c.is_standby():
			again += 1
	_check(armed and again == comps.size(),
		"离开垫子后**重新武装**（fired 已复位：%s），召回后再踏一次 → 又 %d/%d 名待命"
		% [str(armed), again, comps.size()])

	# ⑤ 兜底：从跑道西头插进来、一脚没踩到垫子 —— 踩上第 1 站 `Launch` 也照样触发
	#    （`game.gd::_on_parkour_checkpoint`）。x −19.5 在垫子（x ≥ −19）之外、但在跑道上。
	for c in comps:
		c.set_standby(false)
	var cp0 := _pk.checkpoint
	_pk.checkpoint = -1
	_put(-19.50, 0.10, 4.00)
	await _wait(10)
	var by_launch := 0
	for c in comps:
		if c.is_standby():
			by_launch += 1
	_check(by_launch == comps.size(),
		"没踩到垫子、只踩到跑道 `Launch`（x −19.5）→ 也 **%d/%d 名待命**（保险生效）"
		% [by_launch, comps.size()])
	_pk.checkpoint = cp0

	# 收尾：把她们放回跟随、人回出生点
	for c in comps:
		c.set_standby(false)
	_put(0.00, 0.10, 6.00)
	await _wait(4)


# --- 1c. 小屋里的召唤台 -----------------------------------------------------------

## 用户 2026-10-19：「在你做的这个房子里面可以召唤同伴，如果不玩跑酷了，
## 可以在这里重新呼叫同伴回来」。
##
## 这一节接在 1b 后面：那时 7 名同伴**正以「原地待命」状态留在跑道口**（x ≈ −9），
## 玩家走回小屋踩一下垫子，她们必须**瞬移回来并且恢复跟随**。
func _test_summon_pad() -> void:
	print("\n========== 1c. 小屋召唤台（把同伴叫回来）==========")
	var game := _p.get_parent()
	var comps := _companions()
	_check(comps.size() >= 3, "场上有 %d 名同伴" % comps.size())
	var pad := game.get_node_or_null("MeshHut/SummonPad") as SummonPad
	_check(pad != null, "小屋 `MeshHut` 里摆着召唤台 `SummonPad`")
	if pad == null or comps.is_empty():
		return
	var hut := game.get_node_or_null("MeshHut") as Node3D
	var to_hut := Vector2(pad.global_position.x - hut.global_position.x,
		pad.global_position.z - hut.global_position.z).length()
	# 小屋内部 6.2 × 5.2 m：垫子必须真的在屋里，而不是挂在门外的平台上
	_check(to_hut < 3.2, "垫子在小屋**里面**（离小屋中心 %.2f m，屋内半宽 3.1 / 半深 2.6）"
		% to_hut)

	# ① 前置：把她们**留在跑道口待命**（§1b 收尾时已经放了跟随，这里重新摆一次，
	#    模拟「跑完一段、人回小屋」的状态）
	_put(0.00, 0.10, 6.00)
	for c in comps:
		c.set_standby(true)
	await _wait(4)
	var standby0 := 0
	var far0 := 0.0
	for c in comps:
		if c.is_standby():
			standby0 += 1
		far0 = maxf(far0, c.global_position.distance_to(pad.global_position))
	_check(standby0 == comps.size() and far0 > 5.0,
		"踩之前：%d/%d 名还在跑道口待命（最远 %.1f m）" % [standby0, comps.size(), far0])

	# ② 踏上垫子 → 全部瞬移回小屋、解除待命
	var before_pos: Array[Vector3] = []
	for c in comps:
		before_pos.append(c.global_position)
	_put(pad.global_position.x, pad.global_position.y + 0.10, pad.global_position.z)
	await _wait(8)
	var home := 0
	var standby1 := 0
	var worst := 0.0
	var min_move := 1.0e9
	for i in comps.size():
		var c := comps[i]
		if not c.is_standby():
			home += 1
		else:
			standby1 += 1
		worst = maxf(worst, c.global_position.distance_to(pad.global_position))
		min_move = minf(min_move, c.global_position.distance_to(before_pos[i]))
	_check(home == comps.size() and standby1 == 0,
		"踏上召唤台 → **%d/%d 名同伴回到小屋并恢复跟随**（仍待命 %d 名）"
		% [home, comps.size(), standby1])
	# 判「真的瞬移了」用**位移**，不用「离垫子多远」：刚落地她们就开始往各自的
	# 跟随位走，采样时有人已经在 3~4 m 外了（第一版卡 3.0 m 就是这么假红的）。
	_check(min_move > 10.0,
		"每名同伴都是**瞬移**回来的（最小位移 %.1f m；她们刚才在跑道口）" % min_move)
	_check(worst < 5.0, "落地集中在垫子 %.2f m 内（小屋长轴上一排，间隔 0.7 m）" % worst)
	_check(pad.title_text().contains("召回"), "垫子上的字变成「%s」" % pad.title_text())

	# ③ 反复踩是**允许**的（和一次性 latch 的跑酷准备区相反）
	var n0 := comps.size()
	_put(0.00, 0.10, 6.00)
	# ⚠️ 必须**等真实时间**过冷却（1.2 s）：`_wait(4)` 只是 4 帧，探针里一帧几毫秒，
	#    垫子还在冷却中，第二脚根本不会触发（第一版就是这么假红的）。
	await _wait_ms(1400)
	_put(pad.global_position.x, pad.global_position.y + 0.10, pad.global_position.z)
	await _wait(8)
	# 判据用「人在不在**小屋里面**」而不是「离垫子几米」：刚落地她们就开始往
	# 各自的跟随位挪（有人会走到门口），只要还在屋里就算召回来了。
	var hp := hut.global_position
	var again := 0
	for c in comps:
		var q := c.global_position
		if absf(q.x - hp.x) < 3.6 and absf(q.z - hp.z) < 3.0:
			again += 1
	_check(again == n0, "离开再回来还能再召唤一次（再踩 → %d/%d 名又回到小屋里）" % [again, n0])

	_put(0.00, 0.10, 6.00)
	await _wait(4)


# --- 1d. 第 1 段「稳定基金」/ 第 2 段「体育彩票」 --------------------------------

## 用户 2026-10-19：「跑酷第一段是稳定基金，每次加百分之 0.1，第二段是体育彩票
## 大部分输钱小部分赚小钱」。
func _test_fund_lottery() -> void:
	print("\n========== 1d. 第 1 段「稳定基金」/ 第 2 段「体育彩票」==========")
	var fut := _pk.get_node_or_null("Futures") as ParkourFutures
	_check(fut != null, "场景里有 `Futures` 总控（结算都归它）")
	if fut == null:
		return

	# ① 规则本身：纯函数抽 1000 注，看中奖率和区间
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261019
	var win := 0
	var lo := INF
	var hi := -INF
	for _i in 1000:
		var p := fut.lottery_pct(rng.randf())
		if p > 0.0:
			win += 1
		lo = minf(lo, p)
		hi = maxf(hi, p)
	_check(win >= 180 and win <= 260,
		"体育彩票中奖率 %.1f%%（1000 注，规则 22%%）" % (float(win) * 0.1))
	_check(hi <= ParkourFutures.LOT_WIN_HI + 1e-4 and hi >= ParkourFutures.LOT_WIN_HI - 0.1
			and lo >= -ParkourFutures.LOT_LOSE_HI - 1e-4 and lo <= -ParkourFutures.LOT_LOSE_HI + 0.1,
		"涨跌幅正好落在 −%.2f%% ~ +%.2f%%（实测 %.2f ~ %.2f）"
		% [ParkourFutures.LOT_LOSE_HI, ParkourFutures.LOT_WIN_HI, lo, hi])
	_check(fut.lottery_pct(0.0) > 0.0 and fut.lottery_pct(0.999) < 0.0,
		"r = 0 中奖、r → 1 没中（映射单调、两端都对）")
	# 「大部分输钱」：期望值必须为负
	var sum := 0.0
	for i in 1000:
		sum += fut.lottery_pct((float(i) + 0.5) / 1000.0)
	_check(sum / 1000.0 < -0.5,
		"**大部分输钱**：1000 注均摊 %.2f%%/注，期望为负" % (sum / 1000.0))

	# ② 稳定基金：踩第 1 段的 P1 → 保证金 ×1.001
	fut.margin = fut.start_margin
	fut.settled.clear()
	fut._intro_done.clear()
	var i1 := _idx("P1")
	var b1 := _pk.box_at(i1)
	_put(b1.position.x + b1.size.x * 0.5, _pk.top_at(i1) + 0.05,
		b1.position.z + b1.size.z * 0.5)
	await _wait(6)
	var want := fut.start_margin * (1.0 + ParkourFutures.FUND_PCT / 100.0)
	_check(absf(fut.margin - want) < 0.002 and fut._last_settle.contains("稳定基金"),
		"踩上第 1 段的 P1 → 保证金 %.4f → %.4f 万（+%.2f%%，复利）：%s"
		% [fut.start_margin, fut.margin, ParkourFutures.FUND_PCT, fut._last_settle])

	# ③ 一块板只结算一次（来回走不许刷钱）
	_put(b1.position.x + b1.size.x * 0.5, _pk.top_at(i1) + 0.05,
		b1.position.z + b1.size.z * 0.5)
	await _wait(6)
	_check(absf(fut.margin - want) < 0.0001,
		"同一块板再站一次**不再结算**（保证金仍是 %.4f 万）" % fut.margin)

	# ④ 体育彩票：踩第 2 段的 T1 → 钱按彩票规则动，HUD 上写「体育彩票」
	var i2 := _idx("T1")
	var b2 := _pk.box_at(i2)
	var m2 := fut.margin
	_put(b2.position.x + b2.size.x * 0.5, _pk.top_at(i2) + 0.05,
		b2.position.z + b2.size.z * 0.5)
	await _wait(6)
	var pct2 := (fut.margin / maxf(m2, 0.0001) - 1.0) * 100.0
	_check(fut._last_settle.contains("体育彩票") and absf(pct2) > 0.05,
		"踩上第 2 段的 T1 → 开一注彩票：%.4f → %.4f 万（%+.2f%%）：%s"
		% [m2, fut.margin, pct2, fut._last_settle])
	# 8 名同伴 / 玩家都在跑道上：彩票真的会把保证金往下打，但不会一注清零
	_check(fut.margin > 0.0, "一注彩票不会直接把保证金打到 0（当前 %.4f 万）" % fut.margin)

	# 还原：后面的逐跳回放要用干净的账（不然 20 块板全被标成「已结算」）
	fut.margin = fut.start_margin
	fut.settled.clear()
	fut._intro_done.clear()
	_put(0.00, 0.10, 6.00)
	await _wait(4)


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
		# 「紧张区」= **勉强够**的那一跳（0.80~0.90）。低于门槛的（螺旋塔短跳 0.47）
		# 不算紧张区：它们各自有自己的门槛，而且已经由上面 `bad` 单独记账 ——
		# 把 0.47 也塞进这个区间，会让「紧张区占比」这件事量错（塔的 7 跳会把比例顶穿）。
		if margin >= MARGIN_MIN and margin <= 0.90:
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
		# 大平台（第 4 段的分叉台 J0 / 结算台 M0，5 × 22 m）：落点必然在板上，
		# 「瞄板心算入板深度」在这种尺寸上没有意义（实测会算成「前 7.59」的假红）。
		if b.size.x >= 4.0 and b.size.z >= 4.0:
			continue
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
			# 大平台（J0/M0）和 `_run_hop` 一样瞄「最近点再往里 0.5 m」，别瞄板心
			var aim2 := c2
			if b2.size.x >= 4.0 and b2.size.z >= 4.0:
				aim2 = Vector3(
					clampf(t2.x, b2.position.x + 0.5, b2.position.x + b2.size.x - 0.5), c2.y,
					clampf(t2.z, b2.position.z + 0.5, b2.position.z + b2.size.z - 0.5))
			var d2 := Vector2(aim2.x - t2.x, aim2.z - t2.z).normalized()
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
	# ⚠️ 大平台（第 4 段的 J0 / M0，5 × 22 m）**不能瞄板心**：板心在 8 m 外的侧面，
	#    人一跑就斜着冲出起跳板（实测 M0 那一跳就是这么失败的）。
	#    这种尺寸改成瞄「离起跳点最近的那一点、再往里收 0.5 m」。
	var aim_to := center
	if b.size.x >= 4.0 and b.size.z >= 4.0:
		aim_to = Vector3(
			clampf(takeoff.x, b.position.x + 0.5, b.position.x + b.size.x - 0.5),
			center.y,
			clampf(takeoff.z, b.position.z + 0.5, b.position.z + b.size.z - 0.5))
	var dir := Vector2(aim_to.x - takeoff.x, aim_to.z - takeoff.z).normalized()
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
			var vs := Vector2(aim_to.x - ps.x, aim_to.z - ps.z)
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
		return {"ok": ok2, "pos": pos2, "why": "" if ok2 else "落点 %.2f,%.2f y=%.2f（台面 %.2f）"
			% [pos2.x, pos2.z, pos2.y, _pk.top_at(to_i)]}
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
				var v := Vector2(aim_to.x - pp.x, aim_to.z - pp.z)
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
	return {"ok": ok, "pos": pos, "why": "" if ok else "落点 %.2f,%.2f y=%.2f（台面 %.2f）" % [pos.x, pos.z, pos.y, _pk.top_at(to_i)]}


# --- 5b. 机关（真物理）--------------------------------------------------------

## 六处「机关跳」的驱动：按真实玩法走一遍（等平台 / 踩弹跳板 / 进气流 / 穿传送门）。
## 连续通关里就是靠它过那六处。
func _futures() -> ParkourFutures:
	return _pk.get_node_or_null("Futures") as ParkourFutures


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
		"K6":
			return await _ride_drift(_futures(), ParkourDrift.Mode.LIFT, from_i, to_i, "升降台")
		"K8":
			return await _ride_drift(_futures(), ParkourDrift.Mode.SLIDE, from_i, to_i, "平移台")
		"SP3":
			return await _ride_drift(_futures(), ParkourDrift.Mode.LIFT, from_i, to_i,
				"现货道渡船", "SP2")
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
	# 下船：**走到真的站上对岸**为止。原来是固定 600 ms —— 平台端点只停 1.2 s，
	# 检测到靠岸 + 按方向键的延迟一抖，人还在船上平台就开回去了（实测只挪 0.10 m）。
	_aim(Vector2(-1, 0))
	Input.action_press("move_forward")
	var tw0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - tw0 < 1500:
		await process_frame
		if _inside_box(_p.global_position, _pk.box_at(to_i)):
			break
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
func _drive_portal(_from_i: int, to_i: int) -> Dictionary:
	var pi := _pk.get_node_or_null("Mechanics/PortalIn") as ParkourPortal
	var tgt: Node3D = pi.target() if pi != null else null
	_release_all()
	if pi == null:
		return {"ok": false, "pos": _p.global_position, "dist": -1.0, "why": "没有 PortalIn"}
	var before := pi.teleports
	# ⚠️ 直接把脚塞进门框里，不要「从旁边跑进去」：门悬在竖井边上，跑进去的路径会被
	#    井壁挡住（实测两次都卡在原地、位移 0.00 m）。Area3D 的 body_entered 照样会发。
	_p.global_position = pi.global_position + Vector3(0, 1.0, 0)
	# ⚠️ 进门时给一个**向西的速度**：传送门只清竖直速度、水平速度是保留的（见
	#    parkour_portal.gd），连续通关就靠这股冲量冲上对岸的台面 —— 零速度传过去
	#    会原地掉在出口边缘，下一跳直接「没跑到边缘」。
	_p.velocity = Vector3(-Player.SPEED_RUN, 0.0, 0.0)
	await _wait(5)
	var pos := _p.global_position
	var fired := pi.teleports > before
	var ok := fired and tgt != null and pos.distance_to(pi.exit_point()) < 2.0
	return {"ok": ok, "pos": pos, "dist": float(pi.teleports),
		"why": "" if ok else "没落到出口（实落 %.2f,%.2f,%.2f，出口 %.2f,%.2f,%.2f，门触发 %s）"
			% [pos.x, pos.y, pos.z, pi.exit_point().x, pi.exit_point().y, pi.exit_point().z,
				str(fired)]}


func _test_mechanics() -> void:
	print("\n========== 5b. 机关（弹跳板 / 消失方块 / 上升气流 / 传送门 / 移动平台）==========")
	_pk.enabled = false            # 这一节自己摆人，别让「回本段起点」把人捞走

	# ① 弹跳板 ×2：**峰值 ≥ 4.5 m** 且最终落在 +4.40 的高台上
	# ⚠️ 站号一律**按名字查**，别写死数字：K 段（+13）和第 4 段（+5）各插过一次，
	#    写死的 51/60 已经从「Q1→H1」漂成「W6→V4」—— 那两块是普通板，当然不弹。
	for to_i in [_idx("H1"), _idx("H2")]:
		var res := await _drive_bounce(to_i - 1, to_i)
		var peak := float(res.get("peak", 0.0))
		_check(bool(res["ok"]) and peak >= 4.5,
			"弹跳板 %s→%s：峰值 **+%.2f m**（需求 ≥ +4.5，理论 v²/2g = 13.5²/40 = 4.56）、"
			% [_pk.label_at(to_i - 1), _pk.label_at(to_i), peak]
			+ "最终落在 %s 上（y = %.2f）" % [_pk.label_at(to_i), float(res["pos"].y)])

	# ② 移动平台 ×2：**站着不动也被带走**（相对位移不变）+ 送到对岸
	for to_i in [_idx("F2"), _idx("C3")]:
		var res := await _drive_mover(
			_pk.get_node_or_null("Movers/%s" % ("MoverA" if _pk.label_at(to_i) == "F2" else "MoverB"))
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
	var res_ud := await _drive_updraft(_idx("U1"), _idx("U2"))
	_check(bool(res_ud["ok"]) and float(res_ud.get("peak", 0.0)) >= 5.0,
		"上升气流 U1→U2：柱子里被托到 **+%.2f m**（需求 +5.0）、从出口台出来（y = %.2f）"
		% [float(res_ud.get("peak", 0.0)), float(res_ud["pos"].y)])

	# ⑤ 传送门：真的到了对岸那台（跨 13 m），而且人没卡在半路
	var res_pt := await _drive_portal(_idx("H2"), _idx("L1"))
	var pi := _pk.get_node_or_null("Mechanics/PortalIn") as ParkourPortal
	var span := 0.0
	var tgt: Node3D = null
	if pi != null:
		tgt = pi.target()
		if tgt != null:
			span = pi.global_position.distance_to(tgt.global_position)
	_check(bool(res_pt["ok"]) and span >= 10.0,
		"传送门 %s→%s：跨 **%.2f m**（需求 ≥ 10 m）后落在对岸 %s 的出口（实落 %.2f,%.2f,%.2f）"
		% ["PortalIn", "PortalOut", span, _pk.label_at(_idx("L1")),
			float(res_pt["pos"].x), float(res_pt["pos"].y), float(res_pt["pos"].z)])
	_check(float(res_pt.get("dist", 0.0)) >= 1.0,
		"传送门至少触发过 1 次（计数器 = %.0f，防乒乓冷却生效）" % float(res_pt.get("dist", 0.0)))
	_pk.enabled = true
	_release_all()


# --- 5c. 同花顺期货通（第 3 段的四个机制）----------------------------------------

## 期货通那一节：会动的块怎么坐、蓝块怎么把人送走、薛定谔怎么坍缩。
## ⚠️ 蓝块是「凭空出现」的，人可能已经站在里面才轮到它变实体 —— 所以既要测
##    「站着不动会不会被平仓」，也要测「冷却一次只扣一次」。
func _test_futures() -> void:
	print("\n========== 5c. 同花顺期货通（会动的块 / 蓝块强平 / 薛定谔）==========")
	var fut := _pk.get_node_or_null("Futures") as ParkourFutures
	if fut == null:
		_check(false, "场景里有 Futures（期货通总控）")
		return
	_check(fut.drifts.size() == 6 and fut.hazards.size() == 7 and fut.schro.size() == 3,
		"期货通就位：会动的块 %d 个（K 段 3 + 第 4 段三道 3）、究极蓝块 %d 个、薛定谔块 %d 个"
		% [fut.drifts.size(), fut.hazards.size(), fut.schro.size()])

	# ① 两块板之间那条缝必须**大于射程**：不然玩家可以直接跳过去，机关就白做了
	for pair in [["K5", "K6"], ["K7", "K8"]]:
		var from_i := _idx(String(pair[0]))
		var to_i := _idx(String(pair[1]))
		var h := _hop(from_i, to_i)
		var reach := float(h["reach"]) * float(_m.get("k", 1.055))
		_check(float(h["required"]) > reach,
			"%s→%s 直跳**过不去**（必须跨 %.2f m > 射程 %.2f m）—— 只能坐会动的块"
			% [pair[0], pair[1], float(h["required"]), reach])

	# ② 升降台 / 平移台：站上去**不动**被送到对岸
	var lift := await _ride_drift(fut, ParkourDrift.Mode.LIFT, _idx("K5"), _idx("K6"), "升降台")
	_check(bool(lift["ok"]),
		"升降台 K5→K6：人站着不动升到 +%.2f m 的 K6 上（%s）"
		% [float(_pk.top_at(_idx("K6"))), String(lift.get("why", "ok"))])
	var slide := await _ride_drift(fut, ParkourDrift.Mode.SLIDE, _idx("K7"), _idx("K8"), "平移台")
	_check(bool(slide["ok"]),
		"平移台 K7→K8：人站着不动横过缺口、走到 K8 上（%s）" % String(slide.get("why", "ok")))

	# ③ 布朗块：真的在乱走，而且**跑不出自己的活动半径**
	var brown: ParkourDrift = null
	for d in fut.drifts:
		if d.mode == ParkourDrift.Mode.BROWNIAN:
			brown = d
	if brown != null:
		# ⚠️ 圆心用布朗块**自己的出生点**（`home()`），不能用测试开始时的位置
		var home := brown.home()
		var far := 0.0
		var moved := 0.0
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 2600:
			await process_frame
			far = maxf(far, Vector2(brown.global_position.x - home.x,
				brown.global_position.z - home.z).length())
			moved = maxf(moved, brown.global_position.distance_to(home))
		_check(moved > 0.6 and far <= brown.roam + 0.6,
			"布朗块：2.6 s 内最远走了 %.2f m、离出生点最远 %.2f m（活动半径 %.1f m，不许跑飞）"
			% [moved, far, brown.roam])

	# ④ 究极蓝块：预警 → 实体 → 消失；站进实体里 = 强制平仓
	var hz: Node3D = fut.hazards[0]
	var saved_t := fut._t
	fut.blue_live = 3.0            # `_run()` 为了前几节把它关了，这里打开
	# 观察周期的时候把人放到主平台上（别站在蓝块底下等人来平仓）
	_pk.enabled = false
	_put(SPAWN.x, SPAWN.y, SPAWN.z)
	await _wait(3)
	var seen_live := false
	var seen_dark := false
	fut._t = 0.0
	for _i in 600:
		await physics_frame
		if hz.visible and _hazard_live(fut, hz):
			seen_live = true
		if not hz.visible:
			seen_dark = true
		if seen_live and seen_dark:
			break
	_check(seen_live and seen_dark, "蓝块会**凭空出现再消失**（周期里见过实体，也见过空缺）")
	# 先把人站到 K4 上（检查点 = K4），再**把计数器清零**，然后把他塞进实体蓝块里
	var k4 := _idx("K4")
	var b4 := _pk.box_at(k4)
	_pk.enabled = true
	_pk.reset_run()
	_put(b4.position.x + b4.size.x * 0.5, _pk.top_at(k4) + 0.05, b4.position.z + b4.size.z * 0.5)
	await _wait(6)
	fut.debt = 0
	fut.liquidations = 0
	fut._cool = 0.0
	# ⚠️ 前面的逐跳回放会真的踩过结算台 M0 —— 只要那一刻保证金 ≥ 11 万，
	#    「对冲」就解锁了，强平就只扣 35% 不送回。这一条要测的是**没解锁**的那条路。
	fut.hedged = false
	fut._hedge_checked = false
	var ck := _pk.checkpoint
	var debt0 := fut.debt
	var liq0 := fut.liquidations
	# ⚠️ 顺序不能反：`_put` 进蓝块 → 同一帧就可能被平仓 → 人被送回 K4。
	#    第一版把「清零」写在 `_put` 之后，正好把刚发生的强平擦掉了、还误判成「没触发」。
	fut._t = float(hz.get_meta("offset")) * -1.0 + fut.blue_period - fut.blue_live + 0.05
	_put(hz.global_position.x, hz.global_position.y - 0.9, hz.global_position.z)
	for _i in 20:
		await physics_frame
	_check(fut.liquidations == liq0 + 1 and fut.debt > debt0,
		"站进实体蓝块 → **强制平仓**：强平 %d→%d 次、负债 %d→%d 万（冷却 %.1f s，只扣一次）"
		% [liq0, fut.liquidations, debt0, fut.debt, fut.cooldown])
	var back := _p.global_position
	var want_pos := _pk.respawn_point(ck)
	_check(Vector2(back.x - want_pos.x, back.z - want_pos.z).length() < 0.50
			and absf(back.y - want_pos.y) < 1.20,
		"强制平仓后送回**最近踩过的落脚点**（第 %d 站 %s，实落 %.2f,%.2f,%.2f vs 期望 %.2f,%.2f,%.2f）"
		% [ck + 1, _pk.label_at(ck), back.x, back.y, back.z, want_pos.x, want_pos.y, want_pos.z])
	fut._t = saved_t

	# ⑤ 薛定谔块：踩上去之前不知道颜色，第一次踩到才坍缩成红（阳线）/ 绿（阴线）
	# 前面几节可能已经踩过它们了 —— 找一个还没坍缩的；都坍缩了就**重置一块**再测
	var plate: Node3D = null
	for cand in fut.schro:
		if not cand.has_meta("resolved"):
			plate = cand
			break
	if plate == null:
		plate = fut.schro[0]
		plate.remove_meta("resolved")
		var m0 := plate.get_node_or_null("Mesh") as MeshInstance3D
		m0.material_override = fut._mat(ParkourFutures.SCH_UNKNOWN, 0.45, 1.0)
		var l0 := plate.get_node_or_null("Pct") as Label3D
		l0.text = "?"
		l0.modulate = Color(1, 1, 1, 1)
	var mesh := plate.get_node_or_null("Mesh") as MeshInstance3D
	var before: Color = (mesh.material_override as StandardMaterial3D).albedo_color
	var c0 := fut.collapses
	var pi := _idx(String(plate.name))
	var pb := _pk.box_at(pi)
	# 前面的小节可能已经把这块结算过了（一块只结算一次）—— 清掉重来，
	# 顺便把保证金复位（强平之后是 0，不归位的话「0 乘任何数还是 0」会假绿）
	fut.settled.erase(String(plate.name))
	fut.margin = fut.start_margin
	var m_before := fut.margin
	fut.blue_live = 0.0            # 这一段不要蓝块来捣乱
	_put(pb.position.x + pb.size.x * 0.5, _pk.top_at(pi) + 0.05, pb.position.z + pb.size.z * 0.5)
	await _wait(6)
	var after: Color = (mesh.material_override as StandardMaterial3D).albedo_color
	var lab := plate.get_node_or_null("Pct") as Label3D
	_check(fut.collapses == c0 + 1 and plate.has_meta("resolved"),
		"薛定谔块 %s：踩之前是灰紫（%.2f,%.2f,%.2f），踩到后**坍缩一次**（累计 %d 次）"
		% [plate.name, before.r, before.g, before.b, fut.collapses])
	_check((after.r > after.g and after.r > after.b) or (after.g > after.r and after.g > after.b),
		"坍缩结果一定是**红或绿**（实测 %.2f,%.2f,%.2f），不会是灰紫"
		% [after.r, after.g, after.b])
	_check(lab != null and (lab.text.begins_with("+") or lab.text.begins_with("-")),
		"坍缩后牌子写上真实涨跌幅：「%s」" % (lab.text if lab != null else "（没有牌子）"))
	# 钱要真的动：牌子上写多少，保证金就按多少结（+2.31% ⇒ ×1.0231，−3.87% ⇒ ×0.9613）
	var pct := fut._parse_pct(lab.text)
	var want := m_before * (1.0 + pct / 100.0)
	_check(not is_nan(pct) and absf(fut.margin - want) < 0.02 and fut.settlements >= 1,
		"踩上 %s（%s）→ **保证金真的结算**：¥%.2f → ¥%.2f 万（期望 ¥%.2f，结算过 %d 块）"
		% [plate.name, lab.text, m_before, fut.margin, want, fut.settlements])
	_check(not (await _schro_resolves_again(fut)), "同一个薛定谔块**只坍缩一次**")
	fut.blue_live = 3.0
	_pk.enabled = true
	_release_all()


## ── 5d. 第 4 段「比特币三线」 ────────────────────────────────────────────────
## 用户要的是「不是纯看操作了，而是要动脑子、决策路线」，所以这一节验的是**决策本身**：
## 三道收益算得出来、跨道跳不过去、牌价真的会跳、踩上去那一刻的价格才作数、
## 钱够不够决定强平是「扣钱」还是「爆仓」。
func _test_branch() -> void:
	print("\n========== 5d. 第 4 段：比特币三线（三条路 / 跳价 / 对冲）==========")
	var fut := _futures()
	if fut == null:
		_check(false, "找到 Futures 总控")
		return
	fut.blue_live = 0.0            # 这一节不要蓝块来捣乱
	_pk.enabled = false
	_release_all()

	var prefixes := ["SP", "PP", "BC"]
	var lanes: Array = [[], [], []]
	for li in 3:
		for i in range(1, 4):
			var n := _pk.get_node_or_null("Route/%s%d" % [prefixes[li], i]) as Node3D
			if n != null:
				lanes[li].append(n)
	var total: int = lanes[0].size() + lanes[1].size() + lanes[2].size()
	_check(total == 9, "三条道各有 3 块板（实测 %d 块）" % total)
	if total == 9:
		# 全速起跳的射程（`hop_analysis` 那套：跑速 × 滞空时间 × 实测系数）
		var flat := Player.SPEED_RUN * 2.0 * Player.JUMP_VELOCITY / Player.GRAVITY * 1.054
		var a1 := fut._aabb_of(lanes[0][0])
		var b1 := fut._aabb_of(lanes[1][0])
		var c1 := fut._aabb_of(lanes[2][0])
		var ab: float = a1.position.z - (b1.position.z + b1.size.z)
		var bc: float = b1.position.z - (c1.position.z + c1.size.z)
		_check(ab > flat and bc > flat,
			"跨道缺口 A|B %.2f m、B|C %.2f m 都 > 平地直跳 %.2f m（横着跨不过去，只能选一条）"
			% [ab, bc, flat])

	# 牌价规则三个样：现货一档（永不跳）/ 永续两档 / 币圈四档
	var steps := {"A": 0, "B": 0, "C": 0}
	for q in fut.quotes:
		var lane := String((q["node"] as Node3D).get_meta("lane", "?"))
		if steps.has(lane):
			steps[lane] = maxi(int(steps[lane]), (q["seq"] as Array).size())
	_check(steps["A"] == 1 and steps["B"] == 2 and steps["C"] == 4,
		"牌价规则三种样：现货 %d 档 / 永续 %d 档 / 币圈 %d 档"
		% [steps["A"], steps["B"], steps["C"]])

	# ④ 现货：+3.00% 固定 → 踩上去就是 ×1.03（一分不差）
	var sp2 := _pk.get_node_or_null("Route/SP2") as Node3D
	var bsp2 := fut._aabb_of(sp2)
	fut.margin = 10.0
	fut.settled.erase("SP2")
	_put(bsp2.position.x + bsp2.size.x * 0.5, bsp2.position.y + bsp2.size.y + 0.05,
		bsp2.position.z + bsp2.size.z * 0.5)
	await _wait(6)
	_check(absf(fut.margin - 10.3) < 0.005,
		"现货道 SP2（+3.00%% 固定）→ 10.0000 → %.4f 万（×1.03）" % fut.margin)

	# ⑤ 币圈：牌子在四档之间轮转，**踩上去那一刻是哪一档就按哪一档结算**
	var q := _quote_of(fut, "BC1")
	if q.is_empty():
		_check(false, "找到币圈道 BC1 的跳价牌")
	else:
		var node := q["node"] as Node3D
		var period := float(q["period"])
		var phase := float(q["phase"])
		var slot := period / float((q["seq"] as Array).size())
		fut._t = period * 0.75 - phase + slot * 0.25   # 拨到最后一档（四档里最高的那档）
		fut.margin = 10.0
		fut.settled.erase("BC1")
		var bb := fut._aabb_of(node)
		_put(bb.position.x + bb.size.x * 0.5, bb.position.y + bb.size.y + 0.05,
			bb.position.z + bb.size.z * 0.5)
		await _wait(4)
		var lab := node.get_node_or_null("Pct") as Label3D
		var txt := lab.text if lab != null else "?"
		# 最高档的数值从 `seq` 里取（用户会调杠杆：写死 +9 的话一调就红）
		var hi := -999.0
		for v in (q["seq"] as Array):
			hi = maxf(hi, float(v))
		_check(absf(fut._parse_pct(txt) - hi) < 0.01,
			"币圈道 BC1 的牌子拨到高档：%s（seq 最高档 %+.2f%%）" % [txt, hi])
		_check(absf(fut.margin - 10.0 * (1.0 + hi / 100.0)) < 0.02,
			"踩上高档 → 10.0000 → %.4f 万（**踩的是那一刻的价格**，不是平均价）" % fut.margin)

	# ⑥ 结算台：保证金 ≥ 11 万 → 解锁「对冲」；之后强平只扣 35%，不爆仓、不送回
	var mb := fut._box_named("M0")
	var mcx := mb.position.x + mb.size.x * 0.5
	var mcy := mb.position.y + mb.size.y + 0.05
	var mcz := mb.position.z + mb.size.z * 0.5
	fut.margin = 12.0
	fut.hedged = false
	fut._hedge_checked = false
	_put(mcx, mcy, mcz)
	await _wait(6)
	_check(fut.hedged, "保证金 12.00 万站上结算台 M0 → **解锁对冲**（门槛 %.0f 万）"
		% fut.hedge_target)
	var before := fut.margin
	var liq := fut.liquidations
	var p_before := _p.global_position
	fut._cool = 0.0
	fut.liquidate()
	await _wait(3)
	_check(fut.liquidations == liq + 1
		and absf(fut.margin - before * (1.0 - fut.hedge_cut)) < 0.01,
		"对冲生效：强平一次只扣 %.0f%%（%.2f → %.2f 万）"
		% [fut.hedge_cut * 100.0, before, fut.margin])
	_check(_p.global_position.distance_to(p_before) < 0.5,
		"对冲生效时人**留在原地**（不爆仓、不送回检查点）")

	# ⑦ 保证金不够 → 不解锁；这时强平照旧爆仓（这才是「选哪条道」的代价）
	fut.margin = 10.5
	fut.hedged = false
	fut._hedge_checked = false
	_put(mcx, mcy, mcz)
	await _wait(6)
	_check(not fut.hedged, "保证金 10.50 万 < 阈值 → **没有**解锁对冲（现货道注定够不着）")
	fut._cool = 0.0
	fut.liquidate()
	# ⚠️ **当场**取数：无头模式一帧可能 0.4 s，等两帧就过了 0.9 s 的「重新开仓」tween
	var m_zero := fut.margin
	await _wait(2)
	_check(absf(m_zero) < 0.001, "未解锁时强平 = 爆仓，保证金归零（%.4f 万）" % m_zero)
	# 复位，别把状态留给后面的小节
	fut.hedged = false
	fut._hedge_checked = false
	fut.margin = fut.start_margin
	fut.debt = 0
	fut.liquidations = 0

	# ⑧ 三道各有一台**沿 x 走的渡船** —— 不是照抄段 3 的「上下 / 左右」船
	var ferries := 0
	var fastest := 0.0
	var bc_ferry: ParkourDrift = null
	for d in fut.drifts:
		if not String(d.name).begins_with("Ferry_"):
			continue
		ferries += 1
		fastest = maxf(fastest, d.speed)
		if String(d.name) == "Ferry_BC2":
			bc_ferry = d
	_check(ferries == 3, "三道各一台渡船（实测 %d 台，全部沿 x 走）" % ferries)
	if bc_ferry == null:
		_check(false, "找到币圈道的渡船 Ferry_BC2")
	else:
		var travel := bc_ferry.point_a.distance_to(bc_ferry.point_b)
		_check(travel > 2.0 and bc_ferry.speed >= fastest and bc_ferry.wait_time <= 1.0,
			"币圈道的船最快（%.1f m/s）、行程 %.2f m、到岸只停 %.1f s（不等你就被带回去）"
			% [bc_ferry.speed, travel, bc_ferry.wait_time])

	# ⑨ 不在 `route` 里的板（永续道）**不算检查点** —— 掉下去回分叉台，正是选路线的代价
	var pp2 := _pk.get_node_or_null("Route/PP2") as Node3D
	var bpp2 := fut._aabb_of(pp2)
	_pk.enabled = true
	_pk.reset_run()
	_put(bpp2.position.x + bpp2.size.x * 0.5, bpp2.position.y + bpp2.size.y + 0.05,
		bpp2.position.z + bpp2.size.z * 0.5)
	await _wait(6)
	_check(_pk.checkpoint == -1,
		"站在永续道 PP2 上不算检查点（checkpoint = %d）—— 掉下去回分叉台" % _pk.checkpoint)
	_pk.enabled = true
	_release_all()
	fut.blue_live = 3.0


## ── 5f. 第 8 段「暗网黑市交易」：比纳（延迟加载 / 激光 / 炮弹 / 不会复活）───────
## 用户要的是「跑酷同时击败 boss，这个 boss 不会复活」，2026-10-19 又补了四条：
## 「比纳不能一开始就加载，得进入黑市才加载」「血条增加 3 倍」
## 「死亡后不要一直残留空血条」「名字就叫比纳，不要后缀」。
## 所以这一节验五件事：开场不在 / 过闸门才出现 / 两套火力 / 打得死 / 死了不站起来且血条收起。
func _test_dark_boss() -> void:
	print("
========== 5f. 暗网黑市：比纳（延迟加载 / 激光 / 炮弹 / 不会复活）==========")
	# ① 开场**不该有**比纳：模型（44 骨 FBX）+ 12 个凹包碰撞很贵，用户要求进黑市才加载
	_check(_pk.get_node_or_null("Route/DarkBoss") == null,
		"开场时比纳**没有加载**（Route 下找不到 DarkBoss）")
	var gate := _pk.get_node_or_null("Route/DarkGate") as DarkGate
	_check(gate != null, "黑市入口摆的是**空闸门** DarkGate（没有网格、没有碰撞）")
	if gate == null:
		return
	_pk.enabled = false
	_release_all()
	# ② 站在闸门**东边**（还没进黑市）→ 它不该被喊出来
	_put(gate.global_position.x + 6.0, gate.global_position.y + 1.20,
		gate.global_position.z)
	gate.set_physics_process(true)
	await _wait(8)
	_check(_pk.get_node_or_null("Route/DarkBoss") == null,
		"在闸门东边 6 m 站着，比纳仍然不加载（闸门按 x 触发）")
	# ③ 跨过闸门 → 现场生成
	_put(gate.global_position.x - 1.00, gate.global_position.y + 1.20,
		gate.global_position.z)
	await _wait(10)
	var db := _pk.get_node_or_null("Route/DarkBoss") as DarkBoss
	_check(db != null and gate.spawned(), "跑进黑市（x ≤ %.2f）→ 比纳才被 instantiate"
		% gate.trigger_x)
	if db == null:
		_pk.enabled = true
		return
	_check(absf(db.max_health - 2200.0) < 0.1,
		"血量 %.0f（900 → ×3 的 2700 → 用户嫌肉，削到 2200）" % db.max_health)
	_check(db.display_name == "比纳", "名字就叫「%s」，没有后缀" % db.display_name)
	var hud := _p.get_parent().get_node_or_null("HUD")
	if hud != null and hud.has_method("boss_row_shown"):
		_check(hud.boss_row_shown("比纳"),
			"HUD 上补出了「比纳」那条血条（中途加载也能接上）")
	db.set_physics_process(true)
	# ⑤ 用户 2026-10-19：「如果比纳没打完，也会追过来的」——
	#    把它丢到 90 m 外、玩家站进**内存条市场**（第 9 段），看它是不是照样飞过来。
	#    追击**不看距离**，只有开火才看 `engage_range`（见 dark_boss.gd）。
	db.global_position = Vector3(-320.0, db.global_position.y, -1.7)
	_put(-416.50, 2.05, -8.10)
	await _wait(4)
	var d0 := db.global_position.distance_to(_p.global_position)
	await _wait_ms(1200)
	var d1 := db.global_position.distance_to(_p.global_position)
	_check(d1 < d0 - 3.0,
		"玩家跑进内存条市场（x = −416），比纳照样追：%.1f → %.1f m（−%.1f）"
		% [d0, d1, d0 - d1])
	# 站到 DK5 上（比纳出场就在这一带上方，正好进交战距离）
	db.global_position = Vector3(-374.00, 12.00, -1.70)
	var dk := _pk.get_node_or_null("Route/DK5") as Node3D
	var b := _dark_box(dk)
	_put(b.position.x + b.size.x * 0.5, b.position.y + b.size.y + 0.05,
		b.position.z + b.size.z * 0.5)
	await _wait(4)
	# ⚠️ 比纳是**刚刚**才生成的，激光相位早已跑过好几轮；只重置 `_t_laser` 不够，
	#    必须把 `_laser_state` / `_laser_timer` 一起归零，否则采样时可能刚好在束线熄灭的
	#    那 2.8 s 空档里（无头模式一帧比一帧快，`_wait_ms` 是**真实时间**，
	#    模拟时间早就跑出去老远 —— 第一次改完就是这样假红的）。
	db.set_physics_process(false)
	db._laser_state = 0
	db._laser_timer = 0.0
	db._t_laser = 0.05
	db._t_shell = 0.05
	await _wait(2)
	db.set_physics_process(true)
	var beam := db.get_node_or_null("LaserBeam") as MeshInstance3D
	# 逐帧等两件事出现，而不是等固定时长后碰运气：
	#   ① 激光的**预警**段（`_laser_state == 1`，只存在 0.6 s）
	#   ② 炮弹累计发射数 ≥ 1（`_t_shell = 0.05` → 三帧内打出第一发；
	#      上一版跟激光一起等 700 ms，结果激光先亮、炮弹还没出膛就判了红）
	var saw_warn := false
	var t_laser := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_laser < 1500:
		await process_frame
		if beam != null and db._laser_state == 1 and beam.visible:
			saw_warn = true
		if saw_warn and db.shots_fired() >= 1:
			break
	_check(saw_warn, "激光先出**预警**细束（0.6 s 后才实体）")
	# ⚠️ 别查「在飞几发」：炮弹 20 m/s，0.4 s 就打到人，采样时常常刚好 0 发。
	#    查**累计发射数**才稳。
	_check(db.shots_fired() >= 1, "炮弹真的打出来了（累计 %d 发，同时最多在飞 %d 发）"
		% [db.shots_fired(), db.shell_count()])
	var hp0 := db.health
	db.take_damage(120.0)
	_check(db.health < hp0, "被打掉血：%.0f → %.0f（打光 %.0f 就倒）"
		% [hp0, db.health, db.max_health])
	db.take_damage(100000.0)
	await _wait_ms(300)
	_check(db.killed(), "血量清零 → 倒下")
	# ④ 用户：「死亡后不要一直残留空血条」→ 名字行 + 血条一起收起
	if hud != null and hud.has_method("boss_row_shown"):
		_check(not hud.boss_row_shown("比纳"),
			"倒下后「比纳」那行血条**收了**（不再留一条空条）")
	await _wait_ms(1500)
	_check(db.killed() and db.health <= 0.0,
		"**不会复活**（等 1.5 s 仍是倒下、血量 %.0f）—— 父类默认 6 s 会站起来" % db.health)
	# ⑥ 用户 2026-10-19：「比纳死后过一段时间消失」—— 躺 5 s → 淡出 → 删节点
	var vd := db.vanish_delay
	var vt := db.vanish_time
	var t_v := Time.get_ticks_msec()
	while is_instance_valid(db) and Time.get_ticks_msec() - t_v < 14000:
		await _wait_ms(100)
	var waited := float(Time.get_ticks_msec() - t_v) / 1000.0 + 1.5
	_check(not is_instance_valid(db),
		"倒下约 %.1f s 后**尸体消失**（Route/DarkBoss 已经不存在；延迟 %.1f s + 淡出 %.1f s）"
		% [waited, vd, vt])
	if is_instance_valid(db):
		db.set_physics_process(false)
	_pk.enabled = true
	_release_all()


## ── 5g. 第 9~10 段「内存条市场」：装饰 / 天空盒 / 天降内存条 ─────────────────
## 用户 2026-10-19：「后面横跳区/螺旋塔全改成内存条区域……一边跑一边躲从天空掉下来的
## 内存条」「说到天空我想起来该加天空盒了」。
func _test_ram_market() -> void:
	print("\n========== 5g. 内存条市场（装饰 / 天空盒 / 天降内存条）==========")
	var game := _p.get_parent()
	# ① 天空盒：全景贴图真的挂上去了，而且雾没有把它糊平
	var we := game.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var env: Environment = we.environment if we != null else null
	var pano: Texture2D = null
	if env != null and env.sky != null and env.sky.sky_material is PanoramaSkyMaterial:
		pano = (env.sky.sky_material as PanoramaSkyMaterial).panorama
	_check(pano != null and pano.get_width() >= 2048,
		"天空盒是**全景贴图**：%s（%d×%d）"
		% [pano.resource_path if pano else "没挂", pano.get_width() if pano else -1,
			pano.get_height() if pano else -1])
	_check(env != null and env.fog_sky_affect < 0.01,
		"雾不糊天空（`fog_sky_affect` = %.2f，默认 1.0 会把全景糊成一片灰）"
		% (env.fog_sky_affect if env != null else -1.0))
	# ② 装饰：一百多根内存条 + 两个 MultiMesh（两个 surface 各一个 draw call）
	var ram := _pk.get_node_or_null("RamMarket") as RamMarket
	_check(ram != null, "第 9~10 段有 `RamMarket` 节点（装饰 + 内存条雨）")
	if ram == null:
		return
	_check(ram.stick_count() >= 100,
		"装饰内存条 **%d 根**（平台插槽 2 根/板 + 头顶吊架 5 根/串 + 塔身鳍片 3 根/层）"
		% ram.stick_count())
	var batches := 0
	for c in ram.get_children():
		if c is MultiMeshInstance3D:
			batches += 1
	_check(batches == 2, "两个 surface 各一个 MultiMeshInstance3D（%d 个 draw call 画完全场）"
		% batches)
	# ③ 内存条雨：站到 X3 上，打开开关，看它真的往下掉
	_pk.enabled = false
	_release_all()
	var x3 := _pk.get_node_or_null("Route/X3") as Node3D
	var b := _dark_box(x3)
	_put(b.position.x + b.size.x * 0.5, b.position.y + b.size.y + 0.05,
		b.position.z + b.size.z * 0.5)
	var before := ram.drops_spawned()
	ram.rain_enabled = true
	await _wait_ms(2200)
	_check(ram.drops_spawned() > before,
		"头顶真的在掉内存条（%.1f s 内 %d → %d 根）"
		% [2.2, before, ram.drops_spawned()])
	# ④ 命中：直接朝玩家头顶砸一根（落点圈 0.6 s 预警 + 20 m 自由落体）
	var hp0 := _p.health
	ram.force_drop_now()
	var t_drop := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_drop < 3000 and _p.health >= hp0:
		await process_frame
	_check(_p.health < hp0, "被砸中掉血 %.0f → %.0f（累计命中 %d 次）"
		% [hp0, _p.health, ram.drops_hit()])
	# ⑤ 出了范围就停雨（第 8 段暗网那边不该有内存条砸下来）
	_put(-370.00, 3.00, -1.70)
	# ⚠️ 先等在飞的落点圈走完（预警 0.6 s）再采样：离开那一刻已经亮起的圈会照常
	#    砸下来，立刻采样的话 1.5 s 内会多出一根，看起来像「范围外还在下雨」。
	await _wait_ms(1200)
	var before2 := ram.drops_spawned()
	await _wait_ms(1500)
	_check(ram.drops_spawned() == before2,
		"走出范围（x > %.0f 东侧）就停雨（%d → %d 根）"
		% [ram.rain_x_max, before2, ram.drops_spawned()])
	ram.rain_enabled = false
	_pk.enabled = true
	_release_all()


## ── 5h. 地上的内存条：规格 / 估价 / 拾取 → 资产 ──────────────────────────────
## 用户 2026-10-20：「内存条是可拾取的，每次捡到内存条，随机是 ddr3/ddr4/ddr5，
## 容量随机 2/4/8/16/32/64G……每次随机是 ECC 服务器条、非 ECC 台式条。捡到的
## 内存条换算成为资产，价格行情自己查网络。天上掉下来的内存条不算，只有躺在地上
## 的可以捡」；第二轮「这些看见的都要可以捡，但是不要刷新了，价格应该不对，频率也加上」。
func _test_ram_loot() -> void:
	print("\n========== 5h. 内存条（可拾取 → 资产）==========")
	# ① 规格空间：11 个（代, 频率）× 6 容量 × 2（ECC/非ECC）= 132
	_check(RamSpec.combo_count() == 132,
		"规格空间 = (DDR3 3 档 + DDR4 4 档 + DDR5 4 档) × 6 容量 × 2 = **%d 种**"
		% RamSpec.combo_count())
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261020
	var seen := {}
	for _i in 20000:
		var sp := RamSpec.roll(rng)
		seen[RamSpec.describe(sp, true)] = true
	_check(seen.size() == 132, "20000 次抽取把 132 种全抽到了（%d/132）" % seen.size())
	# ② 估价：容量越大越贵、ECC 比非 ECC 贵、同容量下频率越高越贵
	var mono := true
	var freq_ok := true
	for ddr in RamSpec.DDRS:
		for freq in RamSpec.FREQS[ddr]:
			var last := 0
			for gb in RamSpec.SIZES:
				var pc := RamSpec.price_yuan({"ddr": ddr, "freq": freq, "gb": gb, "ecc": false})
				var ec := RamSpec.price_yuan({"ddr": ddr, "freq": freq, "gb": gb, "ecc": true})
				if pc <= last or ec <= pc:
					mono = false
				last = pc
		var prev := 0
		for freq in RamSpec.FREQS[ddr]:
			var v := RamSpec.price_yuan({"ddr": ddr, "freq": freq, "gb": 16, "ecc": false})
			if v <= prev:
				freq_ok = false
			prev = v
	_check(mono, "每代每频都是「容量越大越贵、ECC 比非 ECC 贵」")
	_check(freq_ok, "同代同容量下频率越高越贵（DDR3 1333 < 1600 < 1866；DDR5 4800 < 5600 < 6400 < 7200）")
	var top := RamSpec.price_yuan({"ddr": "DDR5", "freq": 7200, "gb": 64, "ecc": true})
	var low := RamSpec.price_yuan({"ddr": "DDR3", "freq": 1333, "gb": 2, "ecc": false})
	_check(top >= 22000 and low <= 20,
		"价格跨度 ¥%d（DDR3 1333 2G 非ECC）~ ¥%d（DDR5 7200 64G ECC）" % [low, top])
	# 用户 2026-10-20 拿实际成交价逐项核对后的**锚点**（这一条以前把 DDR3 报高了 2~5 倍）
	var d3_8 := RamSpec.price_yuan({"ddr": "DDR3", "freq": 1600, "gb": 8, "ecc": false})
	var d3_4 := RamSpec.price_yuan({"ddr": "DDR3", "freq": 1600, "gb": 4, "ecc": false})
	_check(d3_8 == 70 and d3_4 == 20,
		"DDR3 1600 8G = ¥%d、4G = ¥%d（用户实测：8G 70 / 4G 20，网上常组 4×4 代替 8×2）"
		% [d3_8, d3_4])
	var d5_16 := RamSpec.price_yuan({"ddr": "DDR5", "freq": 5600, "gb": 16, "ecc": false})
	var d4_16 := RamSpec.price_yuan({"ddr": "DDR4", "freq": 2666, "gb": 16, "ecc": false})
	_check(d5_16 >= 1200 and d5_16 <= 1800 and d4_16 >= 389 and d4_16 <= 759,
		"贴着 2026-10 行情：DDR5 5600 16G ¥%d（1200~1800）、DDR4 2666 16G ¥%d（389~759）"
		% [d5_16, d4_16])
	# DDR5 64G：**消费级与 ECC 是两个世界**（这是上一版最大的坑：上限 11480 连 ECC 下限的 62% 都不到）
	var d5_64 := RamSpec.price_yuan({"ddr": "DDR5", "freq": 5600, "gb": 64, "ecc": false})
	var d5_64e := RamSpec.price_yuan({"ddr": "DDR5", "freq": 5600, "gb": 64, "ecc": true})
	_check(absf(d5_64 - 8000) <= 100,
		"DDR5 5600 64G 消费级 ¥%d（威刚实付 7994）" % d5_64)
	_check(d5_64e >= 18500 and d5_64e <= 19200,
		"DDR5 5600 64G **ECC RDIMM** ¥%d（公开标价 18595~18999）" % d5_64e)
	# ③ 第 9 / 10 段的起点牌（用户 2026-10-20：「第九段内存条的提示怎么没显示」——
	#    生成器只给第 3~8 段立了桅杆，这两段一直没有起点牌，运行时补的）
	var ram := _pk.get_node_or_null("RamMarket") as RamMarket
	_check(ram != null, "有 `RamMarket` 节点")
	if ram == null:
		return
	var sign9 := ram.get_node_or_null("SegSign_S8") as Label3D
	var sign10 := ram.get_node_or_null("SegSign_S9") as Label3D
	_check(sign9 != null and sign9.text.contains("地上") and sign9.text.contains("天上掉的不算")
		and sign9.text.contains("频率"),
		"第 9 段起点提示牌：%s"
		% (sign9.text.replace("\n", " / ") if sign9 != null else "没有"))
	_check(sign10 != null, "第 10 段起点牌：%s"
		% (sign10.text if sign10 != null else "没有"))
	# ④ 看见的都能捡：地上 16 + 台边插的 26 + 塔身鳍片 21，全部贴着台面
	var n_pick := ram.pickable_count()
	_check(n_pick >= 50, "可拾取 **%d 根**（地上 %d + 台边/鳍片 %d；头顶吊架够不着，不算）"
		% [n_pick, ram.ground_count(), ram.decor_count()])
	var tops: Array[float] = []
	for i in range(_pk.segment_start(8), _pk.segment_start(10)):
		var bb := _pk.box_at(i)
		if bb.size.x >= 0.4:
			tops.append(_pk.top_at(i))
	var lying := 0
	var worst := 0.0
	for p in ram.pickable_positions():
		var best := 99.0
		for t in tops:
			best = minf(best, absf(p.y - t))
		worst = maxf(worst, best)
		if best <= 0.35:
			lying += 1
	_check(lying == n_pick and n_pick > 0,
		"每一根都贴着台面（离台面最远 %.2f m，容差 0.35 m）" % worst)
	# ⑤ 捡地上的一根：资产 += 这一根的价格，节点消失
	var fut := _pk.get_node_or_null("Futures") as ParkourFutures
	_check(fut != null, "有 `Futures`（资产账户）")
	if fut == null:
		return
	fut.assets_yuan = 0
	fut.ram_count = 0
	fut.ram_inventory.clear()
	ram.loot_enabled = true
	_pk.enabled = false
	var at: Vector3 = ram.pickable_positions()[0]
	var before_n := ram.pickable_count()
	_put(at.x, at.y + 0.02, at.z)
	await _wait_ms(180)
	var rec := ram.last_picked()
	var sp2: Dictionary = rec.get("spec", {})
	var price := int(rec.get("price", -1))
	_check(ram.pickable_count() == before_n - 1 and ram.loot_picked_count() >= 1,
		"站上去就捡走（可捡 %d → %d 根）" % [before_n, ram.pickable_count()])
	_check(price > 0 and fut.assets_yuan == price and fut.ram_count == 1,
		"捡到 %s → 资产 +¥%d（合计 ¥%d・%d 根）" % [
			RamSpec.describe(sp2), price, fut.assets_yuan, fut.ram_count])
	# ⑥ 插在台边的也能捡（用户：「这些看见的都要可以捡」）
	var before_decor := ram.decor_count()
	var before_assets := fut.assets_yuan
	var dpos: Vector3 = ram.decor_positions()[0]
	_put(dpos.x, dpos.y + 0.02, dpos.z)
	await _wait_ms(200)
	var rec2 := ram.last_picked()
	var price2 := int(rec2.get("price", -1))
	_check(ram.decor_count() == before_decor - 1 and fut.assets_yuan == before_assets + price2,
		"台边插的 %s 也能捡（资产 +¥%d，插着的剩 %d 根）"
		% [RamSpec.describe(rec2.get("spec", {})), price2, ram.decor_count()])
	# ⑦ HUD：三本账在同一行
	var hud := fut.get_node_or_null("FuturesHUD/Debt") as Label
	_check(hud != null and hud.text.contains("资产") and hud.text.contains("保证金")
		and hud.text.contains("负债"),
		"HUD 一行三本账：%s" % (hud.text if hud != null else "没有 HUD"))
	# ⑧ 天上掉下来的**不算**：砸一根下来，资产一分不涨
	var assets_before_drop := fut.assets_yuan
	var count_before_drop := fut.ram_count
	ram.force_drop_now()
	await _wait_ms(2600)
	_check(fut.assets_yuan == assets_before_drop and fut.ram_count == count_before_drop,
		"天降内存条砸下来也**不进资产**（¥%d / %d 根 没变）"
		% [fut.assets_yuan, fut.ram_count])
	# ⑨ 不刷新：等 8 s（老版本 7 s 补一根），根数一根都不许多
	var n_before := ram.pickable_count()
	await _wait_ms(8000)
	_check(ram.pickable_count() == n_before,
		"捡走之后**不补货**（等 8 s，可捡 %d → %d 根）" % [n_before, ram.pickable_count()])
	# ⑩ 最后平台房顶的 RTX 5090（用户 2026-10-20：「房子上面放一个 5090……也是加入
	#    资产的，全新正版现价 59999」）。它挂在 `Island/Props/Shed` 下，￥59999。
	var gpu := _pk.get_node_or_null("Island/Props/Shed/RTX5090") as Rtx5090
	_check(gpu != null and gpu.price() == 59999,
		"最后平台的房顶上有 **RTX 5090**（¥%d）" % (gpu.price() if gpu != null else -1))
	if gpu != null:
		var a0 := fut.assets_yuan
		var gp := gpu.global_position
		_put(gp.x + 2.2, gp.y - 2.5, gp.z)
		await _wait_ms(160)
		var prompt := fut.get_node_or_null("FuturesHUD/Prompt") as Label
		_check(prompt != null and prompt.text.contains("按 F 拾取"),
			"靠近 5090 → 提示「按 F 拾取」（实测：%s）"
			% (prompt.text if prompt != null else "没有提示"))
		await _press_key(KEY_F)
		_check(prompt != null and prompt.text.contains("真的要拾取吗"),
			"第一次 F → 弹确认「真的要拾取吗？」")
		await _press_key(KEY_F)
		await _wait_ms(900)          # 牢笼落地 0.45 s + 0.2 s 才轮到 Boss 出场
		_check(fut.assets_yuan == a0 + 59999,
			"第二次 F 确认 → 资产 +¥59,999（合计 ¥%d）" % fut.assets_yuan)
		var game := _pk.get_parent()
		_check(game.get_node_or_null("TrapCage") != null,
			"确认后牢笼从信号塔顶滑下来罩住传送台（TrapCage）")
		var squash: Node = null
		for c in game.get_children():
			if c is Boss and String(c.name).to_lower().contains("squash"):
				squash = c
		_check(squash != null, "牢笼落地后 **倭瓜优香** 登场（BossSquash）")
	# ⑪ 结算区：站进小屋 → 资产+保证金进银行卡、自动还债
	fut.assets_yuan = 1234
	fut.margin = 5.0
	fut.debt = 2
	var sp := _pk.get_node_or_null("Island/Props/Shed/Settlement") as SettlementPad
	_check(sp != null, "小屋里有结算台（Settlement）")
	if sp != null:
		_put(sp.global_position.x, sp.global_position.y, sp.global_position.z)
		await _wait_ms(300)
		_check(fut.assets_yuan == 0 and fut.margin == 0.0 and fut.bank_yuan > 0,
			"资产+保证金 → 银行卡 ¥%d" % fut.bank_yuan)
		_check(fut.debt == 0,
			"银行卡够还债 → 负债清零（剩 ¥%d）" % fut.bank_yuan)
	ram.loot_enabled = false
	ram.rain_enabled = false
	_pk.enabled = true
	_release_all()


## 这个节点是不是「纯装饰」：内存条市场（PCB 面 / 金手指 / 桁架 / MultiMesh）和
## 跑酷准备区的金色垫子。它们只负责好看、不参与跳跃判定，位置按台面微调
## （+1 mm / +8 mm 之类）就必然不在 0.05 m 网格上 —— 不查它们。
func _inside_decor(n: Node) -> bool:
	var cur := n
	for _i in 8:
		cur = cur.get_parent()
		if cur == null:
			return false
		var nm := String(cur.name)
		if nm == "RamMarket" or nm == "ReadyZone" or nm == "RTX5090":
			return true
	return false


## 非路线站的包围盒（DK5 在 route 里，这里给个通用小工具）
## 这个节点是不是挂在某位 Boss 底下（Boss 的 FBX 模型坐标是原样的，不查网格）
func _inside_boss(n: Node) -> bool:
	var cur := n
	for _i in 10:
		cur = cur.get_parent()
		if cur == null:
			return false
		if cur is Boss:
			return true
	return false


func _dark_box(n: Node3D) -> AABB:
	if n == null:
		return AABB()
	var col := n.get_node_or_null("Col") as CollisionShape3D
	if col != null and col.shape is BoxShape3D:
		var s: Vector3 = (col.shape as BoxShape3D).size
		return col.global_transform * AABB(-s * 0.5, s)
	return AABB()


## 按节点名找一条跳价牌（`quotes` 的顺序是场景遍历顺序，别拿下标猜）
func _quote_of(fut: ParkourFutures, nm: String) -> Dictionary:
	for q in fut.quotes:
		if String((q["node"] as Node3D).name) == nm:
			return q
	return {}


## 蓝块当前是不是「实体」段（和 `parkour_futures._tick_hazards` 同一套相位）
func _hazard_live(fut: ParkourFutures, h: Node3D) -> bool:
	var phase := fmod(fut._t + float(h.get_meta("offset")), fut.blue_period)
	return phase >= fut.blue_period - fut.blue_live


func _schro_resolves_again(fut: ParkourFutures) -> bool:
	var c := fut.collapses
	await _wait(4)
	return fut.collapses != c


## 坐一块会动的板：站上去 → 等它走到另一端 → 走向目标板 → 检查真的落上去了。
func _ride_drift(fut: ParkourFutures, mode: int, _from_i: int, to_i: int,
		what: String, want := "") -> Dictionary:
	var d: ParkourDrift = null
	for cand in fut.drifts:
		# `want`：同一种运动有好几台时按节点名挑（第 4 段三道各一台）
		if cand.mode == mode and (want == "" or String(cand.name).contains(want)):
			d = cand
			break           # ⚠️ 必须 break：不 break 会拿到**最后一台**同模式的车
	if d == null:
		return {"ok": false, "why": "没有这种会动的块"}
	_pk.enabled = false
	_release_all()
	d.force_progress(0.0, 3.0)
	await _wait(2)
	_put(d.global_position.x, d.global_position.y + 0.25, d.global_position.z)
	await _wait(5)
	var t0 := Time.get_ticks_msec()
	var arrived := false
	while Time.get_ticks_msec() - t0 < 14000:
		await process_frame
		if d.progress() > 0.99:
			arrived = true
			break
	if not arrived:
		_pk.enabled = true
		return {"ok": false, "why": "%s 14 s 内没走到另一端" % what}
	var b := _pk.box_at(to_i)
	var c := b.position + b.size * 0.5
	# ⚠️ 到岸之后**必须跳**：会动的块和对岸之间还隔着 1.8 m 的空隙，走过去会直接掉进缝里
	#    （第一版就是这么掉到 y = −33 的）。按住 W 加速，走到离块心 1.30 m（≈块边）时起跳。
	_aim(Vector2(c.x - _p.global_position.x, c.z - _p.global_position.z))
	Input.action_press("move_forward")
	var t1 := Time.get_ticks_msec()
	var jumped := false
	var landed := false
	while Time.get_ticks_msec() - t1 < 3000:
		await process_frame
		var pp := _p.global_position
		var to_center := Vector2(pp.x - d.global_position.x, pp.z - d.global_position.z)
		if not jumped and to_center.length() > 1.30:
			await _jump()
			jumped = true
		elif jumped and _p.is_on_floor() and _inside_box(pp, b):
			landed = true
			break
	if landed:
		# 走到板心再交给下一跳：连续通关里下一跳是「从板心助跑」的，
		# 落在板边会被 `_exit_dist` 判成「没有助跑距离」，跳出去直接掉下去
		_aim(Vector2(c.x - _p.global_position.x, c.z - _p.global_position.z))
		Input.action_press("move_forward")
		await _wait_ms(450)
	_release_all()
	await _wait(4)
	var pos := _p.global_position
	var ok := landed and _p.is_on_floor() and absf(pos.y - _pk.top_at(to_i)) < 0.45 \
		and pos.x > b.position.x - 0.45 and pos.x < b.position.x + b.size.x + 0.45 \
		and pos.z > b.position.z - 0.45 and pos.z < b.position.z + b.size.z + 0.45
	_pk.enabled = true
	return {"ok": ok, "why": "ok" if ok else "落在 %.2f,%.2f y=%.2f（台面 %.2f，on_floor=%s，跳了=%s）"
		% [pos.x, pos.z, pos.y, _pk.top_at(to_i), str(_p.is_on_floor()), str(jumped)]}


## 人是不是站在这个盒子的 footprint 里（只看 xz）
func _inside_box(p: Vector3, b: AABB) -> bool:
	return p.x > b.position.x and p.x < b.position.x + b.size.x \
		and p.z > b.position.z and p.z < b.position.z + b.size.z



## 按名字找站号
func _idx(label: String) -> int:
	for i in _pk.node_count():
		if _pk.label_at(i) == label:
			return i
	return -1


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
		{"station": 24, "seg": 2, "what": "第 3 段中段（K5 大阳线）"},
		{"station": 35, "seg": 3, "what": "第 4 段中段（SP2 现货道）"},
		{"station": 39, "seg": 4, "what": "第 5 段中段（OPT2 权利金）"},
		{"station": 43, "seg": 5, "what": "第 6 段中段（AS2 天地板）"},
		{"station": 47, "seg": 6, "what": "第 7 段中段（FX2 杠杆）"},
		{"station": 54, "seg": 7, "what": "第 8 段中段（DK5 暗网）"},
		{"station": 63, "seg": 8, "what": "第 9 段中段（X4 窄板）"},
		{"station": 71, "seg": 9, "what": "第 10 段中段（W4 螺旋塔）"},
		{"station": 87, "seg": 10, "what": "第 11 段中段（H2 机关区）"},
		{"station": 94, "seg": 11, "what": "第 12 段中段（J1 竖井）"},
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
	_check(not started and idle_time == 0.0 and running and t_mid > 0.0
		and _pk.finished and not _pk.timer_running and _pk.best_seconds() > 0.0,
		"计时器：站跑道 %s → 离开后 %s（%.2f s）→ 撞岛停表 %s，最好成绩 %.2f s（存 user://）"
		% [str(started), str(running), t_mid, str(_pk.finished), _pk.best_seconds()])

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
	_check(absf(top - 8.00) < 0.01, "岛面高度 y = %.2f（第 8 段下降链最后落到这儿）" % top)

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
	print("  路线                  %d 段 / %d 站 / %d 跳 + 9 处机关跳 + 5 段走过去 / 跳距合计 %.1f m"
		% [_pk.segment_count(), _pk.node_count(), int(_m.get("jumps", 0)),
			float(_m.get("gap_sum", 0.0))])
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


## 走**真实输入路径**按一下某个键（F 拾取 / 确认都靠它）
func _press_key(code: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = code
	down.physical_keycode = code
	down.pressed = true
	Input.parse_input_event(down)
	await _wait(3)
	var up := InputEventKey.new()
	up.keycode = code
	up.physical_keycode = code
	up.pressed = false
	Input.parse_input_event(up)
	await _wait(2)


func _put(x: float, y: float, z: float) -> void:
	_release_all()
	_p.global_position = Vector3(x, y, z)
	_p.velocity = Vector3.ZERO


## 场上所有同伴（`game.gd` 的直接子节点，按类型收）—— §1b / §1c 共用
func _companions() -> Array[Companion]:
	var out: Array[Companion] = []
	var game := _p.get_parent()
	for c in game.get_children():
		if c is Companion:
			out.append(c as Companion)
	return out


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
