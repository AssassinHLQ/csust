class_name RamMarket
extends Node3D
## 第 9~10 段「**内存条市场**」—— 2026-10-19 用户：
## 「后面横跳区/螺旋塔全改成内存条区域……一边跑一边躲从天空掉下来的内存条」。
##
## 这个脚本只做**装饰 + 危险物**，**不碰路线几何**：
## 跑酷的站台、碰撞、跳距全部留在 `parkour.tscn` 里原样（245 条自检照样绿），
## 这里只是把「横跳区 → 内存条市场」「绕柱螺旋塔 → 内存条螺旋塔」这套皮披上去。
##
## ── 装饰 ──
## · **平台插槽**：每块站台顶面压一层深绿 PCB + 两条金手指（就像内存条插在槽里）
## · **桁架吊架**：头顶 y ≈ 13.8 一根长桁架，每隔几米垂下一串**倒吊的内存条**
## · **塔身鳍片**：螺旋塔每层向外插三根内存条（散热鳍片的味道）
##
## ── 内存条雨 ──
## 玩家在 x ∈ [−478, −397] 这一段里时，头顶不断掉内存条：
## 先在地上亮一个**金色落点圈**（0.6 s 预警）→ 内存条从 20 m 高处砸下来 →
## 命中掉血 + 击退。跑起来躲，这条路才不是「一路按 W」。
##
## ── 模型 ──
## `models/ram/random_access_memory_ram_ddr4.glb`（Sketchfab / suuugar_mommy，
## **CC BY-NC 4.0**：署名、不可商用）。1168 三角面、两个 surface。
## 为了塞一百多根又不炸 draw call，这里把两个 surface 各做成一个 **MultiMesh**
## （同一批变换喂给两个 MultiMeshInstance3D，等于 2 个 draw call 画完全场）。

const RAM_PATH := "res://models/ram/random_access_memory_ram_ddr4.glb"

## 内存条雨的范围（x 闭区间）——第 9 段 X1 −404.7 到第 10 段 C4 −470 再留点余量
@export var rain_x_min := -478.0
@export var rain_x_max := -397.0
## 雨滴间隔（秒）：0.55 ~ 1.05 随机
@export var rain_interval_min := 0.55
@export var rain_interval_max := 1.05
## 落点预警多久（秒）之后才真的砸下来
@export var warn_time := 0.60
## 从多高掉下来 / 重力 / 伤害 / 击退
@export var drop_height := 20.0
@export var drop_gravity := 30.0
@export var drop_damage := 10.0
@export var drop_knockback := 3.0
## 命中判定半径（m，对玩家中心）
@export var hit_radius := 0.95
## 总开关（自检里逐跳回放 / 连续通关要关掉，见 `_verify_parkour.gd`）
@export var rain_enabled := true

## ── 可拾取的内存条（→ 资产，2026-10-20）──
##
## 用户原话：「内存条是可拾取的……**天上掉下来的内存条不算，只有躺在地上的可以捡**」，
## 第二轮又补：「**这些看见的都要可以捡，但是不要刷新了**」。
##
## 所以「能捡的」= 三批，全部**只减不增**（没有补货，捡完就没了）：
##   · `_ground`  —— 平躺在台面上的 16 根（y = 台面 + 3 cm，带金色呼吸圈）
##   · `_decor`   —— 平台东西两侧**插在边上**的 26 根 + 螺旋塔每层的 3 根鳍片 21 根
##                   （它们本来就是「看得见」的装饰，走过来就能捡走，捡走的那一根
##                    在 MultiMesh 里缩到 0 —— 不重建 buffer，也不多一个节点）
## 头顶吊架（y ≈ 10.2）那 65 根**够不着**，仍然是纯装饰。
## `_drops`（内存条雨）跟这三批**无关**：砸到人只掉血，永远不会进资产。
signal ram_picked(spec: Dictionary, price: int)

## 拾取半径（m，水平距离）/ 允许的高度差
@export var pickup_radius := 1.25
@export var pickup_dy := 1.60
## 自检用总开关：早期几节回放会把人瞬移过去，先关掉免得凭空涨资产
@export var loot_enabled := true

const PCB_COL := Color(0.03, 0.22, 0.12)
const GOLD_COL := Color(1.0, 0.78, 0.30)
const STEEL_COL := Color(0.13, 0.14, 0.16)

var _pk: Parkour
var _player: Player
## 内存条模型的各个部件：{mesh: ArrayMesh, mat: Material, rel: Transform3D}
var _parts: Array[Dictionary] = []
## 内存条在 GLB 根空间里的包围盒（原始尺寸：x 0.183 / y 0.006 / z 0.051）
var _box := AABB()
var _xf: Array[Transform3D] = []
## 装饰用的两个 MultiMeshInstance3D（`_xf` 的下标就是实例下标）
var _batches: Array[MultiMeshInstance3D] = []

var _pcb_mat: StandardMaterial3D
var _gold_mat: StandardMaterial3D
var _steel_mat: StandardMaterial3D

var _drops: Array[Dictionary] = []
var _markers: Array[Dictionary] = []
var _t_rain := 0.4
var _dropped := 0
var _hits := 0
var _built := false

## 平躺在台面上的（可捡）：{node, ring, spec, price, at, t}
var _ground: Array[Dictionary] = []
## 插在台边的 / 塔身鳍片（可捡）：{idx, at, spec, price, hidden}
var _decor: Array[Dictionary] = []
## 这里捡过的：{spec, price}，自检靠它核对「资产 += 这一根的价格」
var _picked_log: Array[Dictionary] = []
var _picked := 0
var _picked_value := 0
var _loot_serial := 0
var _plate_idx: Array[int] = []
var _fut: ParkourFutures
var _loot_rng := RandomNumberGenerator.new()
var _glow_mat: StandardMaterial3D


func _ready() -> void:
	_pk = get_parent() as Parkour
	_loot_rng.randomize()
	# 路线要等 Parkour._ready() 才建好，而子节点先 ready —— 推到下一帧
	_build.call_deferred()


func _physics_process(delta: float) -> void:
	if not _built:
		return
	_tick_rain(delta)
	_tick_ground(delta)


# --- 建场景 -------------------------------------------------------------------

func _build() -> void:
	if _built or _pk == null:
		return
	_built = true
	_measure_model()
	_make_materials()
	var seg9 := 8
	var first := _pk.segment_start(seg9)
	var last := _pk.segment_start(10) - 1        # 第 9~10 段全部
	_build_platform_dressing(first, last)
	_build_truss()
	_build_hanging_racks()
	_build_tower_fins()
	_build_ground_loot(first, last)
	_build_seg_signs()
	_flush_multimeshes()
	print("[RamMarket] 内存条市场就位：%d 根装饰条（x %.1f ~ %.1f）、地上 %d 根可捡"
		% [_xf.size(), rain_x_min, rain_x_max, _ground.size()])


## 量 GLB：把两个 MeshInstance3D 的包围盒合起来（**含 GLB 根节点的缩放**）。
##
## ⚠️ 坑：Sketchfab 导出的 FBX 把「缩小 0.0254 倍」挂在**祖先节点**上，
##    网格顶点本身还是 7.2 个单位的原始尺寸。所以不能直接用 `mi.mesh` 去 MultiMesh
##    （那样一根条子会变成 7 m 长），而是把「网格 → GLB 根」这条链上的变换
##    `rel` 记下来，摆的时候在世界变换里再乘回去（见 `_flush_multimeshes`）。
func _measure_model() -> void:
	var ps := load(RAM_PATH) as PackedScene
	if ps == null:
		push_error("[RamMarket] 找不到 %s" % RAM_PATH)
		return
	var inst := ps.instantiate()
	var first := true
	for c in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null:
			continue
		var rel := _rel_xf(mi)
		var b: AABB = rel * mi.get_aabb()
		_box = b if first else _box.merge(b)
		first = false
		var mat: Material = null
		if mi.material_override != null:
			mat = mi.material_override
		elif (mi.mesh as ArrayMesh).get_surface_count() > 0:
			mat = (mi.mesh as ArrayMesh).surface_get_material(0)
		_parts.append({"mesh": mi.mesh, "mat": mat, "rel": rel})
	inst.queue_free()
	print("[RamMarket] 内存条模型：%d 个 mesh，包围盒 %s，尺寸 %s"
		% [_parts.size(), str(_box.position.snappedf(0.001)), str(_box.size.snappedf(0.001))])


## 网格 → GLB 根（含根自身）的变换。实例没有挂进树，所以一路走到 parent == null 为止。
func _rel_xf(node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = node
	while cur != null:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func _make_materials() -> void:
	_pcb_mat = StandardMaterial3D.new()
	_pcb_mat.albedo_color = PCB_COL
	_pcb_mat.metallic = 0.15
	_pcb_mat.roughness = 0.55
	_pcb_mat.emission_enabled = true
	_pcb_mat.emission = Color(0.02, 0.16, 0.07)
	_pcb_mat.emission_energy_multiplier = 0.35
	_gold_mat = StandardMaterial3D.new()
	_gold_mat.albedo_color = GOLD_COL
	_gold_mat.metallic = 0.9
	_gold_mat.roughness = 0.28
	_gold_mat.emission_enabled = true
	_gold_mat.emission = Color(0.42, 0.26, 0.05)
	_gold_mat.emission_energy_multiplier = 0.45
	_steel_mat = StandardMaterial3D.new()
	_steel_mat.albedo_color = STEEL_COL
	_steel_mat.metallic = 0.6
	_steel_mat.roughness = 0.45


## 一根内存条的世界变换：**底边中点**落在 `at`，绕 Y 转 `yaw`，再绕自身长轴压 `tilt`。
## `s` 是统一缩放：模型原始 0.183 m 长，s = 8 → 1.46 m；高度 0.051 × s。
func _stick_xf(at: Vector3, yaw: float, tilt: float, s: float) -> Transform3D:
	var rot := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -PI * 0.5 + tilt)
	var b := rot * Basis.from_scale(Vector3(s, s, s))
	# 竖起来以后，模型空间的「底边中点」= (中心 x, 中心 y, min z)
	var anchor := Vector3(_box.get_center().x, _box.get_center().y, _box.position.z)
	return Transform3D(b, at - b * anchor)


## 加一根装饰条。`pickable = true` 就同时登记成可拾取（台边插的 / 塔身鳍片）；
## 头顶吊架那批传 false —— 它们挂在 10 m 高，人够不着，只能当背景。
func _add_stick(at: Vector3, yaw: float, tilt: float, s: float, pickable := true) -> void:
	var idx := _xf.size()
	_xf.append(_stick_xf(at, yaw, tilt, s))
	if not pickable:
		return
	var spec := RamSpec.roll(_loot_rng)
	_decor.append({"idx": idx, "at": at, "spec": spec,
		"price": RamSpec.price_yuan(spec), "hidden": false})


## 每块站台：顶面压一层 PCB + 两条金手指，东西两侧各插一根内存条（往外倒）
func _build_platform_dressing(first: int, last: int) -> void:
	for i in range(first, last + 1):
		var b := _pk.box_at(i)
		if b.size.x < 0.5:
			continue
		var top := _pk.top_at(i)
		var c := b.position + b.size * 0.5
		# ① PCB 面：薄板**比台面高 8 mm**（不是齐平！齐平会和台面抢深度，
		#    渲染出来是一圈锯齿状的「撕裂边」—— 上一版就是这样）
		_add_slab(Vector3(c.x, top - 0.002, c.z),
			Vector3(maxf(b.size.x - 0.12, 0.4), 0.02, maxf(b.size.z - 0.12, 0.4)),
			_pcb_mat)
		# ② 两条金手指（南北各一条，压在 PCB 边缘）
		for sign_z in [-1.0, 1.0]:
			_add_slab(Vector3(c.x, top + 0.012, c.z + sign_z * (b.size.z * 0.5 - 0.10)),
				Vector3(maxf(b.size.x - 0.16, 0.4), 0.03, 0.10), _gold_mat)
		# ③ 两根插在东西边缘、往外倒 20° 的内存条（不挡跑线：只在板外侧斜出去）
		#    缩放 10 → 1.83 m 长、0.51 m 高，和 2.4~3.7 m 的台子比例刚好
		var east := Vector3(b.position.x + b.size.x - 0.05, top, c.z)
		var west := Vector3(b.position.x + 0.05, top, c.z)
		_add_stick(east, PI * 0.5, -0.34, 10.0)
		_add_stick(west, PI * 0.5, 0.34, 10.0)


## 头顶桁架：一根贯通的横梁 + 每隔 6 m 一根短吊杆
func _build_truss() -> void:
	var x0 := -398.0
	var x1 := -478.0
	var y := 13.8
	var z := -4.9
	_add_slab(Vector3((x0 + x1) * 0.5, y, z), Vector3(absf(x1 - x0), 0.25, 0.25), _steel_mat)
	_add_slab(Vector3((x0 + x1) * 0.5, y - 0.18, z - 1.6),
		Vector3(absf(x1 - x0), 0.10, 0.10), _steel_mat)
	var x := x0
	while x > x1:
		_add_slab(Vector3(x, y - 0.9, z), Vector3(0.16, 1.8, 0.16), _steel_mat)
		x -= 6.0


## 吊架：每 6 m 一串，从桁架垂下来 5 根倒吊的内存条（y ≈ 10.2，玩家跳不到）
func _build_hanging_racks() -> void:
	var x := -402.0
	var row := 0
	while x > -476.0:
		var z := -4.9 + sin(float(row) * 0.9) * 1.4
		_add_slab(Vector3(x, 11.4, z), Vector3(0.10, 4.6, 0.10), _steel_mat)
		for k in 5:
			var dz := (float(k) - 2.0) * 0.55
			# 倒吊：yaw 绕 Y，tilt = PI 让它翻过来（尖端朝下）。**不可拾取**（10 m 高）
			_add_stick(Vector3(x, 10.2, z + dz), PI * 0.5, PI - 0.08, 12.0, false)
		x -= 6.0
		row += 1


## 螺旋塔：每层平台向外插三根内存条（像散热鳍片）
func _build_tower_fins() -> void:
	var first := _pk.segment_start(9)
	var last := _pk.segment_start(10) - 1
	for i in range(first, last + 1):
		var b := _pk.box_at(i)
		if b.size.x < 0.5:
			continue
		var top := _pk.top_at(i)
		var c := b.position + b.size * 0.5
		var base_yaw := float(i - first) * 0.85
		for k in 3:
			var yaw := base_yaw + float(k) * TAU / 3.0
			var dir := Vector3(cos(yaw), 0.0, sin(yaw))
			var at := Vector3(c.x, top, c.z) + dir * (maxf(b.size.x, b.size.z) * 0.5 + 0.05)
			# 向外倒 35°，看起来像插在塔身上的散热片
			_add_stick(at, -yaw + PI * 0.5, -0.6, 8.5)


func _add_slab(at: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = to_local(at) if is_inside_tree() else at
	add_child(mi)


## 把攒下来的变换一次性喂给两个 MultiMesh（两个 surface 各一个）。
## 每根条子的世界变换 = `_xf[i]`（摆位）× `rel`（网格 → GLB 根，含 Sketchfab 那层缩小）。
func _flush_multimeshes() -> void:
	if _parts.is_empty() or _xf.is_empty():
		return
	for s in _parts.size():
		var part := _parts[s]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = part["mesh"]
		mm.instance_count = _xf.size()
		var rel := part["rel"] as Transform3D
		for i in _xf.size():
			mm.set_instance_transform(i, _xf[i] * rel)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "RamBatch%d" % s
		mmi.multimesh = mm
		if part["mat"] != null:
			mmi.material_override = part["mat"]
		add_child(mmi)
		_batches.append(mmi)


## 捡走一根插在台边的：把它在两个 surface 的实例变换都缩到 0（同一实例下标）。
## 不重建 MultiMesh、不删节点 —— 一百多根只丢一根时，重建 buffer 比缩成 0 贵得多。
func _hide_decor(idx: int) -> void:
	var zero := Transform3D(Basis.from_scale(Vector3(0.001, 0.001, 0.001)),
		Vector3(0.0, -500.0, 0.0))
	for mmi in _batches:
		if mmi.multimesh != null and idx >= 0 and idx < mmi.multimesh.instance_count:
			mmi.multimesh.set_instance_transform(idx, zero)


# --- 内存条雨 -------------------------------------------------------------------

func _tick_rain(delta: float) -> void:
	_tick_markers(delta)
	_tick_drops(delta)
	if not rain_enabled:
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Player
		if _player == null:
			return
	var px := _player.global_position.x
	if px < rain_x_min or px > rain_x_max:
		return
	_t_rain -= delta
	if _t_rain <= 0.0:
		_t_rain = randf_range(rain_interval_min, rain_interval_max)
		_spawn_marker()


## 落点：玩家前方 1.5~5 m、左右 ±2.6 m，脚下有板就落在板上
func _pick_landing() -> Vector3:
	var p := _player.global_position
	var at := p + Vector3(-randf_range(1.5, 5.0), 0.0, randf_range(-2.6, 2.6))
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 4.5, 0), at + Vector3(0, -14.0, 0))
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		at.y = float((hit["position"] as Vector3).y)
	else:
		at.y = p.y
	return at


func _spawn_marker() -> void:
	var at := _pick_landing()
	var ring := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.85
	cyl.bottom_radius = 0.85
	cyl.height = 0.04
	cyl.radial_segments = 24
	ring.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.72, 0.22, 0.55)
	ring.material_override = mat
	ring.position = to_local(at + Vector3(0, 0.06, 0))
	add_child(ring)
	_markers.append({"node": ring, "t": 0.0, "at": at})


func _tick_markers(delta: float) -> void:
	var keep: Array[Dictionary] = []
	for m in _markers:
		var n := m["node"] as MeshInstance3D
		if not is_instance_valid(n):
			continue
		m["t"] = float(m["t"]) + delta
		var t := float(m["t"])
		# 圈慢慢长大 + 变亮，最后一刻收掉、放真家伙
		var k := clampf(t / warn_time, 0.0, 1.0)
		n.scale = Vector3(0.6 + 0.5 * k, 1.0, 0.6 + 0.5 * k)
		if n.material_override is StandardMaterial3D:
			(n.material_override as StandardMaterial3D).albedo_color = \
				Color(1.0, 0.72, 0.22, 0.25 + 0.55 * k)
		if t >= warn_time:
			n.queue_free()
			_spawn_drop(m["at"] as Vector3)
			continue
		keep.append(m)
	_markers = keep


func _spawn_drop(at: Vector3) -> void:
	var root := Node3D.new()
	root.position = to_local(at + Vector3(0, drop_height, 0))
	root.rotation = Vector3(randf_range(-0.4, 0.4), randf_range(0.0, TAU), 0.0)
	# 落下来的这根按 9 倍放大（跟装饰条同一档），先竖起来再乘网格自己的 rel
	var stand := Transform3D(
		Basis(Vector3.RIGHT, -PI * 0.5) * Basis.from_scale(Vector3(9, 9, 9)), Vector3.ZERO)
	for part in _parts:
		var mi := MeshInstance3D.new()
		mi.mesh = part["mesh"]
		if part["mat"] != null:
			mi.material_override = part["mat"]
		mi.transform = stand * (part["rel"] as Transform3D)
		root.add_child(mi)
	add_child(root)
	_drops.append({"node": root, "vy": 0.0, "t": 0.0, "target_y": at.y})
	_dropped += 1


func _tick_drops(delta: float) -> void:
	var keep: Array[Dictionary] = []
	for d in _drops:
		var n := d["node"] as Node3D
		if not is_instance_valid(n):
			continue
		d["vy"] = float(d["vy"]) - drop_gravity * delta
		n.position.y += float(d["vy"]) * delta
		d["t"] = float(d["t"]) + delta
		n.rotation.y += delta * 2.4
		if _player != null and n.global_position.distance_to(_player.global_position) < hit_radius:
			_player.take_damage(drop_damage, n.global_position, drop_knockback)
			_hits += 1
			Sfx.play("ui_toggle", -6.0)
			n.queue_free()
			continue
		if n.position.y < float(d["target_y"]) - 1.5 or float(d["t"]) > 6.0:
			# 砸到平台上：闪一下就消失（不留碎片，省得刷一堆节点）
			n.queue_free()
			continue
		keep.append(d)
	_drops = keep


## --- 第 9 / 10 段的段起点牌（2026-10-20 补）------------------------------------
##
## ⚠️ 用户：「第九段内存条的提示怎么没显示」。查下来**不是牌子写坏了，是根本没生成**：
##    生成器 `make_flush_section.py` 只给第 3~8 段立了 `Beacon_<段名>`；第 9~10 段
##    （X 区 / W 区）是从旧的「第 3~4 段」平移过来的，老桅杆上写的是「第 9/10 段 · 终点」，
##    而**起点**那根牌子一直没有。所以人在 X1 前面什么提示都看不到。
##
## 这里在运行时补两根 billboard 牌，第 9 段那块顺带把**拾取规则**写清楚：
## 地上的能捡、天上掉的不算、每根随机 36 种里的一种。
func _build_seg_signs() -> void:
	var specs := [
		{"seg": 8, "col": Color(1.0, 0.86, 0.42), "text":
			"第 9 段 · 内存条市场・横跳\n地上的、插在台边的都能捡（天上掉的不算）\n每根随机：代 / 频率 / 2~64G / ECC·非ECC（132 种）"},
		{"seg": 9, "col": Color(0.86, 0.92, 1.0), "text": "第 10 段 · 内存条螺旋塔"},
	]
	for spec in specs:
		var i := _pk.segment_start(int(spec["seg"]))
		var b := _pk.box_at(i)
		if b.size.x <= 0.0:
			continue
		var lab := Label3D.new()
		lab.name = "SegSign_S%d" % int(spec["seg"])
		lab.text = String(spec["text"])
		# ⚠️ 字别太大：pixel_size × font_size = 每字多高。第一版 0.010 × 40 = 0.40 m/字，
		#    9 m 外就糊掉半屏、把后面的板全挡了（用户以前就说过「牌子挡视线」）。
		#    现在 0.009 × 30 ≈ 0.27 m/字，9 m 处约 30 px 高，看得清但不占屏。
		lab.font_size = 30
		lab.outline_size = 10
		lab.pixel_size = 0.009
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.no_depth_test = true
		lab.modulate = spec["col"] as Color
		lab.position = Vector3(b.position.x + b.size.x * 0.5,
			_pk.top_at(i) + 3.8, b.position.z + b.size.z * 0.5 + 2.8)
		add_child(lab)


## --- 地上躺着的内存条（可拾取 → 资产）------------------------------------------
##
## ⚠️ 跟上面的「内存条雨」是两套东西：雨里的 `_drops` 是**危险物**（砸掉血、碰完就没），
##    这里 `_ground` 才是**可拾取物**。用户 2026-10-20 特别强调：
##    「天上掉下来的内存条不算，只有躺在地上的可以捡」—— 所以 `_pick()` 只从
##    `_ground` 里删，雨滴就算砸断腿也不会进资产账户（自检 §5h 的第 ⑥ 条盯着）。

func _build_ground_loot(first: int, last: int) -> void:
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_mat.albedo_color = Color(1.0, 0.80, 0.35, 0.30)
	_glow_mat.emission_enabled = true
	_glow_mat.emission = Color(1.0, 0.72, 0.22)
	_glow_mat.emission_energy_multiplier = 1.6
	_plate_idx.clear()
	for i in range(first, last + 1):
		var b := _pk.box_at(i)
		if b.size.x < 1.0 or b.size.z < 0.6:
			continue                 # 太窄的落脚点（螺旋塔内侧）不放，免得整根悬空
		_plate_idx.append(i)
	if _plate_idx.is_empty():
		push_warning("[RamMarket] 第 9~10 段没有能放内存条的台子")
		return
	for i in _plate_idx:
		_spawn_ground(i)
	print("[RamMarket] 可拾取：地上 %d 根 + 台边/鳍片 %d 根（共 %d 根，捡完不补）"
		% [_ground.size(), _decor.size(), pickable_count()])


## 在 1 号站台上放一根：平躺（模型本来就是「长边沿 x」的姿态，不用转），
## 底下垫一个金色呼吸圈当「可拾取」标记。
func _spawn_ground(i: int) -> Dictionary:
	var b := _pk.box_at(i)
	var top := _pk.top_at(i)
	var c := b.position + b.size * 0.5
	var at := Vector3(c.x + randf_range(-0.22, 0.22), top + 0.03,
		c.z + randf_range(-0.18, 0.18))
	var root := Node3D.new()
	root.name = "Loot_%d" % _loot_serial
	_loot_serial += 1
	root.position = at
	root.rotation = Vector3(0.0, randf_range(0.0, TAU), 0.0)
	# 8 倍 → 一根 1.46 m 长，比装饰条（10 倍）小一号，躺在 2.4~3.7 m 的台上刚好
	var s := 8.0
	for part in _parts:
		var mi := MeshInstance3D.new()
		mi.mesh = part["mesh"]
		if part["mat"] != null:
			mi.material_override = part["mat"]
		mi.transform = Transform3D(Basis.from_scale(Vector3(s, s, s)), Vector3.ZERO) \
			* (part["rel"] as Transform3D)
		root.add_child(mi)
	var ring := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.62
	cyl.bottom_radius = 0.62
	cyl.height = 0.02
	cyl.radial_segments = 24
	ring.mesh = cyl
	ring.material_override = _glow_mat
	ring.position = Vector3(0.0, -0.012, 0.0)
	root.add_child(ring)
	add_child(root)
	# 抽规格：11 个（代, 频率）组合 × 6 容量 × ECC/非ECC = 132 种（见 `RamSpec`）
	var spec := RamSpec.roll(_loot_rng)
	var price := RamSpec.price_yuan(spec)
	var rec := {"node": root, "ring": ring, "spec": spec, "price": price,
		"at": at, "t": randf_range(0.0, TAU)}
	_ground.append(rec)
	return rec


func _tick_ground(delta: float) -> void:
	if not loot_enabled:
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Player
		if _player == null:
			return
	var p := _player.global_position
	# ① 平躺在台面上的：呼吸圈 + 近身就捡
	var keep: Array[Dictionary] = []
	var picked: Array[Dictionary] = []
	for g in _ground:
		var n := g["node"] as Node3D
		if not is_instance_valid(n):
			continue
		g["t"] = float(g["t"]) + delta
		var ring := g["ring"] as MeshInstance3D
		if is_instance_valid(ring):
			ring.scale = Vector3.ONE * (1.0 + 0.10 * sin(float(g["t"]) * 2.6))
		if _near(p, g["at"] as Vector3):
			picked.append(g)
			continue
		keep.append(g)
	_ground = keep
	for g in picked:
		_pick_ground(g)
	# ② 插在台边的 / 塔身鳍片：同样近身就捡；捡走的那一根在 MultiMesh 里缩成 0
	#    ⚠️ 不补货（用户 2026-10-20：「不要刷新了」）—— 这批捡完就真没了。
	var left: Array[Dictionary] = []
	for d in _decor:
		if bool(d["hidden"]):
			continue
		if _near(p, d["at"] as Vector3):
			_pick_decor(d)
			continue
		left.append(d)
	_decor = left


func _near(p: Vector3, at: Vector3) -> bool:
	var d := p - at
	return Vector2(d.x, d.z).length() <= pickup_radius and absf(d.y) <= pickup_dy


func _pick_ground(g: Dictionary) -> void:
	var n := g["node"] as Node3D
	if is_instance_valid(n):
		n.queue_free()
	_credit(g["spec"] as Dictionary, int(g["price"]))


func _pick_decor(d: Dictionary) -> void:
	d["hidden"] = true
	_hide_decor(int(d["idx"]))
	_credit(d["spec"] as Dictionary, int(d["price"]))


func _credit(spec: Dictionary, price: int) -> void:
	_picked += 1
	_picked_value += price
	_picked_log.append({"spec": spec, "price": price})
	ram_picked.emit(spec, price)
	if _fut == null:
		_fut = _pk.get_node_or_null("Futures") as ParkourFutures
	if _fut != null:
		_fut.add_ram(spec, price)
	Sfx.play("ui_slider", 0.0)
	print("[RamMarket] 捡到 %s → ¥%d（累计 %d 根 / ¥%d）"
		% [RamSpec.describe(spec, true), price, _picked, _picked_value])


## --- 自检用 ---
func ground_count() -> int:
	return _ground.size()


func decor_count() -> int:
	var n := 0
	for d in _decor:
		if not bool(d["hidden"]):
			n += 1
	return n


## 现在还能捡的根数（躺着 + 台边/鳍片）
func pickable_count() -> int:
	return _ground.size() + decor_count()


func pickable_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for g in _ground:
		out.append(g["at"] as Vector3)
	for d in _decor:
		if not bool(d["hidden"]):
			out.append(d["at"] as Vector3)
	return out


func decor_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for d in _decor:
		if not bool(d["hidden"]):
			out.append(d["at"] as Vector3)
	return out


func pickable_specs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for g in _ground:
		out.append(g["spec"] as Dictionary)
	for d in _decor:
		if not bool(d["hidden"]):
			out.append(d["spec"] as Dictionary)
	return out


func loot_picked_count() -> int:
	return _picked


func loot_picked_value() -> int:
	return _picked_value


func last_picked() -> Dictionary:
	return _picked_log[-1] if not _picked_log.is_empty() else {}


func stick_count() -> int:
	return _xf.size()


func drops_spawned() -> int:
	return _dropped


func drops_hit() -> int:
	return _hits


func active_drops() -> int:
	return _drops.size()


## 自检用：直接朝玩家头顶砸一根（不等计时器）
func force_drop_now() -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Player
	if _player == null:
		return
	_spawn_drop(_player.global_position)
