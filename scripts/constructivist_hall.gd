class_name ConstructivistHall
extends Node3D
## 构成主义（Constructivism）大厅 —— 第二个场景的场地。
##
## 用户 2026-10-27：「完善第二个场景，做关卡，这次使用构成主义」。
##
## ── 风格来源 ──
## 1920 年代苏联构成主义（罗德琴科 / 李西茨基）：纸白 + 正红 + 纯黑，
## 斜线、楔形、圆、粗直的字。标志性构图是李西茨基《用红楔击溃白军》：
## 一个红色三角楔子插进白色圆里 —— 本关正中央那条**红色坡道**就是那个楔子。
##
## ── 布局（世界坐标，单位米）──
##   大厅：x ±14、z ±9、高 10，墙厚 0.35
##   入口：南墙（+Z），场景门在 (0, 0, 8.45)，门两侧各一根红壁柱
##   红楔坡道：x 中心 −10.5、宽 2.6，从 z = +2.8（y=0）爬到 z = −3.6（y=3.2）
##   平台 A：顶面 3.2，中心 (−10.5, −5.3)，3.6 × 3.4
##   平台 B：顶面 4.2，中心 (−5.8, −7.0)，3.2 × 2.8
##   终点台：顶面 5.2，中心 (1.0, −8.2)，6.0 × 1.6（贴着北墙）
##   三个靶子：北墙 (8, 2.6) / (12, 5.4)、东墙 (13.78, 4.0, z=+2)
##
## ⚠️ 平台之间落差都是 **1.0 m**（跳跃高度 1.26 m，留 0.26 余量）；
##    水平间距最大约 2.2 m（跑跳能过）。改高度时别超过 1.1 m。
##
## ── 为什么代码建 + 烘焙 ──
## 和蒙德里安大楼同一套路：参数化建一遍 → `_bake_hall.gd` 烘成
## `scenes/constructivist_hall_baked.tscn` → 在 `next_level.tscn` 里实例化。
## 烘完之后每一块都能在编辑器里拖；改构图改这里的常量再重烘。

const TUCK := 0.02
const SINK := 0.02

# ══════════════════════════ 尺寸 ══════════════════════════
const HALF_W := 14.0
const HALF_D := 9.0
const HEIGHT := 10.0
const WALL_T := 0.35

## 红楔坡道
const RAMP_X := -10.5
const RAMP_W := 2.6
const RAMP_RUN := 6.4
const RAMP_RISE := 3.2
## 低端（+Z）的 z 与高端（−Z）的 z
const RAMP_Z0 := 2.8
const RAMP_Z1 := RAMP_Z0 - RAMP_RUN      # −3.6

## 平台/终点台（top = 顶面高度）
const A_TOP := 3.2
const A_C := Vector3(-10.5, 0.0, -5.3)
const A_SIZE := Vector3(3.6, 0.35, 3.4)
const B_TOP := 4.2
const B_C := Vector3(-5.8, 0.0, -7.0)
const B_SIZE := Vector3(3.2, 0.35, 2.8)
const GOAL_TOP := 5.2
const GOAL_C := Vector3(1.0, 0.0, -8.2)
const GOAL_SIZE := Vector3(6.0, 0.35, 1.6)

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
	_build_shell()
	_build_floor_art()
	_build_route()
	_build_wall_art()
	_build_entrance()
	_build_ceiling_beams()
	_build_lights()
	_report()


# ══════════════════════════ 材质 ══════════════════════════
#
# 构成主义的三个色：纸白（略带暖灰）、正红（比蒙德里安那个更暗、更「印刷」）、
# 纯黑。再加一个深灰给地面 —— 纯黑地面在光照下看不出斜线。

func _make_materials() -> void:
	_mat["paper"] = _std(Color(0.905, 0.878, 0.820), 0.88)
	_mat["red"] = _std(Color(0.745, 0.125, 0.110), 0.62)
	_mat["red_dark"] = _std(Color(0.520, 0.085, 0.075), 0.68)
	_mat["black"] = _std(Color(0.055, 0.055, 0.058), 0.52)
	_mat["floor"] = _std(Color(0.235, 0.225, 0.215), 0.94)
	_mat["gray"] = _std(Color(0.470, 0.455, 0.435), 0.82)
	var lamp := _std(Color(0.97, 0.94, 0.87), 0.55)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.90, 0.72)
	lamp.emission_energy_multiplier = 2.2
	_mat["lamp"] = lamp


func _std(col: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


# ══════════════════════════ 小工具 ══════════════════════════

func _solid(node_name: String, center: Vector3, size: Vector3, mat: Material) -> void:
	_box(_body, node_name, center, size, mat, true)
	solid_count += 1


func _deco(node_name: String, center: Vector3, size: Vector3, mat: Material) -> void:
	_box(_decor, node_name, center, size, mat, false)
	decor_count += 1


func _box(parent: Node3D, node_name: String, center: Vector3, size: Vector3,
		mat: Material, with_collision: bool) -> MeshInstance3D:
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
	return mi


## 旋转盒（斜梁、斜坡碰撞）。`basis` 同时给网格和碰撞。
func _tilted_box(node_name: String, center: Vector3, size: Vector3, basis: Basis,
		mat: Material, collide := false) -> MeshInstance3D:
	var host: Node3D = _body if collide else _decor
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.name = _unique_name(host, node_name)
	mi.transform = Transform3D(basis, center)
	host.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.name = mi.name + "Shape"
		cs.transform = Transform3D(basis, center)
		_body.add_child(cs)
		solid_count += 1
	else:
		decor_count += 1
	return mi


func _unique_name(parent: Node3D, base: String) -> String:
	var nm := base
	var n := 1
	while parent.has_node(NodePath(nm)):
		nm = "%s_%d" % [base, n]
		n += 1
	return nm


func _label(text: String, pos: Vector3, size: float, color: Color,
		yaw := 0.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 96
	l.pixel_size = size / 96.0
	l.modulate = color
	l.outline_size = 18
	l.outline_modulate = Color(0, 0, 0, 0.9) if color.v > 0.5 else Color(0.9, 0.88, 0.82, 0.9)
	l.no_depth_test = false
	l.rotation.y = yaw
	l.position = pos
	_decor.add_child(l)
	decor_count += 1
	return l


# ══════════════════════════ 外壳 ══════════════════════════

func _build_shell() -> void:
	# 地面（深灰）：顶面 y = 0
	_solid("Floor", Vector3(0.0, -0.3, 0.0),
		Vector3(HALF_W * 2.0, 0.6, HALF_D * 2.0), _mat["floor"])
	# 天花板（黑）：底面 y = 10
	_solid("Ceiling", Vector3(0.0, HEIGHT + 0.2, 0.0),
		Vector3(HALF_W * 2.0, 0.4, HALF_D * 2.0), _mat["black"])
	# 四面墙（纸白，内表面严格在 ±HALF_W / ±HALF_D）
	var w := HALF_W + WALL_T * 0.5
	var d := HALF_D + WALL_T * 0.5
	_solid("WallN", Vector3(0.0, HEIGHT * 0.5, -d),
		Vector3(HALF_W * 2.0 + WALL_T * 2.0, HEIGHT, WALL_T), _mat["paper"])
	_solid("WallS", Vector3(0.0, HEIGHT * 0.5, d),
		Vector3(HALF_W * 2.0 + WALL_T * 2.0, HEIGHT, WALL_T), _mat["paper"])
	_solid("WallW", Vector3(-w, HEIGHT * 0.5, 0.0),
		Vector3(WALL_T, HEIGHT, HALF_D * 2.0), _mat["paper"])
	_solid("WallE", Vector3(w, HEIGHT * 0.5, 0.0),
		Vector3(WALL_T, HEIGHT, HALF_D * 2.0), _mat["paper"])
	# 黑色踢脚线（贴墙、凸出 2 cm）
	for spec in [["BaseN", Vector3(0.0, 0.15, -HALF_D + 0.02), Vector3(HALF_W * 2.0, 0.30, 0.04)],
			["BaseS", Vector3(0.0, 0.15, HALF_D - 0.02), Vector3(HALF_W * 2.0, 0.30, 0.04)]]:
		_deco(str(spec[0]), spec[1], spec[2], _mat["black"])
	for spec in [["BaseW", Vector3(-HALF_W + 0.02, 0.15, 0.0), Vector3(0.04, 0.30, HALF_D * 2.0)],
			["BaseE", Vector3(HALF_W - 0.02, 0.15, 0.0), Vector3(0.04, 0.30, HALF_D * 2.0)]]:
		_deco(str(spec[0]), spec[1], spec[2], _mat["black"])


## 地面图案：一个巨大的红圆 + 两条黑色斜线（李西茨基的「红楔击白圆」母题）。
## 全部贴地 1.2 cm，没有碰撞 —— 跑跳不受影响。
func _build_floor_art() -> void:
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 4.2
	cm.bottom_radius = 4.2
	cm.height = 0.024
	cm.radial_segments = 48
	disc.mesh = cm
	disc.material_override = _mat["red"]
	disc.name = "FloorDisc"
	disc.position = Vector3(2.0, 0.012, 1.5)
	_decor.add_child(disc)
	decor_count += 1
	for i in 2:
		var ang := deg_to_rad(24.0)
		_tilted_box("FloorStripe%d" % i, Vector3(2.0, 0.014, 1.5 + (6.5 if i == 0 else -6.5)),
			Vector3(26.0, 0.02, 0.32), Basis(Vector3.UP, ang), _mat["black"])


# ══════════════════════════ 路线：红楔坡道 + 三级平台 ══════════════════════════

func _build_route() -> void:
	# ── 红楔坡道：三角形截面沿 X 挤出；升起方向朝 −Z ──
	var angle := atan2(RAMP_RISE, RAMP_RUN)
	var slope_len := sqrt(RAMP_RUN * RAMP_RUN + RAMP_RISE * RAMP_RISE)
	var z_mid := (RAMP_Z0 + RAMP_Z1) * 0.5
	var mid := Vector3(RAMP_X, RAMP_RISE * 0.5, z_mid)
	# 坡面法线朝上、朝 +Z（因为往 −Z 升）
	var normal := Vector3(0.0, cos(angle), sin(angle))
	var tilt := Basis(Vector3.RIGHT, angle)
	var prism := PrismMesh.new()
	prism.size = Vector3(RAMP_RUN, RAMP_RISE, RAMP_W)
	prism.left_to_right = 1.0
	var ramp := MeshInstance3D.new()
	ramp.name = "Ramp"
	ramp.mesh = prism
	ramp.material_override = _mat["red"]
	ramp.rotation.y = PI * 0.5          # 竖直边落在 −Z（高端），宽度沿 X
	ramp.position = mid
	_decor.add_child(ramp)
	decor_count += 1
	# 碰撞：旋转盒，顶面与斜面重合
	_tilted_box("RampShape", mid - normal * 0.12,
		Vector3(RAMP_W, 0.24, slope_len), tilt, _mat["red"], true)
	# 东侧斜栏板（黑）
	var guard_c := Vector3(RAMP_X + RAMP_W * 0.5 - 0.06, mid.y, mid.z) \
		+ normal * 0.475
	_tilted_box("RampGuard", guard_c, Vector3(0.12, 0.95, slope_len), tilt,
		_mat["black"], true)

	# ── 平台 A / B / 终点台：黑色厚板 + 支撑 ──
	_solid("PlatformA", Vector3(A_C.x, A_TOP - A_SIZE.y * 0.5, A_C.z), A_SIZE, _mat["black"])
	_solid("PlatformAColumn", Vector3(A_C.x, (A_TOP - A_SIZE.y) * 0.5, A_C.z),
		Vector3(1.8, A_TOP - A_SIZE.y, 1.8), _mat["gray"])
	_solid("PlatformB", Vector3(B_C.x, B_TOP - B_SIZE.y * 0.5, B_C.z), B_SIZE, _mat["black"])
	# B 用两根吊杆挂在天花板上
	for dx in [-1.1, 1.1]:
		_deco("HangerB", Vector3(B_C.x + dx, B_TOP + (HEIGHT - B_TOP) * 0.5, B_C.z),
			Vector3(0.16, HEIGHT - B_TOP, 0.16), _mat["black"])
	_solid("GoalLedge", Vector3(GOAL_C.x, GOAL_TOP - GOAL_SIZE.y * 0.5, GOAL_C.z),
		GOAL_SIZE, _mat["black"])
	for dx in [-2.1, 2.1]:
		_deco("GoalBracket", Vector3(GOAL_C.x + dx, GOAL_TOP + 1.2, GOAL_C.z - 0.2),
			Vector3(0.18, 0.5, 1.4), _mat["black"])
		_deco("GoalRod", Vector3(GOAL_C.x + dx, GOAL_TOP + (HEIGHT - GOAL_TOP) * 0.5,
			GOAL_C.z - 0.55), Vector3(0.14, HEIGHT - GOAL_TOP - 0.5, 0.14), _mat["black"])

	# 坡道旁的标语：贴在**西墙**上朝屋里，别浮在空中
	_label("向上", Vector3(-HALF_W + 0.15, 3.4, 0.6), 1.5, _mat["black"].albedo_color,
		PI * 0.5)


# ══════════════════════════ 墙面构图 ══════════════════════════

func _build_wall_art() -> void:
	var zf := -HALF_D + 0.02      # 北墙内表面往里 2 cm
	# ── 红色大楔子（朝上的三角），左侧 ──
	var wedge := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(9.0, 6.0, 0.24)
	pm.left_to_right = 1.0
	wedge.name = "WallWedge"
	wedge.mesh = pm
	wedge.material_override = _mat["red"]
	# 三角形本来就在 XY 平面、沿 Z 挤出（很薄），不用旋转
	wedge.position = Vector3(-5.8, 5.0, zf + 0.06)
	_decor.add_child(wedge)
	decor_count += 1
	# ── 黑色大圆（李西茨基的「圆」）──
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 3.2
	cm.bottom_radius = 3.2
	cm.height = 0.22
	cm.radial_segments = 48
	disc.name = "WallDisc"
	disc.mesh = cm
	disc.material_override = _mat["black"]
	disc.rotation.x = PI * 0.5
	disc.position = Vector3(7.0, 6.3, zf + 0.06)
	_decor.add_child(disc)
	decor_count += 1
	# ── 斜穿整面墙的黑梁（20°）──
	_tilted_box("WallBeam", Vector3(0.0, 7.9, zf + 0.10),
		Vector3(27.0, 0.55, 0.18), Basis(Vector3.BACK, deg_to_rad(14.0)), _mat["black"])
	# ── 红色横带 ──
	_deco("WallBand", Vector3(0.0, 1.15, zf + 0.08), Vector3(27.6, 0.35, 0.12), _mat["red"])
	# ── 字：白圆上的黑「01」与墙上的黑「前进」──
	_label("01", Vector3(7.0, 6.3, zf + 0.20), 2.6, Color(0.93, 0.90, 0.83), 0.0)
	# 北墙左侧被平台挡住、右侧是「01」，标语改放**东墙**（纸白底黑字最清楚）
	_label("前进", Vector3(HALF_W - 0.15, 6.0, 4.0), 2.0, _mat["black"].albedo_color,
		-PI * 0.5)

	# ── 东墙：一条红色竖带 + 一个黑色斜块 ──
	var xe := HALF_W - 0.02
	_deco("EastBand", Vector3(xe, 5.0, 3.4), Vector3(0.10, 8.0, 0.9), _mat["red"])
	_tilted_box("EastBeam", Vector3(xe - 0.08, 6.2, 0.0),
		Vector3(0.16, 1.1, 12.0), Basis(Vector3.RIGHT, deg_to_rad(18.0)), _mat["black"])

	# ── 西墙：坡道后面一块黑色方块 ──
	_deco("WestBlock", Vector3(-HALF_W + 0.06, 3.4, -5.8),
		Vector3(0.12, 4.2, 3.0), _mat["black"])


## 入口：南墙上的红壁柱 + 黑门楣（场景门在 (0, 0, 8.45)）
func _build_entrance() -> void:
	var zs := HALF_D - 0.02
	for dx in [-1.75, 1.75]:
		_solid("PortalPillar", Vector3(dx, 1.9, zs - 0.18),
			Vector3(0.42, 3.8, 0.42), _mat["red"])
	_deco("PortalLintel", Vector3(0.0, 3.95, zs - 0.18),
		Vector3(4.2, 0.35, 0.46), _mat["black"])


## 天花板下两根斜梁 + 两条红色吊带
func _build_ceiling_beams() -> void:
	for i in 2:
		var z := -3.0 + float(i) * 9.0
		_tilted_box("CeilBeam%d" % i, Vector3(0.0, HEIGHT - 0.5, z),
			Vector3(27.0, 0.45, 0.30), Basis(Vector3.BACK, deg_to_rad(-9.0)), _mat["black"])
	for dx in [-4.0, 4.0]:
		_deco("HangingBanner", Vector3(dx, 8.4, -6.0),
			Vector3(1.6, 3.0, 0.06), _mat["red"])


func _build_lights() -> void:
	for p in [Vector3(-8.0, 8.4, -4.0), Vector3(8.0, 8.4, -4.0),
			Vector3(-8.0, 8.4, 4.0), Vector3(8.0, 8.4, 4.0)]:
		var l := OmniLight3D.new()
		l.name = "Light"
		l.position = p
		l.light_color = Color(1.0, 0.94, 0.84)
		l.light_energy = 2.4
		l.omni_range = 17.0
		l.shadow_enabled = false
		add_child(l)
	# 北墙上的红色氛围灯（把红楔/圆从黑里挑出来）
	var red := OmniLight3D.new()
	red.name = "LightRed"
	red.position = Vector3(2.0, 6.5, -6.5)
	red.light_color = Color(1.0, 0.32, 0.26)
	red.light_energy = 1.8
	red.omni_range = 14.0
	red.shadow_enabled = false
	add_child(red)


func _report() -> void:
	print("[Constructivist] 大厅：%.0f × %.0f m、高 %.1f；红楔坡道 %.1f°、平台顶面 %.1f / %.1f / %.1f"
		% [HALF_W * 2.0, HALF_D * 2.0, HEIGHT,
			rad_to_deg(atan2(RAMP_RISE, RAMP_RUN)), A_TOP, B_TOP, GOAL_TOP])
	print("[Constructivist] 碰撞盒 %d 个、装饰 %d 个" % [solid_count, decor_count])