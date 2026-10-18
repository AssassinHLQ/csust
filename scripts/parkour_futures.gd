class_name ParkourFutures
extends Node3D
## 第 3 段「同花顺期货通」的运行期总控。**场景里只有一个空节点**
## （`scenes/parkour.tscn` 的 `Futures`），会动的方块 / 蓝块强平 / 薛定谔坍缩 / 负债 HUD
## 全部在 `_build()` 里按**路线上的落脚板**算出来 —— 几何的唯一真相仍然是那 13 块板。
##
## 用户原话：「三阶段同花顺其实是：同花顺期货通，出现究极蓝色方块，地形更加复杂，
## 不是一直往前，而是四面八方的红绿块，突然出现的蓝块则是强制平仓，不仅本金全部
## 打水漂，还会背上巨额债务。方块会上下移动，有的甚至会左右移动，还有布朗运动，
## 同时还会出现薛定谔的方块，在你踩上去之前，不知道是什么颜色。」
##
## ── 四个机制 ──
## 1. **升降台 / 平移台 / 布朗块**（`parkour_drift.gd`）：两块板之间那条「直跳过不去」的
##    裂缝里放一块会动的板（缺口 6.0 / 6.2 m > 射程，绕不过去）。
## 2. **究极蓝块 = 强制平仓**：每 `blue_period` 秒一轮，先 `blue_warn` 秒半透明预警、
##    再 `blue_live` 秒实体。碰到就**爆仓**：本金归零、负债累加、屏幕白闪、送回检查点。
## 3. **薛定谔块**：踩上去之前是灰紫色（场景里带 `metadata/schrodinger` 的那三块），
##    第一次踩到时才坍缩成红（阳线）/ 绿（阴线），涨跌幅牌子也是那时才写。
## 4. **负债 HUD**：右上角一路累加，强平横幅闪一下就走。
##
## 5. **第 4 段「比特币三线」**（2026-10-18）：分叉台 `J0` 之后三条平行道
##    （现货 `SP1..3` / 永续 `PP1..3` / 币圈 `BC1..3`），各 3 块 + 1 个渡船，
##    最后并到结算台 `M0`。三道的**牌价规则不一样**（固定 / 两档交替 / 四档轮转），
##    所以「踩哪一块、什么时候踩」是决策而不是运气；保证金够 11 万就在 `M0`
##    解锁「对冲」，之后强平块只扣 35% 不爆仓。
##
## ⚠️ 判「踩到蓝块」用的是**盒子重叠**，不是 `Area3D.body_entered`：
##    蓝块是「凭空出现」的，人可能**已经站在里面**才轮到它变实体，`body_entered`
##    那一刻根本不会发。

signal liquidated(debt_total: int, loss: int)
signal collapsed(plate: String, up: bool, pct: float)

const BLUE := Color(0.16, 0.55, 1.0)
const SCH_UP := Color(0.82, 0.13, 0.17)
const SCH_DN := Color(0.09, 0.55, 0.29)
const SCH_UNKNOWN := Color(0.34, 0.30, 0.46)

## 一轮蓝块周期 / 预警时长 / 实体时长（秒）
@export var blue_period := 9.0
@export var blue_warn := 2.0
@export var blue_live := 3.0
## 强平一次欠多少（万）
@export var debt_min := 2
@export var debt_max := 9
## 强平后的冷却（秒）：别让同一次碰撞连扣八次
@export var cooldown := 1.2
## 初始保证金（万）—— 用户 2026-10-18：「修改保证金初始是 10w」
@export var start_margin := 10.0
## 在结算台 M0 上，保证金 ≥ 这个数就解锁「对冲」
@export var hedge_target := 11.0
## 对冲之后，强平块只扣当前保证金的这个比例（不再爆仓）
@export var hedge_cut := 0.35

## ── 账户（单位：万）──
## `margin` = 保证金（真实结算：每块 K 线第一次踩上去，就按它牌子上那个涨跌幅结算一次）
## `debt`   = 负债（强平累加）/ `liquidations` 强平次数 / `collapses` 薛定谔坍缩次数
var margin := 10.0
var debt := 0
var liquidations := 0
var collapses := 0
## 结算过几次 / 最近一次结算的文案
var settlements := 0
var _last_settle := ""
## 已经结算过的板（一块只结算一次，免得来回走刷钱）
var settled := {}
## 13 块 K 线的包围盒 + 台面 + 牌子（结算要用）
var plates: Array[Dictionary] = []
## 第 4 段：会跳价的牌子（现货 / 永续 / 币圈）—— 每帧按 `pct_period` 换档
var quotes: Array[Dictionary] = []
## 在 M0 上解锁的「对冲」：之后强平块只扣钱、不爆仓
var hedged := false
var _hedge_checked := false
## 期权那一段的「到期」总开关：第一次踩到 opt 系的板时记时，行权超时 → 0%
var _opt_t0 := -1.0

var drifts: Array[ParkourDrift] = []
var hazards: Array[Node3D] = []
var schro: Array[Node3D] = []

var _pk: Parkour
var _player: Player
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _cool := 0.0
var _hud_layer: CanvasLayer
var _debt_label: Label
var _result_label: Label
var _banner: Label
var _flash: ColorRect


func _ready() -> void:
	_rng.seed = 2067
	margin = start_margin
	_build.call_deferred()


func _build() -> void:
	_pk = get_parent() as Parkour
	if _pk == null:
		push_warning("[Futures] 父节点不是 Parkour，期货通不工作")
		return
	_make_drift("K5", "K6", ParkourDrift.Mode.LIFT, 2.4, 1.8)
	_make_drift("K7", "K8", ParkourDrift.Mode.SLIDE, 1.8, 2.2)
	_make_drift("K9", "K10", ParkourDrift.Mode.BROWNIAN, 1.8, 1.4)
	_make_hazard("K4", 0.0)
	_make_hazard("K9", blue_period / 3.0)
	_make_hazard("K12", blue_period * 2.0 / 3.0)
	_collect_schro()
	_collect_quotes()
	_collect_plates()
	_build_branch()
	_build_hud()
	print("[Futures] 期货通就位：会动的块 %d、蓝块 %d、薛定谔块 %d、跳价牌 %d"
		% [drifts.size(), hazards.size(), schro.size(), quotes.size()])


## 第 4 段：三条道各一个渡船 + 蓝块 + 结算台。
## 三道在 z 上拉开 9 m（跨道缺口 6 m > 平地直跳 5.09 m，跳不过去）。
func _build_branch() -> void:
	# 现货道：慢速渡船（最稳）
	_make_ferry_x("SP2", "SP3", 3.0, 1.6, 1.5)
	# 永续道：中速渡船 + 爬 0.6 m
	_make_ferry_x("PP2", "PP3", 2.6, 1.4, 1.5)
	# 币圈道：**快船、到岸只停 1 s**（「见顶回落」——不等你就跟着船回去了）
	_make_ferry_x("BC2", "BC3", 2.6, 2.2, 1.0)
	# 蓝块：币圈道两个（落偏就爆），结算台之后两个（对冲有没有解锁，从这里开始不一样）
	_make_hazard("BC1", 0.0)
	_make_hazard("BC3", blue_period * 0.5)
	_make_hazard("M0", blue_period * 0.25, 5.5)
	_make_hazard("M0", blue_period * 0.75, -5.5)
	print("[Futures] 第 4 段三线：现货 %s / 永续 %s / 币圈 %s；结算门槛 %.0f 万"
		% [_quote_summary("A"), _quote_summary("B"), _quote_summary("C"), hedge_target])


func _quote_summary(lane: String) -> String:
	var n := 0
	var lo := 999.0
	var hi := -999.0
	for q in quotes:
		if String((q["node"] as Node3D).get_meta("lane", "")) != lane:
			continue
		n += 1
		for v in (q["seq"] as Array):
			lo = minf(lo, float(v))
			hi = maxf(hi, float(v))
	if n == 0:
		return "（没有跳价牌）"
	return "%d 块 %+.1f%% ~ %+.1f%%" % [n, lo, hi]


# --- 造东西 ---------------------------------------------------------------------

func _index_of(label: String) -> int:
	for i in _pk.node_count():
		if _pk.label_at(i) == label:
			return i
	return -1


func _box_named(label: String) -> AABB:
	var i := _index_of(label)
	if i >= 0:
		return _pk.box_at(i)
	# 第 4 段的永续道 / 币圈道**不在 `route` 里**（走它们不算检查点），
	# 所以不能只查 route —— 直接按节点名去 `Route` 底下捞。
	var n := _pk.get_node_or_null("Route/" + label) as Node3D
	return _aabb_of(n) if n != null else AABB()


func _top_named(label: String) -> float:
	var i := _index_of(label)
	if i >= 0:
		return _pk.top_at(i)
	var b := _box_named(label)
	return b.position.y + b.size.y


## 一个站的包围盒：优先用 `Col`（碰撞就是真值），没有就退回 Mesh 的 AABB。
func _aabb_of(n: Node3D) -> AABB:
	if n == null:
		return AABB()
	var col := n.get_node_or_null("Col") as CollisionShape3D
	if col != null and col.shape is BoxShape3D:
		var s: Vector3 = (col.shape as BoxShape3D).size
		return col.global_transform * AABB(-s * 0.5, s)
	var mi := n.get_node_or_null("Mesh") as MeshInstance3D
	if mi != null and mi.mesh != null:
		return mi.global_transform * mi.get_aabb()
	return AABB()


## 两块板之间放一块会动的板。
##
## 位置是**算出来的**：x 取两块板之间那条缺口的中点；y 取「低的那块板面」
## （登船平、到岸也平）；平移台的 z 两端各压住岸边 0.30 m。
func _make_drift(a_name: String, b_name: String, mode: int, size_z: float,
		move_speed: float) -> void:
	var a := _box_named(a_name)
	var b := _box_named(b_name)
	if a.size.x <= 0.0 or b.size.x <= 0.0:
		push_warning("[Futures] 找不到 %s / %s" % [a_name, b_name])
		return
	var ac := a.position + a.size * 0.5
	var bc := b.position + b.size * 0.5
	var top_a := a.position.y + a.size.y
	var top_b := b.position.y + b.size.y
	var low := minf(top_a, top_b)
	var size := Vector3(2.4, 0.4, size_z)
	var d := ParkourDrift.new()
	d.name = "Drift_%s" % a_name
	d.mode = mode
	d.speed = move_speed
	var x := (ac.x + bc.x) * 0.5
	if mode == ParkourDrift.Mode.LIFT:
		d.point_a = Vector3(x, low - size.y * 0.5, (ac.z + bc.z) * 0.5)
		d.point_b = Vector3(x, maxf(top_a, top_b) - size.y * 0.5, (ac.z + bc.z) * 0.5)
	elif mode == ParkourDrift.Mode.SLIDE:
		d.point_a = Vector3(x, low - size.y * 0.5,
			ac.z - a.size.z * 0.5 - size_z * 0.5 + 0.30)
		d.point_b = Vector3(x, low - size.y * 0.5,
			bc.z + b.size.z * 0.5 + size_z * 0.5 - 0.30)
	else:
		size = Vector3(1.8, 0.4, 1.8)
		d.roam = 2.2
		# ⚠️ 不能浮在跳跃弧线正上方：K9→K10 的跳跃顶点 6.66 m，它原来吊在 6.6 m，
		#    真输入回放一跳就撞到它底面掉下去。现在**和板面齐平、往南让开 3.2 m**。
		d.position = Vector3(x, minf(top_a, top_b) - size.y * 0.5,
			(ac.z + bc.z) * 0.5 - 3.2)
	add_child(d)
	d.add_child(_block_mesh(size, Color(0.95, 0.72, 0.18)
		if mode != ParkourDrift.Mode.BROWNIAN else Color(0.85, 0.42, 0.75)))
	d.add_child(_block_col(size))
	drifts.append(d)


## **沿 x 走的渡船**（第 4 段三道用）。
##
## ⚠️ 不能直接复用 `_make_drift()` 的 LIFT / SLIDE：那两台的端点是「一上一下」和
##    「z 方向左右」，而三道是**一条直线往西**、缺口在 x 上 —— 照抄 SLIDE 会让船
##    飘到隔壁道去（第一版就这么翻车的：人站上去被带走，然后掉进真空）。
##    这里显式给两个端点，y 跟着两岸的台面走（B 道、C 道都是爬上坡）。
## 停船位置离岸边 **0.7 m**：胶囊半径 0.3，缝再小就「腿够长」直接跨过去了。
func _make_ferry_x(a_name: String, b_name: String, size_z: float, move_speed: float,
		hold: float) -> void:
	var a := _box_named(a_name)
	var b := _box_named(b_name)
	if a.size.x <= 0.0 or b.size.x <= 0.0:
		push_warning("[Futures] 找不到 %s / %s" % [a_name, b_name])
		return
	var top_a := a.position.y + a.size.y
	var top_b := b.position.y + b.size.y
	var size := Vector3(2.4, 0.4, size_z)
	var z := (a.position.z + a.size.z * 0.5 + b.position.z + b.size.z * 0.5) * 0.5
	var d := ParkourDrift.new()
	d.name = "Ferry_%s" % a_name
	d.mode = ParkourDrift.Mode.LIFT      # 端点自己给，mode 只是个标签
	d.speed = move_speed
	d.wait_time = hold
	d.point_a = Vector3(a.position.x - 1.9, top_a - size.y * 0.5, z)
	d.point_b = Vector3(b.position.x + b.size.x + 1.9, top_b - size.y * 0.5, z)
	d.position = d.point_a
	add_child(d)
	d.add_child(_block_mesh(size, Color(0.95, 0.72, 0.18)))
	d.add_child(_block_col(size))
	drifts.append(d)


## 究极蓝块：预警（半透明）→ 实体 → 消失，循环。「突然出现」= 从无到有、还带自发光。
## `dz`：沿 z 挪多远（结算台 22 m 宽，两个蓝块得分开摆，不然叠成一坨）。
func _make_hazard(near: String, phase_offset: float, dz := 2.2) -> void:
	var b := _box_named(near)
	if b.size.x <= 0.0:
		return
	var c := b.position + b.size * 0.5
	var n := Node3D.new()
	n.name = "MarginCall_%s_%+.1f" % [near, dz]
	# ⚠️ 不能吊在板心正上方：那样「站着不动」每 9 秒必死一次，跑酷就变成等红灯了。
	#    挪到板沿外 1.9 m：站中心安全，但**落偏到板边**就会被逮到 —— 这才是「强平」该有的味道。
	n.position = Vector3(c.x, b.position.y + b.size.y + 1.2, c.z + dz)
	n.set_meta("offset", phase_offset)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.9, 1.6, 1.9)
	mi.mesh = mesh
	mi.material_override = _mat(BLUE, 0.9, 0.32)
	n.add_child(mi)
	n.set_meta("mesh", mi)
	n.visible = false
	add_child(n)
	hazards.append(n)


## 把 13 块 K 线（站名 `K1`…`K13`）连包围盒一起收进来 —— 结算要看「踩在哪块上」。
func _collect_plates() -> void:
	for i in _pk.node_count():
		var nm := _pk.label_at(i)
		if not nm.begins_with("K") or not nm.substr(1).is_valid_int():
			continue
		_add_plate(nm, _pk.get_node_or_null(NodePath(String(_pk.route[i]))), _pk.box_at(i),
			_pk.top_at(i))
	# 第 4 段三道：牌子会跳，但结算规则一样 —— **踩上去那一刻的牌价就是结算价**
	for q in quotes:
		var n := q["node"] as Node3D
		var b := _aabb_of(n)
		_add_plate(String(n.name), n, b, b.position.y + b.size.y)


func _add_plate(nm: String, node: Node, b: AABB, top: float) -> void:
	if node == null or b.size.x <= 0.0:
		return
	plates.append({"name": nm, "node": node,
		"x0": b.position.x, "x1": b.position.x + b.size.x,
		"z0": b.position.z, "z1": b.position.z + b.size.z, "top": top})


## 第 4 段的跳价牌，靠 `metadata/pct_kind` 认：
##   `spot` 现货 —— `pct_seq` 只有一档，永不跳（稳）
##   `swap` 永续 —— 两档交替，`period` 秒一轮（看时机）
##   `btc`  币圈 —— 四档轮转，波动最大（赌）
func _collect_quotes() -> void:
	var route := _pk.get_node_or_null("Route")
	if route == null:
		return
	for child in route.get_children():
		var n := child as Node3D
		if n == null or not n.has_meta("pct_kind"):
			continue
		var lab := n.get_node_or_null("Pct") as Label3D
		if lab == null:
			continue
		var seq: Array[float] = []
		for v in String(n.get_meta("pct_seq")).split(","):
			seq.append(float(v))
		if seq.is_empty():
			continue
		quotes.append({
			"node": n, "label": lab, "kind": String(n.get_meta("pct_kind")),
			"seq": seq, "period": float(n.get_meta("pct_period", 0.0)),
			"phase": float(n.get_meta("pct_phase", 0.0)), "last": "", "deadline": 0.0,
		})
		quotes[-1]["deadline"] = float(n.get_meta("deadline", 0.0))


## 每帧刷新跳价牌 —— 只有数字真变了才写 Label（一帧改 9 个 Label3D 会掉帧）
func _tick_quotes() -> void:
	for q in quotes:
		var seq: Array = q["seq"]
		var pct := float(seq[0])
		var period := float(q["period"])
		if period > 0.01 and seq.size() > 1:
			var step := period / float(seq.size())
			var t := fmod(_t + float(q["phase"]), period)
			pct = float(seq[mini(int(t / step), seq.size() - 1)])
		var txt := "%+.2f%%" % pct
		# 期权：牌子上带倒计时（「12.0s」→ 0 就作废），踩上去之前就能看见剩余时间
		var dl := float(q["deadline"])
		if dl > 0.0 and _opt_t0 >= 0.0:
			txt += "  %.1fs" % maxf(0.0, dl - (_t - _opt_t0))
		if txt == String(q["last"]):
			continue
		q["last"] = txt
		var lab := q["label"] as Label3D
		if lab == null:
			continue
		lab.text = txt
		lab.modulate = Color(1.0, 0.35, 0.35) if pct >= 0.0 else Color(0.35, 1.0, 0.55)


func _collect_schro() -> void:
	var route := _pk.get_node_or_null("Route")
	if route == null:
		return
	for child in route.get_children():
		if child is Node3D and (child as Node3D).has_meta("schrodinger"):
			var st := child as Node3D
			var i := _index_of(String(st.name))
			st.set_meta("top", _pk.top_at(i))
			var b := _pk.box_at(i)
			st.set_meta("x0", b.position.x)
			st.set_meta("x1", b.position.x + b.size.x)
			st.set_meta("z0", b.position.z)
			st.set_meta("z1", b.position.z + b.size.z)
			schro.append(st)


func _block_mesh(size: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = _mat(col, 0.35, 1.0)
	return mi


func _block_col(size: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	return cs


func _mat(col: Color, emission: float, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.metallic = 0.15
	m.roughness = 0.5
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emission
	return m


# --- HUD ---------------------------------------------------------------------

func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "FuturesHUD"
	_hud_layer.layer = 2
	add_child(_hud_layer)

	_debt_label = Label.new()
	_debt_label.name = "Debt"
	_debt_label.anchor_left = 1.0
	_debt_label.anchor_right = 1.0
	_debt_label.offset_left = -620.0
	_debt_label.offset_right = -28.0
	_debt_label.offset_top = 100.0
	_debt_label.offset_bottom = 136.0
	_debt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_debt_label.add_theme_font_size_override("font_size", 22)
	_debt_label.add_theme_color_override("font_color", Color(1.0, 0.62, 0.62, 1))
	_debt_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_debt_label.add_theme_constant_override("outline_size", 6)
	_debt_label.text = "保证金 ¥%.2f 万　负债 ¥0 万　强平 0 次" % margin
	_hud_layer.add_child(_debt_label)

	# 第二行：最近一次结算（踩板时 +2.31% / −3.87% 就写在这儿，钱也跟着变）
	_result_label = Label.new()
	_result_label.name = "Result"
	_result_label.anchor_left = 1.0
	_result_label.anchor_right = 1.0
	_result_label.offset_left = -620.0
	_result_label.offset_right = -28.0
	_result_label.offset_top = 136.0
	_result_label.offset_bottom = 168.0
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_result_label.add_theme_font_size_override("font_size", 19)
	_result_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95, 1))
	_result_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_result_label.add_theme_constant_override("outline_size", 5)
	_result_label.text = "最近结算：—"
	_hud_layer.add_child(_result_label)

	_banner = Label.new()
	_banner.name = "Banner"
	_banner.anchor_left = 0.5
	_banner.anchor_right = 0.5
	_banner.offset_left = -520.0
	_banner.offset_right = 520.0
	_banner.offset_top = 150.0
	_banner.offset_bottom = 230.0
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 46)
	_banner.add_theme_color_override("font_color", BLUE)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_banner.add_theme_constant_override("outline_size", 10)
	_banner.text = ""
	_banner.modulate.a = 0.0
	_hud_layer.add_child(_banner)

	_flash = ColorRect.new()
	_flash.name = "Flash"
	_flash.color = Color(0.85, 0.93, 1.0, 0.0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(_flash)


# --- 每帧 ---------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _pk == null:
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Player
	_t += delta
	_cool = maxf(0.0, _cool - delta)
	_tick_quotes()
	_tick_hazards()
	_tick_schro()
	_tick_plates()


func _tick_hazards() -> void:
	var live_from := blue_period - blue_live
	var warn_from := live_from - blue_warn
	for h in hazards:
		var phase := fmod(_t + float(h.get_meta("offset")), blue_period)
		var live := phase >= live_from
		var warn := phase >= warn_from and not live
		h.visible = live or warn
		var mi := h.get_meta("mesh") as MeshInstance3D
		if mi != null and mi.material_override is StandardMaterial3D:
			var m := mi.material_override as StandardMaterial3D
			# 预警半透明，实体不透明；「实体」那一瞬间有一下提亮
			m.albedo_color.a = 1.0 if live else 0.32
			m.emission_energy_multiplier = 2.2 if live else 0.9
		if live and _player != null and _cool <= 0.0 and _inside(h.global_position,
				_player.global_position + Vector3(0, 0.9, 0)):
			liquidate()


func _inside(center: Vector3, p: Vector3) -> bool:
	return absf(p.x - center.x) < 1.10 and absf(p.z - center.z) < 1.10 \
		and absf(p.y - center.y) < 1.30


func _tick_schro() -> void:
	if _player == null:
		return
	for plate in schro:
		if plate.has_meta("resolved"):
			continue
		var top := float(plate.get_meta("top"))
		var p := _player.global_position
		if absf(p.y - top) > 0.45:
			continue
		if p.x < float(plate.get_meta("x0")) - 0.25 or p.x > float(plate.get_meta("x1")) + 0.25:
			continue
		if p.z < float(plate.get_meta("z0")) - 0.25 or p.z > float(plate.get_meta("z1")) + 0.25:
			continue
		_resolve(plate, top)


## 结算：**每块 K 线第一次踩上去**，按它牌子上那个涨跌幅结算一次保证金。
##
## ⚠️ 牌子上写的就是真数：`+2.31%` 就是保证金 ×1.0231，`−3.87%` 就是 ×0.9613。
##    薛定谔块先坍缩（`_tick_schro` 在上一行跑）再结算，所以「踩上去才知道」这件事
##    真的会体现在钱上 —— 这是用户问「踩了 −3.87% 为什么保证金不掉」之后补的。
func _tick_plates() -> void:
	if _player == null:
		return
	var p := _player.global_position
	for pl in plates:
		if settled.has(pl["name"]):
			continue
		if absf(p.y - float(pl["top"])) > 0.45:
			continue
		if p.x < float(pl["x0"]) - 0.25 or p.x > float(pl["x1"]) + 0.25:
			continue
		if p.z < float(pl["z0"]) - 0.25 or p.z > float(pl["z1"]) + 0.25:
			continue
		_settle(pl)
	# 结算台 M0：保证金够门槛就解锁「对冲」（一次判定，站在上面就触发）
	if _hedge_checked:
		return
	var mb := _box_named("M0")
	if mb.size.x <= 0.0:
		return
	var mt := mb.position.y + mb.size.y
	if absf(p.y - mt) > 0.45:
		return
	if p.x < mb.position.x - 0.25 or p.x > mb.position.x + mb.size.x + 0.25:
		return
	if p.z < mb.position.z - 0.25 or p.z > mb.position.z + mb.size.z + 0.25:
		return
	_hedge_checked = true
	_try_hedge()


## 结算台结算：够 11 万 → 本段剩下的强平块只扣钱；不够 → 照旧爆仓（这就是「决策」的代价）
func _try_hedge() -> void:
	if margin >= hedge_target:
		hedged = true
		_banner_text("保证金 %.2f 万 → 解锁「对冲」：强平只扣 %.0f%%"
			% [margin, hedge_cut * 100.0], Color(0.45, 1.0, 0.55))
		Sfx.play("ui_toggle", 2.0)
	else:
		_banner_text("保证金 %.2f 万 < %.0f 万：未解锁对冲"
			% [margin, hedge_target], Color(1.0, 0.72, 0.35))
	_update_merge_sign()


func _update_merge_sign() -> void:
	var sign_node := _pk.get_node_or_null("Route/M0/Sign_M0") as Label3D
	if sign_node == null:
		return
	var gain := margin / maxf(start_margin, 0.001) - 1.0
	sign_node.text = "结算台\n本段 %.2f 万（%+.1f%%）\n对冲：%s" % [
		margin, gain * 100.0, "已解锁" if hedged else "未解锁"]


func _settle(pl: Dictionary) -> void:
	var node := pl["node"] as Node3D
	if node == null:
		return
	var lab := node.get_node_or_null("Pct") as Label3D
	if lab == null:
		return
	var pct := _parse_pct(lab.text)
	if is_nan(pct):
		return                       # 薛定谔还没坍缩（牌子还是「?」）→ 下一帧再说
	# 期权：第一次踩到 opt 系的板就开始计时；超时的「行权」按 0% 结算（买方作废）
	var kind := String(node.get_meta("pct_kind", ""))
	var dl := float(node.get_meta("deadline", 0.0))
	if kind.begins_with("opt") and _opt_t0 < 0.0:
		_opt_t0 = _t
	if dl > 0.0 and _opt_t0 >= 0.0 and _t - _opt_t0 > dl:
		pct = 0.0
		_banner_text("期权到期：行权作废（0%）", Color(1.0, 0.72, 0.35))
	settled[pl["name"]] = true
	var before := margin
	margin = maxf(0.0, margin * (1.0 + pct / 100.0))
	settlements += 1
	_last_settle = "最近结算：%s %+.2f%%　%+.2f 万" % [pl["name"], pct, margin - before]
	if _result_label != null:
		_result_label.text = _last_settle
		_result_label.add_theme_color_override("font_color",
			Color(1.0, 0.55, 0.55, 1) if pct < 0.0 else Color(0.55, 1.0, 0.65, 1))
	_update_hud_text()
	Sfx.play("ui_slider", 0.0)
	if margin <= 0.0:
		liquidate("保证金耗尽")


## 从牌子文字里取百分比：「+2.31%」→ 2.31；「?」/空 → NAN
func _parse_pct(t: String) -> float:
	# 牌子上可能带倒计时（「+25.00%  8.4s」）—— 只取 `%` 之前那段
	var v := t.strip_edges()
	var k := v.find("%")
	if k >= 0:
		v = v.substr(0, k)
	v = v.replace("＋", "+").strip_edges()
	if v.is_empty() or not (v.is_valid_float() or (v.begins_with("+") and v.substr(1).is_valid_float())):
		return NAN
	return v.to_float()


## 薛定谔坍缩：红（阳线）/ 绿（阴线）各一半，涨跌幅随机 1.0 ~ 15.0%。
func _resolve(plate: Node3D, _top: float) -> void:
	plate.set_meta("resolved", true)
	var up := _rng.randf() < 0.5
	var pct := _rng.randf_range(1.0, 15.0)
	var mesh := plate.get_node_or_null("Mesh") as MeshInstance3D
	if mesh != null:
		mesh.material_override = _mat(SCH_UP if up else SCH_DN, 0.30, 1.0)
	var lab := plate.get_node_or_null("Pct") as Label3D
	if lab != null:
		lab.text = "%s%.2f%%" % ["+" if up else "-", pct]
		lab.modulate = Color(1, 0.35, 0.35) if up else Color(0.35, 1, 0.55)
	collapses += 1
	Sfx.play("ui_toggle", 2.0)
	collapsed.emit(String(plate.name), up, pct)


# --- 强制平仓 ----------------------------------------------------------------

func liquidate(reason := "强制平仓") -> void:
	if _cool > 0.0:
		return
	_cool = cooldown
	liquidations += 1
	# **对冲**：在结算台 M0 上保证金够 11 万就解锁了 —— 之后只是扣钱，不会爆仓送回。
	# 这是「第 4 段选哪条道」的直接后果：现货道（+9.27%）注定够不着门槛。
	if hedged:
		var cut := margin * hedge_cut
		margin = maxf(0.0, margin - cut)
		debt += int(round(cut))
		if margin <= 0.0:
			margin = start_margin
		_update_hud_text()
		_banner_text("对冲生效：%s 只扣 %.2f 万（剩 %.2f 万）"
			% [reason, cut, margin], Color(0.55, 0.9, 1.0))
		_flash_screen()
		Sfx.play("ui_toggle", 6.0)
		liquidated.emit(debt, int(round(cut)))
		return
	var loss := _rng.randi_range(debt_min, debt_max)
	debt += loss
	margin = 0.0
	_update_hud_text()
	_banner_text("%s！本金归零　负债 +%d 万" % [reason, loss], BLUE)
	_flash_screen()
	Sfx.play("ui_close", 8.0)
	if _player != null and _pk != null:
		_player.global_position = _pk.respawn_point(_pk.respawn_station())
		_player.velocity = Vector3.ZERO
	# 0.9 s 之后「重新开仓」：不这么做的话，一次爆仓之后整局就没钱可掉了
	# （负债留着、越滚越大，那才是这段的主题）
	var tw := create_tween()
	tw.tween_interval(0.9)
	tw.tween_callback(func() -> void:
		margin = start_margin
		_update_hud_text()
		if _result_label != null:
			_result_label.text = "重新开仓：保证金 ¥%.2f 万（负债不清）" % start_margin)
	liquidated.emit(debt, loss)


func _update_hud_text() -> void:
	if _debt_label == null:
		return
	_debt_label.text = "保证金 ¥%.2f 万　负债 ¥%d 万　强平 %d 次%s" % [
		margin, debt, liquidations, "　对冲✓" if hedged else ""]


func _banner_text(text: String, col: Color) -> void:
	if _banner == null:
		return
	_banner.text = text
	_banner.add_theme_color_override("font_color", col)
	_banner.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.9)


func _flash_screen() -> void:
	if _flash == null:
		return
	_flash.color.a = 0.75
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.0, 0.55)
