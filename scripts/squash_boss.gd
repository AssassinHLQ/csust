extends BossAttacker
## 倭瓜优香（第三位 Boss）：两个技能轮着来。
##
## ★ **技能一「压扁天降」**（2026-10-20 用户）：
##    整只被压扁蓄力 → **快速弹起（弹起那一瞬间恢复原形）** → 短暂滞空 →
##    从天上砸向**爱丽丝附近随机一个落点**（地上先亮红圈）→ 落地 **40 伤害 + 大力击退**。
##    用户原话：「倭瓜优香第一个技能变扁然后快速弹起（弹起时变回去），爱丽丝附近随机
##    出现红色预警圈，倭瓜优香短暂滞空后从天而降造成大力击退与 40 伤害」。
## ★ **技能二「原地重砸」**：`BossAttacker` 那套默认流程 ——
##    抬身蓄力 → 正面地面圈涨大 → 结算 26 伤害。用户：「第二个普通攻击，就是你刚刚默认做的」。
##
## ⚠️ 模型是**纯静态网格**（`.obj`，没有骨架），所以「变扁」只能整只对 `model` 做缩放。
##    模型的**原点不在脚底**，直接缩 y 会让倭瓜悬空或埋进地里，所以 `_set_squash()`
##    用 `_rest_bottom`（静止时的脚底高度）做了一次位置补偿：
##        脚底 = position.y + (几何底 × 缩放)  ⇒  压扁时 position.y = 底 − f·(底 − 原位)
##
## ⚠️ 红圈不能挂在 Boss 底下：天降时 Boss 自己会飞起来，挂在它身上的圈会跟着满天飞。
##    所以 `SlamMark` 设了 `top_level = true`，钉在世界坐标上。

const SKILL_SLAM := 0
const SKILL_HEAVY := 1

## 天降：落点在爱丽丝周围这个半径内随机（m）
@export var slam_place_radius := 3.0
## 天降伤害（爱丽丝满血 250）
@export var slam_damage := 40.0
## 天降击退（m/s）。技能二只有 8，这一下「大力」翻倍
@export var slam_knockback := 16.0
## 滞空高度（m）
@export var slam_height := 7.0

## 压扁用的基准（`model` 缩放 / 位置 / 脚底）
var _base_scale := Vector3.ONE
var _base_pos_y := 0.0
var _rest_bottom := 0.0
## 起跳瞬间的地面高度（它可能已经被上一次天降挪过位置，不能写死 0）
var _ground_y := 0.0
var _squash_tween: Tween
var _move_tween: Tween
var _mark: MeshInstance3D
## 下一次用哪个技能（第一下用天降，够震撼）
var _next_skill := SKILL_SLAM
## 技能二抬身前的模型高度
var _base_model_y := 0.0


func _init() -> void:
	attack_interval = 4.2              # 比飞猪慢
	attack_start_delay = 3.0
	windup_time = 1.0                  # 起手很慢，好躲
	attack_range = 12.0
	attack_half_angle_degrees = 32.0   # 正面比飞猪窄
	attack_damage = 26.0               # 技能二的伤害（天降另算，见 slam_damage）
	attack_reach = 3.2
	attack_radius = 3.0
	knockback_force = 8.0
	telegraph_color = Color(0.42, 0.78, 0.25, 0.45)   # 倭瓜绿（技能二那套）


func _ready() -> void:
	super._ready()
	if model != null:
		_base_scale = model.scale
		_base_pos_y = model.position.y
		var b := _mesh_box()
		_rest_bottom = b.position.y
	_build_mark()


## 不打人的时候**慢慢转向爱丽丝**。
##
## 为什么需要：技能二（原地重砸）只在正面 32° 半角内起手，而技能一「天降」会把它
## 直接砸到爱丽丝脚下 —— 落点常常在她侧后方，不转身的话它一辈子放不出第二招
## （自检里就是这样：技能一结束后站在它背后，9 秒都没等到绿圈）。
func _process(delta: float) -> void:
	super._process(delta)
	if _dead or _attacking:
		return
	var p := _find_player()
	if p == null:
		return
	var to := p.global_position - global_position
	to.y = 0.0
	if to.length_squared() < 0.04:
		return
	rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), clampf(2.4 * delta, 0.0, 1.0))


# --- 两个技能轮换 -------------------------------------------------------------

func _attack(player: Player) -> void:
	print("[倭瓜优香] 出手：%s" % ("压扁天降" if _next_skill == SKILL_SLAM else "原地重砸"))
	_attacking = true
	_attack_cooldown = attack_interval
	if _next_skill == SKILL_SLAM:
		_next_skill = SKILL_HEAVY
		await _skill_slam(player)
	else:
		_next_skill = SKILL_SLAM
		await super._attack(player)


## 技能一：压扁 → 弹起 → 滞空 → 天降
func _skill_slam(player: Player) -> void:
	if player == null or not is_instance_valid(player):
		_attacking = false
		return
	_ground_y = global_position.y
	# 落点：爱丽丝附近随机（0.4 ~ slam_place_radius），红圈就是伤害区
	var a := randf() * TAU
	var r := randf_range(0.4, slam_place_radius)
	var center := Vector3(
		player.global_position.x + cos(a) * r, _ground_y,
		player.global_position.z + sin(a) * r)
	# ① 压扁蓄力 0.45 s
	_squash_tween = create_tween()
	_squash_tween.tween_method(_set_squash, 1.0, 0.28, 0.45) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await _squash_tween.finished
	if not _alive():
		_abort()
		return
	# ② 弹起：缩放**瞬间还原**（那是弹力来源），人离地 0.8 m
	_squash_tween = create_tween()
	_squash_tween.tween_method(_set_squash, 0.28, 1.0, 0.13) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_move_tween = create_tween()
	_move_tween.tween_property(self, "global_position:y", _ground_y + 0.8, 0.13)
	Sfx.play("ui_open", 3.0)
	await _squash_tween.finished
	if not _alive():
		_abort()
		return
	# ③ 红圈亮起（落点）+ 腾空飞过去
	_show_mark(center)
	_move_tween = create_tween()
	_move_tween.set_parallel(true)
	_move_tween.tween_property(self, "global_position",
		Vector3(center.x, _ground_y + slam_height, center.z), 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_move_tween.tween_property(_mark, "scale", Vector3.ONE * attack_radius, 0.5)
	await _move_tween.finished
	if not _alive():
		_abort()
		return
	# ④ 滞空 0.18 s：红圈已经画好，这段时间够玩家跑出 3 m
	await get_tree().create_timer(0.18).timeout
	if not _alive():
		_abort()
		return
	# ⑤ 砸下来
	_move_tween = create_tween()
	_move_tween.tween_property(self, "global_position:y", _ground_y, 0.10) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await _move_tween.finished
	_land(center)
	_squash_tween = create_tween()
	_squash_tween.tween_method(_set_squash, 1.0, 0.82, 0.06)
	_squash_tween.tween_method(_set_squash, 0.82, 1.0, 0.20)
	await _squash_tween.finished
	_attacking = false


## 落地结算：红圈里的玩家吃 40 + 强击退（圈半径 = `attack_radius`，和画的一模一样）
func _land(center: Vector3) -> void:
	_hide_mark()
	Sfx.play("ui_close", 5.0)
	var p := _find_player()
	if p != null:
		var flat := Vector3(p.global_position.x - center.x, 0.0,
			p.global_position.z - center.z)
		if flat.length() <= attack_radius:
			p.take_damage(slam_damage, center, slam_knockback)
	print("[倭瓜优香] 天降落地（%.1f, %.1f）→ 圈内 %.0f 伤害 / %.0f 击退"
		% [center.x, center.z, slam_damage, slam_knockback])


# --- 压扁 / 红圈 ---------------------------------------------------------------

## 把模型压到 `f` 倍高（1 = 原形），同时把脚底钉在原地。
func _set_squash(f: float) -> void:
	if model == null:
		return
	var fy := clampf(f, 0.05, 2.0)
	var widen := 1.0 / sqrt(fy)      # 压扁时横向撑开，像被踩了一脚
	model.scale = Vector3(
		_base_scale.x * widen, _base_scale.y * fy, _base_scale.z * widen)
	model.position.y = _rest_bottom - fy * (_rest_bottom - _base_pos_y)


func _build_mark() -> void:
	_mark = MeshInstance3D.new()
	_mark.name = "SlamMark"
	var disk := CylinderMesh.new()
	disk.top_radius = 1.0
	disk.bottom_radius = 1.0
	disk.height = 0.03
	disk.radial_segments = 40
	_mark.mesh = disk
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.12, 0.06, 0.38)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.18, 0.08)
	mat.emission_energy_multiplier = 1.5
	_mark.material_override = mat
	_mark.visible = false
	add_child(_mark)
	# 钉在世界坐标：Boss 腾空时红圈必须留在落点上
	_mark.top_level = true


func _show_mark(center: Vector3) -> void:
	if _mark == null:
		return
	_mark.global_position = Vector3(center.x, center.y + 0.06, center.z)
	_mark.scale = Vector3.ONE * (attack_radius * 0.55)
	_mark.visible = true


func _hide_mark() -> void:
	if _mark != null:
		_mark.visible = false


# --- 技能二的钩子：整只抬起来（没有骨，只能这样）--------------------------------

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


# --- 状态工具 -----------------------------------------------------------------

func _alive() -> bool:
	return is_instance_valid(self) and not _dead


## 被打断（倒下 / 目标没了）：红圈收掉、缩放回原形、允许下次攻击
func _abort() -> void:
	_hide_mark()
	_kill_tweens()
	_set_squash(1.0)
	_attacking = false


func _kill_tweens() -> void:
	if _squash_tween != null and _squash_tween.is_valid():
		_squash_tween.kill()
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	_squash_tween = null
	_move_tween = null


func _die(by_damage: float) -> void:
	_hide_mark()
	_kill_tweens()
	_set_squash(1.0)
	super._die(by_damage)


## 技能一的红圈现在亮着吗（自检用）
func mark_visible() -> bool:
	return _mark != null and _mark.visible


## 下一招是哪个（0 = 天降，1 = 重砸；自检用）
func next_skill() -> int:
	return _next_skill
