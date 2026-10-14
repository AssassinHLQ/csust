class_name Boss
extends StaticBody3D
## Boss「木桩」基类：摆在场地上、吃得下子弹、受击闪白、倒下后重生。
## 现在同时服务两位：
##   · **霸王龙优香**（`models/boss/优香霸王龙.fbx`）—— 有蒙皮的静态 FBX，骨架定尺寸
##   · **飞猪优香**  （`models/boss_pig/猪猪优香.fbx`）—— 纯静态网格（无骨无动画），网格定尺寸
## 行为（冲撞 / 吐息 / AI）留待后续；这一版只解决「模型怎么修、多大、朝向哪」。
##
## ⚠️ 霸王龙那个 FBX 有几个坑，改参数前先读 README §7.2：
##   1. 网格顶点在「绑定空间」，跨度是骨架的 ~298 倍 —— **必须保留蒙皮**。
##      把 skin 置空 → 网格会散成一片「刀刃」；
##      按网格包围盒取景 → 会误判成「模型只有一个像素点」。
##      所以归一化用 **骨架的世界包围盒**（`_bone_box`）。
##      反过来，飞猪没有骨架，只能用网格包围盒（`_mesh_box`）—— 两条路别用混。
##   2. 材质里没有 albedo 贴图 → 必须手工绑，而且要**按材质分别绑**（见 TEXTURES）。
##   3. 挂件（光环/胸牌/球/方块）别再隐藏了：按真实渲染尺度它们是合理的
##      （光环 1.31×0.64×1.36 m 飘在头顶 y=5.59 处，胸牌 0.13 m 在胸前）。
##      之前判成「缩放差 1~2 个数量级」是拿蒙皮前的 8732 当参照，错的。
##   4. 霸王龙自身脸朝 +Z（rotation.y = 0 时），与 Arisu 同一套朝向约定；
##      飞猪也是 **+Z**（实测鼻子在 z=+2.17、尾巴在 z=−1.95），所以两个都不用补 180°。

signal died(by_damage: float)
signal health_changed(current: float, maximum: float)

## 材质名 → 贴图。**这张表是本喵排了 3! = 6 种组合渲图后定的**（工具
## `_probe_boss_texperm.gd`，对照图 `_arisu_captures/_boss/90_texperm_sheet.png`）。
## 判定依据是「贴图内容 ↔ 材质名」：
##   材质       身体  ← boss_body.png         紫身展开图（UV 岛形状就是一条龙）
##   2501_other 胸牌  ← boss_props_atlas.png  MILLENNIUM 校徽 + 工牌条码图集
##   材质.001    嘴/球 ← boss_mouth.png        淡紫底 + 锯齿牙齿
## ❌ 曾经把 props_atlas 贴到身体上：结果整只变成一件"校服"，是错的。
##
## 这是**霸王龙的默认表**；飞猪在场景里用 `texture_map` 覆盖它（见 game.tscn）。
const TEXTURES := {
	"材质": "res://models/boss/tex/boss_body.png",
	"2501_other": "res://models/boss/tex/boss_props_atlas.png",
	"材质.001": "res://models/boss/tex/boss_mouth.png",
}

## HUD 上显示的名字
@export var display_name := "霸王龙优香"
@export_file("*.fbx") var model_path := "res://models/boss/优香霸王龙.fbx"
## 材质名 → 贴图。留空则用霸王龙那张 TEXTURES 表。
## 飞猪用它绑自己那 4 个材质（名字是「材质」「材质.001」「材质.002」「Yuuka_Original_Halo_0Mat」）。
@export var texture_map := {}
## hide_accessories 打开时，**只保留**名字以这个前缀开头的网格（其余当挂件藏掉）
@export var body_name_prefix := "Tyrannosaurus"
## 碰撞盒 = 归一化尺寸 × 这三个系数。
## 霸王龙这套（0.55/0.85/0.62）是量出来的：身体约占全长的六成，剩下是尾巴。
@export var collision_factors := Vector3(0.55, 0.85, 0.62)
## 目标身高（m）。Arisu 约 1.7、靶子柱 1.15；木桩默认 4.5（约 2.6 个 Arisu）
@export var height := 4.5
@export var max_health := 3000.0
@export var respawn_time := 6.0
## 想只留身体（隐藏光环/胸牌/球/方块）就打开
@export var hide_accessories := false
## 贴图之上的着色（白 = 用贴图原色）
@export var tint := Color.WHITE
## 受击闪白的颜色
@export var flash_color := Color(1.0, 0.55, 0.55)

var health: float
var model: Node3D
## 归一化后的视觉尺寸（世界，m）
var visual_size := Vector3.ZERO
var bone_count := 0
## 这一只靠什么定尺寸：「骨架」（霸王龙）还是「网格」（飞猪）。自检要读。
var measure_kind := ""

var _dead := false
var _materials: Array[StandardMaterial3D] = []
var _collision: CollisionShape3D
var _collision_shape: BoxShape3D


func _ready() -> void:
	health = max_health
	_build_model()
	_build_collision()
	health_changed.emit(health, max_health)


## 受击（Weapon 直接调这个，和 Target 的契约一致）
func take_damage(amount: float, _hit_pos := Vector3.ZERO, _hit_dir := Vector3.ZERO) -> void:
	if _dead:
		return
	health = maxf(health - amount, 0.0)
	_flash()
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_die(amount)


func health_ratio() -> float:
	return clampf(health / max_health, 0.0, 1.0) if max_health > 0.0 else 0.0


## 模型的脸朝向（和 Arisu 一样：rotation.y = 0 → 世界 +Z）
func facing() -> Vector3:
	return Vector3(sin(global_rotation.y), 0.0, cos(global_rotation.y))


# --- 建模型 ---

func _build_model() -> void:
	var packed: PackedScene = load(model_path)
	if packed == null:
		push_error("[Boss] 找不到模型：%s" % model_path)
		return
	model = packed.instantiate()
	add_child(model)

	# 1. 可选：隐藏挂件（**默认不隐藏**——它们是合理的，见文件头注释）
	var hidden := 0
	if hide_accessories:
		for mi in _all(model, "MeshInstance3D"):
			if not (mi as MeshInstance3D).name.begins_with(body_name_prefix):
				(mi as MeshInstance3D).visible = false
				hidden += 1

	# 2. 按材质名分别绑贴图（同一份材质会被多个网格共用）
	var tex_map: Dictionary = texture_map if not texture_map.is_empty() else TEXTURES
	var bound := 0
	var missing: Array[String] = []
	for mi in _all(model, "MeshInstance3D"):
		var m := mi as MeshInstance3D
		if not m.visible or m.mesh == null:
			continue
		var am := m.mesh as ArrayMesh
		for s in am.get_surface_count():
			var mat := am.surface_get_material(s)
			if mat is StandardMaterial3D:
				var sm := mat as StandardMaterial3D
				var key := sm.resource_name
				if tex_map.has(key):
					var tex: Texture2D = load(tex_map[key])
					if tex != null:
						sm.albedo_texture = tex
					else:
						push_warning("[Boss] 贴图加载失败：%s" % tex_map[key])
				elif not missing.has(key):
					missing.append(key)
				sm.albedo_color = tint
				if not _materials.has(sm):
					_materials.append(sm)
				bound += 1
			elif mat != null:
				push_warning("[Boss] 材质不是 StandardMaterial3D，受击闪白会失效：%s" % mat.get_class())
	print("[Boss] 贴图槽位 %d 个已绑；表里没覆盖的材质：%s" % [
		bound, str(missing) if not missing.is_empty() else "（无）"])

	# 3. 归一化：量一个包围盒，缩放到目标身高、水平居中、脚底落到 y = 0。
	#
	# ⚠️ 必须在 **Boss 节点自己的局部空间** 里量！
	#    本喵第一版在世界空间量、却把结果当局部坐标去设 model.position ——
	#    而 game.tscn 里 Boss 绕 Y 转了 -90°，于是：
	#      · 水平居中歪掉（实测差 1.8 m）
	#      · 长短轴被转错（12.6 m 的长轴被记到 x 上），碰撞盒跟着变形
	#    正确做法：把测量点先乘 model.global_transform 的逆，落到父节点空间。
	#
	# 另外这里**不需要回测**：此刻 model 的变换还是单位变换，缩放 s 之后
	# 新框 = 原框 × s（均匀缩放、绕自身原点），偏移量可以直接解析算出来。
	#
	# 有骨架就用骨架盒（霸王龙），没有就用网格盒（飞猪）—— 见文件头 §1。
	var skel := _best_skeleton(model)
	var box := AABB()
	if skel != null:
		bone_count = skel.get_bone_count()
		measure_kind = "骨架"
		box = _bone_box(skel)
	else:
		bone_count = 0
		measure_kind = "网格"
		box = _mesh_box()
	if box.size.y <= 0.0001:
		push_error("[Boss %s] %s包围盒退化，无法归一化" % [display_name, measure_kind])
		return
	var s := height / box.size.y
	model.scale = Vector3(s, s, s)
	# 水平居中 + 脚底落在 y = 0（都在父节点空间里）
	model.position = Vector3(
		-box.get_center().x * s, -box.position.y * s, -box.get_center().z * s)
	visual_size = box.size * s
	print("[Boss %s] 模型就位：%d 骨（按%s量），隐藏挂件 %d 个，贴图表面 %d 个，尺寸 %s（目标身高 %.2f m）" % [
		display_name, bone_count, measure_kind, hidden, bound,
		str(visual_size.snappedf(0.01)), height])


## 骨架包围盒，量在 **Boss 节点（model 的父节点）的局部空间**：
## 骨骼点先按 model 的世界变换取逆落回父空间，再统计。
func _bone_box(skel: Skeleton3D) -> AABB:
	var to_parent := model.global_transform.affine_inverse()
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for i in skel.get_bone_count():
		var p: Vector3 = to_parent * (skel.global_transform * skel.get_bone_global_pose(i).origin)
		lo = lo.min(p)
		hi = hi.max(p)
	if lo.x == INF:
		return AABB()
	return AABB(lo, hi - lo)


## 网格包围盒（给**没有骨架**的静态模型用），同样量在父节点空间。
## ⚠️ 千万别拿它去量霸王龙：那个 FBX 的网格顶点在绑定空间，跨度是骨架的 ~298 倍，
##    量出来会是个荒唐的大盒子（这正是文件头 §1 里记的那个坑）。
func _mesh_box() -> AABB:
	var to_parent := model.global_transform.affine_inverse()
	var out := AABB()
	var first := true
	for m in _all(model, "MeshInstance3D"):
		var mi := m as MeshInstance3D
		if not mi.visible or mi.mesh == null:
			continue
		var b: AABB = to_parent * (mi.global_transform * mi.get_aabb())
		if b.size.length() <= 0.0001:
			continue
		out = b if first else out.merge(b)
		first = false
	return out


# --- 碰撞（木桩要能被打到）---

func _build_collision() -> void:
	if visual_size == Vector3.ZERO:
		return
	_collision_shape = BoxShape3D.new()
	# 身体占全长约 6 成（剩下是尾巴，不细究）；盒子稍微往上抬一点，避开脚
	_collision_shape.size = Vector3(
		maxf(visual_size.x * collision_factors.x, 0.5),
		maxf(visual_size.y * collision_factors.y, 0.5),
		maxf(visual_size.z * collision_factors.z, 0.5))
	_collision = CollisionShape3D.new()
	_collision.name = "Collision"
	_collision.shape = _collision_shape
	_collision.position = Vector3(
		model.position.x, _collision_shape.size.y * 0.5, model.position.z)
	add_child(_collision)
	collision_layer = 1
	collision_mask = 0
	print("[Boss] 碰撞盒 size = %s" % str(_collision_shape.size.snappedf(0.01)))


# --- 受击表现 ---

func _flash() -> void:
	# 先**立刻**染成闪白色再渐退：全靠 tween 的话，受击当帧颜色还没变，
	# 视觉上会有一帧延迟（自检也会判为「没闪」）。
	for mat in _materials:
		mat.albedo_color = flash_color
		var tw := create_tween()
		tw.tween_property(mat, "albedo_color", tint, 0.18)


func _die(by_damage: float) -> void:
	_dead = true
	died.emit(by_damage)
	if _collision:
		_collision.set_deferred("disabled", true)
	# 向前扑倒（模型脸朝 +Z，绕 +X 转正角就是低头栽下去）
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(model, "rotation:x", deg_to_rad(72.0), 0.55).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(model, "position:y", model.position.y - visual_size.y * 0.06, 0.55)
	tw.chain().tween_interval(respawn_time)
	tw.chain().tween_callback(_respawn)


func _respawn() -> void:
	_dead = false
	health = max_health
	health_changed.emit(health, max_health)
	if _collision:
		_collision.set_deferred("disabled", false)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(model, "rotation:x", 0.0, 0.35)
	tw.tween_property(model, "position:y", model.position.y + visual_size.y * 0.06, 0.35)


# --- 工具 ---

func _all(node: Node, cls: String) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n == null:
			continue
		if n.is_class(cls):
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out


func _first(node: Node, cls: String) -> Node:
	var r := _all(node, cls)
	return r[0] if not r.is_empty() else null


## 骨头最多的那副骨架。有几只模型带多套 skin（比如同伴的 GLB 会多带 3~8 骨的
## 小骨架当挂件），取第一副可能抓到挂件那副，所以要按骨数挑。
func _best_skeleton(node: Node) -> Skeleton3D:
	var best: Skeleton3D = null
	for s in _all(node, "Skeleton3D"):
		var sk := s as Skeleton3D
		if best == null or sk.get_bone_count() > best.get_bone_count():
			best = sk
	return best
