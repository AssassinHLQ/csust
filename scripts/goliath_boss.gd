extends BossAttacker
## 哥利亚（第七位 Boss，**备用**）：**炮击型** —— 一尊扛着速射炮的重机兵，
## 预警圈落在**离自己 10 m 远**的地方，圈很小但伤害最高。
##
## 其它五位的圈都贴在自己身前 3~5 m，这一位故意拉远：
## 「看到圈才知道它已经瞄准你了」—— 圈外站着完全没事，但圈里一下掉 30。
##
## 素材：`models/boss_goliath/Goliath_Decagram_Vulcan.fbx`（作者：一个睿智），
## 34 骨、单网格、单材质 `Goliath_Decagram_Vulcan`。
## `..._Mask.png` 是原作者渲染遮罩，游戏里不绑。
##
## 蓄力表现：炮口后坐（整只往后挪 + 抬头），结算时猛地往前一顿。

var _base_pos := Vector3.ZERO
var _forward := Vector3.FORWARD


func _init() -> void:
	attack_interval = 3.6
	attack_start_delay = 5.5
	windup_time = 0.9
	attack_range = 30.0                 # 看得最远
	attack_half_angle_degrees = 20.0    # 只瞄正面一条很窄的线
	attack_damage = 30.0                # 和佩洛洛斯拉并列最高
	attack_reach = 10.0                 # 圈落在 10 m 外
	attack_radius = 3.4                 # 圈不大，但那个位置通常是「你以为安全的地方」
	knockback_force = 9.0
	telegraph_color = Color(1.0, 0.52, 0.14, 0.48)    # 炮火的橙


func _ready() -> void:
	super._ready()
	if model == null:
		return
	_base_pos = model.position
	_forward = (to_local(global_position + facing()) - to_local(global_position)).normalized()


## 蓄力：后坐 —— 整只往后挪一点、炮口抬高
func _on_windup_start(_center: Vector3) -> void:
	if model == null:
		return
	_base_pos = model.position
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(model, "position", _base_pos - _forward * 0.25, windup_time * 0.8) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(model, "rotation:x", deg_to_rad(-6.0), windup_time * 0.8)


## 结算：往前一顿（坐力），再回位
func _on_resolved() -> void:
	# ⚠️ 倒下时 `Boss._die()` 正在把这一只往前压，别在这里复位。
	if model == null or _dead:
		return
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(model, "position", _base_pos + _forward * 0.30, 0.09) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(model, "rotation:x", deg_to_rad(3.0), 0.09)
	tw.chain().set_parallel(true)
	tw.tween_property(model, "position", _base_pos, 0.40) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(model, "rotation:x", 0.0, 0.40)
