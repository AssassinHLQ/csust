extends BossAttacker
## 飞猪优香：**骚扰型** Boss —— 它原来只是木桩，这一轮也会打人了。
##
## 与霸王龙共用 `boss_attacker.gd` 那套机制（预警圈 = 伤害区），差别全在参数：
##   圈更小、冷却更短、伤害更低 → 不致命，但逼你一直挪位置。
##
## 它**没有骨架**（纯静态网格，见 README §7.6），所以表现只能靠节点层级的整只微动，
## 不能像霸王龙那样「低头」——那需要骨骼。

var _base_model_y := 0.0


func _init() -> void:
	attack_interval = 3.0              # 比霸王龙勤快
	attack_start_delay = 3.5           # 但它更懒得起手
	windup_time = 0.7
	attack_range = 14.0                # 鼻子短
	attack_half_angle_degrees = 45.0   # 正面却比霸王龙宽
	attack_damage = 14.0
	attack_reach = 3.6
	attack_radius = 3.4
	knockback_force = 5.0
	telegraph_color = Color(0.72, 0.28, 0.95, 0.42)


## 蓄力时整只向上蹦一下（没有骨，只能这样）
func _on_windup_start(_center: Vector3) -> void:
	if model == null:
		return
	_base_model_y = model.position.y
	var tw := create_tween()
	tw.tween_property(model, "position:y",
		_base_model_y + visual_size.y * 0.06, windup_time * 0.5)
	tw.tween_property(model, "position:y", _base_model_y, windup_time * 0.5)


func _on_resolved() -> void:
	# ⚠️ 同理：倒下时 `Boss._die()` 正在把这一只往下压，别在这里复位。
	if model == null or _dead:
		return
	model.position.y = _base_model_y
