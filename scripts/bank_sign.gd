class_name BankSign
extends Node3D
## 屋顶上的 **BANK 招牌**（2026-10-20 用户：「在这个房顶上面放一个 BANK 的牌子，
## 我已经做好模型放桌面了，你来缩放一下适配大小，这样子一个简单的银行就做好了」）。
##
## 模型：`models/bank/BANK.obj`（用户自己做的 Rhino 导出，1765 个三角面）。
## 摆位：`parkour.gd::_spawn_bank_sign()` 挂在 `Island/Props/Shed` 屋顶上，
## 底边贴屋顶（局部 y = 2.5），正面朝向**玩家从跑酷终点走过来的方向**（岛东侧）。
##
## ⚠️ 三个坑（都在这份 Rhino 文件里，改模型前先看）：
##   1. **它是平躺的**：字的平面在 X-Z、厚度在 Y（Rhino 顶视图里画的）。
##      所以要绕 X 转 −90° 立起来；再绕 Y 转 180° 让可读的那一面朝 +Z
##      （只绕 Y 转 180° 不会把字镜过来，看的是同一张正面）。
##      最终旋转 = `Vector3(-90°, 180°, 0)`（Godot 的 `rotation` 是 YXZ 序，
##      正好等于 `Ry(180) × Rx(-90)`）。
##   2. **文件里带一圈「Default」包围盒**（6 个面、尺寸比字还大）。
##      不剔掉的话屋顶上会多出一个大白盒子；`_strip_box()` 按材质名把它丢掉。
##   3. 原文件 `mtllib BANK.mtl` 指向的 mtl **没给出来**，缺了它 Godot 会给所有面
##      一份**匿名**材质（`resource_name` 为空），第 2 条就没法按名字剔。
##      所以仓库里补了一份最小的 `models/bank/BANK.mtl`。
##
## 尺寸：宽度固定 `WIDTH`（3.0 m，屋顶 4.4 m 宽），高度按模型比例 ≈ 0.85 m。
const MODEL := "res://models/bank/BANK.obj"
## 招牌宽度（m）。**字高由「模型宽高比」自动推**，不写死。
## 2.6 m：屋顶 4.4 × 3.4，招牌朝落点方向斜放后占地 2.6 × 0.9 左右，
## 再宽就从北沿探出去了（3.0 m 时实测 z 跨到 −1.9，超出屋顶 −1.7）。
const WIDTH := 2.6
## 字面颜色：米白（银行招牌那种），带一点自发光，远处也读得清
const FACE_COLOR := Color(0.97, 0.94, 0.86)
## 立起来 + 转正：`Ry(180) × Rx(-90)`（见文件头坑 1）
const UPRIGHT := Vector3(-1.5707964, 3.1415927, 0.0)

var width := 0.0
var height := 0.0
## 这个招牌的可读面朝哪：+Z（世界方向 = `(sin(rotation.y), 0, cos(rotation.y))`）
var sign_tris := 0


func _ready() -> void:
	add_to_group("bank_signs")
	_build()


func _build() -> void:
	var src := load(MODEL) as Mesh
	if src == null:
		push_warning("[BankSign] 没有 %s（BANK 旗帜不出现）" % MODEL)
		return
	var mesh := _strip_box(src)
	if mesh == null:
		push_warning("[BankSign] 模型里没有可用的字面")
		return
	var mi := MeshInstance3D.new()
	mi.name = "Letters"
	mi.mesh = mesh
	mi.rotation = UPRIGHT
	add_child(mi)

	# 按「立起来之后」的包围盒定尺寸：宽 = WIDTH，底边贴 y = 0
	var after := Transform3D(Basis.from_euler(UPRIGHT), Vector3.ZERO) * mesh.get_aabb()
	var s := WIDTH / maxf(after.size.x, 0.001)
	mi.scale = Vector3(s, s, s)
	mi.position = Vector3(-after.get_center().x * s, -after.position.y * s,
		-after.get_center().z * s)
	width = after.size.x * s
	height = after.size.y * s
	sign_tris = triangle_count()
	_add_board()
	print("[BankSign] BANK 招牌就位：%.2f × %.2f m（厚 %.3f），%d 个三角面"
		% [width, height, after.size.z * s, sign_tris])


## 深色底板。**没有它白字根本读不清** —— 小屋后面就是亮天空，第一版渲出来
## 「BANK」几乎淹在云里。板子比字大一圈（每边 8 cm），贴在字后面 5 cm。
func _add_board() -> void:
	var board := MeshInstance3D.new()
	board.name = "Board"
	var bm := BoxMesh.new()
	bm.size = Vector3(width + 0.16, height + 0.16, 0.06)
	board.mesh = bm
	board.position = Vector3(0.0, (height + 0.16) * 0.5, -0.05)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.15, 0.17, 0.21)
	m.metallic = 0.35
	m.roughness = 0.5
	board.material_override = m
	add_child(board)


## 把 Rhino 那圈「Default」包围盒剔掉，只留字面；顺便统一材质。
## 返回 `null` 表示一个面都不剩（那时宁可不出招牌，也别挂个大白盒子）。
func _strip_box(src: Mesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var mat := src.surface_get_material(s)
		var nm := String(mat.resource_name) if mat != null else ""
		if nm.to_lower() == "default":
			continue
		var arrays := src.surface_get_arrays(s)
		if arrays.is_empty():
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if verts.is_empty():
			continue
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(out.get_surface_count() - 1, _face_material())
	return out if out.get_surface_count() > 0 else null


func _face_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = FACE_COLOR
	m.metallic = 0.25
	m.roughness = 0.42
	m.emission_enabled = true
	m.emission = Color(0.60, 0.52, 0.40)
	m.emission_energy_multiplier = 0.12
	return m


## 当前用了多少个三角面（自检用：确认没把包围盒一起吃进来）
func triangle_count() -> int:
	var n := 0
	for c in get_children():
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null or String(mi.name) == "Board":
			continue
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			n += (idx.size() / 3) if not idx.is_empty() else (verts.size() / 3)
	return n


## 把正面转向 `target`（世界坐标的点）
func face_towards(target: Vector3) -> void:
	var d := target - global_position
	d.y = 0.0
	if d.length_squared() < 0.001:
		return
	rotation.y = atan2(d.x, d.z)
