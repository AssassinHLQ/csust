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
@export var debt_min := 120
@export var debt_max := 980
## 强平后的冷却（秒）：别让同一次碰撞连扣八次
@export var cooldown := 1.2

## 累计负债（万）/ 强平次数 / 薛定谔坍缩次数
var debt := 0
var liquidations := 0
var collapses := 0

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
var _banner: Label
var _flash: ColorRect


func _ready() -> void:
	_rng.seed = 2067
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
	_build_hud()
	print("[Futures] 期货通就位：会动的块 %d、蓝块 %d、薛定谔块 %d"
		% [drifts.size(), hazards.size(), schro.size()])


# --- 造东西 ---------------------------------------------------------------------

func _index_of(label: String) -> int:
	for i in _pk.node_count():
		if _pk.label_at(i) == label:
			return i
	return -1


func _box_named(label: String) -> AABB:
	var i := _index_of(label)
	return _pk.box_at(i) if i >= 0 else AABB()


func _top_named(label: String) -> float:
	var i := _index_of(label)
	return _pk.top_at(i) if i >= 0 else 0.0


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


## 究极蓝块：预警（半透明）→ 实体 → 消失，循环。「突然出现」= 从无到有、还带自发光。
func _make_hazard(near: String, phase_offset: float) -> void:
	var b := _box_named(near)
	if b.size.x <= 0.0:
		return
	var c := b.position + b.size * 0.5
	var n := Node3D.new()
	n.name = "MarginCall_%s" % near
	# ⚠️ 不能吊在板心正上方：那样「站着不动」每 9 秒必死一次，跑酷就变成等红灯了。
	#    挪到板沿外 1.9 m：站中心安全，但**落偏到板边**就会被逮到 —— 这才是「强平」该有的味道。
	n.position = Vector3(c.x, b.position.y + b.size.y + 1.2, c.z + 2.2)
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
	_debt_label.text = "保证金 ¥1000 万　负债 ¥0 万"
	_hud_layer.add_child(_debt_label)

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
	_tick_hazards()
	_tick_schro()


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

func liquidate() -> void:
	if _cool > 0.0:
		return
	_cool = cooldown
	liquidations += 1
	var loss := _rng.randi_range(debt_min, debt_max)
	debt += loss
	_update_debt()
	_banner_text("强制平仓！本金归零　负债 +%d 万" % loss, BLUE)
	_flash_screen()
	Sfx.play("ui_close", 8.0)
	if _player != null and _pk != null:
		_player.global_position = _pk.respawn_point(_pk.respawn_station())
		_player.velocity = Vector3.ZERO
	liquidated.emit(debt, loss)


func _update_debt() -> void:
	if _debt_label == null:
		return
	_debt_label.text = "保证金 ¥0 万　负债 ¥%d 万　强平 %d 次" % [debt, liquidations]


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
