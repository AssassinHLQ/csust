extends BossAttacker
## 霸王龙优香 · 多段攻击版（第二关校园）。
##
## 动作来自 `models/boss/trex_yuuka_rigged.glb` —— 在 Blender 里就着原 FBX 的
## 73 根骨骼做的：下巴（Bone.005）/ 颈（Bone.003–001）/ 尾（Bone.006–.012）/
## 后腿（Bone.013、Bone.037）。Godot 直读原 FBX 时骨架会被拍平（骨骼静置全在原点），
## 所以这里必须用 GLB 那份。
##
## 攻击不再是单一招：五种打法轮流来，每种对应一段动作 + 自己的一套预警 / 伤害。
## ⚠️ 预警圈仍然**就是**伤害区（`radius` 同时给圈和判定），这条规矩别破。

## 每段攻击：clip 动作名、impact 结算时刻（秒）、len 动作全长、reach 圆心前瞻、
## radius 圈半径（= 伤害半径）、damage、knockback、interval 这段打完后隔多久再出手。
const ATTACKS := [
	{
		"clip": "bite", "label": "撕咬", "impact": 0.50, "len": 1.67,
		"reach": 8.0, "radius": 5.0, "damage": 24.0, "knockback": 8.0,
		"interval": 3.4, "color": Color(1.0, 0.18, 0.06, 0.42),
	},
	{
		"clip": "tail_sweep", "label": "尾扫", "impact": 0.83, "len": 2.00,
		"reach": 3.0, "radius": 11.0, "damage": 20.0, "knockback": 14.0,
		"interval": 4.0, "color": Color(1.0, 0.52, 0.05, 0.36),
	},
	{
		"clip": "stomp", "label": "跺地", "impact": 0.92, "len": 1.83,
		"reach": 1.0, "radius": 7.0, "damage": 28.0, "knockback": 7.0,
		"interval": 4.4, "color": Color(0.95, 0.12, 0.18, 0.40),
	},
	{
		"clip": "charge", "label": "冲锋", "impact": 1.08, "len": 2.33,
		"reach": 12.0, "radius": 5.5, "damage": 22.0, "knockback": 15.0,
		"interval": 5.0, "color": Color(0.92, 0.86, 0.12, 0.34),
	},
	{
		"clip": "roar", "label": "咆哮", "impact": 0.58, "len": 2.50,
		"reach": 8.0, "radius": 13.0, "damage": 8.0, "knockback": 18.0,
		"interval": 5.6, "color": Color(0.62, 0.22, 1.0, 0.32),
	},
]

var _anim: AnimationPlayer
var _attack_index := 0
var _busy := false
var _telegraph_mat: StandardMaterial3D


func _boot() -> void:
	super._boot()
	_setup_anim()


func _ready() -> void:
	super._ready()
	if _telegraph != null and _telegraph.material_override is StandardMaterial3D:
		_telegraph_mat = _telegraph.material_override as StandardMaterial3D


## 找到 GLB 里的 AnimationPlayer，把 idle 设成循环并先播着。
func _setup_anim() -> void:
	if model == null:
		return
	_anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim == null:
		push_warning("[Trex] 模型里没有 AnimationPlayer，攻击只会放预警圈")
		return
	var idle := _anim.get_animation("idle")
	if idle != null:
		idle.loop_mode = Animation.LOOP_LINEAR
		_anim.play("idle")
	print("[Trex %s] 动作就位：%s" % [display_name, str(_anim.get_animation_list())])


func _attack(player: Player) -> void:
	if _busy:
		return
	_busy = true
	_attacking = true
	var cfg: Dictionary = ATTACKS[_attack_index % ATTACKS.size()]
	_attack_index += 1
	_attack_cooldown = float(cfg.interval)

	var reach: float = cfg.reach
	var radius: float = cfg.radius
	var center := global_position + facing() * reach
	_set_telegraph_color(cfg.color)
	_telegraph.global_position = Vector3(center.x, 0.10, center.z)
	_telegraph.scale = Vector3(radius * 0.55, 1.0, radius * 0.55)
	_telegraph.visible = true

	if _anim != null:
		_anim.play(cfg.clip)

	var tw := create_tween()
	tw.tween_property(_telegraph, "scale", Vector3(radius, 1.0, radius), float(cfg.impact))
	await tw.finished
	if not is_instance_valid(self) or _dead:
		_telegraph.visible = false
		_attacking = false
		_busy = false
		return

	var now_player := _find_player()
	if now_player != null:
		var flat := Vector3(now_player.global_position.x - center.x, 0.0,
			now_player.global_position.z - center.z)
		if flat.length() <= radius:
			now_player.take_damage(float(cfg.damage), global_position, float(cfg.knockback))
	_telegraph.visible = false

	# 等这一段动作播完再回 idle，别让下一招把上一招切断
	var left: float = maxf(0.0, float(cfg.len) - float(cfg.impact))
	if left > 0.0:
		await get_tree().create_timer(left).timeout
	if not is_instance_valid(self) or _dead:
		return
	if _anim != null:
		_anim.play("idle")
	_attacking = false
	_busy = false


func _set_telegraph_color(c: Color) -> void:
	if _telegraph_mat == null:
		return
	_telegraph_mat.albedo_color = c
	_telegraph_mat.emission = Color(c.r, c.g, c.b)


## 倒下时停掉动作，交给基类的扑倒动画。
func _die(by_damage: float) -> void:
	_telegraph.visible = false
	if _anim != null:
		_anim.stop()
	super._die(by_damage)
