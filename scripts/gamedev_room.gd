@tool
extends Node3D
## 游戏开发部活动室：模型改成运行时按路径加载，缺模型时只少这栋房子的网格。
##
## 为什么 —— 模型（Sketchfab 作者：起航扬帆了）授权未核实，`.gitignore` 第 93 行
## 把它挡在仓库外。如果写成 `.tscn` 的 `[ext_resource]`，缺模型时 Godot 直接：
##
##     ERROR: Parse Error: [ext_resource] referenced non-existent resource
##     ERROR: Failed loading resource: res://scenes/gamedev_room.tscn
##
## 整个场景加载失败，而 `game.tscn` 又引用了本场景 —— 所以真实后果不是
## 「少一栋房子」，是**游戏根本起不来**（提交 165389a 的说明写的是前者，实测是后者）。
##
## 改成运行时加载后，才真的兑现「缺模型时只少这栋房子」：
## 灯、招牌、碰撞都还在场景里，只是没有房间的网格。
##
## 场景结构（改之前 / 之后一致）：
##   GameDevRoom
##     Model(Node3D, 绕 Y 转 90°)   ← 本脚本把 glb 挂到这里
##       LightA / LightB / LampA_* / LampB_* / SignBoard / Sign / Collision
##   PC5090Rig
## 把 glb 挂在 Model 下面、而不是把 Model 整个换掉，是为了让所有子节点的
## transform 保持原样（它们本来就是相对那个旋转过的父节点摆的）。

const MODEL := "res://models/gamedev_room/gamedev_room.glb"
## 碰撞可视化（只在编辑器里生效，见那个文件的头注）
const COLLIDER_VIS := preload("res://scripts/collider_visualizer.gd")

## BGM 逻辑名（曲目表见 `scripts/music.gd`）
const MUSIC_TRACK := "gamedev"
## BGM 触发区比房间内壁再内缩多少米
const MUSIC_INSET := 0.6

@onready var _model: Node3D = $Model

## 玩家在触发区里的「票数」（不是布尔，理由见 `_on_music_body`）
var _music_inside := 0


func _ready() -> void:
	_sync_room_mesh()
	_ensure_collider_vis()
	# 编辑器里不建：加了也只会是 owner=null 的临时节点，没必要每次都算一遍
	if not Engine.is_editor_hint():
		_build_music_zone()


## 把 `collider_visualizer.gd` 挂成自己的子节点 —— **自动挂，不用手动**。
##
## 用户 2026-11-10：「我不会挂节点」。
##
## 为什么不能把可视化脚本直接挂在根节点上：根节点**已经挂着本脚本**了
## （一个节点只能有一个脚本）。所以这里在运行时给根节点加一个**子节点**，
## 子节点挂可视化脚本、它自己去扫全场的 `CollisionShape3D`。
##
## ⚠️ `owner = null` ⇒ 这个子节点**不会写进 .tscn**，只是编辑器会话里的临时节点，
##    所以场景文件不会因为加了这个功能而变脏。
func _ensure_collider_vis() -> void:
	if not Engine.is_editor_hint():
		return                      # 运行时一个节点都不建
	if get_node_or_null("ColliderVis") != null:
		return                      # 重复 _ready 时不重复加
	var vis := COLLIDER_VIS.new()
	vis.name = "ColliderVis"
	vis.owner = null
	add_child(vis)
	print("[GameDevRoom] 碰撞可视化已挂上（半透明橙方块；在检查器里取消 show_overlay 可关）")


func _sync_room_mesh() -> void:
	# 编辑器里也要把模型挂上 —— 否则在编辑器里打开本场景只看到 24 个碰撞盒、
	# 看不到房间长什么样，没法对照着微调碰撞（用户 2026-11-03 提出）。
	# 挂上去的节点 `owner = null`，**不会被写进 .tscn**。
	var old := _model.get_node_or_null("RoomMesh")
	if old != null:
		# 先摘掉再 queue_free：否则新节点会取到 "_2" 的名字，重复 _ready 时越堆越多
		_model.remove_child(old)
		old.queue_free()

	if not ResourceLoader.exists(MODEL):
		# 按设计允许缺失：只警告，不报错。
		push_warning("[GameDevRoom] 模型不在（按设计允许），只少了房间网格：%s" % MODEL)
		return

	var ps := load(MODEL) as PackedScene
	if ps == null:
		push_warning("[GameDevRoom] 模型加载失败，只少了房间网格：%s" % MODEL)
		return

	var inst := ps.instantiate()
	if inst == null:
		push_warning("[GameDevRoom] 模型实例化失败，只少了房间网格：%s" % MODEL)
		return

	inst.name = "RoomMesh"
	# 编辑期挂进来的节点不能有 owner，否则保存场景时会被"烤"进 .tscn
	inst.owner = null
	_model.add_child(inst)


## ⚠️ 2026-11-10 已**回退**「墙设双面」（`_fix_inverted_walls`）。
##
## 当时的思路：glb 里几块墙的绕序反了（有向体积为负），设 `CULL_DISABLED` 让两边都看得见。
##
## 实机验证：**没修好** ——
##   双面之后「外面看得见、里面也看得见」，但用户截图显示真正的问题是
##   **内层墙皮和外层墙皮之间缺封边**（两层相距约 0.30 m，中间没有连接面），
##   于是从门洞 / 墙角斜着看，视线从夹缝里穿出去 → 看到天空 / 看到隔壁建筑。
##
##   这是**几何缺面**，不是法线问题。双面渲染治不了缺面。
##
## ⇒ 改成在场景里**补墙**：`Model` 下手工加了 3 片 `Body_WallLiner_*`
##   （用户自己拖的位置，本喵没有代码参与）。glb 完全不动。


# ══════════════════════════ BGM 触发区 ══════════════════════════
#
# 用户 2026-11-11：「音乐需要增加」—— 走进游戏开发部活动室淡入
# 「碧蓝档案OST」P70「Pixel Time（游戏开发部）」，走出去淡出。
#
# ── 为什么盒子尺寸是**运行时量出来的**，不是写死在 .tscn 里 ──
# 房间的墙 / 地板碰撞是 24 个手工拖出来的 `CollisionShape3D`，尺寸一直在微调
# （2026-11-10 还补过 3 片墙皮）。盒子一旦烤进 .tscn，改房间时就得记着手动同步，
# 而漏改的症状只是「走到门里半米音乐才响」—— 谁都不会发现。
# ⇒ 直接读 `Model/Collision` 里所有 `BoxShape3D` 算包围盒。
#
# ── 为什么用 Area3D，为什么用计数而不是布尔 ──
# 完整的理由写在 `scripts/shop.gd::_build_music_zone()`；这里照抄同一套做法，
# 两个房间的触发区行为保持一致（进出、传送、掉落都由物理引擎回调，零常态开销）。

func _build_music_zone() -> void:
	var bounds := _collision_bounds()
	if bounds.size == Vector3.ZERO:
		push_warning("[GameDevRoom] 量不到房间碰撞包围盒，BGM 触发区不建（房间可能缺模型/碰撞）")
		return
	var area := Area3D.new()
	area.name = "MusicZone"
	area.collision_layer = 0          # 自己不被撞
	area.collision_mask = 1           # 只感应世界层（玩家在第 1 层）
	area.monitoring = true
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# 高度取包围盒的 2 倍、中心仍在包围盒中心：玩家怎么跳都在里面
	box.size = Vector3(
		maxf(bounds.size.x - MUSIC_INSET * 2.0, 0.5),
		maxf(bounds.size.y * 2.0, 1.0),
		maxf(bounds.size.z - MUSIC_INSET * 2.0, 0.5))
	cs.shape = box
	var c := bounds.get_center()
	cs.position = c
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(_on_music_body.bind(1))
	area.body_exited.connect(_on_music_body.bind(-1))
	print("[GameDevRoom] BGM 触发区：%.2f × %.2f × %.2f m，中心本地 (%.2f, %.2f, %.2f)（曲目 `%s`）"
		% [box.size.x, box.size.y, box.size.z, c.x, c.y, c.z, MUSIC_TRACK])


## 房间（**本节点空间**）里所有碰撞盒的包围盒。
##
## 盒子只有 8 个角：逐个角换到本节点空间再 `expand`。这样 `Model` 那个 90° 的
## 旋转自动被算进去 —— 不用手写「localX→worldZ」之类的坐标映射（那种写法
## 一改 Model 的旋转就又错了）。
func _collision_bounds() -> AABB:
	var col := _model.get_node_or_null("Collision")
	if col == null:
		return AABB()
	var out := AABB()
	var seen := false
	for child in col.get_children():
		var node := child as CollisionShape3D
		if node == null:
			continue
		var box := node.shape as BoxShape3D
		if box == null:
			continue
		# Model 空间 → 本节点空间
		var xf := _model.transform * node.transform
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
	if _music_inside > 0:
		Music.play(MUSIC_TRACK)
	elif Music.current() == MUSIC_TRACK:
		# 只在「放的正好是自己这首」时才停 —— 以后别的房间若共用同一个播放器，
		# 走到门口不该把人家的 BGM 掐掉
		Music.stop()


## 房间被释放 / 换场景时别把 BGM 留在空气里飘。
func _exit_tree() -> void:
	if _music_inside > 0 and Music.current() == MUSIC_TRACK:
		Music.stop(0.6)
