extends BossAttacker
## 霍德（第四位 Boss）：**全向压制型** —— 一座会发光的高塔，蓄力时整座升起，
## 落回来的时候把周围一圈全部震一遍。
##
## 与另外三位共用 `boss_attacker.gd` 的「预警圈 = 伤害区」机制，但它有三处不同：
##   1. `attack_reach = 0` —— 圈**套在自己脚下**，是冲击波而不是扇形。
##   2. `attack_half_angle_degrees = 180` —— 站哪边都会被起手，命中判定仍然是
##      「到圈心的水平距离 ≤ `attack_radius`」。所以唯一出路是**走进圈外**。
##   3. 起手 1.6 s（全场最慢）、间隔 6 s（最长）—— 范围大就得给得起反应时间。
##
## 素材：`models/boss_hod/HOD_Original.fbx`（作者：一个睿智）。
## 有骨架（164 骨），但**没有动画**；蓄力表现只能靠整只升降，不能真「挥」。
## 3 个材质：`HOD_Original`（本体）/ `HOD_Original_Halo`（光环）/
## `HOD_TemporaryTower`（随身的高塔）。两张 `*_Mask.png` 是原作者渲染用的遮罩，
## 游戏里不用，所以不绑。

var _base_model_y := 0.0
## 光环材质：蓄力时点亮（见 `_on_windup_start`）
var _halo_mats: Array[StandardMaterial3D] = []


func _init() -> void:
	attack_interval = 6.0              # 全场最长：范围大
	attack_start_delay = 6.0
	windup_time = 1.6                  # 全场最慢，给足跑出去的时间
	attack_range = 24.0                # 看得远
	attack_half_angle_degrees = 180.0  # 全向
	attack_damage = 24.0
	attack_reach = 0.0                 # ⚠️ 圈心就是自己脚下
	attack_radius = 7.0                # 全场最大圈
	knockback_force = 11.0
	telegraph_color = Color(0.36, 0.72, 1.0, 0.42)   # 霍德的冷蓝


func _ready() -> void:
	super._ready()
	if model == null:
		return
	_base_model_y = model.position.y
	for m in _materials:
		if m.resource_name == "HOD_Original_Halo":
			# 光环那张图是**橙红径向渐变**（64×64），环形是**网格**给的形状，
			# 不是贴图的 alpha —— 所以不用开透明。发光就把同一张贴图当自发光贴图，
			# 平时能量 0（= 不闪），蓄力时点到 3.0。
			m.emission_enabled = true
			m.emission_texture = m.albedo_texture
			m.emission = Color(1.0, 0.72, 0.35)
			m.emission_energy_multiplier = 0.0
			_halo_mats.append(m)


## 蓄力：整座升起，光环跟着亮起来。
## （没有骨骼动画，只能这样；比「砸下去」更适合一座塔。）
func _on_windup_start(_center: Vector3) -> void:
	if model == null:
		return
	_base_model_y = model.position.y
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(model, "position:y",
		_base_model_y + visual_size.y * 0.30, windup_time * 0.75)
	for m in _halo_mats:
		tw.tween_property(m, "emission_energy_multiplier", 3.0, windup_time * 0.75)


func _on_resolved() -> void:
	# ⚠️ 倒下时 `Boss._die()` 正在把这一只往下压，别在这里复位。
	if model == null or _dead:
		return
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(model, "position:y", _base_model_y, 0.18) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	for m in _halo_mats:
		tw.tween_property(m, "emission_energy_multiplier", 0.0, 0.5)
