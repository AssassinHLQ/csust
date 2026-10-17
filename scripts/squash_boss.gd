extends BossAttacker
## 倭瓜优香（第三位 Boss）：**重锤型** —— 一个大倭瓜，抬起来往地上砸。
##
## 与另外两位共用 `boss_attacker.gd` 的「预警圈 = 伤害区」机制，差别全在参数：
## 起手更慢（好躲）、伤害更高、范围更小 ⇒ 逼玩家看准了才走位。
##
## 它和飞猪一样是**纯静态网格**（`.obj`，没有骨架），所以蓄力时只能整只往上一抬
## 再砸回来，不能像霸王龙那样「低头」——那需要骨骼。
##
## 素材：`models/boss_squash/倭瓜优香.obj`（作者：一个睿智），
## 4 个材质：`材质`（倭瓜皮，MTL 自带）+ 优香本体 / 头发 / 光环（要手动绑）。

var _base_model_y := 0.0


func _init() -> void:
	attack_interval = 4.2              # 比飞猪慢
	attack_start_delay = 4.5
	windup_time = 1.0                  # 起手很慢，好躲
	attack_range = 10.0
	attack_half_angle_degrees = 32.0   # 正面比飞猪窄
	attack_damage = 26.0               # 但一下很疼
	attack_reach = 3.2
	attack_radius = 3.0
	knockback_force = 8.0
	telegraph_color = Color(0.42, 0.78, 0.25, 0.45)   # 倭瓜绿


## 蓄力：整只抬起来（没有骨，只能这样）
func _on_windup_start(_center: Vector3) -> void:
	if model == null:
		return
	_base_model_y = model.position.y
	var tw := create_tween()
	tw.tween_property(model, "position:y",
		_base_model_y + visual_size.y * 0.22, windup_time * 0.6)
	tw.tween_property(model, "position:y", _base_model_y, windup_time * 0.4)


func _on_resolved() -> void:
	# ⚠️ 倒下时 `Boss._die()` 正在把这一只往下压，别在这里复位。
	if model == null or _dead:
		return
	model.position.y = _base_model_y
