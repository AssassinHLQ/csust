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
## 平台只到 x = ±20，所以商店整块都在平台外面。
##
## ── 地板（2026-10-21 第二次改：用户圈红框「是这里地板补齐」）──
## 第一版只铺商店脚下那条窄带（x 20.01~34.40、z −19.60~−11.40，14.4 × 8.2 m），
## 从空中看就是平台东边沿突然断掉、伸出去一条舌头。现在铺成**平台东侧整面带**：
##   x 20.01 ~ `deck_east_x`（默认 40.00），z −20.00 ~ +20.00（与平台同深）。
## 即 20.0 × 40.0 m 一整块，边缘和平台齐平。
##
## ⚠️ 地板为什么不和平台叠着放 —— 平台网格在 x 上偏了 5.6 mm（`Floor/Mesh` 的
##    `0.005619049`），两块同高面一重叠就会在接缝处闪（z-fighting），所以地板从
##    20.01 起、**留 1 cm 缝**。胶囊半径 0.30，跨得过去；别为了好看去重叠。
##
## ⚠️ 墙、家具全部是「一个数字 → 网格 + 碰撞盒各一份」（`_box()`），不走 CSG ——
##    见 README §1.13 ⑦「删了网格 ≠ 删了碰撞」。

## 贴面重叠量：两个盒子「正好贴着」= 两个面共面 = z-fighting。
## 用户 2026-10-21：「天使24 出现了 z-fighting」。所以凡是相邻的两个箱子，
## 一律让它们**互相插进去 2 cm**（墙插进地板/屋顶、门柱插进横梁、家具插进地板）。
const TUCK := 0.02

## ── 地块参照（找不到就退回默认值，不会崩）──
@export_group("地块参照")
@export var hut_path: NodePath = ^"../MeshHut"
@export var floor_path: NodePath = ^"../Floor"
@export var floor_mesh_path: NodePath = ^"../Floor/Mesh"

@export_group("尺寸")
## 商店长度 = modules × 初始小屋外墙长。用户要的是「2 个初始房间这么长」。
@export var modules := 2.0
## 墙高。0 = 跟初始小屋一样（2.50）。
## 2026-10-21 用户：「商店太矮了」→ 3.20；2026-10-22 用户：「商店5m」→ **5.00**。
## （2.50 那版比优香还矮，3.20 只是「比人高一点」，5.00 才是正经便利店的层高。）
@export var wall_height := 5.00
## 小屋屋顶外沿 → 商店西墙的空当（走道宽度）
@export var gap := 3.0
## 地板往东铺到哪（世界 x）。2026-10-21 用户圈红框：「是这里地板补齐」——
## 原来只铺商店脚下那条窄带，平台东边沿之外还是一刀切的虚空；现在铺成整面带，
## 默认到 x = 40（比商店东墙 33.90 再远 6 m）。嫌大嫌小就调这一个数。
@export var deck_east_x := 40.0
## 地板比商店东墙再多铺多少（`deck_east_x` 比它小时用它兜底）
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
var shop_height := 0.0
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
	_build_music_zone()
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
	shop_height = wall_height if wall_height > 0.0 else hut_height

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
	var platform_z := 0.0
	var platform_half_z := 20.0
	if box != null:
		platform_right = shape.global_position.x + box.size.x * 0.5
		platform_top = shape.global_position.y + box.size.y * 0.5
		platform_z = shape.global_position.z
		platform_half_z = box.size.z * 0.5

	var hut_x := hut.global_position.x if hut != null else 14.0
	var hut_z := hut.global_position.z if hut != null else -15.5
	var hut_roof_half := hut_len * 0.5 + roof_overhang

	# 商店自己的位置：西墙 = 小屋屋顶外沿 + 走道
	var center_x := hut_x + hut_roof_half + gap + shop_len * 0.5
	var center_z := hut_z
	global_position = Vector3(center_x, platform_top, center_z)

	# ── 地板（2026-10-21 用户圈红框：「是这里地板补齐」）──
	# 原来只铺商店脚下那条窄带（14.4 × 8.2 m），平台东边沿之外还是一刀切的虚空，
	# 从空中看就是平台突然断掉。现在改成**平台东侧整面带**：
	#   x：平台边沿（+1 cm 防 z-fighting）→ `deck_east_x`（默认 40 m，比商店东墙再远 6 m）
	#   z：和平台**同深**（−20 ~ +20），边缘跟平台齐平，不再是突出来的一条舌头
	var x0 := platform_right + 0.01
	var x1 := maxf(center_x + shop_len * 0.5 + deck_margin, deck_east_x)
	var z0 := platform_z - platform_half_z
	var z1 := platform_z + platform_half_z
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

	# ── 收银台用的四种料 ──
	# 柜体：暖橡木；前脸嵌板浅一号；台面是米白人造石；压条/小铃是黄铜
	_mat["counter"] = _std(Color(0.58, 0.42, 0.28), 0.65)
	_mat["counter_light"] = _std(Color(0.68, 0.53, 0.37), 0.60)
	_mat["counter_top"] = _std(Color(0.88, 0.86, 0.82), 0.28, 0.10)
	_mat["brass"] = _std(Color(0.78, 0.62, 0.28), 0.30, 0.85)
	var screen := _std(Color(0.18, 0.34, 0.48), 0.20)
	screen.emission_enabled = true
	screen.emission = Color(0.35, 0.72, 0.95)
	screen.emission_energy_multiplier = 0.8
	_mat["screen"] = screen

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
	var H := shop_height
	var t := wall_thickness
	var door_w := door_width
	var e := TUCK

	# 屋顶：沿用小屋的挑檐
	var roof := Vector3(L + roof_overhang * 2.0, 0.2, D + roof_overhang * 2.0)
	_box("Roof", Vector3(0.0, H + 0.1, 0.0), roof, _mat["roof"])

	# 三面实墙：**下伸进地板、上伸进屋顶各 2 cm**（`TUCK`）。
	# 用户 2026-10-21：「天使24 出现了 z-fighting」——根因就是墙顶面 2.50 与屋顶底面 2.50
	# 正好同一平面、墙底面 0.00 与地板顶面 0.00 也同一平面，两个面抢同一块像素。
	var wall_h := H + e * 2.0
	var wall_y := wall_h * 0.5 - e
	_box("WallWest", Vector3(-L * 0.5 + t * 0.5, wall_y, 0.0), Vector3(t, wall_h, D),
		_mat["wall"])
	_box("WallEast", Vector3(L * 0.5 - t * 0.5, wall_y, 0.0), Vector3(t, wall_h, D),
		_mat["wall"])
	# ⚠️ 2026-10-22 用户：「灰色柱子与白墙重叠了的面闪烁还没有解决」。
	#    探针 `_probe_zfight.gd` 在全店 86 个网格里只找到 4 组「面共面且面积重叠」
	#    的对，就是四个墙角：`WallWest/WallEast` 的**端面**和 `WallSouth` 的**外表面**
	#    都在 x = ±L/2 上，重叠 1.008 m²（= 0.2 × 5.04，整块端面）。
	#    修法：南墙**缩到两侧墙的内表面之间**（L − 2t），变成对接缝，不再压着墙角。
	_box("WallSouth", Vector3(0.0, wall_y, -D * 0.5 + t * 0.5),
		Vector3(L - t * 2.0, wall_h, t), _mat["wall"])

	# 北墙 = 店面：**通高玻璃幕墙**
	#
	# 2026-10-22 用户：「上面这灰的变成玻璃幕墙吧」——原来门头以上是**一整块实心横梁**
	# （`Lintel`，从 2.28 一直盖到 5.00，整片灰），现在换成
	# 「通高竖梃 + 上部幕墙玻璃 + 三道竖分隔 + 顶部压条」。
	#
	# ⚠️ 上部幕墙一律走 `_box_decor`（**不挡人**），原因两条：
	#   ① 5 m 高的玻璃前面没人会去撞，挡不挡人没有意义；
	#   ② `built_count` 保持原样 —— `_probe_shop.gd` 那条「每个箱体网格都有同尺寸
	#      同位置的碰撞盒」是按 `Body` 子节点一一配对的，多塞一堆装饰网格会把判据搅乱。
	var z_out := D * 0.5 - t * 0.5          # 墙心（外表面在 D/2）
	var half_door := door_w * 0.5
	var pier := 0.2
	var sides := [-1.0, 1.0]
	var top_band := 0.14                    # 顶部压条（幕墙顶边的框）
	var head_h := door_height               # 门头：下部玻璃、横梁都对齐它
	var upper_y0 := head_h + 0.12           # 上部幕墙下沿（横梁之上）
	var upper_y1 := H - top_band            # 上沿（压条下面）
	# 通高竖梃：门柱一路顶到屋顶，整面幕墙才有「框」
	for sx in sides:
		_box("Pier%s" % ("W" if sx < 0.0 else "E"),
			Vector3(sx * (half_door + pier * 0.5), wall_y, z_out),
			Vector3(pier, wall_h, t), _mat["trim"])
	# 落地窗：门两侧各一扇，上下各插 2 cm 进竖梃/横梁（这一层**有碰撞**，见探针 §4）
	var bay_x0 := half_door + pier
	var bay_w := L * 0.5 - bay_x0 - t
	var glass_h := door_height - 0.1 + e
	for sx in sides:
		_box("Glass%s" % ("W" if sx < 0.0 else "E"),
			Vector3(sx * (bay_x0 + bay_w * 0.5), 0.1 - e * 0.5 + glass_h * 0.5, z_out),
			Vector3(bay_w, glass_h, 0.06), _mat["glass"])
	# 门头横梁（细条）：门洞顶 → 幕墙下沿
	# 横梁 / 顶部压条的长度也收到两侧墙之内（原来 L 正好和侧墙外表面同面，端头会闪）
	_box_decor("Transom", Vector3(0.0, head_h + 0.05, z_out),
		Vector3(L - t * 2.0, 0.16, t + 0.02), _mat["trim"])
	# 上部幕墙玻璃：门头以上一直到顶部压条
	for sx in sides:
		_box_decor("CurtainGlass%s" % ("W" if sx < 0.0 else "E"),
			Vector3(sx * (bay_x0 + bay_w * 0.5), (upper_y0 + upper_y1) * 0.5, z_out),
			Vector3(bay_w + e * 2.0, upper_y1 - upper_y0, 0.06), _mat["glass"])
	# 门正上方也补一扇幕墙玻璃：不补的话门洞上方就是个「洞」，
	# 从街上直接看进店里的后墙（渲图上一眼就是块米色板，与幕墙断开）。
	# 宽度取「门洞 + 两根竖梃」，两侧压进竖梃里，不会和后墙共面。
	_box_decor("CurtainGlassDoor", Vector3(0.0, (upper_y0 + upper_y1) * 0.5, z_out),
		Vector3(door_w + 2.0 * pier + e * 2.0, upper_y1 - upper_y0, 0.06), _mat["glass"])
	# 门洞正中一道竖梃：门上方那格玻璃背后正好是店里的后墙（米色），
	# 不加这根竖梃，正面看过去那一整块像「实心板」而不像玻璃。
	_box_decor("MullionDoor", Vector3(0.0, (upper_y0 + upper_y1) * 0.5, z_out),
		Vector3(0.08, upper_y1 - upper_y0 + e * 2.0, 0.11), _mat["trim"])
	# 竖分隔：下部一道（3.6）+ 上部三道（2.2 / 3.6 / 5.0），上下对齐才像幕墙
	for sx in sides:
		_box_decor("Mullion%s" % ("W" if sx < 0.0 else "E"),
			Vector3(sx * 3.6, 0.1 - e * 0.5 + glass_h * 0.5, z_out),
			Vector3(0.08, glass_h, 0.10), _mat["trim"])
		for mx in [2.2, 3.6, 5.0]:
			_box_decor("MullionU%d%s" % [int(mx * 10.0), "W" if sx < 0.0 else "E"],
				Vector3(sx * mx, (upper_y0 + upper_y1) * 0.5, z_out),
				Vector3(0.08, upper_y1 - upper_y0 + e * 2.0, 0.10), _mat["trim"])
	# 顶部压条：幕墙顶边 → 屋顶（上沿插进屋顶 2 cm，避免共面）
	_box_decor("HeadBand", Vector3(0.0, H - top_band * 0.5 + e * 0.5, z_out),
		Vector3(L - t * 2.0, top_band + e, t + 0.02), _mat["trim"])

	# 天花板顶板：铺满内框（两侧压进墙里 3 cm），上沿顶进屋顶 1 cm
	_box_decor("Ceiling", Vector3(0.0, H - 0.02, 0.0),
		Vector3(L - t * 2.0 + 0.06, 0.06, D - t * 2.0 + 0.06), _mat["ceiling"])

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

	_build_counter()

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
	_box_standing("Fridge", Vector2(-L * 0.5 + 0.55, -1.6), Vector3(0.65, 1.9, 1.0),
		_mat["fridge"])
	_box_decor("FridgeGlass", Vector3(-L * 0.5 + 0.90, 1.0, -1.6),
		Vector3(0.04, 1.6, 0.86), _mat["glow"])

	# 「5090 展示柜」：玻璃罩里一张发光的显卡（剧情梗）
	var case_x := -3.4
	_box_standing("Showcase", Vector2(case_x, -0.6), Vector3(1.2, 0.84, 0.62),
		_mat["wood"])
	_box_decor("ShowcaseGlass", Vector3(case_x, 1.12, -0.6), Vector3(1.16, 0.56, 0.58),
		_mat["glass"])
	_box_decor("ShowcaseGpu", Vector3(case_x, 1.02, -0.6), Vector3(0.34, 0.12, 0.16),
		_mat["glow"])

	# 靠柜台堆的两只货箱
	_box_standing("Crate0", Vector2(2.6, -2.1), Vector3(0.9, 0.9, 0.9), _mat["crate"])
	_box_standing("Crate1", Vector2(2.6, -1.1), Vector3(0.9, 0.9, 0.9), _mat["crate"])

	# 天花板灯管（装饰）
	for sx in [-1.0, 1.0]:
		_box_decor("CeilingTube%s" % ("W" if sx < 0.0 else "E"),
			Vector3(sx * 2.6, shop_height - 0.08, 0.0), Vector3(1.8, 0.06, 0.4),
			_mat["lamp"])

	# 店员：小空（2026-10-21 用户给的 .blend，Blender 转 GLB；署名见 CREDITS.md）
	_build_clerk()

	# 留给高斯泼溅的空位：**故意不加载**（70 MB 的 .sog 一进场景显存就炸）
	var slot := Node3D.new()
	slot.name = "SplatSlot"
	add_child(slot)


## ── 收银台（2026-10-21 用户：「你给做个好看点的收银台吧」）──
##
## 原来是一个 0.7×1.05×3.6 的橙盒子加一块灰板，太像「一个箱子」。
## 现在按真实收银台拆成六件：踢脚（内缩）→ 柜体 → 台面（前后各出 7 cm 檐）→
## 前沿不锈钢压条 → 收银机（底座 + 屏幕 + 键盘）→ 刷卡机/小铃/提示牌。
## 位置也从「贴东墙」挪到 x = 4.90：原来柜体和东墙之间只剩 0.55 m，小空站不进去。
func _build_counter() -> void:
	var cx := 4.90          # 柜体中心 x
	var cz := 0.20          # 柜体中心 z
	var cw := 0.72          # 柜体进深（x）
	var cl := 3.60          # 柜体长度（z）
	var floor_y := -TUCK

	# 踢脚：内缩 5 cm，让柜体看起来是「浮」在地上的
	_box("CounterKick", Vector3(cx, floor_y + 0.06, cz),
		Vector3(cw - 0.10, 0.12 + TUCK, cl - 0.20), _mat["dark"])

	# 柜体（橡木）。
	# ⚠️ 柜体高度**跟着台面走**（`body_h = top_h − 0.18`）：柜体从 y=0.10 起、
	#    顶上 `TUCK` 之后正好接住台面的底面（`top_h − 0.06`），中间不留缝也不插进去。
	var top_h := 0.88       # 台面高度（米）
	var body_h := top_h - 0.18
	_box("Counter", Vector3(cx, floor_y + 0.12 + body_h * 0.5, cz),
		Vector3(cw, body_h + TUCK, cl), _mat["counter"])

	# 前脸嵌板（朝顾客那面 -X）：浅一号，凹进去 2 cm。
	# ⚠️ 高度必须**跟着 body_h 走**：原来写死 0.60 / 0.62，是给 0.86 高的柜体配的；
	#    柜体降到 0.70 之后嵌板会从柜顶探出 9 cm，像块立起来的板子。
	var face_cy := floor_y + 0.12 + body_h * 0.5
	var face_cy_h := body_h - 0.10
	_box_decor("CounterPanel", Vector3(cx - cw * 0.5 - 0.01, face_cy, cz),
		Vector3(0.03, face_cy_h, cl - 0.36), _mat["counter_light"])
	# 前脸两道压条（装饰）
	for dz in [-1.0, 1.0]:
		_box_decor("CounterTrim%s" % ("A" if dz < 0.0 else "B"),
			Vector3(cx - cw * 0.5 - 0.02, face_cy, cz + dz * (cl * 0.5 - 0.18)),
			Vector3(0.05, face_cy_h, 0.05), _mat["steel"])

	# 台面：6 cm 厚，前后各出檐 7 cm。
	#
	# ⚠️ 2026-10-26 用户「柜台太高了」—— 原来是 **1.04 m**。
	#    芹香按设定身高 1.52 m（`shop_clerk.gd` 的 MODEL_SCALE），1.04 已经到她的
	#    胸口以上，从顾客那侧看过去只剩一个头，柜台像一堵墙。改成 0.88 m
	#    （≈ 她身高的 58%，和真实便利店柜台的比例接近）。
	_box("CounterTop", Vector3(cx, top_h - 0.03, cz),
		Vector3(cw + 0.14, 0.06 + TUCK, cl + 0.16), _mat["counter_top"])
	# 前沿不锈钢压条（顾客那一侧）
	_box_decor("CounterEdge", Vector3(cx - cw * 0.5 - 0.07, top_h - 0.03, cz),
		Vector3(0.02, 0.06, cl + 0.16), _mat["steel"])

	# 收银机：底座 + 屏幕（自发光）+ 键盘
	_box("Register", Vector3(cx + 0.04, top_h + 0.03, cz - 0.55),
		Vector3(0.36, 0.10, 0.30), _mat["dark"])
	_box_decor("RegisterScreen", Vector3(cx + 0.10, top_h + 0.19, cz - 0.55),
		Vector3(0.03, 0.22, 0.32), _mat["screen"])
	_box_decor("RegisterKeys", Vector3(cx - 0.12, top_h + 0.03, cz - 0.55),
		Vector3(0.24, 0.03, 0.28), _mat["steel"])

	# 刷卡机（顾客侧）+ 小铃 + 提示牌
	_box_decor("CardReader", Vector3(cx - cw * 0.5 - 0.02, top_h + 0.10, cz + 1.05),
		Vector3(0.10, 0.14, 0.12), _mat["dark"])
	_box_decor("Bell", Vector3(cx - cw * 0.5 + 0.05, top_h + 0.04, cz + 1.45),
		Vector3(0.10, 0.06, 0.10), _mat["brass"])
	_box_decor("BellTop", Vector3(cx - cw * 0.5 + 0.05, top_h + 0.09, cz + 1.45),
		Vector3(0.05, 0.04, 0.05), _mat["brass"])

	# 柜台后面的墙架（放货）。
	# ⚠️ 必须整块留**离墙 2 cm**：之前 x = L/2-0.16（外沿 6.55）直接捅穿东墙内表面
	# （6.40），墙内表面与架板上下表面相交，从店里看就是一排锯齿（用户报的 z-fighting）。
	var sh_x := shop_len * 0.5 - 0.33
	for i in 3:
		_box_decor("WallShelf", Vector3(sh_x, 1.30 + float(i) * 0.32, cz),
			Vector3(0.22, 0.04, 2.6), _mat["counter"])


## 店员：小空站在柜台后面，朝顾客（-X）。
func _build_clerk() -> void:
	var clerk := ShopClerk.new()
	# 2026-10-22 小空 → 芹香（校服版），节点名跟着换；见 `scripts/shop_clerk.gd`
	clerk.name = "ClerkSerika"
	clerk.position = Vector3(5.86, 0.0, 0.20)
	clerk.rotation.y = -PI * 0.5     # 模型朝 +Z → 转 -90° 朝 -X（柜台外侧）
	add_child(clerk)
	decor_count += 1


## 一组货架：两块侧板 + 三块隔板（全部带碰撞，数字只写一遍）
func _shelf(cx: float, cz: float) -> void:
	var w := 2.4
	var h := 1.8
	var d := 0.45
	for sx in [-1.0, 1.0]:
		_box_standing("ShelfSide", Vector2(cx + sx * (w * 0.5 - 0.05), cz),
			Vector3(0.1, h, d), _mat["wood"])
	for i in 3:
		_box("ShelfBoard", Vector3(cx, h - 0.2 - float(i) * 0.6, cz),
			Vector3(w, 0.08, d), _mat["wood"])


# ══════════════════════════ 灯 ══════════════════════════

func _build_lights() -> void:
	for sx in [-1.0, 1.0]:
		var l := OmniLight3D.new()
		l.name = "ShopLight%s" % ("W" if sx < 0.0 else "E")
		l.position = Vector3(sx * 2.6, shop_height - 0.30, 0.0)
		l.light_color = Color(1.0, 0.93, 0.82)
		l.light_energy = 2.2
		l.omni_range = shop_height * 4.2
		l.shadow_enabled = false
		add_child(l)
	var sign_light := OmniLight3D.new()
	sign_light.name = "SignLight"
	sign_light.position = Vector3(0.0, shop_height + 0.9, shop_depth * 0.5 + 0.9)
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


## 立在地上的箱子：**往下沉 TUCK**，让底面钻进地板里（贴着放会 z-fighting）
func _box_standing(node_name: String, xz: Vector2, size: Vector3, mat: Material) -> void:
	var s := Vector3(size.x, size.y + TUCK, size.z)
	_box(node_name, Vector3(xz.x, s.y * 0.5 - TUCK, xz.y), s, mat)


# ══════════════════════════ 记账 ══════════════════════════

# ══════════════════════════ 商店 BGM ══════════════════════════
#
# 用户 2026-10-26：「UNDERTALE Tem Shop ... 商店音乐，只要前面四十秒，这样子才能循环」。
#
# 做法：店里放一个 Area3D，玩家进来就淡入 BGM、出去就淡出。
#   · 为什么用 Area3D 而不是每帧算距离：Area 由物理引擎管，玩家传送/掉落/走进走出
#     都能收到 entered/exited，不用自己判边界；而且只在状态变化时才回调，零常态开销。
#   · 层设置和「召唤台」一致：`collision_layer = 0`（自己不被撞）、
#     `collision_mask = 1`（只感应世界层，玩家在第 1 层）。
#   · 盒子比墙**内缩 0.6 m**：贴着墙走不该忽开忽关，也给淡入淡出留一点余量。
const MUSIC_TRACK := "shop"

var _music_area: Area3D
var _music_inside := 0


func _build_music_zone() -> void:
	var area := Area3D.new()
	area.name = "MusicZone"
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitoring = true
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# 高度取墙高的 2 倍、中心抬到一半：玩家怎么跳都在里面
	box.size = Vector3(shop_len - 0.6, shop_height * 2.0, shop_depth - 0.6)
	cs.shape = box
	cs.position = Vector3(0.0, shop_height, 0.0)
	area.add_child(cs)
	add_child(area)
	# ⚠️ 用「计数」而不是布尔：玩家被瞬移时可能先 entered B 再 exited A，
	#    布尔量会在同一帧里被后到的 exited 抹掉，出现「人在店里音乐却停了」。
	area.body_entered.connect(_on_music_body.bind(1))
	area.body_exited.connect(_on_music_body.bind(-1))
	_music_area = area
	print("[Shop] BGM 触发区：%.2f × %.2f × %.2f m（曲目 `%s`）" % [
		box.size.x, box.size.y, box.size.z, MUSIC_TRACK])


func _on_music_body(body: Node3D, delta: int) -> void:
	if not body.is_in_group("player"):
		return
	_music_inside = maxi(_music_inside + delta, 0)
	if _music_inside > 0:
		Music.play(MUSIC_TRACK)
	elif _music_inside == 0:
		Music.stop()


func _report() -> void:
	var p := global_position
	print("[Shop] 初始小屋：外墙 %.2f × %.2f × %.2f m（挑檐 %.2f m）"
		% [hut_len, hut_height, hut_depth, roof_overhang])
	print("[Shop] 商店：长 %.2f（= %.0f × %.2f）、进深 %.2f、墙高 %.2f、门 %.2f × %.2f"
		% [shop_len, modules, hut_len, shop_depth, shop_height, door_width, door_height])
	print("[Shop] 世界位置 (%.2f, %.2f, %.2f)：西墙 x=%.2f、东墙 x=%.2f、z %.2f ~ %.2f"
		% [p.x, p.y, p.z, p.x - shop_len * 0.5, p.x + shop_len * 0.5,
			p.z - shop_depth * 0.5, p.z + shop_depth * 0.5])
	print("[Shop] 地板：x %.2f ~ %.2f、z %.2f ~ %.2f（%.1f × %.1f m，顶面 y=%.2f，厚 %.2f）"
		% [deck_rect.position.x, deck_rect.end.x, deck_rect.position.y, deck_rect.end.y,
			deck_rect.size.x, deck_rect.size.y, p.y, deck_thickness])
	print("[Shop] 碰撞盒 %d 个、装饰 %d 个" % [built_count, decor_count])
	print("[Shop] 高斯泼溅：`splatdata/shop_raw.sog`（70 MB）**故意没加载** —— "
		+ "等以后单独做按需流式加载，`SplatSlot` 空着")
