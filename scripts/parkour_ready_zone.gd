class_name ParkourReadyZone
extends Area3D
## 跑酷准备区（2026-10-19 用户：「现在跑酷第一段前，设置跑酷准备区，一旦进入，
## 同伴就原地待命，爱丽丝单枪匹马前去」）。
##
## 摆在第 1 段跑道（`Launch`，x −20 ~ −10）的**东侧入口**：玩家从出生点往西走，
## 踏上这块金色垫子 = 宣布「我要开始跑了」——
## 那一刻 `game.gd` 会把所有 `Companion` 切到**原地待命**（不追、也不会被拉回），
## 之后整条 570 m 只有爱丽丝一个人。
##
## 触发用 `Area3D.body_entered`（`collision_layer = 0`、`collision_mask = 1`），
## 垫子本身**没有碰撞**，踩上去不会垫脚。
##
## ⚠️ 2026-10-20 两个改动（用户反馈）：
##   1. **垫子从 6×4 扩到 13×8**（x −19 ~ −6、z 0 ~ 8）——
##      6×4 只盖住跑道东口，从屋子那边绕过来（走北侧/南侧）**根本踩不到**，
##      同伴就一路跟到跑道上去了（用户：「准备区短了，要延伸到……」）。
##      现在整条 10 m 跑道几乎都在垫子上，从哪边接近都躲不开。
##   2. **不再是「一次性」**：以前 `_fired` 一旦置真就永远不再触发 ——
##      去小屋把同伴**召回**之后再跑，垫子已经死了，同伴照样跟（用户：
##      「召回所有人后再次跑酷，准备区用不了了」）。
##      现在**离开垫子就重新武装**（0.4 s 冷却，免得站在边上抖）。
##
##   另外 `game.gd` 还有一道保险：**踩上第 1 站 `Launch` 也算进准备区**
##   （`checkpoint_reached(0)`），从跑道西头倒着走回来的人也不会漏。

signal entered

## 触发盒尺寸（米）。生成器写进场景的是 (13, 3, 8)。
@export var zone_size := Vector3(13.0, 3.0, 8.0)
## 金色垫子的颜色
@export var pad_color := Color(0.98, 0.78, 0.32)
## 离开垫子后多久才能再次触发（秒）
@export var rearm_delay := 0.45

var _fired := false
var _cool := 0.0


func _ready() -> void:
	add_to_group("ready_zones")
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	var cs := CollisionShape3D.new()
	cs.name = "Trigger"
	var box := BoxShape3D.new()
	box.size = zone_size
	cs.shape = box
	cs.position.y = zone_size.y * 0.5       # 盒子底边贴地
	add_child(cs)
	_build_visuals()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	if _cool > 0.0:
		_cool -= delta


## 金色垫子 + 四根矮柱 + 两块牌子（纯视觉，没有碰撞）
func _build_visuals() -> void:
	var gold := StandardMaterial3D.new()
	gold.albedo_color = pad_color
	gold.metallic = 0.35
	gold.roughness = 0.4
	gold.emission_enabled = true
	gold.emission = pad_color * 0.5
	gold.emission_energy_multiplier = 0.45
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.10, 0.10, 0.12)
	dark.metallic = 0.6
	dark.roughness = 0.35

	# 垫子：2 cm 厚，比地面高 1 cm —— 玩家踩着的还是原来的地面
	var pad := MeshInstance3D.new()
	pad.name = "Pad"
	var bm := BoxMesh.new()
	bm.size = Vector3(zone_size.x, 0.02, zone_size.z)
	pad.mesh = bm
	pad.material_override = gold
	pad.position.y = 0.01
	add_child(pad)

	# 四角矮柱（1.0 m），斜着朝外一点点，像机场的引导灯
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			var pb := BoxMesh.new()
			pb.size = Vector3(0.12, 1.0, 0.12)
			post.mesh = pb
			post.material_override = dark
			post.position = Vector3(sx * (zone_size.x * 0.5 - 0.15), 0.5,
				sz * (zone_size.z * 0.5 - 0.15))
			add_child(post)

	# 字：**竖着的悬浮牌，永远面向镜头**（billboard）。
	#
	# ⚠️ 为什么不用「平铺在地上的字」：Label3D 平铺要自己算欧拉角，而算出来
	#    从玩家那边看总是**镜像/倒着**（A~F 六种都试过，`_arisu_captures/_label/`
	#    里留着对照图）。这一带本来就有「跑酷 · 12 段 →」「第 1 段 · 起点」
	#    两块竖牌，再加一块浮空的并不突兀 —— 而且从任何方向跑过来都读得懂。
	#    位置放在垫子**南侧**（局部 z −3.2），不压跑道、也不压那两块旧牌子。
	var title := Label3D.new()
	title.name = "Sign"
	title.text = "跑酷准备区"
	title.font_size = 72
	title.outline_size = 16
	title.pixel_size = 0.0040
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title.no_depth_test = true
	title.modulate = Color(1.0, 0.90, 0.55)
	title.position = Vector3(0.0, 2.05, -3.2)
	add_child(title)

	var sub := Label3D.new()
	sub.name = "SignSub"
	sub.text = "同伴在此待命 · 爱丽丝单枪匹马"
	sub.font_size = 34
	sub.outline_size = 10
	sub.pixel_size = 0.0036
	sub.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sub.no_depth_test = true
	sub.modulate = Color(1.0, 0.97, 0.86)
	sub.position = Vector3(0.0, 1.62, -3.2)
	add_child(sub)


func _on_body_entered(body: Node3D) -> void:
	if _fired or _cool > 0.0 or not (body is Player):
		return
	_fired = true
	entered.emit()


## 离开垫子 → **重新武装**（这就是「召回同伴后再跑还能用」的关键）
func _on_body_exited(body: Node3D) -> void:
	if not (body is Player):
		return
	_fired = false
	_cool = rearm_delay


## 现在处于「已经触发、还没重新武装」的状态（自检用）
func fired() -> bool:
	return _fired
