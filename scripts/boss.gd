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
## ⚠️ 只在 `collision_mode = BOX`、或其它形态建不出来时才用。
@export var collision_factors := Vector3(0.55, 0.85, 0.62)
## 碰撞形态：
##   BOX          一个方盒子把整只 Boss 框住（老行为，最省，撞哪儿都不准）
##   BOX_PARTS    每块身体一个盒子（由 AABB 得来），便宜但只是「几个方块」
##   CONVEX_HULLS **自动凹包分解**（默认）—— 对应 UE 的 Convex Decomposition：
##                引擎自带 V-HACD，走 `MeshInstance3D.create_multiple_convex_collisions()`
##   TRIMESH      原始网格全量三角面（最准，也最费 —— 用户报「有点卡」就是它）
enum CollisionMode { BOX, BOX_PARTS, CONVEX_HULLS, TRIMESH }
@export var collision_mode: CollisionMode = CollisionMode.CONVEX_HULLS
## 每块身体最多拆几个凸包。8~16 足够描出轮廓，再多收益很小。
@export var max_convex_hulls := 12
@export var max_trimesh_tris := 60000
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
## 多块碰撞体（BOX_PARTS 模式会是好几个）。`_collision` 就是第一个，保持兼容。
var _collisions: Array[CollisionShape3D] = []


func _ready() -> void:
	# 加进 `bosses` 组：同伴的枪（companion_gun.gd）靠这个组找 Boss 当目标。
	# ⚠️ 特意**不用** `targets` 组 —— game.gd 对 `targets` 组和 Boss 是分别连接
	#    `died` 的，Boss 若也进 targets 组会被连两次，一次击杀加两分。
	add_to_group("bosses")
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
	var res := load(model_path)
	if res == null:
		push_error("[Boss] 找不到模型：%s" % model_path)
		return
	# ⚠️ **FBX 导入成 `PackedScene`，OBJ 导入成 `Mesh`** —— 两种都要接。
	#    （倭瓜优香就是 .obj：`wavefront_obj` 导入器的 `type="Mesh"`，
	#    直接 `as PackedScene` 会拿到 null，模型整个不出现。）
	if res is PackedScene:
		model = (res as PackedScene).instantiate() as Node3D
	else:
		model = Node3D.new()
		model.name = "ObjModel"
		var mi := MeshInstance3D.new()
		mi.name = "%s_mesh" % model_path.get_file().get_basename()
		mi.mesh = res as Mesh
		model.add_child(mi)
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
	if collision_mode == CollisionMode.TRIMESH:
		if _build_trimesh_collision():
			return
	elif collision_mode == CollisionMode.CONVEX_HULLS:
		if _build_convex_hulls_collision():
			return
	elif collision_mode == CollisionMode.BOX_PARTS:
		if _build_box_parts_collision():
			return
	_build_box_collision()


## **自动凹包分解（默认）**：引擎自带的 V-HACD，就是 UE 那个 Convex Decomposition。
##
## `MeshInstance3D.create_multiple_convex_collisions(settings)` 会**顺手挂一个
## StaticBody3D 子节点**、里面塞一堆 `ConvexPolygonShape3D`。这里不直接用它：
##   · `_die()` / `_respawn()` 要统一开关碰撞，多一层 body 不好管；
##   · 也不想让 boss 平白多出一个节点。
## 所以把生成的形状**捞出来**、搬进 boss 自己的 CollisionShape3D 里，再把临时 body 删掉。
##
## ⚠️ 耗时实测：猪猪优香最大那块网格（6148 顶点）**103 ms**。
##    之前「跑 5 分钟没结果」是 **FBX 首次导入**在拖，不是分解 —— 别被那次误导。
func _build_convex_hulls_collision() -> bool:
	var settings := MeshConvexDecompositionSettings.new()
	settings.max_convex_hulls = max_convex_hulls
	settings.max_num_vertices_per_convex_hull = 32
	settings.convex_hull_downsampling = 2
	settings.convex_hull_approximation = true
	settings.min_volume_per_convex_hull = 0.0001
	var to_body := global_transform.affine_inverse()
	var made := 0
	for m in _all(model, "MeshInstance3D"):
		var mi := m as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		mi.create_multiple_convex_collisions(settings)
		for c in mi.get_children():
			if not (c is StaticBody3D):
				continue
			for cc in c.get_children():
				if not (cc is CollisionShape3D):
					continue
				var src := (cc as CollisionShape3D).shape
				if not (src is ConvexPolygonShape3D):
					continue
				var pts: PackedVector3Array = (src as ConvexPolygonShape3D).points
				if pts.size() < 4:
					continue
				# ⚠️ **把缩放烘进顶点，不要挂在 CollisionShape3D 的 transform 上。**
				#    Boss 模型是按 `height` 缩放过的，第一版写成
				#    `cs.transform = to_body * cc.global_transform` —— 那是一个带缩放的
				#    CollisionShape3D，Godot 对碰撞体缩放支持很差：玩家贴上去会被
				#    「卡住动不了」（用户就是在这里卡死的）。烘进 points 之后
				#    `cs.transform` 是单位阵，物理侧只看见「一组没缩放的凸包」。
				var xf := to_body * (cc as CollisionShape3D).global_transform
				var local := PackedVector3Array()
				local.resize(pts.size())
				for k in pts.size():
					local[k] = xf * pts[k]
				var hull := ConvexPolygonShape3D.new()
				hull.points = local
				var cs := CollisionShape3D.new()
				cs.name = "Collision" if made == 0 else "Collision%d" % made
				cs.shape = hull
				add_child(cs)
				_collisions.append(cs)
				made += 1
			c.queue_free()
	if made == 0:
		_collisions.clear()
		return false
	_collision = _collisions[0]
	collision_layer = 1
	collision_mask = 0
	print("[Boss] 自动凹包分解：%d 个凸包（V-HACD，UE 同款）" % made)
	return true


## **低模碰撞（默认）**：每块可见网格 → 一个 `BoxShape3D`，位置/尺寸取该网格的 AABB。
##
## ── 为什么最后选的是这个 ──
## ① UE 那种「自动凹包分解」Godot **有**：`MeshConvexDecompositionSettings` +
##    `MeshInstance3D.create_multiple_convex_collisions()`（V-HACD）。但**太慢** ——
##    在猪猪优香这份模型上跑 **5 分钟没出结果**，载入时做等于卡死。
## ② `Mesh.create_convex_shape()`（全部顶点求 QuickHull）同样跑到超时；
##    连「抽 600 个点交给 `ConvexPolygonShape3D.set_points()`」都**不返回**（试过两次）。
## ③ 全量三角网格（上一版）确实准，但用户报「有点卡」。
## ⇒ 折中：**每块身体一个盒子**。盒子是引擎里最便宜的凸形状，
##    4~9 个拼起来轮廓已经有模有样（头/身体/尾巴各一个），
##    而且求 AABB 是 O(1)（导入时就缓存好了），载入零成本。
func _build_box_parts_collision() -> bool:
	var to_body := global_transform.affine_inverse()
	var made := 0
	for m in _all(model, "MeshInstance3D"):
		var mi := m as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var box := mi.get_aabb()
		if box.size.length() < 0.01:
			continue
		var b := BoxShape3D.new()
		b.size = box.size
		var cs := CollisionShape3D.new()
		cs.name = "Collision" if made == 0 else "Collision%d" % made
		cs.shape = b
		cs.transform = to_body * mi.global_transform \
			* Transform3D(Basis.IDENTITY, box.get_center())
		add_child(cs)
		_collisions.append(cs)
		made += 1
	if made == 0:
		_collisions.clear()
		return false
	_collision = _collisions[0]
	collision_layer = 1
	collision_mask = 0
	print("[Boss] 低模碰撞：%d 个盒子（每块身体一个）" % made)
	return true



## 复杂碰撞：把模型**可见**网格的三角形原样做成 `ConcavePolygonShape3D`。
## 子弹打在哪儿就命中哪儿，不再是「一个大方盒子把尾巴 / 空隙都算进去」。
##
## 为什么不用 `create_trimesh_collision()` / `create_convex_collision()`：
## 那两个是给编辑器用的辅助函数，会**多挂一个 StaticBody3D 子节点**，
## 而这里 boss 自己就是 StaticBody3D，`_die()` / `_respawn()` 还要统一开关
## `_collision.disabled` —— 多一层节点会让「倒下后碰撞体关闭」那条自检失效。
func _build_trimesh_collision() -> bool:
	# 顶点要换到**本节点**的局部空间：CollisionShape3D 的 shape 是局部坐标
	var to_body := global_transform.affine_inverse()
	var faces := PackedVector3Array()
	var tris := 0
	for m in _all(model, "MeshInstance3D"):
		var mi := m as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var xf := to_body * mi.global_transform
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			if verts.is_empty():
				continue
			var idx = arr[Mesh.ARRAY_INDEX]
			var indices: PackedInt32Array
			if idx == null or (idx as PackedInt32Array).is_empty():
				indices = PackedInt32Array()
				for i in verts.size():
					indices.append(i)
			else:
				indices = idx
			var n := (indices.size() / 3) * 3
			if (tris + n / 3) > max_trimesh_tris:
				print("[Boss] 三角面将超过上限 %d → 退回盒子形状" % max_trimesh_tris)
				return false
			for i in range(0, n, 3):
				faces.append(xf * verts[indices[i]])
				faces.append(xf * verts[indices[i + 1]])
				faces.append(xf * verts[indices[i + 2]])
			tris += n / 3
	if faces.is_empty():
		return false
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	# ⚠️ 必须开双面：`ConcavePolygonShape3D` 默认只认**正面**，
	#    而模型一旦带负缩放（镜像）或法线朝里，整张网就全是背面 ——
	#    射线会直接穿过去（第一版就是这样，自检报「子弹射线能打到 Boss 本体」红）。
	shape.backface_collision = true
	_collision = CollisionShape3D.new()
	_collision.name = "Collision"
	_collision.shape = shape
	_collision.position = Vector3.ZERO
	add_child(_collision)
	_collisions = [_collision]
	collision_layer = 1
	collision_mask = 0
	print("[Boss] 复杂碰撞：%d 个三角面（三角网格，不再是盒子）" % tris)
	return true


func _build_box_collision() -> void:
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
	_collisions = [_collision]
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
	for c in _collisions:
		c.set_deferred("disabled", true)
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
	for c in _collisions:
		c.set_deferred("disabled", false)
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
