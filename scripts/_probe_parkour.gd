extends SceneTree
## 探针：把跑酷 v2 的**设计依据**打出来（不跑物理，几秒就完）。
##
## 这是「设计 → 建模 → 验证」里的**设计**那一半：每一跳跨多远、抬多高、
## 解析弹道能到多远、**实测模型**余量多少、落点在板内的哪里 —— 全部来自
## `parkour.gd::hop_analysis()`（自检用的是同一个函数，所以文档和断言不会走散）。
##
## 输出四段：
##   0. 路线总览：几段、几站、多长、每段多长
##   1. 每一站（世界坐标、尺寸、台面、属于哪一段）
##   2. 每一跳（解析 + **实测余量 = 解析 × K − 必须跨**）+ 紧张区间统计 + 最难三跳
##   3. 俯视 ASCII 图（一格 2 m：x → 右、z ↓）
##   4. 与平台的关系（起跳边缘、x 跨度、终点岛、分段起点的名字）
##
## 用法：
##   godot --path <工程> --script res://scripts/_probe_parkour.gd -- --splat=off
##
## ⚠️ 加 `--splat=off`：跑酷不依赖画室609，关掉泼溅能省 20 s 解码。
## ⚠️ 要真渲染，不要 `--headless`。
## ⚠️ 退出码：任何一跳实测余量 < 0.40、或落点入板 < 0.12、或节点缺失 → 退 1
##    （所以这个探针同时是**设计闸门**，不是只打印给人看）。

## 实测系数：v1 二分法量的「实测射程 / 解析射程」（平地解析 4.83 → 实测 5.09）
const K := 1.054
const MARGIN_MIN := 0.40
## 解析落点距板边的下限。对直跳来说「解析落点入板深度」恒等于
## `解析射程 − 必须跨`，真正要守的是**实测余量**；这条只兜「别落在板沿上」。
const EDGE_MIN := 0.12
## 图的范围（米）与格子大小（v2 横跨 206 m，1 m 一格就太宽了）
const X0 := -240.0
const X1 := -4.0
const Z0 := -20.0
const Z1 := 10.0
const CELL := 2.0

var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(10)

	var pk := game.get_node_or_null("Parkour") as Parkour
	if pk == null:
		print("!! 场景里没有 Parkour（game.tscn 里没挂 scenes/parkour.tscn？）")
		quit(1)
		return
	pk._build_route()
	var n := pk.node_count()
	var names: Array[String] = []
	for i in n:
		names.append(pk.label_at(i))
	print("========== 0. 路线总览 ==========")
	print("落脚点 %d 个：%s" % [n, " → ".join(PackedStringArray(names))])
	print("玩家跑速 %.2f m/s、起跳 %.2f m/s、重力 %.1f m/s²；实测系数 K = %.3f（player.gd / v1 二分标定）"
		% [Player.SPEED_RUN, Player.JUMP_VELOCITY, Player.GRAVITY, K])
	print("分成 %d 段，段起点（**掉下去回这里**）：" % pk.segment_count())
	var seg_heads: Array[String] = []
	for s in pk.segment_count():
		var st := pk.segment_start(s)
		var en: int = pk.segment_start(s + 1) - 1 if s + 1 < pk.segment_count() else n - 1
		seg_heads.append(pk.label_at(st))
		var seg_len := 0.0
		for i in range(st + 1, en + 1):
			seg_len += float(_hop(pk, i - 1, i)["required"])
		print("  第 %d 段「%s」：第 %d~%d 站（%d 站），跳距合计 %.1f m"
			% [s + 1, pk.segment_name(s), st + 1, en + 1, en - st + 1, seg_len])

	# ── 1. 每一站 ──────────────────────────────────────────────────────────
	print("\n========== 1. 落脚点（世界坐标，台面 = 顶面）==========")
	print("（`Launch` 是画在平台地面上的**标记板**：报的是板顶 0.03，"
		+ "真正的起跳面是平台地面 y = 0.00 —— 差 2.5 cm，对余量无影响）")
	print("%3s %-7s %3s %9s %9s %9s %9s %7s %9s %9s" % [
		"#", "名字", "段", "x最小", "x最大", "z最小", "z最大", "台面", "宽(x)", "深(z)"])
	for i in n:
		var b := pk.box_at(i)
		print("%3d %-7s %3d %9.2f %9.2f %9.2f %9.2f %7.2f %9.2f %9.2f" % [
			i, pk.label_at(i), pk.segment_of(i) + 1, b.position.x, b.position.x + b.size.x,
			b.position.z, b.position.z + b.size.z, pk.top_at(i), b.size.x, b.size.z])

	# ── 2. 每一跳 ─────────────────────────────────────────────────────────
	print("\n========== 2. 每一跳（余量 = 解析射程 × %.3f − 必须跨）==========" % K)
	print("%-13s %8s %7s %7s %7s %8s %8s %s" % [
		"这一跳", "必须跨", "抬升", "解析", "实测", "余量", "入板深度", "落点"])
	var tight := 0
	var jumps := 0
	var gap_sum := 0.0
	var rows: Array = []
	for i in range(1, n):
		var a := pk.box_at(i - 1)
		var b := pk.box_at(i)
		var pair := "%s→%s" % [pk.label_at(i - 1), pk.label_at(i)]
		if a.size.x <= 0.0 or b.size.x <= 0.0:
			print("%-13s （节点缺失）" % pair)
			_fail += 1
			continue
		var h := Parkour.hop_analysis(a, b, Player.JUMP_VELOCITY, Player.GRAVITY, Player.SPEED_RUN)
		if not bool(h["reachable"]):
			print("%-13s ** 抬升 %+.2f 超过跳跃高度，无解 **" % [pair, h["rise"]])
			_fail += 1
			continue
		if float(h["required"]) < 0.5:
			print("%-13s %8s  走过去（相邻同高：独木桥）" % [pair, "0.00"])
			continue
		jumps += 1
		gap_sum += float(h["required"])
		var margin := float(h["reach"]) * K - float(h["required"])
		var land: Vector3 = h["landing"]
		var is_tight := margin <= 0.90
		if is_tight:
			tight += 1
		rows.append({"pair": pair, "req": float(h["required"]), "rise": float(h["rise"]),
			"margin": margin, "edge": float(h["edge_dist"])})
		print("%-13s %8.2f %+7.2f %7.2f %7.2f %8.2f %8.2f  (%.2f, %.2f) %s" % [
			pair, h["required"], h["rise"], h["reach"], float(h["reach"]) * K, margin,
			float(h["edge_dist"]), land.x, land.z,
			"★紧张" if is_tight else ("✓" if bool(h["inside"]) else "**过头**")])
		if margin < MARGIN_MIN:
			_fail += 1
		if not bool(h["inside"]) or float(h["edge_dist"]) < EDGE_MIN:
			_fail += 1

	rows.sort_custom(func(x, y): return float(x["margin"]) < float(y["margin"]))
	print("\n  ★ 跳 %d 个（另有 2 段独木桥是走的）  跳距合计 %.1f m" % [jumps, gap_sum])
	print("  ★ 紧张区间（实测余量 0.40~0.90）：**%d/%d = %.0f%%**（要求 ≥ 1/3）"
		% [tight, jumps, 100.0 * tight / maxf(jumps, 1)])
	if not rows.is_empty():
		print("  ★ 余量范围 %.2f ~ %.2f m（要求全部 ≥ %.2f）" % [
			float(rows[0]["margin"]), float(rows[rows.size() - 1]["margin"]), MARGIN_MIN])
		print("  ★ 最难的三跳（按实测余量）:")
		for r in rows.slice(0, 3):
			print("      %-13s 必须跨 %.2f m，抬升 %+.2f，解析入板 %.2f，**实测余量 %.2f**"
				% [r["pair"], r["req"], r["rise"], r["edge"], r["margin"]])
	print("  ★ 最大抬升 %.2f m（跳跃峰值 %.2f）  最大落差 %.2f m" % [
		_max_rise(pk, n), Player.JUMP_VELOCITY * Player.JUMP_VELOCITY / (2.0 * Player.GRAVITY),
		_min_rise(pk, n)])
	print("  ★ 高度剖面：" + _profile(pk, n))

	# ── 3. 俯视图 ─────────────────────────────────────────────────────────
	print("\n========== 3. 俯视图（一格 %.0f m，x → 右、z ↓；*板 -=独木桥 S=段起点 T=终点岛 _=平台）==========" % CELL)
	print(_draw(pk, n))

	# ── 4. 与平台的关系 ───────────────────────────────────────────────────
	print("\n========== 4. 与平台的关系 ==========")
	var first := pk.box_at(1)
	var island := pk.box_at(n - 1)
	var east := -INF
	for i in range(1, n):
		east = maxf(east, pk.box_at(i).position.x + pk.box_at(i).size.x)
	print("  平台西边缘 x = −20.00；第一块板东边缘 x = %.2f（离平台 %.2f m 的真空）"
		% [first.position.x + first.size.x, -first.position.x - first.size.x - 20.0])
	print("  x 跨度（跑道西端 → 终点岛中心）：%.1f m"
		% absf(island.position.x + island.size.x * 0.5 + 20.0))
	print("  最东边的落脚板 x = %.2f（必须 < 9.0，免得撞上东北角的网格小屋）" % east)
	print("  终点岛：中心 (%.2f, %.2f)，%.0f × %.0f m，台面 y = %.2f —— 「下一个区域」"
		% [island.position.x + island.size.x * 0.5, island.position.z + island.size.z * 0.5,
			island.size.x, island.size.z, pk.top_at(n - 1)])
	print("  段起点：%s" % str(seg_heads))

	print("\n失败 %d 项" % _fail)
	quit(1 if _fail > 0 else 0)


# --- 小工具 -------------------------------------------------------------------

func _hop(pk: Parkour, a: int, b: int) -> Dictionary:
	return Parkour.hop_analysis(pk.box_at(a), pk.box_at(b),
		Player.JUMP_VELOCITY, Player.GRAVITY, Player.SPEED_RUN)


func _max_rise(pk: Parkour, n: int) -> float:
	var m := -INF
	for i in range(1, n):
		if pk.box_at(i - 1).size.x <= 0.0 or pk.box_at(i).size.x <= 0.0:
			continue
		m = maxf(m, pk.top_at(i) - pk.top_at(i - 1))
	return m


func _min_rise(pk: Parkour, n: int) -> float:
	var m := INF
	for i in range(1, n):
		if pk.box_at(i - 1).size.x <= 0.0 or pk.box_at(i).size.x <= 0.0:
			continue
		m = minf(m, pk.top_at(i) - pk.top_at(i - 1))
	return m


func _profile(pk: Parkour, n: int) -> String:
	var out: Array[String] = []
	for i in n:
		if pk.box_at(i).size.x <= 0.0:
			continue
		out.append("%s %.2f" % [pk.label_at(i), pk.top_at(i)])
	return "  ".join(PackedStringArray(out))


func _draw(pk: Parkour, n: int) -> String:
	var cols := int((X1 - X0) / CELL)
	var rows := int((Z1 - Z0) / CELL)
	var grid: Array = []
	for _r in rows:
		grid.append(".".repeat(cols))
	var starts: Array[int] = []
	for s in pk.segment_count():
		starts.append(pk.segment_start(s))
	for r in rows:
		for c in cols:
			var x := X0 + (float(c) + 0.5) * CELL
			var z := Z0 + (float(r) + 0.5) * CELL
			if x >= -20.0 and absf(z) <= 20.0:
				_put(grid, c, r, "_")
			if x >= -20.0 and x <= -10.0 and z >= 2.5 and z <= 5.5:
				_put(grid, c, r, "=")
	for i in range(1, n):
		var b := pk.box_at(i)
		if b.size.x <= 0.0:
			continue
		var ch := "*"
		if pk.label_at(i) == "Island":
			ch = "T"
		elif b.size.z <= 0.9:
			ch = "-"
		elif i in starts:
			ch = "S"
		var c0 := int(floor((b.position.x - X0) / CELL))
		var c1 := int(ceil((b.position.x + b.size.x - X0) / CELL))
		var r0 := int(floor((b.position.z - Z0) / CELL))
		var r1 := int(ceil((b.position.z + b.size.z - Z0) / CELL))
		for r in range(r0, r1):
			for c in range(c0, c1):
				_put(grid, c, r, ch)
	var out: Array[String] = []
	var head := "      "
	var tick := "      "
	for c in cols:
		var x := X0 + (float(c) + 0.5) * CELL
		var v := int(absf(x))
		head += "%d" % (v / 10 % 10) if v % 20 == 0 else " "
		tick += "-" if v % 20 == 0 else " "
	out.append(head)
	out.append(tick)
	for r in rows:
		out.append("%5d %s" % [int(Z0 + (float(r) + 0.5) * CELL), String(grid[r])])
	return "\n".join(PackedStringArray(out))


func _put(grid: Array, c: int, r: int, ch: String) -> void:
	if r < 0 or r >= grid.size():
		return
	var line := String(grid[r])
	if c < 0 or c >= line.length():
		return
	grid[r] = line.substr(0, c) + ch + line.substr(c + 1)


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
