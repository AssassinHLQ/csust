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
##   5. **碰撞盒**：四种形态见 `collision_mode`；蒙皮模型走「骨骼切片」，
##      而且**每物理帧按骨骼当前位置重算**（`_slices` / `_sync_bone_collisions()`）。
##      ⚠️ 子类若自己实现 `_physics_process`，必须调 `super._physics_process(delta)`。
##      来龙去脉见 README §7.3.1。

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
## 被打倒时掉进银行卡的钱（元）。0 = 不掉；飞猪优香 1 万（用户 2026-11）
## ⚠️ 倭瓜优香那 20 万**不走这里** —— 它由 `parkour.gd::_on_avenger_died()` 发，
##    两边都写会重复掉钱。
@export var drop_yuan := 0
## 掉落是**直接进银行卡**（true）还是**先进本轮资产、等跑酷结算再转卡**（false）。
##
## ⚠️ 默认 false 是**故意的**：用户 2026-11「为什么我还没有结算就 40w 了」
##    —— 那时候所有掉落都直接进卡，跑酷的资产结算形同虚设。
##
## 但用户 2026-11-09 单独要求飞猪优香：「把击败奖励从 1w 资产变成直接 1w 进银行卡」。
## 所以做成**按 Boss 开关**，飞猪在 `pig_boss.gd` 里打开它，别的 Boss 行为不变。
@export var drop_to_bank := false
@export var respawn_time := 6.0
## 倒下后要不要站起来。默认 true（练枪木桩 / 比纳以外的那几位）；
## 2026-10-20 的剧情 Boss 倭瓜优香设成 false —— 用户：「倭瓜优香不能复活」，
## 它一倒下牢笼就解开，这场架只有一次。
@export var respawn_on_death := true
## 想只留身体（隐藏光环/胸牌/球/方块）就打开
@export var hide_accessories := false
## 贴图之上的着色（白 = 用贴图原色）
@export var tint := Color.WHITE
## 受击闪白的颜色
@export var flash_color := Color(1.0, 0.55, 0.55)

## ── 进场加载节奏（2026-10-27 用户的分阶段加载策略，见 `boot_gate.gd`）──
## 玩家进场景后离得远就先不建模型；走近 `boot_distance` 米或等满 `boot_max_wait` 秒再建。
## 0/0 = 立即建（旧行为）。
@export var boot_distance := 0.0
@export var boot_max_wait := 0.0

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
var _booted := false

## ── 跟着骨骼走的碰撞盒（2026-11-11 用户报「碰撞错了，而且碰撞没有随着霸王龙放技能改变」）──
##
## 原来 `_build_bone_cluster_collision()` 只在 `_boot()` 那一刻按**当时一个姿态**
## 把骨骼切成几片、建成几个静态盒子，之后盒子就钉死在原地了。技能一播网格甩出去
## 十几米，盒子还留在下颚/尾巴的**旧位置** —— 打不中、人还能从身体穿过去。
## 实测（`_probe_trex_boxes.gd`）：五段技能各播到 impact 时刻，盒子位移全是 **0.00 m**。
##
## 现在每片记下「自己负责哪几根骨头」，`_physics_process` 里按骨骼**当前**位置
## 重算这一片的包围盒。两个做不到的地方值得写清楚：
##
## ⚠️ ① 为什么是「重算 AABB」而不是「把盒子挂在骨骼上」：
##    挂骨骼那版试过（盒子随代表骨做刚体旋转），静止和摆尾/跺地/撕咬都贴得很好，
##    但**弯折**的两段盖不住 —— 冲锋有骨头戳出盒面 1.79 m、咆哮 1.33 m
##    （`_verify_trex_hitbox.gd` 的「最远骨点出格」）。刚性片在骨头互相弯开时
##    必然张缝。重算 AABB 是「所有骨头都在自己包围盒里」的恒等式，
##    因此**任何姿势下都不可能漏出身体**，代价是形状要每帧改尺寸。
##
## ⚠️ ② 改的是 `BoxShape3D.size`（形状自己的尺寸），**不是** `CollisionShape3D` 的
##    缩放 —— 引擎对「带缩放的碰撞体」支持很差（见 `_build_convex_hulls_collision()`
##    里那段「玩家贴上去卡死」）。改形状尺寸是官方支持的路子。
##
## 每项：{ "cs": CollisionShape3D, "bones": PackedInt32Array, "last": AABB }
var _slices: Array[Dictionary] = []
var _follow_skel: Skeleton3D
## 切片盒子往外放的余量（骨点是中心线，离表皮还有距离）。建盒时算一次，每帧沿用。
var _slice_pad := 0.05
## 这片骨骼的包围盒长宽高变化都小于这个值就跳过写入（省掉物理服务器的空写）
const SLICE_EPS := 0.02

const BootGate := preload("res://scripts/boot_gate.gd")
const BankCard := preload("res://scripts/bank_card.gd")


func _ready() -> void:
	# 加进 `bosses` 组：同伴的枪（companion_gun.gd）靠这个组找 Boss 当目标。
	# ⚠️ 特意**不用** `targets` 组 —— game.gd 对 `targets` 组和 Boss 是分别连接
	#    `died` 的，Boss 若也进 targets 组会被连两次，一次击杀加两分。
	add_to_group("bosses")
	health = max_health
	health_changed.emit(health, max_health)
	# 模型 + 碰撞按距离/超时延后（玩家从蒙德里安二层出生，木桩在几十米外）
	BootGate.when_near(self, boot_distance, boot_max_wait, _boot)


func _boot() -> void:
	if _booted:
		return
	_booted = true
	_build_model()
	_build_collision()


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
	# ⚠️ **蒙皮模型必须走骨骼**，不能拿 `MeshInstance3D.get_aabb()` 量。
	#
	# 2026-11-08 用户报「瞄准中间那只霸王龙，打到的是右下角那只」「打得到但人飞不过去」——
	# 本喵用 `_diag_trex_aim.gd` 量出来：三只霸王龙的碰撞盒世界包围盒是
	#   218 × 96 × 99 m / 183 × 80 × 99 m / 253 × 112 × 164 m，
	# 而它们自己只有 24 × 10 × 8 m；盒子中心离身体 39~54 m。
	# 也就是玩家从出生点就被「隐形大盒子」挡住了，射线也在离相机 6 m 处撞上一个盒子。
	#
	# 根因就是 `_mesh_box()` 上面那条警告：这个 FBX 的网格顶点在**绑定空间**，
	# 跨度是骨架的 ~298 倍；而 `mi.global_transform` 每块网格还各自带一个
	# 3.01 / 0.307 / 0.024 的缩放 —— `size × scale` 出来什么都不是。
	# `visual_size` 之所以是对的，正是因为它走的是 `_bone_box()`。
	var skel := _best_skeleton(model)
	if skel != null and _build_bone_cluster_collision(skel):
		return true
	return _build_mesh_box_parts_collision()


## 蒙皮模型：把骨骼点沿「最长的水平轴」切片，每片包一个盒子，**并且每帧跟着骨骼重算**。
##
## 为什么切片而不是「一根骨头一个盒子」：73 根骨会变成 73 个碰撞形状，
## 物理侧每帧都要过一遍，而且大量骨骼是重叠的躯干内部骨，纯属浪费。
## 切片之后一只霸王龙 8 个盒子，轮廓已经能分清头 / 颈 / 躯干 / 尾。
##
## 为什么尺寸烘进 `BoxShape3D.size`、变换只放平移：Godot 对**带缩放的碰撞体**
## 支持很差（见 `_build_convex_hulls_collision()` 里那段「玩家贴上去卡死」）。
##
## ⚠️ 2026-11-11 两处改动（用户：「碰撞错了，而且碰撞没有随着霸王龙放技能改变」）：
##
## ① **切片方式改成按坐标等分**。原来是「按骨头根数等分」——可骨头密度极不均匀
##    （脚趾/下巴一堆小骨、尾巴稀），量出来 6 片是 13.98 / 2.25 / 3.89 / 4.32 / 3.00
##    / 8.78 m，尾巴那一片 14 m 长、把半个身子罩住。按坐标等分后每片长度接近。
## ② **每帧按骨骼当前位置重算每片的包围盒**（`_sync_bone_collisions()`）。
##    为什么不是「把盒子挂到骨骼上做刚体跟随」：那版试过了，静止/摆尾/跺地/撕咬
##    都贴得很好，但身体**弯折**的两段盖不住（冲锋戳出 1.79 m、咆哮 1.33 m）。
##    重算 AABB 是「骨头都在自己的包围盒里」的恒等式 —— 任何姿势都漏不出身体。
func _build_bone_cluster_collision(skel: Skeleton3D) -> bool:
	var to_body := global_transform.affine_inverse()
	var xf := to_body * skel.global_transform
	var pts: Array[Vector3] = []
	for i in skel.get_bone_count():
		pts.append(xf * skel.get_bone_global_pose(i).origin)
	if pts.size() < 6:
		return false
	var overall := _points_aabb(pts)
	if overall.size.y <= 0.0001:
		return false

	# 长轴：取 x / z 里更长的那个（模型可能被旋转过，不能写死 z）
	var axis := 0 if overall.size.x >= overall.size.z else 2
	var lo := overall.position[axis]
	var span := overall.size[axis]
	if span <= 0.0001:
		return false

	# 每片大约「三分之一身高」长 → 霸王龙 25 m 长、10 m 高 ⇒ 6~8 片。
	# ⚠️ 从「半身高、最多 6 片」加密的原因：片越粗，弯折时盒子膨胀得越厉害
	#    （AABB 要把整片包住），细一点畸形小、轮廓也更像身体。
	var slices := clampi(int(round(span / maxf(overall.size.y * 0.35, 0.2))), 3, 8)
	# 骨点是**骨架中心线**，离表皮还有距离：按身高给一圈余量
	var pad := maxf(overall.size.y * 0.055, 0.05)
	_slice_pad = pad
	# 相邻片沿长轴**轻微重叠**（各让出本片长度的 10%），弯折时相邻两片不会张开缝。
	var overlap := span / float(slices) * 0.10

	var made := 0
	for si in slices:
		# 按坐标等分：本片包含 [c0, c1)（最后一片含右端点）
		var c0 := lo + span * float(si) / float(slices) - overlap
		var c1 := lo + span * float(si + 1) / float(slices) + overlap
		var last := si == slices - 1
		var idx := PackedInt32Array()
		for k in pts.size():
			var v: float = pts[k][axis]
			if v >= c0 and (v < c1 or (last and v <= c1)):
				idx.append(k)
		if idx.is_empty():
			continue
		var sub: Array[Vector3] = []
		for k in idx:
			sub.append(pts[k])
		var bb := _points_aabb(sub).grow(pad)
		# 盒子不要探到地面以下（boss 脚底在 y = 0，地下半截纯属浪费）
		if bb.position.y < 0.0:
			var shrink := -bb.position.y
			bb.position.y = 0.0
			bb.size.y = maxf(bb.size.y - shrink, 0.1)
		var box := BoxShape3D.new()
		box.size = bb.size
		var cs := CollisionShape3D.new()
		cs.name = "Collision" if made == 0 else "Collision%d" % made
		cs.shape = box
		cs.transform = Transform3D(Basis.IDENTITY, bb.get_center())
		add_child(cs)
		_collisions.append(cs)
		# 记下「这片负责哪几根骨头」+ 上次算出来的盒子（用来跳过没变化的写入）
		_slices.append({ "cs": cs, "bones": idx, "last": bb })
		made += 1
	if made == 0:
		_collisions.clear()
		_slices.clear()
		return false
	_collision = _collisions[0]
	_follow_skel = skel
	collision_layer = 1
	collision_mask = 0
	print("[Boss] 骨骼切片碰撞：%d 个盒子（骨骼 %d 根，按%s轴等分，每帧跟随骨骼）" % [
		made, skel.get_bone_count(), "x" if axis == 0 else "z"])
	return true


## 每物理帧按骨骼**当前**位置重算每片碰撞盒（见 `_slices` 的注释）。
##
## 1 帧延迟说明：AnimationPlayer 在 `_process` 里刷骨骼，本函数在 `_physics_process`
## 里读，所以盒子最多比网格晚一物理帧（60 Hz 下 16 ms）—— 看不出来。
##
## 开销（`_verify_trex_hitbox.gd` 第 ③ 段实测）：单只 ≈ 40 μs / 帧，
## 第二关三只合计 ≈ 120 μs，约一帧（16.7 ms）的 0.7%。
## 盒子没变化时（`SLICE_EPS` 内）直接跳过写入，所以安静站着时更省。
func _sync_bone_collisions() -> void:
	if _slices.is_empty() or not is_instance_valid(_follow_skel):
		return
	var skel := _follow_skel
	var xf := global_transform.affine_inverse() * skel.global_transform
	for s in _slices:
		var cs: CollisionShape3D = s["cs"]
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		var ids: PackedInt32Array = s["bones"]
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for bi in ids:
			var p: Vector3 = xf * skel.get_bone_global_pose(bi).origin
			lo = lo.min(p)
			hi = hi.max(p)
		if lo.x == INF:
			continue
		var bb := AABB(lo, hi - lo).grow(_slice_pad)
		# 盒子不要探到地面以下（和建盒时同一口径，别让下半截凭空长出来）
		if bb.position.y < 0.0:
			var shrink := -bb.position.y
			bb.position.y = 0.0
			bb.size.y = maxf(bb.size.y - shrink, 0.1)
		var last: AABB = s["last"]
		if last.position.distance_to(bb.position) < SLICE_EPS \
				and last.size.distance_to(bb.size) < SLICE_EPS:
			continue
		(cs.shape as BoxShape3D).size = bb.size
		cs.transform = Transform3D(Basis.IDENTITY, bb.get_center())
		s["last"] = bb


func _physics_process(_delta: float) -> void:
	_sync_bone_collisions()


## 非蒙皮模型的老路径：**每块网格一个盒子**。
## 唯一改动是把世界包围盒**烘进尺寸**，不再给 `CollisionShape3D` 挂缩放。
func _build_mesh_box_parts_collision() -> bool:
	var to_body := global_transform.affine_inverse()
	var made := 0
	for m in _all(model, "MeshInstance3D"):
		var mi := m as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var local := to_body * (mi.global_transform * mi.get_aabb())
		if local.size.length() < 0.01:
			continue
		var b := BoxShape3D.new()
		b.size = local.size
		var cs := CollisionShape3D.new()
		cs.name = "Collision" if made == 0 else "Collision%d" % made
		cs.shape = b
		cs.transform = Transform3D(Basis.IDENTITY, local.get_center())
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


## 一串点的包围盒。
func _points_aabb(pts: Array[Vector3]) -> AABB:
	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	return AABB(lo, hi - lo)



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
	# 正常情况下 `_boot()` 里紧跟在 `_build_model()` 之后调，`model` 一定在。
	# 但 `_build_model()` 在 `load(model_path)` 失败时会提前 return（model 保持 null），
	# 那就别在这里崩 —— 报个明确的错比 Null 崩栈好排查。
	if model == null:
		push_error("[Boss %s] 建碰撞盒时 model 还是 null（模型没加载成功？）" % display_name)
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


## 打倒后往 HUD 上弹一行「银行卡 +¥1.0 万」。
## 没有 HUD（探针 / 无界面的测试场景）时静默跳过。
func _float_reward(yuan: int) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null or not hud.has_method("show_float_text"):
		return
	hud.call("show_float_text",
		"%s 打倒！银行卡 +%s" % [display_name, BankCard.format_yuan(yuan)])


func _die(by_damage: float) -> void:
	_dead = true
	if drop_yuan > 0:
		# ⚠️ 两种走法，由 `drop_to_bank` 决定（见那个字段的注释）：
		#   · false（默认）：先进本轮资产（跑酷的结算台再转银行卡）——
		#     不能直接进卡，用户 2026-11 报过「为什么我还没有结算就 40w 了」。
		#   · true：直接进银行卡（用户 2026-11-09 对飞猪优香的要求）。
		var fut := get_tree().get_first_node_in_group("futures")
		if not drop_to_bank and fut != null and fut.has_method("add_loot"):
			fut.call("add_loot", drop_yuan, "%s 掉落" % display_name)
			print("[Boss %s] 打倒 → 本轮资产 +%s（结算后进银行卡）" % [display_name,
				BankCard.format_yuan(drop_yuan)])
		elif fut != null and fut.has_method("add_bank"):
			# ⚠️ 2026-11-09 修「飞猪优香打完不掉钱了」：
			#
			# 原来这里只调 `BankCard.add()`。卡里确实加了钱，但 `parkour_futures.gd`
			# 自己还维护一份 `bank_yuan`（结算时 `BankCard.set_balance(bank_yuan)` 回写）。
			# 那份没跟着涨 ⇒ 只要进一次跑酷结算，飞猪这 1w 就被旧值**盖掉**。
			# 实测（`_verify_pig_bank_leak.gd`）：打死后 card=10000 / futures=0，
			# 模拟结算后 card 又变回 **0**。
			#
			# `add_bank()` 是期货那边专门给「直接进卡的钱」准备的入口，它会同时
			# 更新 `bank_yuan` 并刷 HUD 的「银行卡」列（见 `parkour_futures.gd:945`）。
			fut.call("add_bank", drop_yuan, "%s 打倒掉落" % display_name)
			print("[Boss %s] 打倒 → 直接进银行卡 %s（余额 %s，已同步期货账本）" % [display_name,
				BankCard.format_yuan(drop_yuan), BankCard.format_yuan(BankCard.balance())])
			_float_reward(drop_yuan)
		else:
			# 没有 futures 节点（比如单独跑探针/测试场景）：只能直接写卡。
			BankCard.add(drop_yuan)
			print("[Boss %s] 打倒 → 直接进银行卡 %s（余额 %s，无期货节点未同步）" % [display_name,
				BankCard.format_yuan(drop_yuan), BankCard.format_yuan(BankCard.balance())])
			_float_reward(drop_yuan)
	died.emit(by_damage)
	for c in _collisions:
		c.set_deferred("disabled", true)
	# ── 模型可能**还没建**（`_boot()` 是 BootGate 近距离才触发的延迟建）──
	#
	# ⚠️⚠️ 2026-11-11 用户：「按 F3 的 F5 游戏崩溃」，报错：
	#     Cannot call method 'set_trans' on a null value.
	#     0 - boss.gd:747  at function: _die
	#     3 - player.gd:590  at function: _dev_key    ← F5 秒杀
	#
	# 真因：F5 给全场 Boss 打 1e9 伤害，而远处的 Boss 还没被 BootGate 建出来，
	# `model` 仍是 null。`tween_property(null, ...)` 返回 **null**，
	# 后面链式的 `.set_trans(...)` 就崩了。
	#
	# 这**不只是调试路径的问题**：任何"Boss 还没生成就被打死"的场合
	# （远程武器、爆炸、脚本强制结算）都会踩到。
	if model == null:
		# 没模型就别演扑倒动画，但**掉落/结算/复活计时照走**
		# （掉落逻辑在上面已经执行完了，这里只跳过视觉）
		if respawn_on_death:
			var tw0 := create_tween()
			tw0.tween_interval(respawn_time)
			tw0.tween_callback(_respawn)
		return
	# 向前扑倒（模型脸朝 +Z，绕 +X 转正角就是低头栽下去）
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(model, "rotation:x", deg_to_rad(72.0), 0.55).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(model, "position:y", model.position.y - visual_size.y * 0.06, 0.55)
	if not respawn_on_death:
		return
	tw.chain().tween_interval(respawn_time)
	tw.chain().tween_callback(_respawn)


func _respawn() -> void:
	_dead = false
	health = max_health
	health_changed.emit(health, max_health)
	for c in _collisions:
		c.set_deferred("disabled", false)
	# 同上：模型可能还没建，这时候没有可复位的视觉
	if model == null:
		return
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
