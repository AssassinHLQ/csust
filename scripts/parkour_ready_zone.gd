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
## 只认一次；垫子本身**没有碰撞**，踩上去不会垫脚。

signal entered

## 触发盒尺寸（米）。生成器写进场景的是 (6, 3, 4)。
@export var zone_size := Vector3(6.0, 3.0, 4.0)
## 金色垫子的颜色
@export var pad_color := Color(0.98, 0.78, 0.32)

var _fired := false


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

	# 字**平铺在垫子上**（像机场跑道的地面字），不做 billboard：
	# 这一带已经有「跑酷 · 12 段 →」「第 1 段 · 起点」两块竖牌子，
	# 再竖一块三行的必然叠在一起（第一版就是这样，字糊成一团）。
	var title := Label3D.new()
	title.name = "Sign"
	title.text = "跑酷准备区"
	title.font_size = 64
	title.outline_size = 14
	title.pixel_size = 0.009
	title.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	title.rotation = Vector3(-PI * 0.5, 0.0, 0.0)     # 面朝上
	title.position = Vector3(0.0, 0.045, 0.55)
	add_child(title)

	var sub := Label3D.new()
	sub.name = "SignSub"
	sub.text = "同伴在此待命 · 爱丽丝单枪匹马"
	sub.font_size = 32
	sub.outline_size = 10
	sub.pixel_size = 0.0075
	sub.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	sub.modulate = Color(0.12, 0.10, 0.06)
	sub.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	sub.position = Vector3(0.0, 0.045, -0.85)
	add_child(sub)


func _on_body_entered(body: Node3D) -> void:
	if _fired or not (body is Player):
		return
	_fired = true
	entered.emit()


## 已经触发过了没有（自检用）
func fired() -> bool:
	return _fired
