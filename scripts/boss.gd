class_name Boss
extends StaticBody3D
## 霸王龙优香 —— 目前是「木桩」：摆在场地上、吃得下子弹、受击闪白、倒下后重生。
## 行为（冲撞 / 吐息 / AI）留待后续；这一版只解决「模型怎么修、多大、朝向哪」。
##
## ⚠️ 这个 FBX 有几个坑，改参数前先读 README §7.2：
##   1. 网格顶点在「绑定空间」，跨度是骨架的 ~298 倍 —— **必须保留蒙皮**。
##      把 skin 置空 → 网格会散成一片「刀刃」；
##      按网格包围盒取景 → 会误判成「模型只有一个像素点」。
##      所以归一化用 **骨架的世界包围盒**。
##   2. 材质里没有 albedo 贴图 → 必须手工绑，否则整只白模。
##   3. 光环/胸牌/球/方块这 5 个挂件的缩放与身体差 1~2 个数量级 → 隐藏。
##   4. 模型自身脸朝 +Z（rotation.y = 0 时），与 Arisu 同一套朝向约定。

signal died(by_damage: float)
signal health_changed(current: float, maximum: float)

@export_file("*.fbx") var model_path := "res://models/boss/优香霸王龙.fbx"
@export_file("*.png") var texture_path := "res://models/boss/tex/body_basecolor.png"
## 目标身高（m）。Arisu 约 1.7、靶子柱 1.15；木桩默认 4.5（约 2.6 个 Arisu）
@export var height := 4.5
@export var max_health := 3000.0
@export var respawn_time := 6.0
@export var hide_accessories := true
## 贴图之上的着色（白 = 用贴图原色）
@export var tint := Color.WHITE
## 受击闪白的颜色
@export var flash_color := Color(1.0, 0.55, 0.55)

var health: float
var model: Node3D
## 归一化后的视觉尺寸（世界，m）
var visual_size := Vector3.ZERO
var bone_count := 0

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

	# 1. 隐藏挂件（缩放与身体差 1~2 个数量级）
	var hidden := 0
	for mi in _all(model, "MeshInstance3D"):
		if not (mi as MeshInstance3D).name.begins_with("Tyrannosaurus"):
			(mi as MeshInstance3D).visible = false
			hidden += 1

	# 2. 绑贴图（材质是共享的，4 个部件同一份，绑一次就够）
	var tex: Texture2D = load(texture_path) if texture_path != "" else null
	var surfaces := 0
	for mi in _all(model, "MeshInstance3D"):
		var m := mi as MeshInstance3D
		if not m.visible or m.mesh == null:
			continue
		var am := m.mesh as ArrayMesh
		for s in am.get_surface_count():
			var mat := am.surface_get_material(s)
			if mat is StandardMaterial3D:
				var sm := mat as StandardMaterial3D
				if sm.albedo_texture == null and tex != null:
					sm.albedo_texture = tex
				sm.albedo_color = tint
				if not _materials.has(sm):
					_materials.append(sm)
				surfaces += 1
			elif mat != null:
				push_warning("[Boss] 材质不是 StandardMaterial3D，受击闪白会失效：%s" % mat.get_class())

	# 3. 按【骨架】包围盒归一化。
	#
	# ⚠️ 必须在 **Boss 节点自己的局部空间** 里量！
	#    本喵第一版在世界空间量、却把结果当局部坐标去设 model.position ——
	#    而 game.tscn 里 Boss 绕 Y 转了 -90°，于是：
	#      · 水平居中歪掉（实测差 1.8 m）
	#      · 长短轴被转错（12.6 m 的长轴被记到 x 上），碰撞盒跟着变形
	#    正确做法：把骨骼点先乘 model.global_transform 的逆，落到父节点空间。
	#
	# 另外这里**不需要回测**：此刻 model 的变换还是单位变换，缩放 s 之后
	# 新框 = 原框 × s（均匀缩放、绕自身原点），偏移量可以直接解析算出来。
	var skel := _first(model, "Skeleton3D") as Skeleton3D
	if skel == null:
		push_error("[Boss] 模型里没有 Skeleton3D")
		return
	bone_count = skel.get_bone_count()
	var box := _bone_box(skel)
	if box.size.y <= 0.0001:
		push_error("[Boss] 骨架包围盒退化，无法归一化")
		return
	var s := height / box.size.y
	model.scale = Vector3(s, s, s)
	# 水平居中 + 脚底落在 y = 0（都在父节点空间里）
	model.position = Vector3(
		-box.get_center().x * s, -box.position.y * s, -box.get_center().z * s)
	visual_size = box.size * s
	print("[Boss] 模型就位：%d 骨，隐藏挂件 %d 个，贴图表面 %d 个，尺寸 %s（目标身高 %.2f m）" % [
		bone_count, hidden, surfaces, str(visual_size.snappedf(0.01)), height])


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


# --- 碰撞（木桩要能被打到）---

func _build_collision() -> void:
	if visual_size == Vector3.ZERO:
		return
	_collision_shape = BoxShape3D.new()
	# 身体占全长约 6 成（剩下是尾巴，不细究）；盒子稍微往上抬一点，避开脚
	_collision_shape.size = Vector3(
		maxf(visual_size.x * 0.55, 0.5),
		maxf(visual_size.y * 0.85, 0.5),
		maxf(visual_size.z * 0.62, 0.5))
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
