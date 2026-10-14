extends BossAttacker
## 霸王龙优香：**重击型** Boss。
##
## 攻击机制全在 `boss_attacker.gd`（预警圈 = 伤害区），这里只定它自己那套参数，
## 外加一点模型表现。飞猪（`pig_boss.gd`）继承同一个基类，但参数是「骚扰型」——
## 两只 Boss 的压迫感因此完全不同：这一只是「慢，但被打中很疼、还飞得远」。


func _init() -> void:
	# ⚠️ 参数写在 `_init()` 而不是 `_ready()`：`_init` 在**场景属性之前**跑，
	#    所以 game.tscn 里若想单独微调这一只，写进场景仍然生效（场景优先）。
	#    写成 `_ready()` 反而会把场景里的值盖掉。
	attack_interval = 4.5              # 慢
	attack_start_delay = 2.0
	windup_time = 0.9                  # 蓄力久 → 有充足时间躲开
	attack_range = 18.0
	attack_half_angle_degrees = 32.0   # 正面窄
	attack_damage = 24.0               # 但一下很疼（满血 100 约 4 下）
	attack_reach = 5.0
	attack_radius = 4.8
	knockback_force = 8.0
	telegraph_color = Color(1.0, 0.18, 0.06, 0.42)


## 蓄力时低头前倾（模型脸朝 +Z，绕 +X 转正角就是埋头）
func _on_windup_start(_center: Vector3) -> void:
	if model == null:
		return
	var tw := create_tween()
	tw.tween_property(model, "rotation:x", deg_to_rad(10.0), windup_time * 0.9)


func _on_resolved() -> void:
	# ⚠️ 已经倒下时不要抢 `rotation:x`：`Boss._die()` 正在用它把这一只扑倒，
	#    这里复位会把它拉回来（表现就是「死了又站起来一半」）。
	if model == null or _dead:
		return
	var tw := create_tween()
	tw.tween_property(model, "rotation:x", 0.0, 0.25)
