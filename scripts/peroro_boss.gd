extends BossAttacker
## 佩洛洛斯拉（第五位 Boss）：**突进型** —— 一只巨大的佩洛洛（圆滚滚的鸟），
## 冷静的时候原地晃，一低头就猛地啄过来。
##
## 与另外三位共用同一套「预警圈 = 伤害区」，但参数全往「快」那一头拉：
##   起手 0.55 s（全场最快）、间隔 3 s（最短）、圈 2.6 m（最小）、伤害 30（偏高）。
## 换句话说：**它不给你思考时间，但它只打自己面前那一小块**。
## 躲法也和另外几位相反 —— 不用跑远，横着挪一步就够了。
##
## 素材：`models/boss_perorozilla/Perorozilla_Original.fbx`（作者：一个睿智）。
## 有骨架（47 骨），无动画。6 个网格共用**同一个**材质 `Perorozilla_Original_Body`，
## 所以一张贴图即可。其中 `Perorozilla_Emotion_01..05` 是**表情变体**
## （同一张脸的五种画法叠在同一个位置，原作靠开关切换）——
## 全开着会糊成一团，所以只留一张，见 `EMOTION_KEEP`。
##
## 五张表情的实际内容（`_probe_peroro_emotion.gd` 逐张出图看过，
## 对照图 `_arisu_captures/_boss/90_emotion_0.png` ~ `95_emotion_5.png`）：
##   0 = 全藏（本体自带的脸：圆眼 + 粉舌头，最干净）
##   1 = 额角红色「青筋」—— 生气
##   2 = 脸颊汗珠 —— 紧张
##   3 = 眉毛竖杠（渲染出来像五根黑条，效果差）
##   4 = 和「全藏」几乎一样
##   5 = 眼睛加高光/瞠目
## 现在留 1（生气），因为它和「一低头就啄过来」的设定最搭。

## 保留哪一个表情（0..5）。0 表示全藏、只用本体自带的脸。
const EMOTION_KEEP := 1

var _base_pos := Vector3.ZERO
## 本体朝向在「Boss 父空间」里的单位向量（模型被父节点转过，不能直接用 facing）
var _forward := Vector3.FORWARD


func _init() -> void:
	attack_interval = 3.0              # 最短
	attack_start_delay = 5.0
	windup_time = 0.55                 # 最快
	attack_range = 16.0
	attack_half_angle_degrees = 26.0   # 只打正面一条窄道
	attack_damage = 30.0
	attack_reach = 4.5
	attack_radius = 2.6                # 最小圈
	knockback_force = 13.0             # 啄一下飞得远
	telegraph_color = Color(1.0, 0.82, 0.22, 0.48)   # 佩洛洛的黄


func _ready() -> void:
	super._ready()
	if model == null:
		return
	_base_pos = model.position
	_forward = (to_local(global_position + facing()) - to_local(global_position)).normalized()
	_hide_extra_emotions()


## 只留 `EMOTION_KEEP` 那一张表情，其余藏掉（否则五张脸叠在一起）。
func _hide_extra_emotions() -> void:
	var hidden := 0
	for m in _all(model, "MeshInstance3D"):
		var mi := m as MeshInstance3D
		if not mi.name.begins_with("Perorozilla_Emotion_"):
			continue
		var idx := int(mi.name.get_slice("_", 2)) if mi.name.count("_") >= 2 else 0
		if idx != EMOTION_KEEP:
			mi.visible = false
			hidden += 1
	print("[佩洛洛斯拉] 表情变体藏起 %d 张，保留 #%d" % [hidden, EMOTION_KEEP])


## 蓄力：先后仰（像鸟蓄势），起手结束的那一刻才啄出去。
func _on_windup_start(_center: Vector3) -> void:
	if model == null:
		return
	_base_pos = model.position
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(model, "position", _base_pos - _forward * 0.45, windup_time * 0.8) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(model, "rotation:x", deg_to_rad(-14.0), windup_time * 0.8)


## 结算：往前猛地一啄再退回来。
func _on_resolved() -> void:
	# ⚠️ 倒下时 `Boss._die()` 正在把这一只往下压，别在这里复位。
	if model == null or _dead:
		return
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(model, "position", _base_pos + _forward * 1.1, 0.10) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(model, "rotation:x", deg_to_rad(18.0), 0.10)
	tw.chain().set_parallel(true)
	tw.tween_property(model, "position", _base_pos, 0.35) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(model, "rotation:x", 0.0, 0.35)
