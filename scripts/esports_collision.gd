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
