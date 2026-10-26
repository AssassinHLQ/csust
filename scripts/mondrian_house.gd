class_name MondrianHouse
extends Node3D
## 蒙德里安风格的两层大房子 —— 盖在「天使24」商店**正对面**（商店南门外那片空地）。
##
## ── 用户 2026-10-26 原话 ──
## 「新建场景，进入入口在这个商店对面建个大房子，要有一二层，使用蒙德里安风格建筑做」
##
## ── 盖在哪（全部现场量过，不是估的）──
## `_probe_mondrian_site.gd` 的结论：
##   商店墙体 x 20.70 ~ 33.90、z −18.30 ~ −12.70；门在南墙（+Z 侧）z = −12.70、中心 x = 27.30。
##   商店地板 Deck 铺到 x 20.01 ~ 40.00、z −20.00 ~ +20.00（`shop.gd::_build_deck`）。
##   商店南门外 z −10 ~ +18 的整片区域，从上往下打射线全是 y ≈ 0 的平地，**没有任何障碍**。
## 所以本节点摆在 **(29, 0, −2)**：北墙外表面落在 z = −8.00，
## 与商店门（z = −12.70）留 **4.70 m** 的走道 —— 出门直走几步就进这个大门。
##
## ── 为什么是「代码建」而不是在编辑器里一块块摆 ──
## ① 蒙德里安的立面是**一张网格**：黑线把白底切成格子，再往格子里填红/蓝/黄。
##    这种构图用几十个盒子在编辑器里手摆，改一个数就要动一片；写成参数，改 `HALF_W`
##    整张立面跟着重排。
## ② 楼梯要「看得见的是台阶、踩上去是斜坡」（见下面 `_build_stairs()` 那段），
##    这种「视觉与碰撞故意不是同一个形状」的做法没法只靠摆节点表达。
##
## ── 尺寸一览（本节点局部坐标，单位米）──
##   外墙：x ±8.00、z ±6.00、高 8.00（一层 4.20 + 二层 3.80），墙厚 0.25
##   门洞：x ±1.10、高 2.60，开在北墙（−Z）
##   楼梯：贴西墙内侧，宽 1.60，21 级踏步从 y=0 爬到 y=4.20（坡度 0.6 → 30.96°）
##   屋顶：8.00 ~ 8.30，四周挑檐 0.50
##
## ── 三个容易踩的坑（都写在正文对应位置）──
##   · 台面/柜体接地的那个面会和地砖**共面**（都在 y = 0）→ 一律往地下多伸 `SINK`。
##   · `CharacterBody3D` **不会上台阶**（`_verify_mesh_hut.gd` 量过：10 cm 的坎就把
##     `cast_motion` 的 safe 从 1.000 打到 0.387）→ 台阶只能当装饰，碰撞用整块斜坡。
##   · 立面上黑线与彩色板必须**一层压一层、各有各的凸出量**，否则两块的正面共面 = 闪。

## 相邻两块互相插进去的深度（米）。
## 两个盒子「正好贴着」= 两个面共面 = z-fighting，用户 2026-10-21 在天使24 上踩过一次。
const TUCK := 0.02
## 底部往地下多伸的深度（米）。凡是底面落在 y = 0 的东西都要加 ——
## 否则它的底面和地砖顶面（都在 y = 0）共面，走动时会闪。
const SINK := 0.02

# ══════════════════════════ 尺寸 ══════════════════════════

## 外墙半宽（x 方向）。±8.00 → 总面宽 **16.00 m**。
const HALF_W := 8.00
## 外墙半深（z 方向）。±6.00 → 总进深 **12.00 m**。
const HALF_D := 6.00
## 墙厚
const WALL_T := 0.25
## 一层地面 → 二层地面（= 二层楼板顶面）
const FLOOR_H := 4.20
## 二层地面 → 墙顶
const TOP_H := 8.00
## 楼板厚（二层楼板：3.95 ~ 4.20）
const SLAB_T := 0.25
## 屋顶板厚
const ROOF_T := 0.30
## 屋顶挑檐（四周各伸出多少）
const EAVE := 0.50

## 门洞半宽、门洞高
const DOOR_HALF := 1.10
const DOOR_H := 2.60

## 楼梯
const STAIR_W := 1.60
## 踏步级数（第 1 级踏面在 0.21 m，第 20 级在 4.20 m）
const STAIR_STEPS := 20
## 楼梯总水平段长（斜坡在 z 上跨过的距离）
const STAIR_RUN := 7.00
## 楼梯总爬升
const STAIR_RISE := FLOOR_H
## 第 1 级踏步踢面所在的 z（低 z 端）
const STAIR_Z0 := -4.30

## 立面线条的凸出量：彩色板 < 竖线 < 横线。
## 三级不同的凸出量保证**任何两条线交叉处都不共面**（共面就会闪）。
const FACE_PANEL := 0.05
const FACE_PILLAR := 0.07
const FACE_BAND := 0.09

## 单独 instance 出来看效果时打开；`game.gd` 里是显式 `build()`（和 shop.gd 一个套路）
@export var auto_build := false

var _mat: Dictionary[String, Material] = {}
var _body: StaticBody3D
var _decor: Node3D
var _built := false
var solid_count := 0
var decor_count := 0


func _ready() -> void:
	if auto_build:
		build()


func build() -> void:
	if _built:
		return
	_built = true
	_make_materials()
	_body = StaticBody3D.new()
	_body.name = "Body"
	add_child(_body)
	_decor = Node3D.new()
	_decor.name = "Decor"
	add_child(_decor)
	_build_walls()
	_build_floor_slab()
	_build_stairs()
	_build_roof()
	_build_facade()
	_build_interior()
	_build_lights()
	_report()


# ══════════════════════════ 材质 ══════════════════════════

## 蒙德里安的四种颜色取自他自己的画（Composition with Red Blue and Yellow, 1930）：
## 红 #DD0100、蓝 #225095、黄 #FAC901，底是**略带暖调的灰白**（不是纯白 ——
## 纯白在室外阳光下会过曝成一团死白，反而看不出格子）。
func _make_materials() -> void:
	_mat["white"] = _std(Color(0.945, 0.937, 0.910), 0.86)
	_mat["black"] = _std(Color(0.075, 0.075, 0.075), 0.55)
	_mat["red"] = _std(Color(0.855, 0.098, 0.086), 0.62)
	_mat["blue"] = _std(Color(0.106, 0.286, 0.596), 0.62)
	_mat["yellow"] = _std(Color(0.965, 0.749, 0.086), 0.62)
	# 室内地面：暖灰（比外墙深一档，脚下有分量）
	_mat["floor"] = _std(Color(0.62, 0.60, 0.56), 0.88)
	# 二层地面：浅一号，进深方向不会糊成一片
	_mat["floor2"] = _std(Color(0.70, 0.68, 0.64), 0.86)
	# 楼梯踏面
	_mat["stair"] = _std(Color(0.78, 0.76, 0.72), 0.80)
	# 玻璃：半透明、双面（从里往外也要看得见）
	var glass := _std(Color(0.62, 0.80, 0.88, 0.18), 0.06)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.metallic_specular = 0.9
	_mat["glass"] = glass
	# 灯管
	var lamp := _std(Color(0.96, 0.94, 0.86), 0.60)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.92, 0.74)
	lamp.emission_energy_multiplier = 2.0
	_mat["lamp"] = lamp


func _std(col: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


# ══════════════════════════ 建模小工具 ══════════════════════════

## 有碰撞的盒子（网格 + `BoxShape3D` 成对出现）。
## ⚠️ 不走 CSG：CSG 的碰撞要 `use_collision = true` 才生成，而且布尔运算在
##    8 m 高的墙上会把门洞切成许多碎面，反而更难维护。
func _solid(node_name: String, center: Vector3, size: Vector3, mat: Material) -> void:
	_box_into(_body, node_name, center, size, mat, true)
	solid_count += 1


## 纯装饰（看得见摸不着）
func _deco(node_name: String, center: Vector3, size: Vector3, mat: Material) -> void:
	_box_into(_decor, node_name, center, size, mat, false)
	decor_count += 1


## 只有碰撞、没有网格（楼梯那块隐形斜坡用这个）
func _collide(node_name: String, center: Vector3, size: Vector3,
		basis: Basis = Basis.IDENTITY) -> void:
	var cs := CollisionShape3D.new()
	cs.name = node_name
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = Transform3D(basis, center)
	_body.add_child(cs)
	solid_count += 1


func _box_into(parent: Node3D, node_name: String, center: Vector3, size: Vector3,
		mat: Material, with_collision: bool) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.name = _unique_name(parent, node_name)
	mi.position = center
	parent.add_child(mi)
	if with_collision:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.name = mi.name + "Shape"
		cs.position = center
		parent.add_child(cs)


## 同名兄弟（立面上一排竖线、一排台阶）自动加 _1 _2 后缀，
## 免得 Godot 自动改成 `@MeshInstance3D@108` 这种读不懂的名字。
func _unique_name(parent: Node3D, base: String) -> String:
	var nm := base
	var n := 1
	while parent.has_node(NodePath(nm)):
		nm = "%s_%d" % [base, n]
		n += 1
	return nm


# ══════════════════════════ 屋壳（四面墙 + 门窗洞）══════════════════════════

## 四面墙。每面墙**按门窗洞切成若干块**再逐块建 —— 这是「用盒子拼出洞口」的唯一办法。
##
## 为什么不用 CSG 一次挖出来：见 `_solid()` 上面那段（碰撞要单独开关、布尔会产生碎面）。
## 为什么四面墙都从 y = −SINK 起：见 `SINK` 的注释（底面与地砖共面会闪）。
##
## 洞口一览：
##   北墙（−Z）：门 x ±1.10、y 0~2.60
##   南墙（+Z）：窗 x 2.50~6.50、y 5.00~7.20（二层）
##   东墙（+X）：窗 z −4.00~0.00，y 1.00~3.20（一层）/ 5.00~7.20（二层）
##   西墙（−X）：窗 z 0.50~4.50，y 1.00~3.20（一层）/ 5.00~7.20（二层）
func _build_walls() -> void:
	var w: Material = _mat["white"]
	var y0 := -SINK
	var y1 := TOP_H
	var full_h := y1 - y0
	var mid_y := (y0 + y1) * 0.5
	var oz := HALF_D - WALL_T * 0.5      # 南北墙在 z 上的中心
	var ox := HALF_W - WALL_T * 0.5      # 东西墙在 x 上的中心

	# ── 北墙：门 x ±1.10、高 2.60 ──
	_solid("WallN_W", Vector3((-HALF_W - DOOR_HALF) * 0.5, mid_y, -oz),
		Vector3(HALF_W - DOOR_HALF, full_h, WALL_T), w)
	_solid("WallN_E", Vector3((HALF_W + DOOR_HALF) * 0.5, mid_y, -oz),
		Vector3(HALF_W - DOOR_HALF, full_h, WALL_T), w)
	# 门楣：门顶 2.60 → 墙顶 8.00
	_solid("WallN_Lintel", Vector3(0.0, (DOOR_H + y1) * 0.5, -oz),
		Vector3(DOOR_HALF * 2.0, y1 - DOOR_H, WALL_T), w)

	# ── 南墙：二层窗 x 2.50~6.50、y 5.00~7.20 ──
	_solid("WallS_W", Vector3((-HALF_W + 2.50) * 0.5, mid_y, oz),
		Vector3(2.50 + HALF_W, full_h, WALL_T), w)
	_solid("WallS_Sill", Vector3(4.50, (y0 + 5.00) * 0.5, oz),
		Vector3(4.00, 5.00 - y0, WALL_T), w)
	_solid("WallS_Head", Vector3(4.50, (7.20 + y1) * 0.5, oz),
		Vector3(4.00, y1 - 7.20, WALL_T), w)
	_solid("WallS_E", Vector3((6.50 + HALF_W) * 0.5, mid_y, oz),
		Vector3(HALF_W - 6.50, full_h, WALL_T), w)
	_deco("GlassS", Vector3(4.50, (5.00 + 7.20) * 0.5, oz),
		Vector3(4.00, 7.20 - 5.00, 0.06), _mat["glass"])

	# ── 东墙：窗 z −4.00~0.00，两层各一扇 ──
	var wsize := Vector3(WALL_T, full_h, 2.00)          # 窗两侧各 2.00 m 的墙
	_solid("WallE_N", Vector3(ox, mid_y, -5.00), wsize, w)
	_solid("WallE_S", Vector3(ox, mid_y, 3.00), Vector3(WALL_T, full_h, 6.00), w)
	_solid("WallE_Sill1", Vector3(ox, (y0 + 1.00) * 0.5, -2.00),
		Vector3(WALL_T, 1.00 - y0, 4.00), w)
	_solid("WallE_Mid", Vector3(ox, (3.20 + 5.00) * 0.5, -2.00),
		Vector3(WALL_T, 5.00 - 3.20, 4.00), w)
	_solid("WallE_Top", Vector3(ox, (7.20 + y1) * 0.5, -2.00),
		Vector3(WALL_T, y1 - 7.20, 4.00), w)
	_deco("GlassE1", Vector3(ox, (1.00 + 3.20) * 0.5, -2.00),
		Vector3(0.06, 3.20 - 1.00, 4.00), _mat["glass"])
	_deco("GlassE2", Vector3(ox, (5.00 + 7.20) * 0.5, -2.00),
		Vector3(0.06, 7.20 - 5.00, 4.00), _mat["glass"])

	# ── 西墙：窗 z 0.50~4.50，两层各一扇 ──
	_solid("WallW_N", Vector3(-ox, mid_y, -2.75), Vector3(WALL_T, full_h, 6.50), w)
	_solid("WallW_S", Vector3(-ox, mid_y, 5.25), Vector3(WALL_T, full_h, 1.50), w)
	_solid("WallW_Sill1", Vector3(-ox, (y0 + 1.00) * 0.5, 2.50),
		Vector3(WALL_T, 1.00 - y0, 4.00), w)
	_solid("WallW_Mid", Vector3(-ox, (3.20 + 5.00) * 0.5, 2.50),
		Vector3(WALL_T, 5.00 - 3.20, 4.00), w)
	_solid("WallW_Top", Vector3(-ox, (7.20 + y1) * 0.5, 2.50),
		Vector3(WALL_T, y1 - 7.20, 4.00), w)
	_deco("GlassW1", Vector3(-ox, (1.00 + 3.20) * 0.5, 2.50),
		Vector3(0.06, 3.20 - 1.00, 4.00), _mat["glass"])
	_deco("GlassW2", Vector3(-ox, (5.00 + 7.20) * 0.5, 2.50),
		Vector3(0.06, 7.20 - 5.00, 4.00), _mat["glass"])


# ══════════════════════════ 一层地面 + 二层楼板 ══════════════════════════

## 一层地面：**视觉有、碰撞没有**。
##
## 顶面在 0.02，而地砖在 0.00 —— 差 2 cm。这一版玩家已经能上 0.30 m 的台阶
## （`step_climb.gd`），2 cm 的坎完全不是问题；但**依然不给碰撞**，原因是
## 「底面和地砖共面」这个老毛病：给碰撞就得让底面落到 y = 0，而 0 和地砖顶面
## 重合 → 闪。代价只是玩家小腿陷进去 2 cm（4 m 外的越肩相机上约 2 px，看不出来）
## —— `mesh_hut.tscn` 的 `FloorPlate` 是同一个取舍。
##
## ⚠️ 底面从 −0.01 起（不是 0）：0 会和地砖顶面共面 → 闪。
func _build_floor_slab() -> void:
	_deco("FloorPlate", Vector3(0.0, (-0.01 + 0.02) * 0.5, 0.0 - 0.0),
		Vector3(HALF_W * 2.0 - WALL_T * 2.0, 0.03, HALF_D * 2.0 - WALL_T * 2.0),
		_mat["floor"])

	# ── 二层楼板：整块**减去**楼梯井 ──
	# 井口 = x −7.75 ~ −6.15、z −4.30 ~ +2.70（正好罩住整段楼梯，见 `_build_stairs()`）。
	# 拆成三块：东侧一大块 + 西侧南北两条窄带。
	var slab_y := FLOOR_H - SLAB_T * 0.5
	var xe1 := -HALF_W + WALL_T          # −7.75 西墙内表面
	var xe2 := -HALF_W + WALL_T + STAIR_W  # −6.15 楼梯东沿
	var zi0 := HALF_D - WALL_T           # +5.75
	var stair_lo := STAIR_Z0             # −4.30 第 1 级踢面
	var stair_hi := STAIR_Z0 + STAIR_RUN                        # +2.70 最后一级踏面外沿
	# 东侧主体：x −6.15 ~ +7.75
	_solid("SlabE", Vector3((xe2 + HALF_W - WALL_T) * 0.5, slab_y, 0.0),
		Vector3(HALF_W - WALL_T - xe2, SLAB_T, zi0 * 2.0), _mat["floor2"])
	# 西侧北条：z −5.75 ~ −4.30
	var n_len := stair_lo + zi0
	_solid("SlabWN", Vector3((xe1 + xe2) * 0.5, slab_y, (-zi0 + stair_lo) * 0.5),
		Vector3(STAIR_W, SLAB_T, n_len), _mat["floor2"])
	# 西侧南条：z +2.70 ~ +5.75
	_solid("SlabWS", Vector3((xe1 + xe2) * 0.5, slab_y, (stair_hi + zi0) * 0.5),
		Vector3(STAIR_W, SLAB_T, zi0 - stair_hi), _mat["floor2"])


# ══════════════════════════ 楼梯 ══════════════════════════
#
# **真台阶、真碰撞** —— 每一级都站得住，脚踩在踏面上，不浮空。
#
# 能做到这一步，是因为先给玩家补了「上台阶」能力（`scripts/step_climb.gd`）。
# 在那之前实测过：Godot 的 `CharacterBody3D` **连 0.10 m 的竖直坎都上不去**
# （`_probe_step_climb.gd`，六档全测，门槛在 0.05 ~ 0.10 之间），
# 38°/40° 倒角踢面也救不了（`_probe_stair_forms.gd`，最多爬到 0.10 m）。
# 补上之后同样的六档：**0.05 / 0.10 / 0.15 / 0.21 / 0.30 全部爬上去，
# 0.45 仍被挡住** —— 正好是想要的（踏步 0.21 要能上，桌面 0.80、柜台 1.04 要挡住）。
#
# ⚠️ 因此这里的踏步**必须有碰撞**，而且每一级都要从地面实心堆到本级踏面：
#    悬空的「一片片踏板」会在上台阶逻辑的「③ 往下够地面」那一步踩空
#    （`test_move` 够不到实心面就不认这一级）。
#
# 参数（0.21 高 × 0.35 深 = 31° 名义坡度，符合建筑规范里楼梯的常见比例）：
#   `STAIR_STEPS` 20 级 × 踢面 `STAIR_RISE/20` = 0.21
#   `STAIR_RUN` 7.00 m / 20 = 0.35 每级踏面
func _build_stairs() -> void:
	var n := float(STAIR_STEPS)
	var per_rise := STAIR_RISE / n           # 0.21
	var per_run := STAIR_RUN / n             # 0.35
	var cx := -HALF_W + WALL_T + STAIR_W * 0.5   # 楼梯中线 x = −6.95

	# ── ① 踏步：每级一块「从地下实心堆到本级踏面」的整块，**带碰撞** ──
	# 侧面按蒙德里安配色循环上色：连成一条斜的彩色带，是这栋楼里最像画的一处。
	# ⚠️ 竖直方向从 −SINK 起（不是 0）：底面会和一层地面共面 → 闪。
	var palette: Array[Material] = [
		_mat["stair"], _mat["stair"], _mat["red"], _mat["stair"],
		_mat["stair"], _mat["blue"], _mat["stair"], _mat["stair"], _mat["yellow"],
	]
	for i in range(1, STAIR_STEPS + 1):
		var top_y := per_rise * float(i)
		var z_a := STAIR_Z0 + per_run * float(i - 1)
		var z_b := z_a + per_run
		var mat: Material = palette[(i - 1) % palette.size()]
		_solid("Step", Vector3(cx, (top_y - SINK) * 0.5, (z_a + z_b) * 0.5),
			Vector3(STAIR_W, top_y + SINK, z_b - z_a), mat)

	# ── ② 顶部落脚平台：最后一级踏面外沿 → 二层楼板边缘 ──
	# 顶面 4.20 与二层楼板同高；在 z 上**贴边对接**（2.70 / 2.70）不是重叠。
	var land_z0 := STAIR_Z0 + per_run * (n - 1.0)   # 2.35
	var land_z1 := STAIR_Z0 + STAIR_RUN             # 2.70
	_solid("StairLanding", Vector3(cx, (FLOOR_H - SINK) * 0.5, (land_z0 + land_z1) * 0.5),
		Vector3(STAIR_W, FLOOR_H + SINK, land_z1 - land_z0), _mat["stair"])

	# ── ③ 东侧栏板：从踏步面往上 0.95 m，一路跟着台阶升高 ──
	# 没有它的话，走到半空一脚踩偏就掉回一层。
	# 做成整块**阶梯状**：每级一块竖直挡板，比斜板省事，也不会和踏步共面。
	for i in range(1, STAIR_STEPS + 1):
		var top_y := per_rise * float(i)
		var z_a := STAIR_Z0 + per_run * float(i - 1)
		_deco("Guard", Vector3(-HALF_W + WALL_T + STAIR_W - 0.06, top_y + 0.475,
			z_a + per_run * 0.5), Vector3(0.12, 0.95, per_run + 0.01), _mat["black"])
		_collide("GuardShape",
			Vector3(-HALF_W + WALL_T + STAIR_W - 0.06, top_y + 0.475, z_a + per_run * 0.5),
			Vector3(0.12, 0.95, per_run + 0.01))


# ══════════════════════════ 屋顶 ══════════════════════════

## 屋顶 = 一块厚 0.30 的白板 + 四周一圈黑檐口（Mondrian 的黑线在这里收口）。
## 板底 8.00 = 墙顶，**贴边**不是重叠；檐口再往外挑 0.50。
func _build_roof() -> void:
	_solid("Roof", Vector3(0.0, TOP_H + ROOF_T * 0.5, 0.0),
		Vector3((HALF_W + EAVE) * 2.0, ROOF_T, (HALF_D + EAVE) * 2.0), _mat["white"])
	# 檐口：四条边的黑边，比屋面板**薄**一点但更往外一点，形成一圈阴影线
	var t := 0.22
	for spec in [
		["EaveN", Vector3(0.0, TOP_H + ROOF_T + 0.10, -(HALF_D + EAVE))],
		["EaveS", Vector3(0.0, TOP_H + ROOF_T + 0.10, HALF_D + EAVE)],
	]:
		_deco(str(spec[0]), spec[1] as Vector3,
			Vector3((HALF_W + EAVE) * 2.0 + 0.30, t, 0.34), _mat["black"])
	for spec in [
		["EaveW", Vector3(-(HALF_W + EAVE), TOP_H + ROOF_T + 0.10, 0.0)],
		["EaveE", Vector3(HALF_W + EAVE, TOP_H + ROOF_T + 0.10, 0.0)],
	]:
		_deco(str(spec[0]), spec[1] as Vector3,
			Vector3(0.34, t, (HALF_D + EAVE) * 2.0), _mat["black"])


# ══════════════════════════ 立面（蒙德里安）══════════════════════════
#
# 构图规则（照着 Mondrian 的 Composition 系列）：
#   · 白底；
#   · 若干**等宽黑线**把白底切成大小不一的矩形；
#   · 只有少数几个矩形被填成红/蓝/黄，其余一律留白；
#   · 线的粗细一致、位置不对称 —— 这是「画」和「贴瓷砖」的区别。
#
# ⚠️ 三条硬性规矩（都是踩过坑之后定下来的）：
#   1. **三种元素的凸出量必须互不相同**（`FACE_PANEL` < `FACE_PILLAR` < `FACE_BAND`）：
#      彩色板和黑线一旦同深，两条边在转角处就共面 → 用户 2026-10-21 在天使24 上
#      看到的那种「边上一走动就闪」。三层深度让横线永远压在竖线上面。
#   2. **线不许等距**：等距的网格读起来是窗棂、是瓷砖，不是画。每个立面的竖线
#      间距都刻意做得长短不一。
#   3. **黑线不贯穿整面**：Mondrian 的线常常在半途停住。贯穿 + 等距 = 格子布。
#      所以每条线单独给起止，不是「一根从东墙量到西墙」。
func _build_facade() -> void:
	_build_facade_north()
	_build_facade_south()
	_build_facade_side(1.0)      # +X 东
	_build_facade_side(-1.0)     # −X 西


## 北立面（正面，朝商店）。门开在这里，所以门两侧的线要避开洞口。
func _build_facade_north() -> void:
	var zf := -HALF_D                     # 北立面外表面
	var z_p := zf - FACE_PILLAR * 0.5
	var z_d := zf - FACE_PANEL * 0.5
	var z_b := zf - FACE_BAND * 0.5

	# ── 竖线：x 位置 / 起点 y / 终点 y（门那两条从门顶起）──
	# 长度刻意不齐：−5.00 只到 6.30 就停，3.20 从 2.90 才起 —— 这是「画」的关键。
	for spec in [[-6.60, 0.0, TOP_H], [-5.00, 0.0, 6.30],
			[-DOOR_HALF, DOOR_H, TOP_H], [DOOR_HALF, DOOR_H, TOP_H],
			[3.20, 2.90, TOP_H], [6.10, 0.0, 4.20]]:
		var px: float = spec[0]
		var y0: float = spec[1]
		var y1: float = spec[2]
		_deco("PillarN", Vector3(px, (y0 + y1) * 0.5, z_p),
			Vector3(0.28, y1 - y0, FACE_PILLAR), _mat["black"])

	# ── 横线：y 位置 / x 起点 / x 终点（在门洞上方断开）──
	for spec in [[2.90, -HALF_W, -2.30], [2.90, 2.30, HALF_W],
			[FLOOR_H, -HALF_W, HALF_W], [6.30, -7.40, 1.60],
			[TOP_H - 0.15, -HALF_W, HALF_W]]:
		var py: float = spec[0]
		var x0: float = spec[1]
		var x1: float = spec[2]
		_deco("BandN", Vector3((x0 + x1) * 0.5, py, z_b),
			Vector3(x1 - x0, 0.30, FACE_BAND), _mat["black"])

	# ── 彩色矩形：贴在格子里，四周留出黑线的位置 ──
	_deco("PanelNRed", Vector3(-7.05, 5.05, z_d), Vector3(1.10, 1.90, FACE_PANEL),
		_mat["red"])
	_deco("PanelNYellow", Vector3(4.30, 7.35, z_d), Vector3(2.80, 1.00, FACE_PANEL),
		_mat["yellow"])
	_deco("PanelNBlue", Vector3(5.55, 3.60, z_d), Vector3(1.10, 1.00, FACE_PANEL),
		_mat["blue"])

	# ── 门套：黑门楣 + 深色门槛 ──
	_deco("DoorHead", Vector3(0.0, DOOR_H + 0.15, z_b),
		Vector3(DOOR_HALF * 2.0 + 0.56, 0.30, FACE_BAND), _mat["black"])
	_deco("DoorSill", Vector3(0.0, 0.015, -HALF_D + WALL_T * 0.5),
		Vector3(DOOR_HALF * 2.0, 0.05, WALL_T + 0.10), _mat["black"])


## 南立面（背面）。二层那扇窗 x 2.50~6.50 / y 5.00~7.20 要避开线。
func _build_facade_south() -> void:
	var zf := HALF_D
	var z_p := zf + FACE_PILLAR * 0.5
	var z_d := zf + FACE_PANEL * 0.5
	var z_b := zf + FACE_BAND * 0.5

	for spec in [[-6.90, 0.0, TOP_H], [-4.10, 0.0, 5.00], [1.20, 5.00, TOP_H],
			[6.90, 0.0, 7.20]]:
		var px: float = spec[0]
		var y0: float = spec[1]
		var y1: float = spec[2]
		_deco("PillarS", Vector3(px, (y0 + y1) * 0.5, z_p),
			Vector3(0.28, y1 - y0, FACE_PILLAR), _mat["black"])
	for spec in [[2.20, -HALF_W, 2.50], [2.20, 6.50, HALF_W], [7.20, 0.50, HALF_W],
			[TOP_H - 0.15, -HALF_W, HALF_W]]:
		var py: float = spec[0]
		var x0: float = spec[1]
		var x1: float = spec[2]
		_deco("BandS", Vector3((x0 + x1) * 0.5, py, z_b),
			Vector3(x1 - x0, 0.30, FACE_BAND), _mat["black"])

	_deco("PanelSBlue", Vector3(-7.10, 6.60, z_d), Vector3(0.90, 2.20, FACE_PANEL),
		_mat["blue"])
	_deco("PanelSYellow", Vector3(-1.30, 1.60, z_d), Vector3(2.20, 1.40, FACE_PANEL),
		_mat["yellow"])


## 东/西立面。`side` = +1 东、−1 西。
## 这两面各有一扇 4 m 宽的窗（一层 y 1.00~3.20、二层 y 5.00~7.20），
## 线要绕开窗洞，所以竖线只放在窗洞之外，横线在窗上下各压一道。
func _build_facade_side(side: float) -> void:
	var xf := HALF_W * side
	var x_p := xf + FACE_PILLAR * 0.5 * side
	var x_d := xf + FACE_PANEL * 0.5 * side
	var x_b := xf + FACE_BAND * 0.5 * side
	var tag := "E" if side > 0.0 else "W"
	# 窗的 z 范围（和 `_build_walls()` 里的一致）
	var wz0 := -4.00 if side > 0.0 else 0.50
	var wz1 := 0.00 if side > 0.0 else 4.50
	var zp_left := wz0 - 1.60
	var zp_right := wz1 + 1.60

	for spec in [[zp_left, 0.0, TOP_H], [zp_right, 0.0, 5.00]]:
		var pz: float = spec[0]
		var y0: float = spec[1]
		var y1: float = spec[2]
		_deco("Pillar%s" % tag, Vector3(x_p, (y0 + y1) * 0.5, pz),
			Vector3(FACE_PILLAR, y1 - y0, 0.28), _mat["black"])
	# 窗洞上下各一道（贴着窗台/窗顶走，绕开玻璃）
	for spec in [[0.85, -HALF_D, HALF_D], [3.35, wz0 - 0.10, wz1 + 0.10],
			[4.85, wz0 - 0.10, wz1 + 0.10], [7.35, -HALF_D, HALF_D]]:
		var py: float = spec[0]
		var z0: float = spec[1]
		var z1: float = spec[2]
		_deco("Band%s" % tag, Vector3(x_b, py, (z0 + z1) * 0.5),
			Vector3(FACE_BAND, 0.30, z1 - z0), _mat["black"])

	# 彩色板：一块吊在二层高处，一块压在一层低处
	var hi_mat: Material = _mat["blue"] if side > 0.0 else _mat["red"]
	var lo_mat: Material = _mat["red"] if side > 0.0 else _mat["yellow"]
	_deco("Panel%sHi" % tag, Vector3(x_d, 6.20, zp_left), Vector3(FACE_PANEL, 1.90, 2.20),
		hi_mat)
	_deco("Panel%sLo" % tag, Vector3(x_d, 0.55, zp_right), Vector3(FACE_PANEL, 0.90, 2.40),
		lo_mat)

	# ── 东、西立面也各挂一块彩色板，绕到侧面时不至于全白 ──
	_deco("PanelEast", Vector3(HALF_W + FACE_PANEL * 0.5, 6.30, 3.40),
		Vector3(FACE_PANEL, 1.60, 2.60), _mat["blue"])
	_deco("PanelWest", Vector3(-HALF_W - FACE_PANEL * 0.5, 6.30, -3.40),
		Vector3(FACE_PANEL, 1.60, 2.60), _mat["red"])


# ══════════════════════════ 室内家具 ══════════════════════════

## 两层各摆几件，别让 16 × 12 m 的空间空成仓库。
## 家具全部**贴墙或靠角**，中间留出从大门直通楼梯的走道。
func _build_interior() -> void:
	var wood: Material = _mat["floor"]
	# ── 一层：南墙一张长桌 + 两把条凳 ──
	_solid("TableTop", Vector3(2.20, 2.02, 4.30), Vector3(4.20, 0.12, 1.10), wood)
	for sx in [-1.0, 1.0]:
		_solid("TableLeg", Vector3(2.20 + sx * 1.85, 1.0, 4.30),
			Vector3(0.14, 2.0, 0.90), wood)
	for dz in [-1.0, 1.0]:
		_solid("Bench", Vector3(2.20, 0.44, 4.30 + dz * 1.15),
			Vector3(3.40, 0.12, 0.42), wood)
		_solid("BenchLeg", Vector3(2.20, 0.22, 4.30 + dz * 1.15),
			Vector3(0.12, 0.44, 0.36), wood)

	# ── 一层：南墙上挂一幅「画」（框 + 白底 + 三色块）──
	# 这是整栋楼的点题之处：屋里也挂一张蒙德里安。
	var art_z := HALF_D - WALL_T - 0.06
	_deco("ArtFrame", Vector3(-2.60, 2.90, art_z), Vector3(4.40, 2.90, 0.10), _mat["black"])
	_deco("ArtCanvas", Vector3(-2.60, 2.90, art_z - 0.06), Vector3(4.16, 2.66, 0.06),
		_mat["white"])
	_deco("ArtRed", Vector3(-3.60, 3.60, art_z - 0.10), Vector3(1.30, 1.10, 0.04),
		_mat["red"])
	_deco("ArtBlue", Vector3(-1.45, 2.20, art_z - 0.10), Vector3(1.70, 0.90, 0.04),
		_mat["blue"])
	_deco("ArtYellow", Vector3(-3.75, 1.90, art_z - 0.10), Vector3(1.00, 0.70, 0.04),
		_mat["yellow"])

	# ── 二层：东墙一组矮柜 + 中央一张长桌 ──
	var y2 := FLOOR_H
	_solid("Cabinet", Vector3(HALF_W - WALL_T - 0.30, y2 + 0.45, 1.20),
		Vector3(0.55, 0.90, 3.20), _mat["yellow"])
	_solid("DeskTop", Vector3(-1.20, y2 + 0.76, 0.60), Vector3(3.60, 0.10, 1.30), wood)
	for sx in [-1.0, 1.0]:
		_solid("DeskLeg", Vector3(-1.20 + sx * 1.55, y2 + 0.38, 0.60),
			Vector3(0.12, 0.76, 1.10), wood)

	# ── 二层：楼梯井四周的栏杆（东沿，从北墙一直拦到楼梯上口）──
	# 只拦到 z = −0.10：再往南就是楼梯的出入口，拦上人就上不来二层了。
	_solid("RailE", Vector3(-(HALF_W - WALL_T) + STAIR_W - 0.05,
		FLOOR_H + 0.475, (-(HALF_D - WALL_T) - 0.10) * 0.5),
		Vector3(0.10, 0.95, (HALF_D - WALL_T) - 0.10), _mat["black"])


# ══════════════════════════ 灯 ══════════════════════════

## 两层各两盏（关阴影：本项目对功耗敏感，shop.gd 里也是这么做的）。
## 没有实体灯管的话，8 m 高的室内白天也是一片灰，看不出红/蓝/黄。
func _build_lights() -> void:
	for row in [[3.40, "1"], [7.20, "2"]]:
		var h: float = row[0]
		var tag: String = row[1]
		for sx in [-1.0, 1.0]:
			var l := OmniLight3D.new()
			l.name = "Light%s%s" % [tag, "W" if sx < 0.0 else "E"]
			l.position = Vector3(sx * 3.20, h, 0.40)
			l.light_color = Color(1.0, 0.94, 0.84)
			l.light_energy = 2.4
			l.omni_range = 13.0
			l.shadow_enabled = false
			add_child(l)
			_deco("Tube%s%s" % [tag, "W" if sx < 0.0 else "E"],
				Vector3(sx * 3.20, h + 0.10, 0.40), Vector3(1.80, 0.08, 0.30), _mat["lamp"])


# ══════════════════════════ 自检输出 ══════════════════════════

func _report() -> void:
	var p := global_position
	var per_run := STAIR_RUN / float(STAIR_STEPS)
	print("[Mondrian] 两层大房子：占地 %.2f × %.2f m、墙高 %.2f（一层 %.2f + 二层 %.2f）、墙厚 %.2f"
		% [HALF_W * 2.0, HALF_D * 2.0, TOP_H, FLOOR_H, TOP_H - FLOOR_H, WALL_T])
	print("[Mondrian] 世界位置 (%.2f, %.2f, %.2f)：x %.2f ~ %.2f、z %.2f ~ %.2f"
		% [p.x, p.y, p.z, p.x - HALF_W, p.x + HALF_W, p.z - HALF_D, p.z + HALF_D])
	print("[Mondrian] 门洞：宽 %.2f × 高 %.2f，开在北墙 z = %.2f（朝商店）"
		% [DOOR_HALF * 2.0, DOOR_H, p.z - HALF_D])
	print("[Mondrian] 楼梯：%d 级 × (%.2f 高 / %.2f 深)，坡度 %.2f（%.2f°），真踏步真碰撞"
		% [STAIR_STEPS, STAIR_RISE / float(STAIR_STEPS), per_run,
			STAIR_RISE / STAIR_RUN, rad_to_deg(atan2(STAIR_RISE / float(STAIR_STEPS), per_run))])
	print("[Mondrian] 碰撞盒 %d 个、装饰 %d 个" % [solid_count, decor_count])
