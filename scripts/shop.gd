class_name Shop
extends Node3D
## 商店（新区域）：盖在**初始小屋**（`MeshHut`）右边的平台外面。
##
## ── 用户 2026-10-21 的原话 ──
## 「现在要做新的区域，商店，…但是不要在这个场景加载，否则会爆炸显存，你先建一个商店房子，
##   这个房子是 2 个初始房间这么长，可能放不下，你往初始房子右边虚空扩建地板面就行了」
##
## 所以这一版**只盖房子 + 铺地板**，高斯泼溅（`splatdata/shop_raw.sog`，70 MB）一概不加载 ——
## `SplatSlot` 是个空节点，等以后单独做「按需流式加载」再往里塞。
##
## ── 尺寸从哪来 ──
## 不写死数字，直接从 `MeshHut/Hut/Walls`（CSGBox3D）与 `Hut/Roof` 上量：
##   长 = `modules` × 小屋外墙长（2 × 6.60 = **13.20 m**）
##   进深 = 小屋外墙进深（5.60 m）　墙高 = 小屋墙高（2.50 m）
## 这样以后改小屋（用户把墙从 3.00 压到 2.50 那次），商店跟着变，不会两边对不上。
##
## ── 盖在哪 ──
## 小屋在 (14, 0, -15.5)，屋顶外沿 x = 17.70；
## 留 `gap` = 3.0 m 走道 → 商店西墙 x = **20.70**，东墙 x = **33.90**，中心 x = 27.30。
## 平台只到 x = ±20，所以商店整块都在平台外面 —— 地板从平台边沿 `x = 20.01` 一路铺到 34.40。
##
## ⚠️ 地板为什么不和平台叠着放 —— 平台网格在 x 上偏了 5.6 mm（`Floor/Mesh` 的
##    `0.005619049`），两块同高面一重叠就会在接缝处闪（z-fighting），所以地板从
##    20.01 起、**留 1 cm 缝**。胶囊半径 0.30，跨得过去；别为了好看去重叠。
##
## ⚠️ 墙、家具全部是「一个数字 → 网格 + 碰撞盒各一份」（`_box()`），不走 CSG ——
##    见 README §1.13 ⑦「删了网格 ≠ 删了碰撞」。

## ── 地块参照（找不到就退回默认值，不会崩）──
@export_group("地块参照")
@export var hut_path: NodePath = ^"../MeshHut"
@export var floor_path: NodePath = ^"../Floor"
@export var floor_mesh_path: NodePath = ^"../Floor/Mesh"

@export_group("尺寸")
## 商店长度 = modules × 初始小屋外墙长。用户要的是「2 个初始房间这么长」。
@export var modules := 2.0
## 小屋屋顶外沿 → 商店西墙的空当（走道宽度）
@export var gap := 3.0
## 地板比商店进深每侧多铺多少（留出沿街走的余地，别一脚踩空）
@export var walk_pad := 1.3
## 地板比商店东墙再多铺多少
@export var deck_margin := 0.5
@export var deck_thickness := 0.5
@export var door_width := 1.6
@export var door_height := 2.3

@export_group("外观")
@export var sign_text := "天使24"
@export var wall_thickness := 0.2
## 单独 instance 出来看效果时打开；`game.gd` 里是等铺完地砖再手动 `build()`（材质才一样）
@export var auto_build := false

## 量出来的数（自检 / 探针直接读，别自己再算一遍）
var hut_len := 0.0
var hut_depth := 0.0
var hut_height := 0.0
var roof_overhang := 0.4
var shop_len := 0.0
var shop_depth := 0.0
## 地板范围：世界坐标 (x, z)，`position` = 西南角
var deck_rect := Rect2()
var built_count := 0              # 带碰撞的箱体
var decor_count := 0              # 不挡人的装饰

var _built := false
var _body: StaticBody3D           # 墙 + 家具：一个刚体装所有碰撞盒
var _decor: Node3D                # 门框、招牌、灯、玻璃外的装饰
var _mat := {}


func _ready() -> void:
	if auto_build:
		build()


## 由 `game.gd` 在地砖铺完之后调用（顺序见 `game.gd::_build_shop()`）。
func build() -> void:
	if _built:
		return
	_built = true
	_measure()
	_make_materials()
	_body = StaticBody3D.new()
	_body.name = "Body"
	add_child(_body)
	_decor = Node3D.new()
	_decor.name = "Decor"
	add_child(_decor)
	_build_deck()
	_build_shell()
	_build_interior()
	_build_lights()
	_report()


# ══════════════════════════ 量尺寸 ══════════════════════════

func _measure() -> void:
	var hut := _find_3d(hut_path, "MeshHut")
	var walls: CSGBox3D = null
	var roof: CSGBox3D = null
	if hut != null:
		walls = hut.get_node_or_null("Hut/Walls") as CSGBox3D
		roof = hut.get_node_or_null("Hut/Roof") as CSGBox3D
	hut_len = walls.size.x if walls != null else 6.6
	hut_depth = walls.size.z if walls != null else 5.6
	hut_height = walls.size.y if walls != null else 2.5
	roof_overhang = 0.4
	if roof != null:
		roof_overhang = maxf((roof.size.x - hut_len) * 0.5, (roof.size.z - hut_depth) * 0.5)

	shop_len = modules * hut_len
	shop_depth = hut_depth

	# 平台：走碰撞盒（BoxShape3D），不走网格 —— 网格在 x 上偏了 5.6 mm
	var floor_body := _find_3d(floor_path, "Floor")
	var shape: CollisionShape3D = null
	if floor_body != null:
		shape = floor_body.get_node_or_null("Collision") as CollisionShape3D
	var box: BoxShape3D = null
	if shape != null:
		box = shape.shape as BoxShape3D
	var platform_right := 20.0
	var platform_top := 0.0
	if box != null:
		platform_right = shape.global_position.x + box.size.x * 0.5
		platform_top = shape.global_position.y + box.size.y * 0.5

	var hut_x := hut.global_position.x if hut != null else 14.0
	var hut_z := hut.global_position.z if hut != null else -15.5
	var hut_roof_half := hut_len * 0.5 + roof_overhang

	# 商店自己的位置：西墙 = 小屋屋顶外沿 + 走道
	var center_x := hut_x + hut_roof_half + gap + shop_len * 0.5
	var center_z := hut_z
	global_position = Vector3(center_x, platform_top, center_z)

	# 地板：从平台边沿（+1 cm 防 z-fighting）铺到商店东墙 + deck_margin
	var x0 := platform_right + 0.01
	var x1 := center_x + shop_len * 0.5 + deck_margin
	var z0 := center_z - (shop_depth * 0.5 + walk_pad)
	var z1 := center_z + (shop_depth * 0.5 + walk_pad)
	deck_rect = Rect2(Vector2(x0, z0), Vector2(x1 - x0, z1 - z0))


## 先按 NodePath 找；找不到就在当前场景里按名字找
## （`Shop` 挂在 `Game` 下面时路径是 `../MeshHut`，单独摆进关卡时也能兜住）
func _find_3d(path: NodePath, fallback_name: String) -> Node3D:
	var n := get_node_or_null(path) as Node3D
	if n != null:
		return n
	var root := get_tree().current_scene
	if root != null:
		return root.find_child(fallback_name, true, false) as Node3D
	return null


# ══════════════════════════ 材质 ══════════════════════════

func _make_materials() -> void:
	_mat["wall"] = _std(Color(0.80, 0.76, 0.68), 0.88)
	_mat["roof"] = _std(Color(0.26, 0.30, 0.36), 0.90, 0.05)
	_mat["trim"] = _std(Color(0.52, 0.49, 0.45), 0.70)
	_mat["wood"] = _std(Color(0.55, 0.40, 0.26), 0.82)
	_mat["steel"] = _std(Color(0.55, 0.57, 0.60), 0.42, 0.60)
	_mat["metal"] = _std(Color(0.44, 0.46, 0.50), 0.45, 0.70)
	_mat["crate"] = _std(Color(0.55, 0.40, 0.25), 0.85)
	_mat["fridge"] = _std(Color(0.86, 0.89, 0.92), 0.30)
	_mat["dark"] = _std(Color(0.16, 0.18, 0.21), 0.60)

	var lamp := _std(Color(0.95, 0.90, 0.75), 0.60)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.90, 0.66)
	lamp.emission_energy_multiplier = 2.0
	_mat["lamp"] = lamp

	var sign := _std(Color(0.72, 0.88, 1.0), 0.40)
	sign.emission_enabled = true
	sign.emission = Color(0.45, 0.78, 1.0)
	sign.emission_energy_multiplier = 1.8
	_mat["sign"] = sign

	# 玻璃：店面两扇大窗 + 展示柜
	var glass := _std(Color(0.62, 0.80, 0.86, 0.20), 0.06)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.metallic_specular = 0.9
	_mat["glass"] = glass

	var glow := _std(Color(0.80, 0.95, 1.0), 0.30)
	glow.emission_enabled = true
	glow.emission = Color(0.55, 0.85, 1.0)
	glow.emission_energy_multiplier = 2.4
	_mat["glow"] = glow

	# 天花板：屋顶底面本来是深灰（0.26），店里的灯只照到墙、照不到顶上，
	# 从店里抬头就是一块黑板。贴一层浅色顶板（不挡人）。
	_mat["ceiling"] = _std(Color(0.86, 0.85, 0.82), 0.90)

	# 货架上的「商品」：几只彩色小盒，纯装饰
	_mat["goods_a"] = _std(Color(0.85, 0.42, 0.38), 0.60)
	_mat["goods_b"] = _std(Color(0.42, 0.66, 0.82), 0.60)
	_mat["goods_c"] = _std(Color(0.86, 0.74, 0.36), 0.60)

	_mat["deck"] = _deck_material()


func _std(col: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


## 地板材质：**克隆平台已经铺好的那块**（`game.gd::_dress_empty_lot()` 的成品），
## 再把 UV 改成「世界三平面」—— 平台是 40 m 见方用 16× UV，地板 15.4 × 8.2 用同一张图，
## 不改采样方式会被拉成一条条。三平面按世界坐标取图，密度跟平台对齐。
func _deck_material() -> StandardMaterial3D:
	var src_mesh := get_node_or_null(floor_mesh_path) as MeshInstance3D
	var src: StandardMaterial3D = null
	if src_mesh != null:
		src = src_mesh.get_active_material(0) as StandardMaterial3D
	var m: StandardMaterial3D = null
	if src != null:
		m = src.duplicate() as StandardMaterial3D
	else:
		m = StandardMaterial3D.new()
		var tex := load("res://assets/tex/lot_paver.png") as Texture2D
		if tex != null:
			m.albedo_texture = tex
		m.albedo_color = Color(0.58, 0.62, 0.68)
		m.roughness = 0.95
	# 平台：uv1_scale = 16 铺满 40 m ⇒ 每米 0.4 个循环。三平面也照这个密度。
	var per_meter := 0.4
	if src != null and src.uv1_scale.x > 0.0:
		per_meter = src.uv1_scale.x / 40.0
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * per_meter
	return m


# ══════════════════════════ 地板 ══════════════════════════

func _build_deck() -> void:
	var deck := StaticBody3D.new()
	deck.name = "Deck"
	add_child(deck)
	var p := global_position
	var size := Vector3(deck_rect.size.x, deck_thickness, deck_rect.size.y)
	var center := Vector3(
		deck_rect.position.x - p.x + deck_rect.size.x * 0.5,
		-deck_thickness * 0.5,
		deck_rect.position.y - p.z + deck_rect.size.y * 0.5)
	_box_into(deck, "Deck", center, size, _mat["deck"])
	built_count += 1


# ══════════════════════════ 屋壳 ══════════════════════════

func _build_shell() -> void:
	var L := shop_len
	var D := shop_depth
	var H := hut_height
	var t := wall_thickness
	var door_w := door_width

	# 屋顶：沿用小屋的挑檐
	var roof := Vector3(L + roof_overhang * 2.0, 0.2, D + roof_overhang * 2.0)
	_box("Roof", Vector3(0.0, H + 0.1, 0.0), roof, _mat["roof"])

	# 西墙（朝小屋）、东墙、南墙：实墙
	_box("WallWest", Vector3(-L * 0.5 + t * 0.5, H * 0.5, 0.0), Vector3(t, H, D),
		_mat["wall"])
	_box("WallEast", Vector3(L * 0.5 - t * 0.5, H * 0.5, 0.0), Vector3(t, H, D),
		_mat["wall"])
	_box("WallSouth", Vector3(0.0, H * 0.5, -D * 0.5 + t * 0.5), Vector3(L, H, t),
		_mat["wall"])

	# 北墙 = 店面：两根门柱 + 两扇大玻璃 + 门上方一根横梁（横梁就是门楣）
	var z_out := D * 0.5 - t * 0.5          # 墙心（外表面在 D/2）
	var half_door := door_w * 0.5
	var pier := 0.2
	var sides := [-1.0, 1.0]
	for sx in sides:
		_box("Pier%s" % ("W" if sx < 0.0 else "E"),
			Vector3(sx * (half_door + pier * 0.5), door_height * 0.5, z_out),
			Vector3(pier, door_height, t), _mat["trim"])
	# 横梁：从门顶（2.30）盖到墙顶（2.50）
	_box("Lintel", Vector3(0.0, (door_height + H) * 0.5, z_out),
		Vector3(L, H - door_height, t), _mat["trim"])
	# 玻璃：门两侧各一扇，从 0.10 到门顶
	var bay_x0 := half_door + pier
	var bay_w := L * 0.5 - bay_x0 - t
	var glass_h := door_height - 0.1
	for sx in sides:
		_box("Glass%s" % ("W" if sx < 0.0 else "E"),
			Vector3(sx * (bay_x0 + bay_w * 0.5), 0.1 + glass_h * 0.5, z_out),
			Vector3(bay_w, glass_h, 0.06), _mat["glass"])
	# 玻璃分隔条：让店面读起来像「橱窗 + 门」，而不是一个空洞
	for sx in sides:
		_box_decor("Mullion%s" % ("W" if sx < 0.0 else "E"),
			Vector3(sx * 3.6, 0.1 + glass_h * 0.5, z_out), Vector3(0.08, glass_h, 0.10),
			_mat["trim"])

	# 天花板顶板（浅色，见 `_make_materials()` 里那段）
	_box_decor("Ceiling", Vector3(0.0, H - 0.03, 0.0),
		Vector3(L - 0.5, 0.03, D - 0.5), _mat["ceiling"])

	# 门框（装饰，不挡人）：两根竖梃 + 一根门头
	for sx in sides:
		_box_decor("DoorJamb%s" % ("W" if sx < 0.0 else "E"),
			Vector3(sx * (half_door + 0.06), door_height * 0.5, D * 0.5 + 0.04),
			Vector3(0.12, door_height + 0.1, 0.08), _mat["trim"])
	_box_decor("DoorHead", Vector3(0.0, door_height + 0.05, D * 0.5 + 0.04),
		Vector3(door_w + 0.24, 0.12, 0.08), _mat["trim"])

	# 招牌：门正上方一块发光板 + `Label3D`
	_box_decor("SignBoard", Vector3(0.0, H + 0.55, D * 0.5 + 0.06),
		Vector3(3.4, 0.72, 0.08), _mat["sign"])
	var lb := Label3D.new()
	lb.name = "SignText"
	lb.text = sign_text
	lb.font_size = 80
	lb.pixel_size = 0.005
	lb.outline_size = 18
	lb.modulate = Color(0.06, 0.10, 0.16)
	lb.outline_modulate = Color(0.85, 0.95, 1.0, 0.9)
	lb.position = Vector3(0.0, H + 0.55, D * 0.5 + 0.11)
	lb.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_decor.add_child(lb)
	decor_count += 1


# ══════════════════════════ 店内 ══════════════════════════

func _build_interior() -> void:
	var L := shop_len
	var D := shop_depth

	# 柜台：贴着东墙，面朝门口
	_box("Counter", Vector3(L * 0.5 - 0.55, 0.525, 0.2), Vector3(0.7, 1.05, 3.6),
		_mat["wood"])
	_box("CounterTop", Vector3(L * 0.5 - 0.55, 1.09, 0.2), Vector3(0.9, 0.08, 3.8),
		_mat["steel"])
	_box("Register", Vector3(L * 0.5 - 0.55, 1.26, -0.8), Vector3(0.32, 0.26, 0.45),
		_mat["dark"])

	# 两排货架：贴南墙
	for i in 2:
		_shelf(-3.2 + float(i) * 4.4, -D * 0.5 + 0.45)

	# 货架上的商品（纯装饰，不挡人）：顶层 3 只、中层 2 只
	var goods := ["goods_a", "goods_b", "goods_c"]
	for i in 2:
		var cx := -3.2 + float(i) * 4.4
		for j in 3:
			_box_decor("Goods", Vector3(cx - 0.7 + float(j) * 0.7, 1.73, -D * 0.5 + 0.45),
				Vector3(0.18, 0.18, 0.30), _mat[goods[(i + j) % 3]])
		for j in 2:
			_box_decor("Goods", Vector3(cx - 0.35 + float(j) * 0.7, 1.13, -D * 0.5 + 0.45),
				Vector3(0.18, 0.18, 0.26), _mat[goods[(j + 2) % 3]])

	# 冰柜：贴西墙（进门左手边），发光的门面
	_box("Fridge", Vector3(-L * 0.5 + 0.55, 0.95, -1.6), Vector3(0.65, 1.9, 1.0),
		_mat["fridge"])
	_box_decor("FridgeGlass", Vector3(-L * 0.5 + 0.90, 1.0, -1.6),
		Vector3(0.04, 1.6, 0.86), _mat["glow"])

	# 「5090 展示柜」：玻璃罩里一张发光的显卡（剧情梗）
	var case_x := -3.4
	_box("Showcase", Vector3(case_x, 0.42, -0.6), Vector3(1.2, 0.84, 0.62),
		_mat["wood"])
	_box_decor("ShowcaseGlass", Vector3(case_x, 1.12, -0.6), Vector3(1.16, 0.56, 0.58),
		_mat["glass"])
	_box_decor("ShowcaseGpu", Vector3(case_x, 1.02, -0.6), Vector3(0.34, 0.12, 0.16),
		_mat["glow"])

	# 靠柜台堆的两只货箱
	_box("Crate0", Vector3(L * 0.5 - 1.6, 0.45, -2.1), Vector3(0.9, 0.9, 0.9),
		_mat["crate"])
	_box("Crate1", Vector3(L * 0.5 - 1.6, 0.45, -1.1), Vector3(0.9, 0.9, 0.9),
		_mat["crate"])

	# 天花板灯管（装饰）
	for sx in [-1.0, 1.0]:
		_box_decor("CeilingTube%s" % ("W" if sx < 0.0 else "E"),
			Vector3(sx * 2.6, hut_height - 0.08, 0.0), Vector3(1.8, 0.06, 0.4),
			_mat["lamp"])

	# 留给高斯泼溅的空位：**故意不加载**（70 MB 的 .sog 一进场景显存就炸）
	var slot := Node3D.new()
	slot.name = "SplatSlot"
	add_child(slot)


## 一组货架：两块侧板 + 三块隔板（全部带碰撞，数字只写一遍）
func _shelf(cx: float, cz: float) -> void:
	var w := 2.4
	var h := 1.8
	var d := 0.45
	for sx in [-1.0, 1.0]:
		_box("ShelfSide", Vector3(cx + sx * (w * 0.5 - 0.05), h * 0.5, cz),
			Vector3(0.1, h, d), _mat["wood"])
	for i in 3:
		_box("ShelfBoard", Vector3(cx, h - 0.2 - float(i) * 0.6, cz),
			Vector3(w, 0.08, d), _mat["wood"])


# ══════════════════════════ 灯 ══════════════════════════

func _build_lights() -> void:
	for sx in [-1.0, 1.0]:
		var l := OmniLight3D.new()
		l.name = "ShopLight%s" % ("W" if sx < 0.0 else "E")
		l.position = Vector3(sx * 2.6, hut_height - 0.30, 0.0)
		l.light_color = Color(1.0, 0.93, 0.82)
		l.light_energy = 2.2
		l.omni_range = 10.5
		l.shadow_enabled = false
		add_child(l)
	var sign_light := OmniLight3D.new()
	sign_light.name = "SignLight"
	sign_light.position = Vector3(0.0, hut_height + 0.9, shop_depth * 0.5 + 0.9)
	sign_light.light_color = Color(0.62, 0.86, 1.0)
	sign_light.light_energy = 1.1
	sign_light.omni_range = 6.0
	sign_light.shadow_enabled = false
	add_child(sign_light)


# ══════════════════════════ 建盒子的唯一入口 ══════════════════════════

## 带碰撞的箱子：网格与 `BoxShape3D` 用**同一个 size、同一个位置**
func _box(node_name: String, center: Vector3, size: Vector3, mat: Material) -> void:
	_box_into(_body, node_name, center, size, mat)
	built_count += 1


func _box_into(parent: Node3D, node_name: String, center: Vector3, size: Vector3,
		mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	# ⚠️ 同名兄弟（6 块 ShelfBoard、2 只 Crate…）交给 Godot 自动改名会变成
	#    `@MeshInstance3D@108` 这种，名字就配不上碰撞盒了。这里自己加后缀，编号可读。
	var nm := _unique_name(parent, node_name)
	mi.name = nm
	mi.position = center
	parent.add_child(mi)
	if parent is StaticBody3D:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.name = nm + "Shape"
		cs.position = center
		parent.add_child(cs)


## `ShelfBoard` → `ShelfBoard` / `ShelfBoard2` / `ShelfBoard3`…（兄弟里不重名）
func _unique_name(parent: Node, want: String) -> String:
	var n := want
	var i := 2
	while parent.has_node(NodePath(n)):
		n = "%s%d" % [want, i]
		i += 1
	return n


## 只做样子、不挡人的东西（门框、玻璃罩、灯管、招牌）
func _box_decor(node_name: String, center: Vector3, size: Vector3, mat: Material) -> void:
	_box_into(_decor, node_name, center, size, mat)
	decor_count += 1


# ══════════════════════════ 记账 ══════════════════════════

func _report() -> void:
	var p := global_position
	print("[Shop] 初始小屋：外墙 %.2f × %.2f × %.2f m（挑檐 %.2f m）"
		% [hut_len, hut_height, hut_depth, roof_overhang])
	print("[Shop] 商店：长 %.2f（= %.0f × %.2f）、进深 %.2f、墙高 %.2f、门 %.2f × %.2f"
		% [shop_len, modules, hut_len, shop_depth, hut_height, door_width, door_height])
	print("[Shop] 世界位置 (%.2f, %.2f, %.2f)：西墙 x=%.2f、东墙 x=%.2f、z %.2f ~ %.2f"
		% [p.x, p.y, p.z, p.x - shop_len * 0.5, p.x + shop_len * 0.5,
			p.z - shop_depth * 0.5, p.z + shop_depth * 0.5])
	print("[Shop] 地板：x %.2f ~ %.2f、z %.2f ~ %.2f（%.1f × %.1f m，顶面 y=%.2f，厚 %.2f）"
		% [deck_rect.position.x, deck_rect.end.x, deck_rect.position.y, deck_rect.end.y,
			deck_rect.size.x, deck_rect.size.y, p.y, deck_thickness])
	print("[Shop] 碰撞盒 %d 个、装饰 %d 个" % [built_count, decor_count])
	print("[Shop] 高斯泼溅：`splatdata/shop_raw.sog`（70 MB）**故意没加载** —— "
		+ "等以后单独做按需流式加载，`SplatSlot` 空着")
