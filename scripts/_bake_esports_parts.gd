extends SceneTree
## 把 `esports_parts.json`（每件物体一个 AABB）烘成**成品碰撞场景**。
##
##   godot --path . --headless --script res://scripts/_bake_esports_parts.gd
##
## 产出：`res://scenes/esports_collision_baked.tscn`
##   Node3D "EsportsCollision"
##     └ StaticBody3D "AutoCol"（layer 1）
##          ├ Part_0001 … （一件物体一个 BoxShape3D）
##
## ── 为什么要「离线烘」（2026-11-09）──
## 使用者：「你总是做大了碰撞，书本桌子本来是两个不同的碰撞，结果你只做一个大的碰撞。」
##
## 旧做法在**运行时**把「按材质合并的 59 个网格」切体素 —— 由材质合并，
## 书和桌子同材质就分不开，只能糊成一大坨。
## 新做法**离线**从不合并的 FBX（738 件）量每件的 AABB，一件一个盒子：
##   书 → 一个几厘米的小盒子
##   桌子 → 它自己的盒子
##   两者**互相独立**，人可以站在桌上、书也挡得住。
##
## 离线烘的额外好处：运行时零计算（旧版建 760 个盒子要 575 ms）。

const JSON_PATH := "res://models/esports_room/esports_parts.json"
const OUT := "res://scenes/esports_collision_baked.tscn"
## 碰撞层：1 = 世界层
const LAYER := 1
## 小于这个体积不做碰撞（装饰碎片）
const MIN_VOLUME := 0.0008
## 三边之和小于这个不做碰撞（细杆、贴片）
const MIN_EXTENT := 0.10
## 大于这个体积的**外墙件**要按门洞切开（否则门被封死）
const WALL_VOLUME := 20.0

## 盖住超过这个比例的「整间房 footprint」的薄片，判为**天花板**而不是地板。
## 见 `is_floor_box()` 上面那段：房间被 Y=-1 翻转，天花板会躺到地面高度。
const ROOM_FOOTPRINT_RATIO := 0.90
## 整间房的水平面积（在 `_run` 里按全部零件算）
var _room_footprint := 0.0

## ── 不做碰撞的物件（按名字精确匹配）── 2026-11-09
##
## 用户：「电竞房进不去门,挡住了」「优化电竞房碰撞」。
##
## 本喵从 `esports_parts.json` 量出：门洞在**局部 +Z 那面墙**上，
## x 从 −2.55 到 1.00（宽 3.55 m），z 2.70..2.91，可通行高度 y 0.30..3.30
## （地板顶面 y=0.30，墙从 0.30 起）。
##
## 但门洞里塞满了这些东西：
##   · `JJKJ209 / 211 / 213 / 214` —— 四块**门板/玻璃**，各自 18~22 万三角面，
##     y 0.58..3.30，x 合起来盖住 −3.79..1.08 ⇒ **整个门洞被填满**
##   · `物件_6` —— y 0.30..0.60、x 恰好 −2.55..1.00，是门洞正下方那根**门槛条**
##     （30 cm 高，踩不上去）
##
## 把它们的碰撞去掉：**画面里门板/门槛照旧在**（只是不再挡人），
## 玩家能从门洞走进去。这是本项目一贯的口径「碰撞只为玩法服务，
## 不为「这扇门看起来是关的」服务」。
##
## ⚠️ 只影响碰撞生成，不动模型、不动贴图。
const NO_COLLIDE := [
	"JJKJ209", "JJKJ211", "JJKJ213", "JJKJ214",
	"物件_6",
]

## 地板碰撞**抬高**这么多米（2026-11-10）。
##
## 使用者：「碰撞调高一点点让角色的脚露出来」
##
## 背景：角色站在电竞房地板上时，脚会陷进地板里。
## 抬高碰撞地板顶面一点点，角色就会「站得高一点」，脚自然露在视觉地板之上 ——
## 这是最省事、最不破坏视觉的做法（视觉模型一个像素都不动）。
##
## 只对「地板那一类」生效（见 `is_floor_box`），家具不受影响。
const FLOOR_LIFT := 0.06

## 判断一个盒子是不是「地板」：底边贴地（< 0.05）、顶面在膝盖以下（< 0.6）、
## 而且水平投影够大（> 4 m²）—— 这样只命中真正的地板，不会把桌椅也算进去。
##
## ⚠️⚠️ 2026-11-11 第四次修「门进不去」—— 真凶找到了，而且**不是**地板逻辑本身。
##
## 用户从 2026-11-09 起反复报「门进不去」，前几轮探针都说"能过"，全是假的：
## 那些探针用**射线**判"打到房间中心就算通"，射线从障碍物**上方**穿了过去；
## 而玩家胶囊（半径 0.30 / 总高 2.10）是被障碍物的**侧面**挡住的 ——
## **射线和人是两回事**，这个教训必须记住。
##
## 这次用 `_probe_esports_walk.gd` 把玩家胶囊从四个方向真推一遍，四个方向
## 全部卡在离墙面 0.30 m 处，挡住的都是**同一个形状**：
##     `AutoCol/P0007_0`  AABB 10.40 × 0.30 × 16.84（= 整间房外框）
## 它对应 `esports_parts.json` 里的 **`物件_8` / 材质_3**，局部 `y 3.30~3.60`
## —— **那是天花板，不是地板**。
##
## 局部 y 对照（一目了然，两块高度完全不同，本来不该混）：
##     物件_1  y 0.00~0.30  9.20 × 0.30 × 10.73   ← 真地板
##     物件_8  y 3.30~3.60  10.40 × 0.30 × 16.84  ← 天花板
##
## 为什么天花板会封住门口：房间在 `game.tscn` 里 `Y = -1` 翻转（模型是倒着建的），
## 局部 y=3.45 映射到世界 ≈ 0.15 —— **天花板翻过来正好平躺在地面高度**，
## 一整片 10.4×16.8 m 的板把地面和门洞全盖住了。
##
## 所以这里改成**按零件名 + 局部高度**认地板，不再只看烘焙后的 y：
## 只有「局部底边贴 0」的才抬升；天花板（局部 y 高）永远不参与。
func is_floor_box(center: Vector3, size: Vector3) -> bool:
	var y_bottom := center.y - size.y * 0.5
	var y_top := center.y + size.y * 0.5
	if y_bottom > 0.05:
		return false
	if y_top > 0.60:
		return false
	if size.x * size.z <= 4.0:
		return false
	# 盖住几乎整间房 footprint 的薄片 = 天花板（翻转后躺在地上），不当地板
	if _room_footprint > 0.0 and (size.x * size.z) >= _room_footprint * ROOM_FOOTPRINT_RATIO:
		return false
	return true


## 这块零件在**模型局部坐标**里是不是贴地的板？（判天花板用这个，不看烘焙后的 y）
##
## 房间被 `Y = -1` 翻转后，局部「天花板」在世界里跑到地面高度，
## 所以**不能用烘焙后的 y 判断**它是不是地板 —— 必须回原始 JSON 的局部 y。
func is_local_floor_slab(p: Dictionary) -> bool:
	var lo: Array = p.get("min", [])
	var hi: Array = p.get("max", [])
	if lo.is_empty() or hi.is_empty():
		return false
	var y0: float = lo[1]
	var y1: float = hi[1]
	# 局部底边必须贴着 0（允许 5 cm 误差），且顶面在膝盖以下
	return y0 <= 0.05 and y1 <= 0.60


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not FileAccess.file_exists(JSON_PATH):
		print("[bake] !! 找不到 %s —— 先跑 tools/dump_esports_parts.py" % JSON_PATH)
		quit(1)
		return
	var txt := FileAccess.get_file_as_string(JSON_PATH)
	var data: Variant = JSON.parse_string(txt)
	if typeof(data) != TYPE_DICTIONARY:
		print("[bake] !! JSON 解析失败")
		quit(1)
		return
	var parts: Array = data.get("parts", [])
	print("[bake] 读到 %d 件物体" % parts.size())

	var root := Node3D.new()
	root.name = "EsportsCollision"
	var body := StaticBody3D.new()
	body.name = "AutoCol"
	body.collision_layer = LAYER
	body.collision_mask = 0
	root.add_child(body)
	body.owner = root

	# 先用全部零件的 AABB 求整间房的范围（门洞判断要用）
	var room := AABB()
	var first := true
	for p in parts:
		var b := _box_of(p)
		room = b if first else room.merge(b)
		first = false
	print("[bake] 整体包围盒 pos=%s size=%s" % [
		str(room.position.snappedf(0.01)), str(room.size.snappedf(0.01))])
	_room_footprint = room.size.x * room.size.z
	print("[bake] 房间 footprint 水平面积 %.2f m²（>%.0f%% 的薄片判为天花板）"
		% [_room_footprint, ROOM_FOOTPRINT_RATIO * 100.0])

	# ── 天花板补偿（2026-11-11）──
	# 房间在 `game.tscn` 里 `Y=-1` 翻转（模型倒着建），`y_local` 映射到世界是
	#     y_world = 房间根 y − y_local  （根 y = 3.61，底面正好贴地 0.01）
	# 天花板局部 y=3.45 → 世界 3.61−3.45 = **0.16**，也就是说它翻过来正好
	# 平躺在地面高度，一整片 10.4×16.8 m 的板把地面和三个门洞全盖住了。
	#
	# 所以抬升量要按**翻转后的世界高度**算，让天花板落回头顶之上：
	#     目标世界 y ≈ 3.30（房间净高），对应的局部 y = 3.61 − 3.30 = 0.31
	# 也就是要把它的 box 中心从局部 3.45 **改到 0.31**（不是 ±0 平移）。
	var roof_local_target := 0.0
	var ceil_parts: Array = []
	for p in parts:
		var lo2: Array = p.get("min", [])
		var hi2: Array = p.get("max", [])
		if lo2.is_empty():
			continue
		# 局部 y 高（>2 m）且是薄板（厚度 <0.5）且水平投影很大（>30 m²）→ 天花板
		var ly0: float = lo2[1]
		var ly1: float = hi2[1]
		var thin: bool = (ly1 - ly0) < 0.5
		var area: float = (float(hi2[0]) - float(lo2[0])) * (float(hi2[2]) - float(lo2[2]))
		if ly0 > 2.0 and thin and area > 30.0:
			ceil_parts.append(str(p.get("name", "")))
			# 目标局部 y：让它在世界落在「房间高度 − 板厚」处
			roof_local_target = maxf(roof_local_target, ly1)
	# 世界映射：y_world = room_top − y_local（Y=-1）
	# 想让天花板世界位于 `room.size.y − 板厚` 处 → y_local = 板厚
	# 简单做法：把它的局部中心改到「板厚/2 + 0.01」—— 翻转后正好落在屋顶下方
	if not ceil_parts.is_empty():
		print("[bake] 认出天花板零件 %s（局部 y 顶部 %.2f）→ 翻转后会落在世界 y≈%.2f"
			% [str(ceil_parts), roof_local_target, room.size.y - roof_local_target])

	var n_one := 0
	var n_skip := 0
	var n_multi := 0
	var n_nocol := 0
	var n_lift := 0
	var n_ceil := 0
	for i in parts.size():
		var p: Dictionary = parts[i]
		# 门板 / 门槛：不做碰撞（否则门被封死，见 `NO_COLLIDE` 的说明）
		if NO_COLLIDE.has(str(p.get("name", ""))):
			n_nocol += 1
			print("[bake] 跳过碰撞：%s（门洞要让路）" % str(p.get("name")))
			continue
		var boxes: Array = p.get("boxes", [])
		if boxes.is_empty():
			# 老格式（只有 min/max）→ 退回单盒子
			var b := _box_of(p)
			var s0 := b.size
			if s0.x * s0.y * s0.z < MIN_VOLUME or (s0.x + s0.y + s0.z) < MIN_EXTENT:
				n_skip += 1
				continue
			_add_shape(body, root, b.get_center(), s0, "Part_%04d" % i)
			n_one += 1
			continue
		if boxes.size() > 1:
			n_multi += 1
		var is_ceiling: bool = ceil_parts.has(str(p.get("name", "")))
		if is_ceiling:
			print("[bake] ★ 零件 #%d %s 判为天花板，盒子 %d 个" % [i, str(p.get("name")), boxes.size()])
		# ★ 一件物体可能拆成多个**贴着它形状**的盒子（空气已被排掉）
		var k := 0
		for bx in boxes:
			var arr: Array = bx
			var c := Vector3(arr[0], arr[1], arr[2])
			var s := Vector3(arr[3], arr[4], arr[5])
			if s.x * s.y * s.z < MIN_VOLUME or (s.x + s.y + s.z) < MIN_EXTENT:
				n_skip += 1
				continue
			if is_ceiling:
				# 天花板：翻转后它会躺在世界地面高度把门封死。
				# 世界映射 y_world = room_top − y_local，所以想让它在世界落到
				# `room.size.y − 板厚` 处，局部中心应当 = 板厚/2。
				# 这里直接把局部中心挪到板厚的一半 —— 翻转后正好贴在屋顶下表面。
				var old_y := c.y
				c.y = s.y * 0.5
				n_ceil += 1
				if n_ceil <= 4:
					print("[bake]   天花板盒子 #%d 局部 y %.2f → %.2f（翻转后世界 y≈%.2f）"
						% [k, old_y, c.y, room.size.y - c.y])
			elif is_floor_box(c, s):
				# 地板整体抬高一点点，让角色脚露在视觉地板之上（见 FLOOR_LIFT 说明）
				c.y += FLOOR_LIFT
				n_lift += 1
			_add_shape(body, root, c, s, "P%04d_%d" % [i, k])
			k += 1
		n_one += k

	print("[bake] 盒子 %d 个（%d 件被拆成多块以排掉空气）、跳过 %d 个碎片、%d 件门板不建碰撞"
		% [n_one, n_multi, n_skip, n_nocol])
	print("[bake] 其中 %d 个地板盒子抬高了 %.2f 米（让角色脚露出来）" % [n_lift, FLOOR_LIFT])
	print("[bake] 其中 %d 个天花板盒子挪到局部 y≈板厚/2（翻转后贴屋顶，不再封门）"
		% n_ceil)
	print("[bake] StaticBody 下共 %d 个形状" % body.get_child_count())

	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err != OK:
		print("[bake] !! pack 失败 %d" % err)
		quit(1)
		return
	err = ResourceSaver.save(ps, OUT)
	if err != OK:
		print("[bake] !! 保存失败 %d" % err)
		quit(1)
		return
	print("[bake] 写出 %s" % OUT)
	quit(0)


func _box_of(p: Dictionary) -> AABB:
	var lo: Array = p["min"]
	var hi: Array = p["max"]
	return AABB(
		Vector3(lo[0], lo[1], lo[2]),
		Vector3(hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2]))


## 大件（墙 / 地板 / 天花板）：如果它盖住了**门口**，就按门洞切成
## 「左墩 + 门楣 + 右墩」，中间留空给人走。
##
## ⚠️ 为什么必须做：外墙在原始 FBX 里可能是**一整块带门洞的多边形**，
##    它的 AABB 是完整矩形 —— 直接做一个盒子就把门封死了。
##    （2026-11-09 实测：不切的话门口射线被挡。）
func _emit_wall(body: StaticBody3D, root: Node3D, b: AABB, room: AABB, idx: int) -> int:
	# 只有「贴在最外沿 + 又高又薄」的件才需要开门洞
	var thin_z := b.size.z < 0.6
	var spans_x := b.size.x > room.size.x * 0.7
	var at_edge := absf(b.position.z + b.size.z - (room.position.z + room.size.z)) < 0.6
	if not (thin_z and spans_x and at_edge):
		_add_shape(body, root, b.get_center(), b.size, "Wall_%04d" % idx)
		return 1

	var t := maxf(b.size.z, 0.15)
	var z := b.position.z + b.size.z - t * 0.5
	var door_w := 2.4
	var door_h := 2.4
	var door_x := room.position.x + room.size.x * 0.5
	var n := 0
	var lx1 := door_x - door_w * 0.5
	var rx0 := door_x + door_w * 0.5
	# 左墩
	if lx1 - b.position.x > 0.05:
		_add_shape(body, root, Vector3((b.position.x + lx1) * 0.5,
			b.position.y + b.size.y * 0.5, z),
			Vector3(lx1 - b.position.x, b.size.y, t), "DoorL_%04d" % idx)
		n += 1
	# 右墩
	if b.position.x + b.size.x - rx0 > 0.05:
		_add_shape(body, root, Vector3((rx0 + b.position.x + b.size.x) * 0.5,
			b.position.y + b.size.y * 0.5, z),
			Vector3(b.position.x + b.size.x - rx0, b.size.y, t), "DoorR_%04d" % idx)
		n += 1
	# 门楣
	var lintel := b.size.y - door_h
	if lintel > 0.05:
		_add_shape(body, root, Vector3(door_x, b.position.y + door_h + lintel * 0.5, z),
			Vector3(door_w, lintel, t), "Lintel_%04d" % idx)
		n += 1
	return n


func _add_shape(body: StaticBody3D, root: Node3D, center: Vector3, size: Vector3,
		nm: String) -> void:
	var shape := BoxShape3D.new()
	# 三边必须 > 0，否则 BoxShape3D 报错
	shape.size = Vector3(maxf(size.x, 0.02), maxf(size.y, 0.02), maxf(size.z, 0.02))
	var cs := CollisionShape3D.new()
	cs.name = nm
	cs.shape = shape
	body.add_child(cs)
	cs.owner = root
	cs.position = center
