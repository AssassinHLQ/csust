extends Node3D
## 第二关「蒙德里安厅」的**室内**。外壳是 models/mondrian/mondrian_building.glb
## （来自 蒙德里安建筑/mondrian_building.blend，2026-10-31 那栋）。
##
## 为什么要单独建一层室内：GLB 是一整套实心体量 —— 从里面看外盒背面会被剔除
## （等于能看见天空），也没有碰撞。所以在体量内部贴 0.25 m 做一层薄壳：
## 楼板 / 四壁 / 天花，外面看不出差别，里面是实的。
##
## 楼层对应模型体量（Godot 坐标，Y 朝上，北 = -Z）：
##   L1 = Base    x[-12,12]  z[-8,8]   y 0.6 → 4.8   （东边被 Yellow_Block 占了，房间收到 x=5.75）
##   L2 = Mid     x[-10,8]   z[-7,7]   y 4.8 → 9.2   （西北角被 Blue_Block 占，房间从 x=-7.75 起）
##   L3 = Upper   x[-5,10]   z[-6,5]   y 9.2 → 13.0
## 南面 z≈8 是主入口，北面 z≈-8 是通关后开的出口（两处都在 Blender 里布尔切了洞）。
##
## 路线：L1 → 西侧斜坡井 → L2 → 东侧斜坡井 → L3 → 10.3 起跳台 → 11.3 终点台。
## 烘焙产物：scenes/mondrian_hall_interior_baked.tscn（改了常量重跑 _bake_mondrian_hall.gd）。

@export var auto_build := true

const FLOOR_Y := 0.5
const WALL_T := 0.30
const SLAB_T := 0.25

## 房间净空（内表面）
const L1_MIN := Vector2(-11.75, -7.75)
const L1_MAX := Vector2(5.75, 7.75)
const L1_TOP := 4.8
const L2_MIN := Vector2(-7.75, -6.75)
const L2_MAX := Vector2(7.75, 6.75)
const L2_TOP := 9.2
const L3_MIN := Vector2(-4.75, -5.75)
const L3_MAX := Vector2(9.75, 4.75)
const L3_TOP := 13.0

## 门洞（x0, x1, 底, 顶）
const DOOR_MAIN := Vector4(-4.30, 0.20, 0.55, 4.30)
const DOOR_EXIT := Vector4(1.00, 5.50, 0.55, 4.30)

## 斜坡井
const RAMP1_X := Vector2(-7.5, -5.0)
const RAMP1_Z0 := 5.0
const RAMP1_Z1 := -3.4
const RAMP2_X := Vector2(3.0, 5.5)
const RAMP2_Z0 := -4.0
const RAMP2_Z1 := 3.0

## 顶层终点
const PLAT_C := Vector2(6.5, -3.2)
const PLAT_TOP := 10.3
const LEDGE_C := Vector2(2.6, -4.9)
const LEDGE_TOP := 11.3

var _mat: Dictionary[String, Material] = {}
var _body: StaticBody3D
var _decor: Node3D
var _lights: Node3D
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
	_lights = Node3D.new()
	_lights.name = "Lights"
	add_child(_lights)
	_build_room1()
	_build_room2()
	_build_room3()
	_build_roof()
	_build_ramps()
	_build_grids()
	_build_lights()
	_build_furniture()
	_build_shell_collision()
	print("[mondrian_hall] solid=%d decor=%d" % [solid_count, decor_count])


# ══════════════════════════ 外壳碰撞（只有 collision，没有网格）══════════════════════════
#
# GLB 本身不带碰撞。室内墙体在里收 0.25 m，从外面推墙会先穿进那 0.25 m 的缝里，
# 从内侧看立面是背面被剔除的 —— 会「看穿」。所以按模型体量在外表面补一层碰撞壳。

func _shape(nm: String, center: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.name = _unique(_body, nm)
	cs.position = center
	_body.add_child(cs)


func _col_wall(nm: String, along_x: bool, at: float, from: float, to: float,
		bottom: float, top: float, openings: Array = []) -> void:
	var cuts: Array = openings.duplicate()
	cuts.sort_custom(func(a, b): return a[0] < b[0])
	var cursor := from
	var idx := 0
	for o in cuts:
		if o[0] > cursor:
			_col_seg(nm, along_x, at, cursor, o[0], bottom, top, idx)
			idx += 1
		cursor = max(cursor, o[1])
	if cursor < to:
		_col_seg(nm, along_x, at, cursor, to, bottom, top, idx)
	for o in cuts:
		if o[3] < top - 0.001:
			_col_seg(nm + "Head", along_x, at, o[0], o[1], o[3], top, idx)


func _col_seg(nm: String, along_x: bool, at: float, from: float, to: float,
		bottom: float, top: float, idx: int) -> void:
	var h: float = top - bottom
	if to - from <= 0.001 or h <= 0.001:
		return
	if along_x:
		_shape("%sC%d" % [nm, idx], Vector3((from + to) * 0.5, bottom + h * 0.5, at),
			Vector3(to - from, h, WALL_T))
	else:
		_shape("%sC%d" % [nm, idx], Vector3(at, bottom + h * 0.5, (from + to) * 0.5),
			Vector3(WALL_T, h, to - from))


func _build_shell_collision() -> void:
	# Base 外皮（正 / 北两面留门洞）
	_col_wall("ShellBaseS", true, 8.0, -12.0, 12.0, 0.6, 4.8,
		[[DOOR_MAIN.x, DOOR_MAIN.y, DOOR_MAIN.z, DOOR_MAIN.w]])
	_col_wall("ShellBaseN", true, -8.0, -12.0, 12.0, 0.6, 4.8,
		[[DOOR_EXIT.x, DOOR_EXIT.y, DOOR_EXIT.z, DOOR_EXIT.w]])
	_col_wall("ShellBaseW", false, -12.0, -8.0, 8.0, 0.6, 4.8)
	_col_wall("ShellBaseE", false, 12.0, -8.0, 8.0, 0.6, 4.8)
	# Mid / Upper 外皮
	_col_wall("ShellMidN", true, -7.0, -10.0, 8.0, 4.8, 9.2)
	_col_wall("ShellMidS", true, 7.0, -10.0, 8.0, 4.8, 9.2)
	_col_wall("ShellMidW", false, -10.0, -7.0, 7.0, 4.8, 9.2)
	_col_wall("ShellMidE", false, 8.0, -7.0, 7.0, 4.8, 9.2)
	_col_wall("ShellUpN", true, -6.0, -5.0, 10.0, 9.2, 13.0)
	_col_wall("ShellUpS", true, 5.0, -5.0, 10.0, 9.2, 13.0)
	_col_wall("ShellUpW", false, -5.0, -6.0, 5.0, 9.2, 13.0)
	_col_wall("ShellUpE", false, 10.0, -6.0, 5.0, 9.2, 13.0)
	# 进不去的实体体量：直接给实心碰撞
	_shape("ColYellow", Vector3(10.0, 3.1, 7.0), Vector3(8.0, 5.0, 8.0))
	_shape("ColBlue", Vector3(-12.0, 9.0, 6.0), Vector3(8.0, 4.0, 8.0))
	_shape("ColRedRoof", Vector3(4.5, 14.4, -3.5), Vector3(7.0, 2.8, 5.0))
	_shape("ColSkylight", Vector3(-2.5, 13.45, -2.0), Vector3(3.0, 0.9, 4.0))
	_shape("ColTerrace", Vector3(-5.0, 4.98, 10.0), Vector3(22.0, 0.4, 4.0))


# ══════════════════════════ 材质 ══════════════════════════

func _std(col: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


func _make_materials() -> void:
	_mat["white"] = _std(Color(0.855, 0.850, 0.825), 0.86)
	_mat["floor"] = _std(Color(0.585, 0.578, 0.560), 0.93)
	_mat["black"] = _std(Color(0.052, 0.052, 0.056), 0.55)
	_mat["red"] = _std(Color(0.780, 0.115, 0.100), 0.62)
	_mat["blue"] = _std(Color(0.095, 0.190, 0.610), 0.62)
	_mat["yellow"] = _std(Color(0.930, 0.800, 0.160), 0.62)
	var lamp := _std(Color(0.98, 0.96, 0.90), 0.5)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.95, 0.85)
	lamp.emission_energy_multiplier = 1.5
	_mat["lamp"] = lamp


# ══════════════════════════ 基础几何 ══════════════════════════

func _unique(parent: Node, base: String) -> String:
	var nm := base
	var i := 1
	while parent.has_node(nm):
		i += 1
		nm = "%s_%d" % [base, i]
	return nm


func _solid(nm: String, center: Vector3, size: Vector3, mat: Material) -> void:
	_box(_body, nm, center, size, mat, true)
	solid_count += 1


func _deco(nm: String, center: Vector3, size: Vector3, mat: Material) -> void:
	_box(_decor, nm, center, size, mat, false)
	decor_count += 1


func _box(parent: Node3D, nm: String, center: Vector3, size: Vector3,
		mat: Material, collide: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.name = _unique(parent, nm)
	mi.position = center
	parent.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.name = mi.name + "Shape"
		cs.position = center
		_body.add_child(cs)
	return mi


## 斜坡：沿 Z 倾斜的盒子，网格和碰撞共用一个 basis。
func _slope(nm: String, x: Vector2, z0: float, z1: float,
		y0: float, y1: float, mat: Material) -> void:
	var run: float = z1 - z0
	var rise: float = y1 - y0
	var length := sqrt(run * run + rise * rise)
	var c := Vector3((x.x + x.y) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5)
	var basis := Basis(Vector3.RIGHT, -atan2(rise, run))
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(x.y - x.x, 0.3, length)
	mi.mesh = bm
	mi.material_override = mat
	mi.name = _unique(_body, nm)
	mi.transform = Transform3D(basis, c)
	_body.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = bm.size
	cs.shape = bs
	cs.name = mi.name + "Shape"
	cs.transform = Transform3D(basis, c)
	_body.add_child(cs)
	solid_count += 1


## 一道墙。openings 每项 = [沿墙起, 沿墙止, 底, 顶]。
func _wall(nm: String, along_x: bool, at: float, from: float, to: float,
		bottom: float, top: float, openings: Array = []) -> void:
	var cuts: Array = openings.duplicate()
	cuts.sort_custom(func(a, b): return a[0] < b[0])
	var cursor := from
	var seg := 0
	for o in cuts:
		if o[0] > cursor:
			_wall_seg(nm, along_x, at, cursor, o[0], bottom, top, seg)
			seg += 1
		cursor = max(cursor, o[1])
	if cursor < to:
		_wall_seg(nm, along_x, at, cursor, to, bottom, top, seg)
	for o in cuts:
		if o[2] > bottom + 0.001:
			_wall_seg(nm + "Sill", along_x, at, o[0], o[1], bottom, o[2], seg)
			seg += 1
		if o[3] < top - 0.001:
			_wall_seg(nm + "Head", along_x, at, o[0], o[1], o[3], top, seg)
			seg += 1


func _wall_seg(nm: String, along_x: bool, at: float, from: float, to: float,
		bottom: float, top: float, idx: int) -> void:
	var h: float = top - bottom
	if to - from <= 0.001 or h <= 0.001:
		return
	if along_x:
		_solid("%s_%d" % [nm, idx], Vector3((from + to) * 0.5, bottom + h * 0.5, at),
			Vector3(to - from, h, WALL_T), _mat["white"])
	else:
		_solid("%s_%d" % [nm, idx], Vector3(at, bottom + h * 0.5, (from + to) * 0.5),
			Vector3(WALL_T, h, to - from), _mat["white"])


## 楼板：(x0,z0)-(x1,z1)，顶面在 y；holes 是 Rect2（x, z, 宽, 深）。
func _slab(nm: String, lo: Vector2, hi: Vector2, y: float, holes: Array = []) -> void:
	var top := y
	var mid := y - SLAB_T * 0.5
	if holes.is_empty():
		_solid(nm, Vector3((lo.x + hi.x) * 0.5, mid, (lo.y + hi.y) * 0.5),
			Vector3(hi.x - lo.x, SLAB_T, hi.y - lo.y), _mat["floor"])
		return
	var h: Rect2 = holes[0]
	_solid(nm + "_N", Vector3((lo.x + hi.x) * 0.5, mid, (lo.y + h.position.y) * 0.5),
		Vector3(hi.x - lo.x, SLAB_T, h.position.y - lo.y), _mat["floor"])
	_solid(nm + "_S", Vector3((lo.x + hi.x) * 0.5, mid, (h.end.y + hi.y) * 0.5),
		Vector3(hi.x - lo.x, SLAB_T, hi.y - h.end.y), _mat["floor"])
	_solid(nm + "_W", Vector3((lo.x + h.position.x) * 0.5, mid, h.get_center().y),
		Vector3(h.position.x - lo.x, SLAB_T, h.size.y), _mat["floor"])
	_solid(nm + "_E", Vector3((h.end.x + hi.x) * 0.5, mid, h.get_center().y),
		Vector3(hi.x - h.end.x, SLAB_T, h.size.y), _mat["floor"])


# ══════════════════════════ 三层房间 ══════════════════════════

func _build_room1() -> void:
	_solid("F1_Floor", Vector3((L1_MIN.x + L1_MAX.x) * 0.5, FLOOR_Y - 0.03,
		(L1_MIN.y + L1_MAX.y) * 0.5),
		Vector3(L1_MAX.x - L1_MIN.x, 0.06, L1_MAX.y - L1_MIN.y), _mat["floor"])
	_wall("W1_S", true, L1_MAX.y, L1_MIN.x, L1_MAX.x, FLOOR_Y, L1_TOP,
		[[DOOR_MAIN.x, DOOR_MAIN.y, DOOR_MAIN.z, DOOR_MAIN.w]])
	_wall("W1_N", true, L1_MIN.y, L1_MIN.x, L1_MAX.x, FLOOR_Y, L1_TOP,
		[[DOOR_EXIT.x, DOOR_EXIT.y, DOOR_EXIT.z, DOOR_EXIT.w]])
	_wall("W1_W", false, L1_MIN.x, L1_MIN.y, L1_MAX.y, FLOOR_Y, L1_TOP)
	_wall("W1_E", false, L1_MAX.x, L1_MIN.y, L1_MAX.y, FLOOR_Y, L1_TOP)
	# L1 天花 = L2 楼板；西侧开第一个井（井口要盖住斜坡上半段，否则爬坡撞头）
	_slab("F2", Vector2(L1_MIN.x - 0.15, L1_MIN.y - 0.15),
		Vector2(L2_MAX.x + 0.15, L1_MAX.y + 0.15), L1_TOP,
		[Rect2(RAMP1_X.x, -3.8, RAMP1_X.y - RAMP1_X.x, 6.0)])
	_well_trim("Well1", RAMP1_X, -3.8, 2.2, L1_TOP)


func _build_room2() -> void:
	_wall("W2_S", true, L2_MAX.y, L2_MIN.x, L2_MAX.x, L1_TOP, L2_TOP)
	_wall("W2_N", true, L2_MIN.y, L2_MIN.x, L2_MAX.x, L1_TOP, L2_TOP)
	_wall("W2_W", false, L2_MIN.x, L2_MIN.y, L2_MAX.y, L1_TOP, L2_TOP)
	_wall("W2_E", false, L2_MAX.x, L2_MIN.y, L2_MAX.y, L1_TOP, L2_TOP)
	# L2 天花 = L3 楼板；东侧开第二个井
	_slab("F3", Vector2(L2_MIN.x - 0.15, L2_MIN.y - 0.15),
		Vector2(L3_MAX.x + 0.15, L2_MAX.y + 0.15), L2_TOP,
		[Rect2(RAMP2_X.x, -1.6, RAMP2_X.y - RAMP2_X.x, 4.6)])
	_well_trim("Well2", RAMP2_X, -1.6, 3.0, L2_TOP)


func _build_room3() -> void:
	_wall("W3_S", true, L3_MAX.y, L3_MIN.x, L3_MAX.x, L2_TOP, L3_TOP)
	_wall("W3_N", true, L3_MIN.y, L3_MIN.x, L3_MAX.x, L2_TOP, L3_TOP)
	_wall("W3_W", false, L3_MIN.x, L3_MIN.y, L3_MAX.y, L2_TOP, L3_TOP)
	_wall("W3_E", false, L3_MAX.x, L3_MIN.y, L3_MAX.y, L2_TOP, L3_TOP)
	# 起跳台 + 终点台
	_solid("PlatformB", Vector3(PLAT_C.x, PLAT_TOP - 0.175, PLAT_C.y),
		Vector3(3.0, 0.35, 2.4), _mat["white"])
	_solid("PlatformB_Col", Vector3(PLAT_C.x, (L2_TOP + PLAT_TOP - 0.35) * 0.5, PLAT_C.y),
		Vector3(0.4, PLAT_TOP - 0.35 - L2_TOP, 0.4), _mat["black"])
	_solid("GoalLedge", Vector3(LEDGE_C.x, LEDGE_TOP - 0.175, LEDGE_C.y),
		Vector3(5.4, 0.35, 1.6), _mat["white"])
	_deco("GoalLedge_Red", Vector3(LEDGE_C.x, LEDGE_TOP + 0.01, LEDGE_C.y),
		Vector3(4.9, 0.02, 1.2), _mat["red"])
	_deco("PlatformB_Blue", Vector3(PLAT_C.x, PLAT_TOP + 0.01, PLAT_C.y),
		Vector3(2.6, 0.02, 2.0), _mat["blue"])


func _build_roof() -> void:
	_slab("F5", Vector2(L3_MIN.x - 0.15, L3_MIN.y - 0.15),
		Vector2(L3_MAX.x + 0.15, L3_MAX.y + 0.15), L3_TOP)


func _build_ramps() -> void:
	_slope("Ramp1", RAMP1_X, RAMP1_Z0, RAMP1_Z1, FLOOR_Y, L1_TOP, _mat["white"])
	_slope("Ramp2", RAMP2_X, RAMP2_Z0, RAMP2_Z1, L1_TOP, L2_TOP, _mat["white"])
	_ramp_rail("Ramp1", RAMP1_X, RAMP1_Z0, RAMP1_Z1, FLOOR_Y, L1_TOP)
	_ramp_rail("Ramp2", RAMP2_X, RAMP2_Z0, RAMP2_Z1, L1_TOP, L2_TOP)


## 斜坡两侧的白色栏板 + 黑压顶（带碰撞，防止从侧面滑下去）。
func _ramp_rail(nm: String, x: Vector2, z0: float, z1: float, y0: float, y1: float) -> void:
	var run: float = z1 - z0
	var rise: float = y1 - y0
	var length := sqrt(run * run + rise * rise)
	var basis := Basis(Vector3.RIGHT, -atan2(rise, run))
	var mid_u := (x.x + x.y) * 0.5
	var mid_y: float = (y0 + y1) * 0.5
	var mid_z: float = (z0 + z1) * 0.5
	for k in range(2):
		var side: float = x.x + 0.10 if k == 0 else x.y - 0.10
		var tag: String = "W" if side < mid_u else "E"
		_sloped_box("%s_Rail%s" % [nm, tag], Vector3(side, mid_y + 0.575, mid_z),
			Vector3(0.12, 0.85, length), basis, _mat["white"], true)
		_sloped_box("%s_Rail%s_Cap" % [nm, tag], Vector3(side, mid_y + 1.03, mid_z),
			Vector3(0.16, 0.06, length), basis, _mat["black"], false)


func _sloped_box(nm: String, c: Vector3, size: Vector3, basis: Basis,
		mat: Material, collide: bool) -> void:
	var host: Node3D = _body if collide else _decor
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.name = _unique(host, nm)
	mi.transform = Transform3D(basis, c)
	host.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.name = mi.name + "Shape"
		cs.transform = Transform3D(basis, c)
		_body.add_child(cs)
		solid_count += 1


## 井口黑色压边（装饰）。
func _well_trim(nm: String, x: Vector2, z0: float, z1: float, y: float) -> void:
	_deco(nm + "_TrimN", Vector3((x.x + x.y) * 0.5, y + 0.01, z0),
		Vector3(x.y - x.x + 0.16, 0.02, 0.16), _mat["black"])
	_deco(nm + "_TrimS", Vector3((x.x + x.y) * 0.5, y + 0.01, z1),
		Vector3(x.y - x.x + 0.16, 0.02, 0.16), _mat["black"])
	_deco(nm + "_TrimW", Vector3(x.x, y + 0.01, (z0 + z1) * 0.5),
		Vector3(0.16, 0.02, z1 - z0), _mat["black"])
	_deco(nm + "_TrimE", Vector3(x.y, y + 0.01, (z0 + z1) * 0.5),
		Vector3(0.16, 0.02, z1 - z0), _mat["black"])


# ══════════════════════════ 装饰：色块 + 黑线格 ══════════════════════════

func _build_grids() -> void:
	# 一层
	_panel_on("L1_N_Red", "N", L1_MIN, L1_MAX, -6.0, 2.5, 4.6, 2.6, _mat["red"])
	_panel_on("L1_N_Blue", "N", L1_MIN, L1_MAX, -10.3, 2.5, 2.4, 2.6, _mat["blue"])
	_panel_on("L1_W_Yellow", "W", L1_MIN, L1_MAX, 0.0, 2.4, 3.6, 2.2, _mat["yellow"])
	_panel_on("L1_S_Blue", "S", L1_MIN, L1_MAX, 3.2, 2.2, 3.0, 2.4, _mat["blue"])
	_band("L1_Band", "N", L1_MIN, L1_MAX, -3.0, 3.95, 17.0, 0.12)
	_band("L1_V1", "N", L1_MIN, L1_MAX, -4.3, 2.6, 0.12, 4.1)
	_band("L1_V2", "N", L1_MIN, L1_MAX, -1.6, 2.6, 0.12, 4.1)
	_skirt("L1", L1_MIN, L1_MAX, FLOOR_Y)
	# 二层
	_panel_on("L2_N_Yellow", "N", L2_MIN, L2_MAX, 3.0, 7.0, 5.0, 2.4, _mat["yellow"])
	_panel_on("L2_W_Red", "W", L2_MIN, L2_MAX, 1.0, 6.9, 3.4, 2.2, _mat["red"])
	_panel_on("L2_E_Blue", "E", L2_MIN, L2_MAX, -1.0, 7.0, 3.0, 2.2, _mat["blue"])
	_band("L2_Band", "N", L2_MIN, L2_MAX, 0.0, 8.45, 15.0, 0.12)
	_skirt("L2", L2_MIN, L2_MAX, L1_TOP)
	# 三层
	_panel_on("L3_N_Red", "N", L3_MIN, L3_MAX, 6.6, 11.0, 3.4, 2.6, _mat["red"])
	_panel_on("L3_N_Blue", "N", L3_MIN, L3_MAX, 0.0, 11.0, 4.4, 2.6, _mat["blue"])
	_panel_on("L3_E_Yellow", "E", L3_MIN, L3_MAX, 0.0, 10.9, 3.4, 2.2, _mat["yellow"])
	_band("L3_Band", "N", L3_MIN, L3_MAX, 2.0, 12.15, 14.0, 0.12)
	_skirt("L3", L3_MIN, L3_MAX, L2_TOP)
	# 一层地面：一圈黑框，给尺度感
	var gy := FLOOR_Y + 0.035
	_deco("FloorEdgeN", Vector3(-3.0, gy, -6.0), Vector3(13.0, 0.02, 0.10), _mat["black"])
	_deco("FloorEdgeS", Vector3(-3.0, gy, 6.0), Vector3(13.0, 0.02, 0.10), _mat["black"])
	_deco("FloorEdgeW", Vector3(-9.5, gy, 0.0), Vector3(0.10, 0.02, 12.0), _mat["black"])
	_deco("FloorEdgeE", Vector3(3.5, gy, 0.0), Vector3(0.10, 0.02, 12.0), _mat["black"])


## 在房间某一面墙上贴一块（side: N/S/E/W，uv 是沿墙 / 竖直的坐标）。
func _panel_on(nm: String, side: String, lo: Vector2, hi: Vector2,
		u: float, v: float, w: float, h: float, mat: Material, extra := 0.0) -> void:
	# 墙厚 0.3、以房间净空线为中线，所以内表面在 ±0.15，装饰再往里 0.03
	var off: float = WALL_T * 0.5 + 0.03 + extra
	match side:
		"N":
			_deco(nm, Vector3(u, v, lo.y + off), Vector3(w, h, 0.04), mat)
		"S":
			_deco(nm, Vector3(u, v, hi.y - off), Vector3(w, h, 0.04), mat)
		"W":
			_deco(nm, Vector3(lo.x + off, v, u), Vector3(0.04, h, w), mat)
		"E":
			_deco(nm, Vector3(hi.x - off, v, u), Vector3(0.04, h, w), mat)


## 黑色细条（黑线格的横 / 竖线）。
func _band(nm: String, side: String, lo: Vector2, hi: Vector2,
		u: float, v: float, w: float, h: float) -> void:
	_panel_on(nm, side, lo, hi, u, v, w, h, _mat["black"])


## 贴地的黑色踢脚线。
func _skirt(nm: String, lo: Vector2, hi: Vector2, floor_y: float) -> void:
	var v := floor_y + 0.07
	var off: float = WALL_T * 0.5 + 0.03
	var cx := (lo.x + hi.x) * 0.5
	var cz := (lo.y + hi.y) * 0.5
	_deco(nm + "_SkirtN", Vector3(cx, v, lo.y + off), Vector3(hi.x - lo.x, 0.14, 0.04), _mat["black"])
	_deco(nm + "_SkirtS", Vector3(cx, v, hi.y - off), Vector3(hi.x - lo.x, 0.14, 0.04), _mat["black"])
	_deco(nm + "_SkirtW", Vector3(lo.x + off, v, cz), Vector3(0.04, 0.14, hi.y - lo.y), _mat["black"])
	_deco(nm + "_SkirtE", Vector3(hi.x - off, v, cz), Vector3(0.04, 0.14, hi.y - lo.y), _mat["black"])


# ══════════════════════════ 灯 ══════════════════════════

func _lamp(nm: String, pos: Vector3, energy: float, color: Color) -> void:
	var l := OmniLight3D.new()
	l.name = nm
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = 18.0
	l.shadow_enabled = false
	_lights.add_child(l)


func _build_lights() -> void:
	var rows := [
		[Vector3(-6.0, L1_TOP - SLAB_T - 0.02, 0.0), 1.5],
		[Vector3(2.0, L1_TOP - SLAB_T - 0.02, 2.0), 1.4],
		[Vector3(-3.0, L2_TOP - SLAB_T - 0.02, 0.0), 1.4],
		[Vector3(4.0, L2_TOP - SLAB_T - 0.02, 0.0), 1.4],
		[Vector3(3.0, L3_TOP - SLAB_T - 0.02, -1.0), 1.3],
	]
	for i in range(rows.size()):
		var p: Vector3 = rows[i][0]
		var e: float = rows[i][1]
		_deco("CeilLamp%d" % i, p, Vector3(6.0, 0.05, 1.8), _mat["lamp"])
		_lamp("Lamp%d" % i, p - Vector3(0, 0.6, 0), e * 0.75, Color(1.0, 0.96, 0.88))


# ══════════════════════════ 室内陈设 ══════════════════════════
#
# 全部是装饰（不带碰撞）：跑道和靶子的视线都留空了 —— 一层斜坡在 x[-7.5,-5.0]，
# 二层斜坡在 x[3.0,5.5]，三层从斜坡口到起跳台那一条也不摆东西。

func _cyl(nm: String, center: Vector3, radius: float, height: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 24
	mi.mesh = cm
	mi.material_override = mat
	mi.name = _unique(_decor, nm)
	mi.position = center
	_decor.add_child(mi)
	decor_count += 1


## 椅子：黑托柱 + 座面 + 靠背。
func _chair(nm: String, base: Vector3, yaw: float, seat: Material) -> void:
	var b := Basis(Vector3.UP, yaw)
	_sloped_box(nm + "_Col", base + Vector3(0, 0.22, 0), Vector3(0.14, 0.44, 0.14), b, _mat["black"], true)
	_sloped_box(nm + "_Seat", base + Vector3(0, 0.46, 0), Vector3(0.52, 0.08, 0.52), b, seat, true)
	_sloped_box(nm + "_Back", base + b * Vector3(0, 0.78, -0.24), Vector3(0.52, 0.56, 0.07), b, seat, true)


## 桌子：台面 + 两端黑腿板。
func _desk(nm: String, center: Vector3, size: Vector2, height: float, top_mat: Material) -> void:
	_solid(nm + "_Top", Vector3(center.x, center.y + height, center.z),
		Vector3(size.x, 0.08, size.y), top_mat)
	_solid(nm + "_LegW", Vector3(center.x - size.x * 0.5 + 0.14, center.y + height * 0.5, center.z),
		Vector3(0.12, height, size.y * 0.78), _mat["black"])
	_solid(nm + "_LegE", Vector3(center.x + size.x * 0.5 - 0.14, center.y + height * 0.5, center.z),
		Vector3(0.12, height, size.y * 0.78), _mat["black"])


## 展台：白座 + 黑压边 + 顶上一个色块（当雕塑看）。
func _pedestal(nm: String, base: Vector3, size: float, art: Material) -> void:
	_solid(nm + "_Base", base + Vector3(0, size * 0.5, 0), Vector3(size, size, size), _mat["white"])
	_deco(nm + "_Rim", base + Vector3(0, size + 0.01, 0),
		Vector3(size + 0.05, 0.02, size + 0.05), _mat["black"])
	_solid(nm + "_Art", base + Vector3(0, size + 0.32, 0),
		Vector3(size * 0.5, 0.62, size * 0.5), art)


## 挂画：黑框 + 白画布 + 红黄蓝三块 + 一条竖黑线。
func _art(nm: String, side: String, lo: Vector2, hi: Vector2,
		u: float, v: float, w: float, h: float) -> void:
	_panel_on(nm + "_Frame", side, lo, hi, u, v, w, h, _mat["black"], 0.02)
	_panel_on(nm + "_Canvas", side, lo, hi, u, v, w - 0.18, h - 0.18, _mat["white"], 0.05)
	_panel_on(nm + "_Red", side, lo, hi, u - w * 0.20, v + h * 0.17,
		w * 0.40, h * 0.52, _mat["red"], 0.075)
	_panel_on(nm + "_Yel", side, lo, hi, u + w * 0.30, v + h * 0.28,
		w * 0.26, h * 0.30, _mat["yellow"], 0.075)
	_panel_on(nm + "_Blu", side, lo, hi, u + w * 0.28, v - h * 0.22,
		w * 0.30, h * 0.34, _mat["blue"], 0.075)
	_panel_on(nm + "_Line", side, lo, hi, u + w * 0.05, v,
		0.05, h - 0.2, _mat["black"], 0.09)


## 吊灯：黑吊杆 + 白色灯盘。
func _pendant(nm: String, top: Vector3, drop: float) -> void:
	_deco(nm + "_Rod", top - Vector3(0, drop * 0.5, 0), Vector3(0.04, drop, 0.04), _mat["black"])
	_cyl(nm + "_Shade", top - Vector3(0, drop, 0), 0.32, 0.09, _mat["lamp"])


func _rug(nm: String, center: Vector3, size: Vector2, mat: Material) -> void:
	_deco(nm, Vector3(center.x, center.y + 0.015, center.z), Vector3(size.x, 0.02, size.y), mat)
	var t := 0.10
	_deco(nm + "_BdN", Vector3(center.x, center.y + 0.028, center.z - size.y * 0.5),
		Vector3(size.x, 0.02, t), _mat["black"])
	_deco(nm + "_BdS", Vector3(center.x, center.y + 0.028, center.z + size.y * 0.5),
		Vector3(size.x, 0.02, t), _mat["black"])
	_deco(nm + "_BdW", Vector3(center.x - size.x * 0.5, center.y + 0.028, center.z),
		Vector3(t, 0.02, size.y), _mat["black"])
	_deco(nm + "_BdE", Vector3(center.x + size.x * 0.5, center.y + 0.028, center.z),
		Vector3(t, 0.02, size.y), _mat["black"])


func _build_furniture() -> void:
	_build_furniture_l1()
	_build_furniture_l2()
	_build_furniture_l3()


func _build_furniture_l1() -> void:
	var f := FLOOR_Y
	# 门内接待台
	_desk("L1_Desk", Vector3(-2.0, f, 4.2), Vector2(2.2, 0.9), 1.0, _mat["white"])
	_deco("L1_DeskFront", Vector3(-2.0, f + 0.55, 4.66), Vector3(1.4, 0.5, 0.05), _mat["red"])
	_deco("L1_DeskTop", Vector3(-2.0, f + 1.04, 4.2), Vector3(2.3, 0.04, 1.0), _mat["black"])
	# 地毯
	_rug("L1_Rug", Vector3(-2.2, f, -0.8), Vector2(8.6, 6.4), _mat["blue"])
	# 长桌 + 四把椅
	_desk("L1_Table", Vector3(1.4, f, -2.2), Vector2(2.4, 1.1), 0.74, _mat["white"])
	_chair("L1_ChairN1", Vector3(0.4, f, -0.8), PI, _mat["white"])
	_chair("L1_ChairN2", Vector3(2.2, f, -0.8), PI, _mat["yellow"])
	_chair("L1_ChairS1", Vector3(0.4, f, -3.6), 0.0, _mat["white"])
	_chair("L1_ChairS2", Vector3(2.2, f, -3.6), 0.0, _mat["red"])
	# 西侧展台
	_pedestal("L1_Ped1", Vector3(-9.6, f, -4.4), 1.0, _mat["yellow"])
	_pedestal("L1_Ped2", Vector3(-9.6, f, -1.4), 1.0, _mat["red"])
	# 西墙长凳
	_solid("L1_Bench", Vector3(-10.9, f + 0.42, 3.2), Vector3(0.55, 0.12, 3.0), _mat["yellow"])
	_solid("L1_BenchBase", Vector3(-10.9, f + 0.20, 3.2), Vector3(0.32, 0.40, 2.4), _mat["black"])
	# 挂画
	_art("L1_Art1", "W", L1_MIN, L1_MAX, -4.8, 2.7, 1.9, 1.5)
	_art("L1_Art2", "E", L1_MIN, L1_MAX, -3.4, 2.7, 1.7, 1.3)
	_art("L1_Art3", "S", L1_MIN, L1_MAX, -8.6, 2.7, 1.8, 1.4)
	# 吊灯
	_pendant("L1_Pend1", Vector3(-6.0, L1_TOP - SLAB_T, 1.2), 0.95)
	_pendant("L1_Pend2", Vector3(1.8, L1_TOP - SLAB_T, 1.2), 0.95)


func _build_furniture_l2() -> void:
	var f := L1_TOP
	_rug("L2_Rug", Vector3(-1.0, f, -1.4), Vector2(6.6, 4.6), _mat["yellow"])
	_desk("L2_Table", Vector3(-1.0, f, -1.4), Vector2(3.4, 1.2), 0.74, _mat["white"])
	_chair("L2_ChairN1", Vector3(-2.2, f, 0.0), PI, _mat["blue"])
	_chair("L2_ChairN2", Vector3(-0.4, f, 0.0), PI, _mat["white"])
	_chair("L2_ChairN3", Vector3(1.2, f, 0.0), PI, _mat["red"])
	_chair("L2_ChairS1", Vector3(-2.2, f, -2.8), 0.0, _mat["white"])
	_chair("L2_ChairS2", Vector3(-0.4, f, -2.8), 0.0, _mat["yellow"])
	_chair("L2_ChairS3", Vector3(1.2, f, -2.8), 0.0, _mat["white"])
	# 南墙沙发
	_solid("L2_Sofa", Vector3(-5.4, f + 0.42, 4.9), Vector3(2.8, 0.45, 0.95), _mat["blue"])
	_solid("L2_SofaBack", Vector3(-5.4, f + 0.88, 5.32), Vector3(2.8, 0.95, 0.18), _mat["blue"])
	_solid("L2_SofaArmW", Vector3(-6.8, f + 0.62, 4.9), Vector3(0.18, 0.6, 0.95), _mat["black"])
	_solid("L2_SofaArmE", Vector3(-4.0, f + 0.62, 4.9), Vector3(0.18, 0.6, 0.95), _mat["black"])
	# 东侧展台
	_pedestal("L2_Ped1", Vector3(6.4, f, -4.6), 0.9, _mat["blue"])
	_art("L2_Art1", "W", L2_MIN, L2_MAX, -3.6, 7.2, 1.8, 1.4)
	_art("L2_Art2", "E", L2_MIN, L2_MAX, -3.8, 7.2, 1.6, 1.2)
	_pendant("L2_Pend1", Vector3(-3.2, L2_TOP - SLAB_T, 0.4), 1.0)
	_pendant("L2_Pend2", Vector3(2.6, L2_TOP - SLAB_T, 0.4), 1.0)


func _build_furniture_l3() -> void:
	var f := L2_TOP
	# 西侧休息角
	_solid("L3_Sofa", Vector3(-3.5, f + 0.42, -1.4), Vector3(0.95, 0.45, 2.8), _mat["red"])
	_solid("L3_SofaBack", Vector3(-3.92, f + 0.88, -1.4), Vector3(0.18, 0.95, 2.8), _mat["red"])
	_desk("L3_Table", Vector3(-1.7, f, -1.4), Vector2(1.3, 1.3), 0.52, _mat["white"])
	_deco("L3_TableTop", Vector3(-1.7, f + 0.56, -1.4), Vector3(1.4, 0.03, 1.4), _mat["black"])
	_chair("L3_Chair1", Vector3(-0.5, f, -1.4), -PI * 0.5, _mat["yellow"])
	_chair("L3_Chair2", Vector3(-2.9, f, 0.2), PI, _mat["blue"])
	# 展台
	_pedestal("L3_Ped1", Vector3(8.6, f, -4.4), 0.9, _mat["yellow"])
	_art("L3_Art1", "W", L3_MIN, L3_MAX, 2.6, 10.9, 1.6, 1.3)
	_art("L3_Art2", "S", L3_MIN, L3_MAX, -2.4, 10.9, 1.6, 1.3)
	_pendant("L3_Pend1", Vector3(-1.7, L3_TOP - SLAB_T, -1.4), 1.2)
	_pendant("L3_Pend2", Vector3(1.6, L3_TOP - SLAB_T, -1.4), 1.2)
