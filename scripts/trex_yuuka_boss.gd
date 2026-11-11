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

## ── 追击（2026-11-11 用户：「霸王龙要能跑动，追人那种」）──
##
## ⚠️ 这份 GLB 里**没有走路动作** —— 只有 bite / charge / idle / roar / stomp / tail_sweep。
## 所以腿是**程序化**摆的：绕「模型左右轴」给大腿 + 小腿加正弦摆动，左右反相。
## （`charge` 那段是前冲顶撞、腿是钉住的，循环起来不像跑步，试过出图否掉了。）
##
## 走位本身很简单 —— 这只是一只 `StaticBody3D`，直接改 `global_position` 就能动。
## 三个必须一起做的配套：
##   · **拴绳**：跑太远要回家，不然它会一路追出校园
##   · **贴地**：向下打一条射线，走坡不浮空也不陷进去
##   · **停下来才打**：`_busy` 期间不挪窝，免得一边滑一边咬
@export var chase_speed := 12.0
## 每秒最多转多少度（25 m 长的大块头，转太快像陀螺）
@export var chase_turn_speed := 80.0
## 走到离玩家这么近就停下开打
@export var chase_stop_distance := 7.0
## 多远开始追（比拴绳小的话就是「进了校园才追」）
@export var chase_notice_range := 60.0
## 拴绳：离出生点超过这个距离就往回走
@export var chase_leash := 45.0
## 大腿摆动的最大角度（度）
@export var leg_swing_deg := 20.0
## 小腿反向弯的角度（度）
@export var leg_knee_deg := 18.0
## 每秒几个完整步频
@export var leg_cycle_hz := 1.15

var _home := Vector3.ZERO
var _walking := false
var _walk_phase := 0.0
## [{ "bone": int, "axis": Vector3, "phase": float, "amp": float }]
var _leg_bones: Array[Dictionary] = []
var _leg_skel: Skeleton3D
var _model_y0 := 0.0

## ── 血量（2026-11-09 用户：「霸王龙增强血量，两倍」）──
##
## 原来这三只走 `Boss.max_health` 的默认值 **3000**（`boss.gd:65`），
## 场景 `next_level.tscn` 里**没有**任何覆盖。×2 ⇒ **6000**。
##
## 写在 `_init()` 而不是 `_ready()`：`_init` 在场景属性之前跑，所以
## `next_level.tscn` / `game.tscn` 里若某一只想单独微调，仍以场景为准
## （和 `trex_boss.gd` / `pig_boss.gd` 的写法保持一致）。
##
## ⚠️ 只动血量，**不动** `ATTACKS` 里的伤害 —— 用户只说了「血量两倍」。
const BASE_HEALTH := 6000.0


func _init() -> void:
	max_health = BASE_HEALTH


func _boot() -> void:
	super._boot()
	_setup_anim()
	_setup_legs()


func _ready() -> void:
	super._ready()
	# 出生点 = 拴绳的圆心（`_boot()` 会晚一点才跑，这里先记下来）
	_home = global_position
	# 摆腿要在 AnimationPlayer **之后**写骨骼，否则会被动画覆盖回去
	process_priority = 100
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


## 找出腿骨、算好「模型 X 轴在每根骨局部空间里的方向」。
##
## 摆腿要绕模型的左右轴（模型脸朝 +Z，所以就是 X 轴）。骨头自己的局部坐标系
## 和它错开，所以要换一次：`axis_local = bone_rest_basis⁻¹ * Vector3.RIGHT`。
## 左腿大腿 `.014` / 小腿 `.015`，右腿 `.038` / `.039`（`.013`/`.037` 是髋根骨）。
func _setup_legs() -> void:
	_leg_skel = _best_skeleton(model)
	if _leg_skel == null:
		return
	if model is Node3D:
		_model_y0 = (model as Node3D).position.y
	# 骨名 → (相位, 角度系数)：左腿相位 0，右腿相位 π（反相 = 一前一后）
	var spec := [
		["Bone.014", 0.0, 1.0], ["Bone.015", -0.35, -0.9],
		["Bone.038", 0.0, 1.0], ["Bone.039", -0.35, -0.9],
	]
	_leg_bones.clear()
	for e in spec:
		var nm: String = e[0]
		var bi := _leg_skel.find_bone(nm)
		if bi < 0:
			push_warning("[Trex] 找不到腿骨 %s，摆腿会缺一条" % nm)
			continue
		var rest := _leg_skel.get_bone_global_rest(bi)
		var axis := (rest.basis.inverse() * Vector3.RIGHT).normalized()
		var phase: float = float(e[1]) + (PI if nm in ["Bone.038", "Bone.039"] else 0.0)
		var amp: float = float(e[2]) * (leg_swing_deg if e[2] > 0.0 else leg_knee_deg)
		_leg_bones.append({
			"bone": bi, "axis": axis, "phase": phase, "amp": amp,
		})
	print("[Trex %s] 跑动就位：%d 根腿骨（%.0f m/s，拴绳 %.0f m）" % [
		display_name, _leg_bones.size(), chase_speed, chase_leash])


func _process(delta: float) -> void:
	# ⚠️ 必须调 super：`BossAttacker._process()` 里是攻击冷却与起手判定，
	#    漏掉这一行整只 Boss 就再也不会攻击了（而且不报错，很难查）。
	super._process(delta)
	_tick_chase(delta)
	_tick_legs(delta)


# --- 追击走位 ---

func _tick_chase(delta: float) -> void:
	if _dead or _busy:
		_walking = false
		return
	var player := _find_player()
	if player == null:
		_walking = false
		return
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	var home_flat := Vector3(global_position.x - _home.x, 0.0,
		global_position.z - _home.z)

	var target := Vector3.ZERO
	if home_flat.length() > chase_leash:
		# 拴绳优先：已经跑出太远，先回家（哪怕玩家就在眼前）
		target = _home - global_position
		target.y = 0.0
	elif dist > chase_stop_distance and dist <= chase_notice_range:
		target = to_player

	if target.length() > 0.01:
		_face_towards(target, delta)
		# 朝**当前朝向**走，而不是直接朝目标走 —— 这样它是「先转身再迈步」，
		# 不会横着平移过去（大块头横向滑步特别假）
		global_position += facing() * chase_speed * delta
		_walking = true
		_snap_to_ground()
	else:
		_walking = false
		# 站住的时候也慢慢转向玩家（对峙感）
		if dist > 0.01:
			_face_towards(to_player, delta * 0.7)


## 把朝向朝 `dir` 转，最多 `chase_turn_speed` 度/秒
func _face_towards(dir: Vector3, delta: float) -> void:
	if dir.length_squared() < 0.0001:
		return
	var want := atan2(dir.x, dir.z)
	var diff := wrapf(want - rotation.y, -PI, PI)
	var step := deg_to_rad(chase_turn_speed) * delta
	rotation.y += clampf(diff, -step, step)


## 向下打一条射线贴地：走坡不浮空也不陷进去。
## 射线起点在头顶上方 8 m —— 霸王龙有 9~10.5 m 高，从原点往下打会先撞到自己的碰撞盒。
func _snap_to_ground() -> void:
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var from := Vector3(global_position.x, _home.y + 8.0, global_position.z)
	var to := from - Vector3.UP * 24.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var gy: float = (hit["position"] as Vector3).y
	# 平滑贴地：地面有起伏时不要一格一格地跳
	global_position.y = lerpf(global_position.y, gy, 0.5)


# --- 程序化摆腿 ---

func _tick_legs(delta: float) -> void:
	if _leg_skel == null or _leg_bones.is_empty() or _dead:
		return
	if not _walking or _anim == null or _anim.current_animation != "idle":
		# 站住 / 正在放技能 → 让动画自己管腿，身体的起伏也归位
		if model is Node3D and not _dead:
			(model as Node3D).position.y = _model_y0
		return
	_walk_phase = fmod(_walk_phase + delta * TAU * leg_cycle_hz, TAU)
	for e in _leg_bones:
		var bi: int = e["bone"]
		var ang := deg_to_rad(float(e["amp"])) * sin(_walk_phase + float(e["phase"]))
		# 在**当前**姿态上叠加，而不是拿 rest 覆盖 —— 这样 idle 里的呼吸/摆尾还在
		var q := _leg_skel.get_bone_pose_rotation(bi)
		_leg_skel.set_bone_pose_rotation(bi,
			q * Quaternion(e["axis"] as Vector3, ang))
	if model is Node3D:
		# 身体随步频颠一下（两步一个周期）
		(model as Node3D).position.y = _model_y0 + sin(_walk_phase * 2.0) * 0.12


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
