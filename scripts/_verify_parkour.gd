extends SceneTree
## 验「跑酷路线」：把「从平台跳出去、落到信号塔岛」这件事**真的跑一遍**。
##
## 这一套和别的自检不太一样：别的多半是「读状态、比数值」，这一套的主体是
## **用真输入开一个真玩家，把 12 站挨个跳过去**。理由是跑酷这种东西，
## 几何对不对可以算，但「人到底跳不跳得过去」只有一个可信的判据：跳给他看。
##
## 七节：
##   1. 结构与几何 —— 网格/碰撞是否严丝合缝、0.05 网格、节点齐不齐
##   2. 胶囊与台面 —— 站在板上是台面 +0.000；**挂边容忍到底多少**（真物理量）
##   3. 实测跳跃能力 —— 在空域二分法量出「平跳最远」「抬升 0.80 最远」，
##      再拿它去核对本关的每一跳（`player.gd` 一改，这里就会红）
##   4. 逐跳回放 —— 每一跳单独跳一次（记下实际落点），最后**一口气通一次关**
##   5. 反例 —— 不跳就过不去；摔下去回检查点而不是回出生点；传送台能回平台
##   6. 与平台既有东西不打架 —— 画室墙/柱子/靶子/Boss/小屋/受保护弹道
##   7. 终点区域 —— 岛够大、够平、灯不多、指路牌在
##
## 用法：
##   godot --path <工程> --script res://scripts/_verify_parkour.gd -- --splat=off
##
## ⚠️ 三条纪律（和 `_verify_move_feel` 同一套）：
##   · **等真实毫秒**，不等帧数（真窗口能跑到 1000 fps，等 60 帧只有 16 ms）
##   · 开局把鼠标设成 VISIBLE（有人碰鼠标不会把视角带歪）
##   · 每一节自己摆好人和检查点状态，不靠上一节的残留

const SPAWN := Vector3(0, 0.05, 6)
## 「离边缘还有多少米就按跳」。跑速 6.8 m/s、物理 60 Hz ⇒ 一格 0.113 m，
## 所以 0.15 大致等于「踩着边起跳」。这个数会直接从余量里扣掉（见 §4 的注释）。
const JUMP_LEAD := 0.15
## 起跳前的助跑距离。0.89 m 就能从静止加到满速（v²/2a = 6.8²/52），给 1.6 m 很宽裕
const RUNUP := 1.6
## 标定台的空域（远离平台和跑酷，免得互相干扰）
const RIG := Vector3(200, 0, 0)

var _fail := 0
var _pass := 0
var _p: Player
var _pk: Parkour
var _space: PhysicsDirectSpaceState3D
## 量出来的数，最后打表
var _m := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
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
	_check(_pk.node_count() == 12, "路线有 %d 站（期望 12：跑道 + 10 块板 + 窄梁 + 岛）"
		% _pk.node_count())
	var want := ["Launch", "P1", "P2", "P3", "Beam", "P4", "P5", "P6", "P7", "P8", "P9", "Island"]
	var got: Array[String] = []
	for i in _pk.node_count():
		got.append(_pk.label_at(i))
	_check(got == want, "顺序正确：%s" % " → ".join(PackedStringArray(got)))

	# 网格与碰撞必须指着同一块体积：Mesh 的世界 AABB vs Col 的世界 AABB。
	# 这两个数一旦走散，就是「看得见的地方踩不住 / 踩得住的地方是空的」。
	var worst := 0.0
	var worst_name := ""
	var mismatched: Array[String] = []
	for i in _pk.node_count():
		var node := _pk.get_node_or_null(NodePath(String(_pk.route[i])))
		if node == null:
			continue
		var mesh := node.get_node_or_null("Mesh") as MeshInstance3D
		var col := node.get_node_or_null("Col") as CollisionShape3D
		if mesh == null or col == null:
			continue          # 跑道标记本来就没有碰撞，见下一段
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

	# 跑道标记：必须有网格、**必须没有碰撞**（有碰撞就是一道 2.5 cm 的坎）
	var runway := _pk.get_node_or_null("Launch") as MeshInstance3D
	_check(runway != null and runway.mesh != null and _pk.get_node_or_null("Launch/Col") == null,
		"跑道标记有外观、没有碰撞体（有的话就是一道路沿石）")

	# 0.05 m 网格纪律
	var off: Array[String] = []
	for n in _walk(_pk):
		if not (n is Node3D) or n is Light3D or n is Label3D or n is Area3D:
			continue
		var xf := (n as Node3D).transform
		for v in [xf.origin, xf.basis.get_scale()]:
			for c in 3:
				var q: float = absf(v[c]) / 0.05
				if absf(q - roundf(q)) > 0.001:
					off.append("%s %s=%.3f" % [n.name, "xyz"[c], v[c]])
	_check(off.is_empty(), "所有 position / scale 都落在 0.05 m 网格上%s"
		% ("" if off.is_empty() else "（越界：%s）" % str(off.slice(0, 4))))

	# 碰撞层：SpringArm 的 collision_mask = 1，板子不在 1 层的话相机会穿地
	var bad_layer: Array[String] = []
	for n in _walk(_pk):
		if n is StaticBody3D and (n as StaticBody3D).collision_layer != 1:
			bad_layer.append("%s(%d)" % [n.name, (n as StaticBody3D).collision_layer])
	_check(bad_layer.is_empty(), "所有 StaticBody3D 都在碰撞层 1 上（相机 SpringArm 才挡得住）%s"
		% ("" if bad_layer.is_empty() else str(bad_layer)))

	var st := _stats(_pk)
	print("  小结：%d 个节点，%d 个网格，%d 个碰撞形状，%d 盏灯，%d 个 Label3D"
		% [st["nodes"], st["meshes"], st["shapes"], st["lights"], st["labels"]])


# --- 2. 胶囊与台面（真物理）----------------------------------------------------

func _test_capsule() -> void:
	print("\n========== 2. 胶囊与台面（真物理量的两个数）==========")
	_pk.enabled = false          # 这一节故意要摔下去，别让检查点把人捞回来
	var p3 := _pk.box_at(3)      # P3：3 × 3 m，全程最大的一块板
	var top := _pk.top_at(3)
	var x_mid := p3.position.x + p3.size.x * 0.5

	for probe in [
		{"label": "板正中", "dx": 0.0, "want": top},
		{"label": "板内沿（距边 0.10）", "dx": -1.40, "want": top},
	]:
		_put(x_mid + float(probe["dx"]), top + 1.0, p3.position.z + p3.size.z * 0.5)
		await _wait_ms(700)
		_check(absf(_p.global_position.y - float(probe["want"])) < 0.02,
			"%s：站在 y = %.3f（台面 %.2f）" % [probe["label"], _p.global_position.y, top])

	# 挂边：站在板外多远还托得住。
	#
	# ⚠️ 两件事都会把这个数搞错，都踩过：
	#   1. **不能拿 P3 的西边缘测** —— 窄梁紧贴着它（同高、从 x = −38.50 开始），
	#      人根本不是「挂在边上」，是**站在梁上**（第一版就是这么量的，量到 +0.40）。
	#      所以这里测的是南边缘（z 方向），那边什么都没有。
	#   2. 极限是**几何定死的**：胶囊半径 0.30、`floor_max_angle` 45°，
	#      球心在面外 0.30 m 时接触法线正好 45°（tan45° × 0.30 = 0.30）。
	#      但临界点上「掉不掉」跟落地那一下的动能有关（2.5 m 高摔下来只有 +0.20，
	#      轻轻放下去能到 +0.30），所以断言给区间、不给单点。
	var hang := -99.0
	for over in [0.10, 0.20, 0.30, 0.40]:
		_put(x_mid, top + 1.0, p3.position.z - float(over))
		await _wait_ms(700)
		if _p.is_on_floor() and _p.global_position.y > top - 0.5:
			hang = float(over)
	_check(hang >= 0.15 and hang <= 0.35,
		"挂边容忍（南边缘）：站到板外 **+%.2f m** 还托得住、+0.40 就掉"
		% hang + "（胶囊半径 0.30 = 几何极限）")
	_m["hang"] = hang

	# 窄梁：横向站多远还站得住 —— 这就是「窄」的量化
	var beam := _pk.box_at(4)
	var bx := beam.position.x + beam.size.x * 0.5
	var bz := beam.position.z + beam.size.z * 0.5
	var btop := _pk.top_at(4)
	var wide := -99.0
	for off in [0.0, 0.20, 0.40, 0.50, 0.60, 0.70]:
		_put(bx, btop + 0.6, bz + float(off))
		await _wait_ms(700)
		if _p.is_on_floor() and _p.global_position.y > btop - 0.5:
			wide = float(off)
	_m["beam_wide"] = wide
	_check(wide >= 0.45 and wide <= 0.75,
		"0.80 m 宽的窄梁：**中心**偏 %.2f m 还站得住、再远就掉（梁半宽 0.40 + 挂边）" % wide)
	_pk.enabled = true
	_release_all()


# --- 3. 实测跳跃能力（标定）----------------------------------------------------

func _test_calibration() -> void:
	print("\n========== 3. 实测跳跃能力（空域里二分法量，不用解析值）==========")
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

	# 拿实测值核对本关每一跳。
	#
	# 做法：实测比解析远 `k = 平跳实测 / 平跳解析`（这里有 +5% 左右 —— 解析假设
	# 「从板的边缘起跳」，而实际起跳点可以站到边缘外一点点、起跳后也还在继续加速）。
	# 于是**任意抬升**的预期射程 = 解析射程 × k，拿它减每一跳的距离就是余量。
	# 这样只需要标定两次（平跳 + 一次抬升），又能把每一跳都管住。
	var k := flat / flat_theory
	_m["k"] = k
	var scaled_rise := rise_theory * k
	_check(absf(rise - scaled_rise) <= 0.45,
		"模型自洽：抬升 0.80 的实测 %.2f m 与「解析 × %.2f」= %.2f m 相差 ≤ 0.45"
		% [rise, k, scaled_rise])
	var worst := INF
	var worst_name := ""
	var bad: Array[String] = []
	for i in range(1, _pk.node_count()):
		var h := _hop(i - 1, i)
		if float(h["required"]) < 0.5:
			continue                       # 这一站是「走过去」的，不是跳
		var expected := float(h["reach"]) * k
		var margin := expected - float(h["required"])
		var name := "%s→%s" % [_pk.label_at(i - 1), _pk.label_at(i)]
		if margin < worst:
			worst = margin
			worst_name = name
		if margin < 0.40:
			bad.append("%s 余量 %.2f" % [name, margin])
	_m["worst_margin"] = worst
	_m["worst_name"] = worst_name
	_check(bad.is_empty(), "按**实测**能力核对每一跳：最紧的是 %s，余量 %.2f m（要求 ≥ 0.40）%s"
		% [worst_name, worst, "" if bad.is_empty() else str(bad)])
	_check(worst >= 0.40, "最紧一跳的余量 %.2f m ≥ 起跳提前量 %.2f + 误差 0.25"
		% [worst, JUMP_LEAD])


## 在空域搭两组板（起跳板 + 目标板），二分法量「还能跨多远」。
func _build_rig() -> Node3D:
	var rig := Node3D.new()
	rig.name = "ParkourRig"
	root.add_child(rig)
	_add_slab(rig, Vector3(RIG.x, -0.25, 0), Vector3(3, 0.5, 3))
	return rig


## 反复试跳：把目标板摆到 gap 处，跳得过去就说明 gap 可过。二分 5 次。
func _bisect_gap(rig: Node3D, rise: float, lo: float, hi: float) -> float:
	var target := _add_slab(rig, Vector3(0, 0, 0), Vector3(3, 0.5, 3))
	var ok := lo
	for _step in 6:
		var mid := (lo + hi) * 0.5
		# 起跳板西缘 x = RIG.x − 1.5；目标板东缘要离它 mid
		target.position = Vector3(RIG.x - 1.5 - mid - 1.5, rise - 0.25, 0)
		await _wait(2)
		var res := await _try_rig_jump(target, rise, mid)
		if bool(res):
			ok = mid
			lo = mid
		else:
			hi = mid
	return ok


func _try_rig_jump(target: Node3D, rise: float, gap: float) -> bool:
	_release_all()
	_p.global_position = Vector3(RIG.x + 1.30, 0.05, 0)
	_p.velocity = Vector3.ZERO
	_p._yaw = PI * 0.5            # move_forward = 世界 −X
	_p._facing_yaw = _p._yaw + PI
	_p.model_root.rotation.y = _p._facing_yaw
	await _wait(3)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	# 冲到起跳板西缘
	var t0 := Time.get_ticks_msec()
	var jumped := false
	while Time.get_ticks_msec() - t0 < 1500:
		await process_frame
		if _p.global_position.x <= RIG.x - 1.5 + JUMP_LEAD and _p.is_on_floor():
			Input.action_press("jump")
			await process_frame
			await process_frame
			Input.action_release("jump")
			jumped = true
			break
	if not jumped:
		_release_all()
		return false
	# 等落地（或者掉下去）
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
	_pk.checkpoint = -1
	var rows: Array[String] = []
	var fails := 0
	for i in range(1, _pk.node_count()):
		var h := _hop(i - 1, i)
		var walk := float(h["required"]) < 0.5
		var res := await _run_hop(i - 1, i, walk)
		var pair := "%s→%s" % [_pk.label_at(i - 1), _pk.label_at(i)]
		var ok: bool = bool(res["ok"])
		if not ok:
			fails += 1
		rows.append("%-13s %s 必须跨 %5.2f 抬升 %+5.2f → 实落 (%7.2f, %7.2f) %s" % [
			pair, "走 " if walk else "跳 ", h["required"], h["rise"],
			float(res["pos"].x), float(res["pos"].z), "✓" if ok else "**✗**"])
		_check(ok, "%s：落在 %s 上（y = %.2f，台面 %.2f）"
			% [pair, _pk.label_at(i), float(res["pos"].y), _pk.top_at(i)])
		if not walk:
			var pred: Vector3 = h["landing"]
			var d := Vector2(float(res["pos"].x) - pred.x, float(res["pos"].z) - pred.z).length()
			_check(d <= 0.90, "    解析预测落点与实际相差 %.2f m（≤ 0.90）" % d)
	_check(fails == 0, "12 站逐跳全部通过（失败 %d 跳）" % fails)
	print("\n  " + "\n  ".join(PackedStringArray(rows)))
	_release_all()
	await _wait(2)

	# 一口气通一次关：不重置、不重摆，从起跳跑道直接打到岛上
	print("\n  ── 连续通关（中途不重置）──")
	_pk.checkpoint = -1
	var chain_ok := true
	var chain_log: Array[String] = []
	for i in range(1, _pk.node_count()):
		var walk := float(_hop(i - 1, i)["required"]) < 0.5
		var res := await _run_hop(i - 1, i, walk, i == 1)
		if not bool(res["ok"]):
			chain_ok = false
			chain_log.append("%s✗" % _pk.label_at(i))
			break
		chain_log.append(_pk.label_at(i))
	_check(chain_ok, "连续通关：%s（检查点 %d/%d）"
		% [" → ".join(PackedStringArray(chain_log)), _pk.checkpoint + 1, _pk.node_count()])
	_check(_pk.checkpoint == _pk.node_count() - 1,
		"到达终点站（检查点 = %d = 信号塔岛）" % _pk.checkpoint)
	_release_all()


## 跑一站：把玩家摆到上一站、镜头对准下一站，按住 W+Shift 冲过去。
##
## `walk` = 这一站是「走过去」的（相邻、同高），不按跳。
## `place` = 要不要把玩家先摆到上一站（否则用他当前站着的位置接着跑）。
func _run_hop(from_i: int, to_i: int, walk: bool, place := true) -> Dictionary:
	var a := _pk.box_at(from_i)
	var b := _pk.box_at(to_i)
	var h := _hop(from_i, to_i)
	var takeoff: Vector3 = h["takeoff"]
	var center := b.position + b.size * 0.5
	var dir := Vector2(center.x - takeoff.x, center.z - takeoff.z).normalized()
	if place:
		# 单独测这一跳：摆回上一站、清速度、站稳再跑
		_release_all()
		_p.global_position = Vector3(takeoff.x - dir.x * RUNUP, _pk.top_at(from_i) + 0.05,
			takeoff.z - dir.y * RUNUP)
		_p.velocity = Vector3.ZERO
	else:
		# 连续通关：**不松键、不停顿**，落地就接着跑（人就是这么跑的）。
		# 松一下键会吃 30 m/s² 的摩擦，在 2.2 m 的小板上很容易滑到边缘外。
		await process_frame
	# 镜头对准目标：move_forward 正好朝 dir（推导见 _verify_parkour 头注释）
	_p._yaw = atan2(-dir.x, -dir.y)
	_p._facing_yaw = _p._yaw + PI
	_p.model_root.rotation.y = _p._facing_yaw
	if place:
		await _wait(3)

	Input.action_press("move_forward")
	Input.action_press("sprint")
	var t0 := Time.get_ticks_msec()
	var jumped := false
	if walk:
		# 「走过去」的一站（P3 → 窄梁：相邻、同高）：**不按跳**，一路跑进目标板 1.0 m。
		# 这一段同时就是窄梁的平衡测试 —— 跑歪了就掉下去，下面的 ok 判定会红。
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
			var remain := (takeoff.x - pp.x) * dir.x + (takeoff.z - pp.z) * dir.y
			if remain <= JUMP_LEAD and _p.is_on_floor():
				Input.action_press("jump")
				await process_frame
				await process_frame
				Input.action_release("jump")
				jumped = true
				break
		if not jumped:
			_release_all()
			return {"ok": false, "pos": _p.global_position, "why": "没跑到边缘"}

	# 等落地：落在这一站的台面高度附近、或者掉到台面以下 3 m
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
	print("\n========== 5. 反例（过不去 / 摔下去 / 回平台）==========")
	_pk.enabled = true

	# ① 不按跳，直接跑出边缘 → 必然掉下去（这一条同时证明「间距是真的」）
	var h := _hop(2, 3)                       # P2→P3，全线最远的一跳
	var takeoff: Vector3 = h["takeoff"]
	var c := _pk.box_at(3)
	var dir := Vector2(c.position.x + c.size.x * 0.5 - takeoff.x, 0).normalized()
	_release_all()
	_pk.checkpoint = -1
	_p.global_position = Vector3(takeoff.x - dir.x * RUNUP, _pk.top_at(2) + 0.05, takeoff.z)
	_p.velocity = Vector3.ZERO
	_p._yaw = atan2(-dir.x, -dir.y)
	await _wait(3)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	var fell := false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2500:
		await process_frame
		if _p.global_position.y < _pk.top_at(2) - 2.0:
			fell = true
			break
	_release_all()
	_check(fell, "P2→P3 这一段**不按跳**会掉下去（掉到 y = %.1f）—— 间距是真的"
		% _p.global_position.y)

	# ② 摔落 → 回**最近踩过的落脚点**，而不是出生点
	_pk.checkpoint = -1
	_pk.rescues = 0
	var p3 := _pk.box_at(3)
	_put(p3.position.x + p3.size.x * 0.5, _pk.top_at(3) + 0.05, p3.position.z + p3.size.z * 0.5)
	await _wait(4)
	_check(_pk.checkpoint == 3, "在 P3 上站一下 → 检查点推进到第 4 站（%s）" % _pk.label_at(_pk.checkpoint))
	_p.global_position = Vector3(_p.global_position.x, -13.0, _p.global_position.z)
	await _wait(4)
	var back := _p.global_position
	var want := _pk.respawn_point(3)
	_check(_pk.rescues == 1 and back.distance_to(want) < 0.30,
		"摔到 y = −13 → 被送回 P3 台面正中（实落 %.2f, %.2f，期望 %.2f, %.2f，第 %d 次）"
		% [back.x, back.z, want.x, want.z, _pk.rescues])
	_check(_pk.FALL_Y > -60.0 and _pk.FALL_Y < -5.0,
		"跑酷的兜底线 %.0f m **高于** game.gd 的 −60 m，所以抢在它前面出手" % _pk.FALL_Y)

	# ③ 回到主平台 → 检查点清空；此时再摔，归 game.gd 的兜底管
	_p.global_position = SPAWN
	_p.velocity = Vector3.ZERO
	await _wait(4)
	_check(_pk.checkpoint == -1, "站在主平台上 → 检查点清空（免得路人被塞进跑酷中段）")
	_p.global_position = Vector3(0, -59.5, 6)
	await _wait_ms(400)
	_check(_p.global_position.distance_to(SPAWN) < 0.30,
		"不在跑酷里摔下去 → 还是 game.gd 送回出生点（y = %.2f）" % _p.global_position.y)

	# ④ 岛上的传送台 → 回平台
	var pad := _pk.get_node_or_null("Island/Props/ReturnPad") as Node3D
	_check(pad != null, "岛上有传送台节点（Island/Props/ReturnPad）")
	if pad != null:
		_pk.checkpoint = 11
		_p.global_position = pad.global_position + Vector3(0, 0.10, 0)
		_p.velocity = Vector3.ZERO
		await _wait_ms(500)
		_check(_p.global_position.distance_to(_pk.return_target) < 0.30 and _pk.checkpoint == -1,
			"踏上传送台 → 回到主平台 %s，检查点清空（y = %.2f）"
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
	# 受保护的自检弹道：玩家(6, −4) → 靶1(6, −10)
	others.append({"b": AABB(Vector3(5.4, 0, -10.6), Vector3(1.2, 2.0, 6.6)),
		"n": "受保护弹道 玩家(6,−4)→靶1(6,−10)"})

	var hits: Array[String] = []
	for i in mine.size():
		for o in others:
			if mine[i].intersects(o["b"]):
				hits.append("%s ∩ %s" % [mine_names[i], o["n"]])
	_check(hits.is_empty(), "跑酷的 %d 块实体与画室墙/柱子/靶子/两位 Boss/小屋/受保护弹道都不相交%s"
		% [mine.size(), "" if hits.is_empty() else "（撞上：%s）" % str(hits)])

	var island := _pk.box_at(_pk.node_count() - 1)
	_check(island.position.x + island.size.x <= -20.0,
		"终点岛整块在平台之外（x 最大 %.2f ≤ −20）" % (island.position.x + island.size.x))

	# 小屋（x 从 9.25 起）在这条线的反方向，隔着一整个平台 —— 写死一条，
	# 免得哪天有人把跑酷挪到东边去还指望这套自检能发现
	var east := -INF
	for b in mine:
		east = maxf(east, b.position.x + b.size.x)
	_check(east < 9.0, "跑酷最东边 x = %.2f，与东北角的网格小屋（x ≥ 9.25）隔着 %.2f m"
		% [east, 9.25 - east])

	# 跑道那道 2.5 cm 的标记板**不能挡人**（这是 §1.13 那个坎的复现测试）
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
	# 理论值：0.89 m 加速到 6.8 m/s（走 0.26 s），剩下 0.34 s 匀速 → 约 3.2 m。
	# 关键是**别被那道 2.5 cm 的标记板挡住**：被挡住的话这里只有零点几米。
	_check(dx >= 3.0 and absf(_p.global_position.y) < 0.30,
		"从跑道东端往西跑 0.6 s：前进 %.2f m、y = %.2f（理论 3.2 m；标记板没有挡人）"
		% [dx, _p.global_position.y])
	_pk.enabled = true


# --- 7. 终点区域 ---------------------------------------------------------------

func _test_island() -> void:
	print("\n========== 7. 终点区域（信号塔岛）==========")
	var island := _pk.box_at(_pk.node_count() - 1)
	var top := _pk.top_at(_pk.node_count() - 1)
	_check(island.size.x >= 12.0 and island.size.z >= 12.0,
		"岛面 %.0f × %.0f m（≥ 12 × 12，装得下下一章要摆的东西）" % [island.size.x, island.size.z])
	_check(absf(top - 4.70) < 0.01, "岛面高度 y = %.2f（终点比最高的落脚板低 1.00 m）" % top)

	var last := _hop(_pk.node_count() - 2, _pk.node_count() - 1)
	var land: Vector3 = last["landing"]
	var blocked: Array[String] = []
	for d in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var safe := _cast_safe(land + Vector3(0, 0.5, 0), d * 3.0)
		if safe < 0.999:
			blocked.append("%s %.2f" % [str(d), safe])
	_check(blocked.is_empty(), "落点 (%0.1f, %0.1f) 四周各 3 m 是净空的%s"
		% [land.x, land.z, "" if blocked.is_empty() else str(blocked)])

	# 落点往外（东）3 m 就该走出岛沿 —— 岛是有边界的，不是无限地面
	var off := _cast_safe(land + Vector3(0, 0.5, 0), Vector3(1, 0, 0) * 9.0)
	_check(off < 0.999, "从落点往东走 9 m 会走到岛沿（safe = %.2f，岛东缘 x = %.2f）"
		% [off, island.position.x + island.size.x])

	var st := _stats(_pk)
	_check(st["lights"] <= 3, "整条路线 %d 盏灯（≤ 3；本项目对功耗敏感）" % st["lights"])
	var shadowed := 0
	for n in _walk(_pk):
		if n is Light3D and (n as Light3D).shadow_enabled:
			shadowed += 1
	_check(shadowed == 0, "所有灯都关阴影（%d 盏开着）" % shadowed)

	var signs: Array[String] = []
	for n in _walk(_pk):
		if n is Label3D:
			signs.append("%s：「%s」" % [n.name, (n as Label3D).text.replace("\n", " / ")])
	_check(signs.size() >= 3, "指路牌 %d 块：%s" % [signs.size(), str(signs)])
	_m["signs"] = signs.size()


# --- 结果 ---------------------------------------------------------------------

func _print_table() -> void:
	print("\n================ 跑酷一览（实测）================")
	print("  平跳最远（实测）      %.2f m   ← 解析 %.2f m"
		% [float(_m.get("flat", 0.0)), float(_m.get("flat_theory", 0.0))])
	print("  抬升 0.80 m 最远      %.2f m" % float(_m.get("rise", 0.0)))
	print("  挂边容忍              +%.2f m（胶囊半径 0.30）" % float(_m.get("hang", 0.0)))
	print("  0.80 m 窄梁横向余量   ±%.2f m" % float(_m.get("beam_wide", 0.0)))
	print("  全线最紧的一跳        %s，余量 %.2f m"
		% [String(_m.get("worst_name", "")), float(_m.get("worst_margin", 0.0))])
	print("  路线                  12 站 / 10 跳 / 1 段窄梁 / 56 m / 抬升 5.70 m")


# --- 工具 ---------------------------------------------------------------------

## 取第 from_i → to_i 站的解析分析（自检和探针共用 parkour.gd 的实现）
func _hop(from_i: int, to_i: int) -> Dictionary:
	return Parkour.hop_analysis(_pk.box_at(from_i), _pk.box_at(to_i),
		Player.JUMP_VELOCITY, Player.GRAVITY, Player.SPEED_RUN)


## 把玩家摆到某个世界坐标，并清掉速度
func _put(x: float, y: float, z: float) -> void:
	_release_all()
	_p.global_position = Vector3(x, y, z)
	_p.velocity = Vector3.ZERO


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


## 一个 StaticBody3D 的世界包围盒（并它的所有碰撞形状）
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
	print("失败 %d 项" % _fail)
	quit(1 if _fail > 0 else 0)


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
