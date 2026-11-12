extends Node3D
## 电竞房碰撞（2026-11-09 v3）：用**离线烘好的**「一件物体一个盒子」。
##
## ── 使用者原话 ──
## 「你总是做大了碰撞，我体验不好，书本桌子本来是两个不同的碰撞，
##   结果你只做一个大的碰撞」
##
## ── 为什么旧版会「做成一坨」──
## 屋壳 GLB 是**按材质合并**的：`build_esports_room.py::merge_by_material()`
## 把 FBX 里 **738 个独立物件**合成 **59 个材质桶**（为省 draw call）。
## 于是「书」和「桌子」如果同材质就进了同一个网格 —— 只能给整个网格一个盒子，
## 碰撞自然变成一大坨，人也钻不过桌子底下。
##
## ── 现在怎么做 ──
## 分两步，**离线算好、运行时零开销**：
##   ① `tools/dump_esports_parts.py`（Blender）
##      从容**未合并**的 FBX 里逐件量世界 AABB → `models/esports_room/esports_parts.json`
##      实测：728 件物体（对比 GLB 只有 59 个）
##          小到 0.33×0.08×0.07 的书、0.42×0.26×0.08 的摆件，**各自独立**
##   ② `scripts/_bake_esports_parts.gd`（Godot）
##      把 JSON 烘成 `scenes/esports_collision_baked.tscn`
##      —— 一件一个 `BoxShape3D`，共 **335 个形状**
##
## 本脚本只负责**自检**：确认 `BakedCollision` 那个实例在。
## 真正干活的形状全在场景文件里，运行时不需要建任何东西
## （旧版运行时建 760 个盒子要 **575 ms**，现在 0 ms）。
##
## ⚠️ 2026-11-11 起本脚本还兼职一件事：**电竞房的 BGM 触发区**（见文件末尾）。
##    本节点就是 `EsportsRoom` 的根，而 BGM 必须跟着这栋房子的「现没现身」走
##    （房间默认是藏着的），挂在别处拿不到那个状态 —— 所以没另开一个脚本。
##    触发区的做法与 `scripts/gamedev_room.gd::_build_music_zone()` 一致。

## 烘好的碰撞场景（在 `esports_room.tscn` 里被实例化成 `BakedCollision`）
const BAKED_NODE := "BakedCollision"
## 烘好的碰撞体（一件物体一个盒子）在这个路径下
const BAKED_AUTOCOL := "BakedCollision/AutoCol"

## ── BGM ──
## 曲目表见 `scripts/music.gd`（逻辑名 `esports`）
const MUSIC_TRACK := "esports"
## 触发区比房间**往外扩**多少米（每边）。
##
## 用户 2026-11-11：「电竞房判定范围往外扩一圈2m」。
## 早先是往内缩 0.6 m（怕贴墙走忽开忽关），但那样跨门槛时会卡在墙线上；
## 现在改成外扩 2 m：墙外 2 m 就开、走出 2 m 才停。
const MUSIC_GROW := 2.0

var _reported := false
var _music_inside := 0
var _music_area: Area3D


func _ready() -> void:
	# 房子默认藏着（`game.tscn` 里 `visible = false`，买完才降下来），
	# 所以「现身」这件事本身就是一次状态变化，必须接上。
	visibility_changed.connect(_refresh_music)
	await get_tree().process_frame
	build_collision()
	_build_music_zone()
	_build_base_steps()
	_open_cabinet()


## 对外入口（探针也调）。**幂等**：只报一次。
func build_collision() -> void:
	if _reported:
		return
	_reported = true
	var baked := get_node_or_null(BAKED_NODE)
	if baked == null:
		# ⚠️ 不要静默失败：没有碰撞玩家会直接掉出房间
		push_warning("[EsportsCol] 没找到 %s —— 碰撞场景丢了？"
			% BAKED_NODE
			+ " 重新生成：blender 跑 tools/dump_esports_parts.py，"
			+ "再 godot 跑 scripts/_bake_esports_parts.gd")
		print("[EsportsCol] !! 缺 %s，屋子没有碰撞" % BAKED_NODE)
		return
	var body := baked.get_node_or_null("AutoCol")
	var n := 0 if body == null else body.get_child_count()
	print("[EsportsCol] 用烘好的碰撞：%s，%d 个形状（一件物体一个盒子）" % [
		BAKED_NODE, n])


# ══════════════════════════ BGM 触发区 ══════════════════════════
#
# 用户 2026-11-11：「Colorful Mess 这个放电竞房里面」——
# 走进电竞房开，走出去停（不淡化）。曲目在 `scripts/music.gd`（逻辑名 `esports`）。
#
# ── 和部室（`scripts/gamedev_room.gd`）的做法一样的地方 ──
# 用 `Area3D` 而不是每帧算距离、用**计数**而不是布尔（理由见
# `scripts/shop.gd::_build_music_zone()`），盒子尺寸**运行时量**、不写死在 .tscn 里。
#
# ── 不一样的两点，都是这栋房子特有的 ──
# 1. **这房子平时是藏着的**（`game.tscn` 里 `visible = false`，买完才从天而降）。
#    而 `Area3D.monitoring` 跟可见性无关 —— 不判可见性的话，玩家在还没出现的
#    房子那块空地上走过就会响起 BGM。所以：
#      · 进出时判 `is_visible_in_tree()`；
#      · 并且接 `visibility_changed`：万一玩家已经站在那块地上、房子才落地，
#        也能当场补上（不然要等他走出去再走进来）。
# 2. 碰撞是**离线烘好的 769 个盒子**（`BakedCollision/AutoCol`），不是手拖的几个。
#    房间还在改（门、家具都在动），所以同样**不写死尺寸**，直接从这些盒子量包围盒，
#    再按 `MUSIC_GROW` 往外扩一圈（见那个常量的说明）。

func _build_music_zone() -> void:
	if _music_area != null and is_instance_valid(_music_area):
		return
	var bounds := _baked_bounds()
	if bounds.size == Vector3.ZERO:
		push_warning("[EsportsCol] 量不到烘好的碰撞包围盒，BGM 触发区不建"
			+ "（重新烘焙：blender 跑 tools/dump_esports_parts.py + scripts/_bake_esports_parts.gd）")
		return
	var area := Area3D.new()
	area.name = "MusicZone"
	area.collision_layer = 0          # 自己不被撞
	area.collision_mask = 1           # 只感应世界层（玩家在第 1 层）
	area.monitoring = true
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# 水平方向**往外扩 MUSIC_GROW**（用户 2026-11-11：「电竞房判定范围往外扩一圈2m」），
	# 也就是音乐在墙外 2 m 就开始响、走出去 2 m 才停 —— 跨越门槛时不会正好卡在墙线上。
	# 高度仍取包围盒的 2 倍、中心在包围盒中心：那本来就已经远超墙高，没必要再往外长。
	box.size = Vector3(
		maxf(bounds.size.x + MUSIC_GROW * 2.0, 0.5),
		maxf(bounds.size.y * 2.0, 1.0),
		maxf(bounds.size.z + MUSIC_GROW * 2.0, 0.5))
	cs.shape = box
	var c := bounds.get_center()
	cs.position = c
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(_on_music_body.bind(1))
	area.body_exited.connect(_on_music_body.bind(-1))
	_music_area = area
	print("[EsportsCol] BGM 触发区：%.2f × %.2f × %.2f m（房间 %.2f × %.2f × %.2f，水平每边 +%.1f m），中心本地 (%.2f, %.2f, %.2f)（曲目 `%s`）"
		% [box.size.x, box.size.y, box.size.z,
			bounds.size.x, bounds.size.y, bounds.size.z, MUSIC_GROW,
			c.x, c.y, c.z, MUSIC_TRACK])


## `BakedCollision/AutoCol` 里所有碰撞盒的包围盒（**本节点空间**）。
## 逐个盒子的 8 个角换到本节点空间再 `expand` —— 房子的旋转（`game.tscn` 里
## 它转了 180°）自动被算进去，不用手写坐标映射。
func _baked_bounds() -> AABB:
	var auto_col := get_node_or_null(BAKED_AUTOCOL) as Node3D
	if auto_col == null:
		return AABB()
	var inv := global_transform.affine_inverse()
	var out := AABB()
	var seen := false
	for child in auto_col.get_children():
		var node := child as CollisionShape3D
		if node == null or node.disabled:
			continue
		var box := node.shape as BoxShape3D
		if box == null:
			continue
		var xf := inv * node.global_transform
		var h := box.size * 0.5
		for i in 8:
			var p: Vector3 = xf * Vector3(
				h.x if (i & 1) != 0 else -h.x,
				h.y if (i & 2) != 0 else -h.y,
				h.z if (i & 4) != 0 else -h.z)
			if seen:
				out = out.expand(p)
			else:
				out = AABB(p, Vector3.ZERO)
				seen = true
	return out


func _on_music_body(body: Node3D, delta: int) -> void:
	if not body.is_in_group("player"):
		return
	_music_inside = maxi(_music_inside + delta, 0)
	_refresh_music()


## 按「人在不在里面」+「房子现身没有」这两个条件定音乐状态。**幂等**。
func _refresh_music() -> void:
	if _music_inside > 0 and is_visible_in_tree():
		Music.play(MUSIC_TRACK)
	elif Music.current() == MUSIC_TRACK:
		# 只在「放的正好是自己这首」时才停 —— 免得以后别的房间共用同一个播放器
		# 时，走到门口把人家的 BGM 掐掉
		Music.stop()


## 房间被释放 / 换场景时别把 BGM 留在空气里飘。
func _exit_tree() -> void:
	if _music_inside > 0 and Music.current() == MUSIC_TRACK:
		Music.stop()


# ══════════════════════ 底座外沿 → 台阶环 ══════════════════════
#
# 用户 2026-11-11：「电竞房下面那个碰撞的最大的底座，应该改成台阶而不是长方体」
#                    → 选「底座四边外沿做成台阶环」。
#
# ── 这块「底座」是什么 ──
# `AutoCol/P0000_0` = **9.20 × 0.30 × 10.73 m，y 0.06~0.36**，就是 `esports_parts.json`
# 里的 `物件_1` —— **房间地板**（比屋外地面高 30 cm）。烘焙脚本 `_bake_esports_parts.gd`
# 的 `FLOOR_LIFT` 又把它整体抬了 0.06 m（让角色的脚露在地板之上）。
# 所以玩家现在进屋是**一步跨 36 cm** —— 接近 `step_climb.gd` 的 0.38 m 上限，
# 手感是「卡一下再上去」。
#
# ── 做成什么 ──
# 在底座四周**外沿**铺一圈 3 级踏步（每级 0.10 m 高、0.22 m 深），
# 从屋外地面一级级走到台面高度。台阶**不覆盖**底座本身（底座保持原样当平台），
# 所以室内走动、家具、门洞全都不受影响。
#
# ⚠️ 只加**水平外沿**的台阶，不动 `AutoCol` 里任何一个原盒子：
#    动原盒子等于重新烘焙碰撞，门洞/家具那些刚调好的东西全得重验一遍。
#
# ⚠️ 台阶在底座**外沿之外**，所以三面会被墙压住（墙就立在底座外沿上，0.21 m 厚）——
#    那三面的台阶玩家实际走不到，但留着无害（撞墙前先踩上台阶，反而更自然）。
#    真正有用的那面是 **+Z 门那一侧**：底座在那边本来就短一截（z 只到 2.91，
#    而门墙在 2.70~2.91），台阶正好补在门口外头。

## 台阶级数
const STEP_COUNT := 3
## 每级进深（米）。0.22 m 比常见脚掌长（约 26 cm）略窄，但碰撞体的胶囊半径 0.30，
## 实际踩上去很稳；再放宽会和门洞、家具挤在一起。
const STEP_DEPTH := 0.22
## 台阶命名，自检按名字找
const STEP_NODE := "BaseSteps"


## 找出「玩家脚下那块底座」，**按世界坐标认**。
##
## ⚠️⚠️ 别按局部 y 认 —— 这间房在 `game.tscn` 里是 **`Y=-1` 翻转**的
## （`Transform3D(1,0,0, 0,-1,0, 0,0,-1, …)`，模型是倒着建的），
## 所以「局部 y 大」= 「世界 y 小」：
##
##     局部 y 0.06~0.36（烘焙脚本里叫「地板」物件_1）→ 世界 y 3.25~3.55   ← 跑顶上去了
##     局部 y 3.27~3.57（烘焙脚本里叫「天花板」物件_8）→ 世界 y 0.04~0.34  ← 玩家踩的是这块
##
## 本喵第一版按局部 y 找，正好找反：台阶被铺在了玩家够不着的顶层板边上
## （探针量出来的 —— 射线在门口上方 3.55 m 处才命中台阶）。
##
## 判据（**世界空间**，相对「全部碰撞盒的最低处」算，不写死绝对高度）：
##   顶面离最低处不超过 0.80 m + 水平投影最大（> 4 m²）。
## 用相对量而不是 `y < 0.8`：独立加载 `esports_room.tscn` 时房间摆在世界原点、
## 局部坐标直接就是世界坐标（底座在 y 0.06~0.36），绝对判据也成立；
## 但放在 game.tscn 里、或以后有人把它抬高/放低，相对量都不会误判。
func _find_base_box() -> AABB:
	var auto_col := get_node_or_null(BAKED_AUTOCOL) as Node3D
	if auto_col == null:
		return AABB()
	# 先求所有盒子的世界范围，拿到「最低处」
	var all_boxes: Array[AABB] = []
	var lowest := INF
	for child in auto_col.get_children():
		var node := child as CollisionShape3D
		if node == null or node.disabled:
			continue
		var box := node.shape as BoxShape3D
		if box == null:
			continue
		var a: AABB = node.global_transform * AABB(-box.size * 0.5, box.size)
		all_boxes.append(a)
		lowest = minf(lowest, a.position.y)
	if all_boxes.is_empty() or lowest == INF:
		return AABB()
	# 顶面在「最低处 + 0.80 m」以内、水平投影最大的那块 = 底座台面
	var best := AABB()
	var best_area := 4.0
	for a in all_boxes:
		if a.end.y > lowest + 0.80:
			continue
		var area := a.size.x * a.size.z
		if area > best_area:
			best_area = area
			best = a
	return best


## 绕底座外沿铺一圈台阶。**幂等**：已经有了就不再建。
##
## 全部按**世界坐标**摆，最后再换算回本节点空间（`global_transform.affine_inverse()`）——
## 因为房间是翻转的，直接在局部空间里「往上加 y」会变成往下（见 `_find_base_box` 的说明）。
##
## ⚠️ 只在**房间真的摆进场地时**才建台阶：这栋房子在 `game.tscn` 里带 `Y=-1` 翻转
## （`basis.y.y < 0`），翻转之后「哪块板在玩家脚下」才确定。独立加载
## `esports_room.tscn`（探针/自检常这么干）时没有那个翻转，两块大板上下互换，
## 「底座」根本不存在 —— 那种情况下建出来的台阶会挂在半空中
## （实测：每级只有 0.018 m 高，因为选中的是另一块薄板）。
func _build_base_steps() -> void:
	# ⚠️ 先看场景里有没有**已经摆好的**（`scenes/esports_room.tscn` 里现在就有一个
	#    `BaseSteps` 静态节点，是烘进场景的）—— 有就什么都不做，别叠出第二份。
	#    这一步要放在翻转判断**之前**：静态节点是房间本地空间的，
	#    独立加载 tscn 时（没有翻转）它照样在，不该被跳过。
	if get_node_or_null(STEP_NODE) != null:
		return
	if global_basis.y.y >= 0.0:
		return                      # 没摆进场地（未翻转），不建
	var base := _find_base_box()
	if base.size == Vector3.ZERO:
		push_warning("[EsportsCol] 找不到底座盒，台阶环不建")
		return

	var body := StaticBody3D.new()
	body.name = STEP_NODE
	add_child(body)

	var inv := global_transform.affine_inverse()
	var bottom := base.position.y
	var top := base.end.y
	# 每级高度 = 底座厚度 ÷ 级数（0.30 ÷ 3 = 0.10），不写死 ——
	# 写死会在底座厚度变化时让最内圈比台面高出一截。
	var step_h := (top - bottom) / float(STEP_COUNT)
	var cx := base.get_center().x
	var cz := base.get_center().z

	var made := 0
	for j in STEP_COUNT:                       # j=0 最内圈（最高、齐平台面）→ j=2 最外圈（最矮）
		var step_top := top - float(j) * step_h
		var outer_grow := float(j + 1) * STEP_DEPTH
		var inner_grow := float(j) * STEP_DEPTH
		# 竖直方向：每一级都从底座**底边**一直立到自己的顶面（台阶是实心的裙边，
		# 底下不悬空，玩家从外面看也不会看到缝）
		var h := step_top - bottom
		var y_c := bottom + h * 0.5
		# 四片围成一圈（南北两片铺满外框，东西两片夹在中间 —— 避免四角叠两层）
		var out_x := base.size.x + outer_grow * 2.0
		var out_z := base.size.z + outer_grow * 2.0
		var in_x := base.size.x + inner_grow * 2.0
		var in_z := base.size.z + inner_grow * 2.0
		var half_d := STEP_DEPTH * 0.5
		# 南 / 北
		_add_step_box_world(body, inv, Vector3(out_x, h, STEP_DEPTH),
			Vector3(cx, y_c, cz - base.size.z * 0.5 - inner_grow - half_d))
		_add_step_box_world(body, inv, Vector3(out_x, h, STEP_DEPTH),
			Vector3(cx, y_c, cz + base.size.z * 0.5 + inner_grow + half_d))
		# 西 / 东
		_add_step_box_world(body, inv, Vector3(STEP_DEPTH, h, in_z),
			Vector3(cx - base.size.x * 0.5 - inner_grow - half_d, y_c, cz))
		_add_step_box_world(body, inv, Vector3(STEP_DEPTH, h, in_z),
			Vector3(cx + base.size.x * 0.5 + inner_grow + half_d, y_c, cz))
		made += 4

	print("[EsportsCol] 底座台阶环：%d 级 × 每级 %.3f m 高 / %.2f m 深，共 %d 个碰撞盒"
		% [STEP_COUNT, step_h, STEP_DEPTH, made])
	print("[EsportsCol]   底座世界 y %.2f ~ %.2f，台阶外扩到 %.2f m（最外圈顶面 y=%.2f）"
		% [bottom, top, float(STEP_COUNT) * STEP_DEPTH, top - float(STEP_COUNT - 1) * step_h])


## 按**世界**尺寸/位置加一个台阶盒（内部换算回本节点空间）。
## ⚠️ 房间 basis 是纯旋转（Y、Z 各 −1，行列式 +1），所以尺寸不用缩放，只需换中心点。
##
## ⚠️⚠️ 2026-11-12：房间被整体放大到 **1.5 倍**（`game.tscn` 里 `EsportsRoom`
##      的 basis 三轴 ×1.5）之后，这条「尺寸不用缩放」就**不再成立**了 ——
##      往 1.5 倍的父节点里塞 `size = 世界尺寸` 的盒子，物理世界里会变成 1.5 倍大。
##      目前这个函数只被 `_build_base_steps()` 用，而那条路径在
##      `scenes/esports_room.tscn` 已经有 `BaseSteps` 时会**直接 return**（见那儿第一句），
##      所以现在跑不到。真要再用它，先把尺寸除以 `global_basis` 的缩放。
func _add_step_box_world(body: StaticBody3D, inv: Transform3D,
		size_world: Vector3, centre_world: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size_world
	cs.shape = box
	cs.position = inv * centre_world
	body.add_child(cs)


# ══════════════════ 衣柜：把烘出来的实心块挖成能进人的壳 ══════════════════
#
# 用户 2026-11-12：「这个电竞房柜子要可以进去」。
#
# ── 原来为什么进不去 ──
# 柜子（GLB 里的网格 `M_Scene_-_Root`，世界 x 46.91~48.92 / y 0.46~3.41 / z 18.30~19.48）
# 在 `esports_collision_baked.tscn` 里被烘成了 **8 个实心盒** `P0057_0..7`：
#     2 列（x 对半分）× 4 层（y 0.46~1.20 / 1.20~1.94 / 1.94~2.67 / 2.67~3.41），
#     而且每一块都是 **1.19 m 全进深** —— 整个柜体内部是实心的一坨。
# 烘焙工具是按「一件物体一个盒子」出的，它当然不知道柜子应该是个洞。
#
# ── 现在怎么做 ──
#   ① 找出柜子网格的世界包围盒（按名字找，GLB 里它就叫 `M_Scene_-_Root`）；
#   ② 把**完全落在柜子内部、且顶面低于柜顶一个层高**的那些盒子 `disabled`
#      —— 也就是挖掉下面 3 层，**保留最顶一层当柜顶**（不然人会从柜子上方飞出去）；
#   ③ 在左右两侧补两片 0.1 m 厚的薄墙，免得人在柜子里横着穿出侧板。
#      **前后都不封**：这样不管门朝哪一侧都能走进去（本喵没法从网格可靠判断哪边是正面，
#      封错一边就直接把人挡在外面了）。
#
# ── 代价（要如实知道）──
# 柜子里的**层板是纯视觉的**（GLB 网格），碰撞挖空之后玩家会和层板穿插。
# 玩家胶囊高 1.5 m、柜内净高 2.16 m（0.51 地板 ~ 2.67 柜顶），钻进去是够的。
#
# ── 复烘会怎样 ──
# 这段逻辑是**按位置**挖的，不认盒子名字，所以重新烘焙（盒子重编号）也不会失效。
# 但柜子本身挪了位置的话，`M_Scene_-_Root` 的包围盒会跟着变，挖的范围自然也跟着变。
const CABINET_MESH := "M_Scene_-_Root"
## 柜顶保留的厚度：等于烘出来的最上一层的层高（0.74 m）
const CABINET_KEEP_TOP := 0.75
## 侧板厚度
const CABINET_WALL := 0.10


func _open_cabinet() -> void:
	var auto_col := get_node_or_null(BAKED_AUTOCOL) as Node3D
	if auto_col == null:
		return

	# ── ① 柜子的世界包围盒 ──
	# ⚠️ 只认 `Room` 实例下面的那个（`Lod/HighModel`、`Lod/MidModel` 里还有同名副本，
	#    一起 merge 也无所谓 —— 它们位置相同，但显式限定来源更好读）。
	var cab := AABB()
	var found := false
	var glb := get_node_or_null("Room")
	if glb == null:
		return
	for mi in glb.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m == null or m.mesh == null or String(m.name) != CABINET_MESH:
			continue
		var b: AABB = m.global_transform * m.mesh.get_aabb()
		cab = b if not found else cab.merge(b)
		found = true
	if not found:
		push_warning("[EsportsCol] 找不到柜子网格 %s，柜子挖空跳过" % CABINET_MESH)
		return

	var ceiling := cab.end.y - CABINET_KEEP_TOP
	var inv := global_transform.affine_inverse()
	var scl: Vector3 = global_basis.get_scale().abs()
	if scl.x < 0.001 or scl.y < 0.001 or scl.z < 0.001:
		return

	# ── ② 挖空：中心落在柜内、且顶面低于柜顶的盒子 ──
	#
	# ⚠️ 判据用「**中心**落在柜内」，不是「整个盒子完全包含在柜内」——
	#    第一版用后者只挖掉 4 个，最底下那层（y 0.46~1.20）两块没挖掉，
	#    正好挡在玩家腿上，人还是进不去（实测 `_verify_esports_cabinet_walk` 3/6）。
	#    烘出来的盒子跟网格包围盒之间差个一两厘米很常见，用中心判就不会被这点误差挡住。
	var killed := 0
	for c in auto_col.get_children():
		var cs := c as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		var half: Vector3 = cs.global_basis.get_scale().abs() \
			* (cs.shape as BoxShape3D).size * 0.5
		var cb := AABB(cs.global_position - half, half * 2.0)
		var centre := cb.get_center()
		if not cab.has_point(centre):
			continue
		# 「柜顶」= **底面**在柜顶线及以上的那层。
		#
		# ⚠️ 这里不能用 `cb.end.y > ceiling`（顶面）判 —— 第一/二版就是这么写的，
		#    而 y 1.94~2.67 那两块的顶面正好等于 ceiling（2.660）加上浮点误差，
		#    被误判成「柜顶层」留了下来，结果它们卡在玩家胸口，人还是进不去
		#    （实测只挖掉 4 个，`_verify_esports_cabinet_walk` 3/6）。
		#    改判**底面**：顶层的底面 2.67 ≥ 2.640 ✓ 留下；1.94 < 2.640 ⇒ 挖掉。
		if cb.position.y >= ceiling - 0.02:
			continue
		cs.disabled = true
		killed += 1

	# ── ③ 左右两片薄墙（世界尺寸 → 本节点空间要除以缩放）──
	var wall_h := ceiling - cab.position.y
	var y_c := cab.position.y + wall_h * 0.5
	var depth := cab.end.z - cab.position.z
	for x in [cab.position.x + CABINET_WALL * 0.5, cab.end.x - CABINET_WALL * 0.5]:
		var cs2 := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(CABINET_WALL, wall_h, depth) / scl
		cs2.shape = box
		cs2.position = inv * Vector3(float(x), y_c, cab.get_center().z)
		auto_col.add_child(cs2)

	print("[EsportsCol] 柜子挖空：禁用 %d 个实心盒，保留柜顶（y<%.2f），补两侧 0.1 m 薄墙；柜内净高 %.2f m"
		% [killed, ceiling, wall_h])
