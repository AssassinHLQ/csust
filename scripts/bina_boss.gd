extends BossAttacker
## 比纳（第六位 Boss，**备用**）：**横扫型** —— 一条盘起来的巨蛇，蓄力时把头往后甩，
## 结算时整条甩过来，正面 75° 全扫一遍。
##
## 与另外五位的区别：**扇形最宽**（75°）、击退最远（14 m/s，能把人扫出好几米），
## 但伤害偏低（22）—— 它的威胁是「被扫到场地边上」，不是一下打死你。
##
## 素材：`models/boss_binah/Binah_Original.fbx`（作者：一个睿智），44 骨、无动画。
## 3 个材质：`Binah_Original`（本体 + 4 个环共用）、`Binah_Original_Weapon`（武器面）、
## `Binah_Halo`（头顶光环）。`Binah_Original_Mask.png` 是原作者渲染遮罩，游戏里不绑。
##
## 蓄力表现只能整条转（没有动画）：蛇摆头比「跳一下」更像一条蛇。

var _base_yaw := 0.0


func _init() -> void:
	attack_interval = 5.0
	attack_start_delay = 7.0
	windup_time = 1.1
	attack_range = 22.0
	attack_half_angle_degrees = 75.0    # 全场最宽的扇形
	attack_damage = 22.0                # 但单下不疼
	attack_reach = 5.0
	attack_radius = 5.5
	knockback_force = 14.0              # 全场最强击退：被扫飞
	telegraph_color = Color(0.86, 0.27, 0.58, 0.42)   # 比纳的紫红


func _ready() -> void:
	super._ready()
	if model != null:
		_base_yaw = model.rotation.y


## 蓄力：把头甩到一侧（绕自身 Y 轴）
func _on_windup_start(_center: Vector3) -> void:
	if model == null:
		return
	_base_yaw = model.rotation.y
	var tw := create_tween()
	tw.tween_property(model, "rotation:y", _base_yaw - 0.55, windup_time * 0.85) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## 结算：反向甩回去，再慢慢归位
func _on_resolved() -> void:
	# ⚠️ 倒下时 `Boss._die()` 正在把这一只往前压，别在这里复位。
	if model == null or _dead:
		return
	var tw := create_tween()
	tw.tween_property(model, "rotation:y", _base_yaw + 0.55, 0.12) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(model, "rotation:y", _base_yaw, 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
