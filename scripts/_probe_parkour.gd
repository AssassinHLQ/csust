extends SceneTree
## 探针：把跑酷路线的**设计依据**打出来（不跑物理，几秒就完）。
##
## 这是「设计 → 建模 → 验证」里的**设计**那一半：每一跳跨多远、抬多高、
## 解析弹道能到多远、余量多少、落点在板内的哪里 —— 全部来自
## `parkour.gd::hop_analysis()`（自检用的是同一个函数，所以文档和断言不会走散）。
##
## 另外画一张**俯视 ASCII 图**：跑酷是一条又长又窄的线，文字表格看不出形状，
## 图一眼就能看出「板在平台的哪一侧、朝哪个方向甩出去、最后一个区域多大」。
##
## 用法：
##   godot --path <工程> --script res://scripts/_probe_parkour.gd -- --splat=off
##
## ⚠️ 加 `--splat=off`：跑酷不依赖画室609，关掉泼溅能省 20 s 解码。
## ⚠️ 要真渲染，不要 `--headless`。

## 图的范围（米）
const X0 := -98.0
const X1 := -6.0
const Z0 := -10.0
const Z1 := 14.0
const CELL := 1.0

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
	print("========== 0. 路线 ==========")
	print("落脚点 %d 个（顺序就是路线顺序）：" % n)
	var names: Array[String] = []
	for i in n:
		names.append(pk.label_at(i))
	print("  " + " → ".join(PackedStringArray(names)))
	print("玩家跑速 %.2f m/s、起跳 %.2f m/s、重力 %.1f m/s²（来自 player.gd）"
		% [Player.SPEED_RUN, Player.JUMP_VELOCITY, Player.GRAVITY])

	# ── 1. 每一站的世界包围盒 ──────────────────────────────────────────────
	print("\n========== 1. 落脚点（世界坐标，台面 = 顶面）==========")
	print("（`Launch` 是画在平台地面上的**标记板**：报的是板顶 0.03，"
		+ "真正的起跳面是平台地面 y = 0.00 —— 差 2.5 cm，对余量无影响）")
	print("%3s %-8s %9s %9s %9s %9s %8s %9s %9s" % [
		"#", "名字", "x最小", "x最大", "z最小", "z最大", "台面", "宽(x)", "深(z)"])
	for i in n:
		var b := pk.box_at(i)
		print("%3d %-8s %9.2f %9.2f %9.2f %9.2f %8.2f %9.2f %9.2f" % [
			i, pk.label_at(i), b.position.x, b.position.x + b.size.x,
			b.position.z, b.position.z + b.size.z, pk.top_at(i), b.size.x, b.size.z])

	# ── 2. 每一跳 ─────────────────────────────────────────────────────────
	print("\n========== 2. 每一跳（解析弹道；实测数字见 _verify_parkour 第 3 节）==========")
	print("%-14s %8s %7s %8s %8s %9s %8s %s" % [
		"这一跳", "必须跨过", "抬升", "滞空", "射程", "余量", "落点入板", "落点"])
	var worst_gap := 0.0
	var worst_name := ""
	var worst_margin := INF
	var worst_margin_name := ""
	for i in range(1, n):
		var a := pk.box_at(i - 1)
		var b := pk.box_at(i)
		if a.size.x <= 0.0 or b.size.x <= 0.0:
			print("%-14s （节点缺失，跳过）" % ("%s→%s" % [pk.label_at(i - 1), pk.label_at(i)]))
			_fail += 1
			continue
		var h := Parkour.hop_analysis(a, b, Player.JUMP_VELOCITY, Player.GRAVITY, Player.SPEED_RUN)
		var pair := "%s→%s" % [pk.label_at(i - 1), pk.label_at(i)]
		if not bool(h["reachable"]):
			print("%-14s %8.2f %7.2f  ** 抬升超过跳跃高度 %.2f m，无解 **"
				% [pair, h["required"], h["rise"],
					Player.JUMP_VELOCITY * Player.JUMP_VELOCITY / (2.0 * Player.GRAVITY)])
			_fail += 1
			continue
		var margin: float = float(h["reach"]) - float(h["required"])
		var land: Vector3 = h["landing"]
		print("%-14s %8.2f %+7.2f %7.3f %8.2f %9.2f %8.2f  (%.3f, %.3f)  %s" % [
			pair, h["required"], h["rise"], h["time"], h["reach"], margin,
			float(h["edge_dist"]), land.x, land.z,
			"✓" if bool(h["inside"]) else "**落点不在板里：会跳过头**"])
		if not bool(h["inside"]):
			_fail += 1
		if margin < worst_margin:
			worst_margin = margin
			worst_margin_name = pair
		if float(h["required"]) > worst_gap and absf(float(h["rise"])) < 0.05:
			worst_gap = float(h["required"])
			worst_name = pair

	print("\n  ★ 最紧的一跳（余量最小）：%s，余量 %.2f m" % [worst_margin_name, worst_margin])
	print("  ★ 最远的平跳：%s，%.2f m（平跳解析上限 %.2f m）"
		% [worst_name, worst_gap, Player.SPEED_RUN * 2.0 * Player.JUMP_VELOCITY / Player.GRAVITY])
	print("  ★ 最大抬升：%.2f m（跳跃峰值 %.2f m）" % [
		_max_rise(pk, n), Player.JUMP_VELOCITY * Player.JUMP_VELOCITY / (2.0 * Player.GRAVITY)])
	print("  ★ 全程水平长度：%.1f m（x %.1f → %.1f）" % [
		_length(pk, n), pk.box_at(0).position.x,
		pk.box_at(n - 1).position.x + pk.box_at(n - 1).size.x])
	print("  ★ 高度剖面：" + _profile(pk, n))
	print("  ★ 解析参考：平跳上限 %.2f m、抬升 0.80 m 时上限 %.2f m、落差 1.00 m 时上限 %.2f m"
		% [_flat_reach(), _rise_reach(0.8), _rise_reach(-1.0)])

	# ── 3. 俯视图 ─────────────────────────────────────────────────────────
	print("\n========== 3. 俯视图（一格 %.0f m，x → 右、z ↓；*=落脚板 T=信号塔岛 =跑道 )==========" % CELL)
	print(_draw(pk, n))

	# ── 4. 与平台上既有东西的关系 ─────────────────────────────────────────
	print("\n========== 4. 与平台的关系 ==========")
	var island := pk.box_at(n - 1)
	print("  平台西边缘 x = −20.00；第一块板东边缘 x = %.2f（离平台 %.2f m 的真空）"
		% [pk.box_at(1).position.x + pk.box_at(1).size.x,
			-pk.box_at(1).position.x - pk.box_at(1).size.x - 20.0])
	print("  跑道（只有外观、无碰撞）x ∈ [−20.00, −10.00]、z ∈ [2.50, 5.50]")
	print("  信号塔岛：中心 (%.2f, %.2f)，%.0f × %.0f m，台面 y = %.2f —— 这就是「下一个区域」"
		% [island.position.x + island.size.x * 0.5, island.position.z + island.size.z * 0.5,
			island.size.x, island.size.z, pk.top_at(n - 1)])
	print("  岛面可走面积 %.0f m²（去掉四角柱/信号塔/掩体后仍留得下东西）"
		% (island.size.x * island.size.z))

	print("\n失败 %d 项" % _fail)
	quit(1 if _fail > 0 else 0)


# --- 小工具 -------------------------------------------------------------------

func _max_rise(pk: Parkour, n: int) -> float:
	var m := -INF
	for i in range(1, n):
		if pk.box_at(i - 1).size.x <= 0.0 or pk.box_at(i).size.x <= 0.0:
			continue
		m = maxf(m, pk.top_at(i) - pk.top_at(i - 1))
	return m


func _length(pk: Parkour, n: int) -> float:
	var a := pk.box_at(0)
	var b := pk.box_at(n - 1)
	return absf((b.position.x + b.size.x) - a.position.x)


func _profile(pk: Parkour, n: int) -> String:
	var out: Array[String] = []
	for i in n:
		if pk.box_at(i).size.x <= 0.0:
			continue
		out.append("%s %.2f" % [pk.label_at(i), pk.top_at(i)])
	return "  ".join(PackedStringArray(out))


## 解析：平跳最远 = 跑速 × 2v/g
func _flat_reach() -> float:
	return Player.SPEED_RUN * 2.0 * Player.JUMP_VELOCITY / Player.GRAVITY


## 解析：抬升 h 时还能跨多远
func _rise_reach(h: float) -> float:
	var disc := Player.JUMP_VELOCITY * Player.JUMP_VELOCITY - 2.0 * Player.GRAVITY * h
	if disc < 0.0:
		return 0.0
	return Player.SPEED_RUN * (Player.JUMP_VELOCITY + sqrt(disc)) / Player.GRAVITY


func _draw(pk: Parkour, n: int) -> String:
	var cols := int((X1 - X0) / CELL)
	var rows := int((Z1 - Z0) / CELL)
	var grid: Array = []
	for _r in rows:
		grid.append(".".repeat(cols))
	# 平台本体（x ≥ −20 的那部分算「地面」）
	for r in rows:
		for c in cols:
			var x := X0 + (float(c) + 0.5) * CELL
			var z := Z0 + (float(r) + 0.5) * CELL
			if x >= -20.0 and absf(z) <= 20.0:
				_put(grid, c, r, "_")
	# 跑道
	for r in rows:
		for c in cols:
			var x := X0 + (float(c) + 0.5) * CELL
			var z := Z0 + (float(r) + 0.5) * CELL
			if x >= -20.0 and x <= -10.0 and z >= 2.5 and z <= 5.5:
				_put(grid, c, r, "=")
	for i in n:
		var b := pk.box_at(i)
		if b.size.x <= 0.0:
			continue
		var ch := "*"
		if i == 0:
			continue
		if i == n - 1:
			ch = "T"
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
		head += "%d" % (int(absf(x)) / 10 % 10) if int(absf(x)) % 10 == 0 else " "
		tick += "-" if int(absf(x)) % 10 == 0 else " "
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
