class_name SummonPad
extends Area3D
## 「召唤同伴」台（2026-10-19 用户：「在你做的这个房子里面可以召唤同伴，如果不玩跑酷了，
## 可以在这里重新呼叫同伴回来」）。
##
## 摆在小屋 `MeshHut` 里、门正对着的那条走道上（局部 `(1.0, 0.03, 0.3)`）。
## 玩家踏上去 → `game.gd` 把所有 `Companion` **瞬移回小屋**并恢复跟随。
##
## 为什么需要它：跑酷准备区（`parkour_ready_zone.gd`）会把 7 名同伴**原地待命**
## 留在 x ≈ −9 的跑道口，而且**关掉了「被甩 26 m 就拉回」的保险**。
## 跑完全程再走回小屋时，她们还在 500 m 外站着 —— 这个台子就是唯一的「召回」入口。
##
## 和其它触发台的区别：
##   · 准备区是**一次性**的（`_fired`  latch，踩过一次就再也不响应）；
##   · 这个是**可以反复踩**的：离开再回来 = 再召唤一次（带 1.2 s 冷却，免得站在上面抖）。
##
## `collision_layer = 0`（自己不被任何东西撞到）、`collision_mask = 1`（只感应世界层的玩家），
## 垫子本身**没有碰撞**，踩上去不会垫脚。

signal summoned

## 垫子尺寸（米）：2.4 宽（局部 x）× 1.8 深（局部 z）。小屋里两侧都留得下走道。
@export var pad_size := Vector2(2.4, 1.8)
## 金色垫子的颜色（和跑酷准备区同一套）
@export var pad_color := Color(0.98, 0.78, 0.32)
## 两次召唤之间的冷却（秒）
@export var retrigger := 1.2

## 召唤成功后牌子上的字显示多久
const RESULT_TIME := 2.6
const BASE_TEXT := "召唤同伴"
## ⚠️ 小屋只有 6.2 × 5.2 m，这块垫子 1.8 m 宽 —— 字必须比跑酷准备区那块**小一半**：
##    准备区是 64 px × 0.009 = 0.58 m 高的字（垫子 6 × 4 m 放得下），
##    照抄过来会大字压出垫子外、糊一地（第一版实测就是这样）。
const SUB_TEXT := "站上来召回全员"

var _cool := 0.0
var _hold := 0.0
var _title: Label3D
var _sub: Label3D


func _ready() -> void:
	add_to_group("summon_pads")
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	var cs := CollisionShape3D.new()
	cs.name = "Trigger"
	var box := BoxShape3D.new()
	box.size = Vector3(pad_size.x, 2.4, pad_size.y)
	cs.shape = box
	cs.position.y = 1.2                    # 盒子底边贴地
	add_child(cs)
	_build_visuals()
	body_entered.connect(_on_body_entered)


## 金色垫子 + 四角矮柱 + 地面字（纯视觉，没有碰撞）
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

	# 垫子：2 cm 厚，比地面高 1 cm
	var pad := MeshInstance3D.new()
	pad.name = "Pad"
	var bm := BoxMesh.new()
	bm.size = Vector3(pad_size.x, 0.02, pad_size.y)
	pad.mesh = bm
	pad.material_override = gold
	pad.position.y = 0.01
	add_child(pad)

	# 四角矮柱（0.8 m）：比准备区矮一截，小屋里别显得挤
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			var pb := BoxMesh.new()
			pb.size = Vector3(0.10, 0.80, 0.10)
			post.mesh = pb
			post.material_override = dark
			post.position = Vector3(sx * (pad_size.x * 0.5 - 0.12), 0.40,
				sz * (pad_size.y * 0.5 - 0.12))
			add_child(post)

	# 字**竖着**立在垫子上方、永远面向镜头（billboard）。
	#
	# ⚠️ 为什么不用「平铺在地上的字」：Label3D 平铺要自己算欧拉角，
	#    算歪了就是**左右镜像**（能看到背面）—— 本喵在这里试了 4 种角、
	#    在小屋里并排摆了 4 块对照牌，仍然没法保证从门口看是正的
	#    （`_arisu_captures/_label/` 里留了对照图）。这块垫子只有 2.4 m 宽，
	#    值不上为它调一个只对某个视角成立的角。
	#    billboard 没有这个问题：从哪个方向看都是正的。
	var flat_ui := BaseMaterial3D.BILLBOARD_ENABLED
	_title = Label3D.new()
	_title.name = "Sign"
	_title.text = BASE_TEXT
	_title.font_size = 64
	_title.outline_size = 14
	_title.pixel_size = 0.0040
	_title.billboard = flat_ui
	_title.no_depth_test = true
	_title.modulate = Color(1.0, 0.92, 0.62)
	_title.position = Vector3(0.0, 1.55, 0.0)
	add_child(_title)

	_sub = Label3D.new()
	_sub.name = "SignSub"
	_sub.text = SUB_TEXT
	_sub.font_size = 34
	_sub.outline_size = 9
	_sub.pixel_size = 0.0042
	_sub.billboard = flat_ui
	_sub.no_depth_test = true
	_sub.modulate = Color(1.0, 0.97, 0.86)
	_sub.position = Vector3(0.0, 1.18, 0.0)
	add_child(_sub)


func _process(delta: float) -> void:
	if _cool > 0.0:
		_cool -= delta
	if _hold > 0.0:
		_hold -= delta
		if _hold <= 0.0 and _title != null:
			_title.text = BASE_TEXT


func _on_body_entered(body: Node3D) -> void:
	if _cool > 0.0 or not (body is Player):
		return
	_cool = retrigger
	summoned.emit()


## 召唤完在垫子上写一句结果（「已召回 7 人」），2.6 s 后变回「召唤同伴」。
func show_result(text: String) -> void:
	if _title == null:
		return
	_title.text = text
	_hold = RESULT_TIME


## 当前垫子上的字（自检用）
func title_text() -> String:
	return _title.text if _title != null else ""
