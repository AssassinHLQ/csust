class_name BossAttacker
extends Boss
## Boss 主动攻击的**公共部分**：冷却 → 起手 → 地面预警圈涨大 → 结算 → 收圈。
##
## 两位 Boss 都继承它，各自只改参数与两个钩子：
##   · 霸王龙优香（`trex_boss.gd`）：圈大、伤害高、击退强 —— **重击型**
##   · 飞猪优香（`pig_boss.gd`）：圈小、冷却短、伤害低 —— **骚扰型**
##
## ⚠️ **全篇最重要的一条：预警圈半径必须同时就是伤害半径**（`attack_radius`）。
##    第一版判定沿用了「发现距离」`attack_range`(18 m)，于是玩家站在**看得见的
##    圈外面**照样被扣血 —— 预警圈等于在骗人。现在判定固定是
##    「玩家到圈心的水平距离 ≤ `attack_radius`」，和画出来的圈一一对应。
##    自检 `_verify_trex_attack.gd` 里有一条「圈外（但在 18 m 内）不掉血」专门锁它。
##
## ⚠️ 另一个坑：`_telegraph` 是一个平时 `visible = false` 的 MeshInstance3D。
##    `_verify_boss.gd` 原来从 **boss 节点**往下扫网格数「隐藏挂件」，会把它当成
##    挂件而假红。那边已改成只扫 `boss.model` —— 以后再往 Boss 身上加特效时留意
##    同类写法（凡是从 boss 节点往下遍历网格的自检，都要排除特效节点）。

## 两次攻击的间隔（秒）
@export var attack_interval := 4.5
## 进场后隔多久开始第一次攻击（秒）。给玩家一点喘息时间。
@export var attack_start_delay := 2.0
## 预警圈从 55% 涨到 100% 的蓄力时间（秒）
@export var windup_time := 0.9
## **发现**玩家并起手的水平距离（m）。⚠️ 它不是伤害半径，见 `attack_radius`。
@export var attack_range := 18.0
## 只在正面这个半角内起手（度）
@export_range(1.0, 180.0, 1.0) var attack_half_angle_degrees := 32.0
## 命中扣多少血（玩家满血 100）
@export var attack_damage := 24.0
## 预警圈圆心离本体的水平距离（m）
@export var attack_reach := 5.0
## 预警圈半径（m）。**同时就是伤害半径**，两者必须一致，见文件头。
@export var attack_radius := 4.8
## **高度容差（m）**：玩家比本体高出超过这个值就打不到。
##
## ⚠️ 2026-11-11 修用户报的 bug：「飞起来发现飞猪优香居然打得到我,
##    证明之前 boss 攻击范围有误,没考虑高度,直接攻击范围内无限高的单位」
##
## 真因：原来的判定把 y 分量**硬编码成 0**
## （`Vector3(dx, 0.0, dz).length() <= attack_radius`），
## 于是伤害区是一根「无限高的圆柱」—— 玩家飞到 100 m 高空照样挨打。
## 发现玩家那一步也一样（只比了水平朝向）。
##
## 现在改成：**水平距离照旧**（预警圈画在地上的圆仍然一一对应），
## 但额外要求 `|玩家y − 本体y| <= attack_max_height`。
##
## ⚠️ 2026-11-11 第二轮：第一版取固定 6 m，用户实测「飞起来还是打得到我」——
##    因为**低空平飞只有 1~2 m**，6 m 形同虚设。
##    改成**由子类按体型给**：默认 3.0（猪/倭瓜这类矮的），
##    高大的（霸王龙本体 4.5 m）在各自脚本里调大。
##    判据口径：容差 ≈ 本体高度 × 1.5，让「跳起来躲」还有意义，
##    但「离地一米」不再免疫。
@export var attack_max_height := 3.0
## 命中时的水平击退（m/s）
@export var knockback_force := 8.0
## 预警圈颜色（霸王龙红、飞猪紫 —— 场上有两只时能一眼看出是谁要打你）
@export var telegraph_color := Color(1.0, 0.18, 0.06, 0.42)

var _attack_cooldown := 0.0
var _attacking := false
var _telegraph: MeshInstance3D
## 设置页里的「Boss 攻击」开关：关掉后两位 Boss 都只挨打、不还手
var _settings_enabled := true


func _ready() -> void:
	super._ready()
	_attack_cooldown = attack_start_delay
	_telegraph = MeshInstance3D.new()
	_telegraph.name = "AttackTelegraph"
	var disk := CylinderMesh.new()
	disk.top_radius = 1.0
	disk.bottom_radius = 1.0
	disk.height = 0.025
	disk.radial_segments = 32
	_telegraph.mesh = disk
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = telegraph_color
	mat.emission_enabled = true
	mat.emission = Color(telegraph_color.r, telegraph_color.g, telegraph_color.b)
	mat.emission_energy_multiplier = 1.2
	_telegraph.material_override = mat
	_telegraph.visible = false
	add_child(_telegraph)
	# 设置（Esc 菜单）：Boss 是否主动攻击
	GameSettings.listen(_on_setting_changed)
	_apply_settings()


func _process(delta: float) -> void:
	if not _settings_enabled or _dead or _attacking:
		return
	_attack_cooldown -= delta
	if _attack_cooldown > 0.0:
		return
	var player := _find_player()
	if player == null:
		return
	var to_player := player.global_position - global_position
	var flat_to_player := Vector3(to_player.x, 0.0, to_player.z)
	if to_player.length() > attack_range or flat_to_player.length_squared() < 0.001:
		return
	# 高度：飞太高就不起手（否则它会对着天上的玩家空放一圈，看着像 bug）
	if absf(to_player.y) > attack_max_height:
		return
	if facing().dot(flat_to_player.normalized()) \
			< cos(deg_to_rad(attack_half_angle_degrees)):
		return
	_attack(player)


## 起手 → 蓄力 → 结算。子类要加模型表现就覆盖 `_on_windup_start` / `_on_resolved`。
func _attack(_player: Player) -> void:
	_attacking = true
	_attack_cooldown = attack_interval
	# 预警圈**就是**伤害区：圆心在正面 attack_reach 处、半径 attack_radius。
	var center := global_position + facing() * attack_reach
	_telegraph.global_position = Vector3(center.x, 0.08, center.z)
	_telegraph.scale = Vector3(attack_radius * 0.55, 1.0, attack_radius * 0.55)
	_telegraph.visible = true
	_on_windup_start(center)
	var tw := create_tween()
	tw.tween_property(_telegraph, "scale",
		Vector3(attack_radius, 1.0, attack_radius), windup_time)
	await tw.finished
	if not is_instance_valid(self) or _dead:
		_telegraph.visible = false
		_attacking = false
		return

	var now_player := _find_player()
	if now_player != null:
		var flat := Vector3(
			now_player.global_position.x - center.x, 0.0,
			now_player.global_position.z - center.z)
		# ⚠️ 高度也要判：蓄力这 0.9 s 里玩家可能已经飞上去了。
		#    原来只比水平距离 ⇒ 伤害区是「无限高的圆柱」，见 `attack_max_height`。
		var dy := absf(now_player.global_position.y - global_position.y)
		if flat.length() <= attack_radius and dy <= attack_max_height:
			now_player.take_damage(attack_damage, global_position, knockback_force)
	_telegraph.visible = false
	_attacking = false
	_on_resolved()


## 蓄力开始时的钩子：子类在这里做模型表现（低头 / 起跳等）
func _on_windup_start(_center: Vector3) -> void:
	pass


## 结算结束的钩子：子类在这里把模型复位
func _on_resolved() -> void:
	pass


# --- 设置（Esc 菜单 / scripts/game_settings.gd）---

func _apply_settings() -> void:
	_settings_enabled = bool(GameSettings.value("boss_attack"))


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "boss_attack":
		_apply_settings()


func _find_player() -> Player:
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		return players[0] as Player
	return get_tree().root.find_child("Player", true, false) as Player
