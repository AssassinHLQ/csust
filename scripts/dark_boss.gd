class_name DarkBoss
extends Boss
## 第 8 段「暗网黑市交易」的总管 —— **霍德（Hod）**，在爱丽丝附近**绕着飞**。
##
## 用户原话：「再后面是暗网黑市交易，比纳 boss 将出现向我们发射激光、炮弹。这个更加危险，
## 这一阶段也持续久点道路长点，我们需要跑酷同时击败 boss，这个 boss 不会复活。」
## 2026-10-21 用户：「后面需要改一下黑市的boss，比纳放上去还是很生硬换成霍德，
## 而且不要一直在一个地方，要在爱丽丝附近到处飞来飞去」——
##   · 模型换成 `models/boss_hod/HOD_Original.fbx`（3 万面 / 164 骨 / **没有动画**）；
##   · 走位从「跟着一个固定偏移平移」改成**绕着爱丽丝游走**（见下面 `_fly()`）。
##
## ── 和竞技场那六位的区别 ──
## 那六位是**近战扇形**（`boss_attacker.gd`：预警 → 横扫），玩家站在场地上躲；
## 这一位是**空中炮台**，两种远程攻击：
##   · **激光**：0.6 s 预警（半透明细束，瞄准你**那一刻**的位置）→ 实体 0.25 s。
##     只要不在束线上就没事 —— 跑酷里「别停」就是躲它。
##   · **炮弹**：每 1.8 s 一发，朝你**出膛那一刻**的位置飞（带上抛），命中掉血 + 击退 ——
##     真正的威胁是**被击退掉下板**。
##
## ⚠️ 用户：「这个 boss 不会复活」→ 覆写 `_respawn()`：`_die()` 之后
##    模型前扑、碰撞关掉，躺 `vanish_delay` 秒后**淡出消失**（2026-10-19 用户：
##    「比纳死后过一段时间消失」），节点最后 `queue_free()`。
##
## ⚠️ 血量、名字在 `_init()` 里给默认值（场景里不写），这样场景只需要挂脚本 + 位置。

const BEAM_ON := Color(1.0, 0.22, 0.18, 0.92)
const BEAM_WARN := Color(1.0, 0.35, 0.30, 0.28)
const SHELL_COL := Color(0.95, 0.35, 0.12)

## 激光：多久一发 / 预警 / 实体 / 伤害 / 判定半径
@export var laser_interval := 3.4
@export var laser_aim_time := 0.6
@export var laser_live_time := 0.25
@export var laser_damage := 14.0
@export var laser_radius := 1.1
## 炮弹：多久一发 / 速度 / 重力 / 伤害 / 击退
@export var shell_interval := 1.8
@export var shell_speed := 20.0
@export var shell_gravity := 12.0
@export var shell_damage := 18.0
@export var shell_knockback := 6.0
## 只在这个半径里有玩家时才开火（跑酷路线长，别隔着 100 m 打空气）
@export var engage_range := 46.0
## 绕着爱丽丝飞的**半径带**（m）：太近会糊住镜头，太远又不像在缠着你
@export var fly_radius_min := 5.0
@export var fly_radius_max := 9.5
## 飞在爱丽丝头顶多高（m）
@export var fly_height := 6.0
## 最高飞行速度（m/s）。爱丽丝跑起来约 20 m/s，这个数要够追，但别让她一回头就已经贴脸
@export var fly_speed_max := 18.0
## 多久换一个新的「绕飞点」（秒）
@export var fly_retarget := 2.0
## 倒下后多久开始消失 / 消失动画多长（秒）。
## 用户 2026-10-19：「比纳死后过一段时间消失」—— 尸体别一直躺在跑道上挡视线。
@export var vanish_delay := 5.0
@export var vanish_time := 1.4

var _beam: MeshInstance3D
var _beam_mat: StandardMaterial3D
var _shell_mat: StandardMaterial3D
var _t_laser := 0.0
var _t_shell := 0.0
var _laser_state := 0          # 0 空闲 / 1 预警 / 2 实体
var _laser_timer := 0.0
var _aim_from := Vector3.ZERO
var _aim_to := Vector3.ZERO
var _shells: Array[Dictionary] = []
var _shots := 0
var _player: Player
var _killed := false
## 程序化动画（这份 FBX **没有动画**：164 骨、纯静态、连 AnimationPlayer 都没有）——
## 悬停上下浮动 + 缓慢摆头 + 开火时的一下「反冲」。基准值在 `_ready` 里量。
var _anim_t := 0.0
var _base_model_pos := Vector3.ZERO
var _base_model_scale := Vector3.ONE
var _base_model_yaw := 0.0
## 绕飞状态（2026-10-21）：当前方位角 / 半径 / 高度偏移 / 实际速度
var _orbit_angle := 0.0
var _orbit_radius := 7.0
var _orbit_dy := 0.0
var _fly_speed := 0.0
var _retarget := 0.0
## 刚才这一帧转了多少弧度（侧倾用，见 `_process`）
var _orbit_dyaw := 0.0


func _init() -> void:
	# 用户 2026-10-21：黑市那只换成霍德（比纳那只放上去"还是很生硬"）
	display_name = "霍德"
	model_path = "res://models/boss_hod/HOD_Original.fbx"
	# key 必须与 FBX 里的材质 `resource_name` 一字不差（`_probe_hod.gd` 量出来的三个）
	texture_map = {
		"HOD_Original": "res://models/boss_hod/HOD_Original.png",
		"HOD_Original_Halo": "res://models/boss_hod/HOD_Original_Halo.png",
		"HOD_TemporaryTower": "res://models/boss_hod/HOD_TemporaryTower.png",
	}
	collision_factors = Vector3(0.8, 0.9, 0.8)
	height = 6.0
	# 2026-10-19 上午用户：「比纳血条增加 3 倍」→ 900 → 2700；
	# 同一天下午：「比纳太肉了，削弱一点点血量」→ **2200**（−18.5%）。
	# 血条是按比例画的，长度不变，只是少打 500 点。想再调就改这一行。
	max_health = 2200.0
	# 倒下后躺多久：`_ready()` 会再按导出参数 `vanish_delay` 覆盖一次
	respawn_time = 5.0


func _ready() -> void:
	super._ready()
	_build_fx()
	if model != null:
		_base_model_pos = model.position
		_base_model_scale = model.scale
		_base_model_yaw = model.rotation.y
	_setup_rig()
	died.connect(_on_died)
	# 父类 `_die()` 末尾会 `chain().tween_interval(respawn_time)` 再回调 `_respawn()`：
	# 这个数就是「倒下后躺多久」。这里把它接到 `vanish_delay`（导出参数），
	# 之后 `_respawn()` 被覆写成「消失」而不是「站起来」。
	respawn_time = vanish_delay
	# 先用**半速**开火：玩家第一次见到它时还在 K 线上，别一上来就被激光点名
	_t_laser = laser_interval * 0.5
	_t_shell = 0.8


## **不会复活，而且会消失**（用户 2026-10-19：「比纳死后过一段时间消失」）。
##
## 父类这里本来是「站起来」（重置血量 / 恢复碰撞 / 播起身动作）。我们改成：
## 倒下 → 躺 `vanish_delay`（默认 5 s）→ 淡出 + 下沉 1.4 s → **删掉节点**。
## 删掉之后 `Route/DarkBoss` 不存在，血条行早就收了（`hud.gd` 在血量归零时收行）。
func _respawn() -> void:
	_vanish()


func _vanish() -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	if model != null:
		tw.tween_property(model, "position:y", model.position.y - 1.4, vanish_time)
		tw.tween_property(model, "scale", model.scale * 0.6, vanish_time)
	for mat in _materials:
		if mat == null:
			continue
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var c := mat.albedo_color
		tw.tween_property(mat, "albedo_color", Color(c.r, c.g, c.b, 0.0), vanish_time)
	tw.chain().tween_callback(queue_free)
	print("[DarkBoss] 霍德的尸体消失（躺 %.1f s，淡出 %.1f s 后删除节点）"
		% [vanish_delay, vanish_time])


func _on_died(_by_damage: float) -> void:
	_killed = true
	_beam.visible = false
	for s in _shells:
		var n := s["node"] as Node3D
		if is_instance_valid(n):
			n.queue_free()
	_shells.clear()
	print("[DarkBoss] 霍德被击败（不复活）")


func _build_fx() -> void:
	_beam = MeshInstance3D.new()
	_beam.name = "LaserBeam"
	var bm := BoxMesh.new()
	bm.size = Vector3(1, 1, 1)
	_beam.mesh = bm
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.albedo_color = BEAM_WARN
	_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam.material_override = _beam_mat
	_beam.visible = false
	add_child(_beam)
	_shell_mat = StandardMaterial3D.new()
	_shell_mat.albedo_color = SHELL_COL
	_shell_mat.emission_enabled = true
	_shell_mat.emission = SHELL_COL
	_shell_mat.emission_energy_multiplier = 2.2


## 飞行中的「活着」感：上下浮 + 缓慢摆头 + **侧倾**（转弯时像在飘）。
## **没有骨骼动画**（FBX 连 AnimationPlayer 都没有），所以这里是**程序化骨骼动画**：
## 骨架 164 根，挑出能扭的几组（见 `_setup_rig()`），每帧直接写 `set_bone_pose_rotation`。
## ⚠️ `_dead` 之后不能再动：父类 `_die()` 正在用 tween 把模型往前扑，抢了会打架。
func _process(delta: float) -> void:
	if model == null or _dead:
		return
	_anim_t += delta
	model.position = _base_model_pos + Vector3(
		sin(_anim_t * 0.9) * 0.55, sin(_anim_t * 1.7) * 0.28, 0.0)
	model.rotation.y = _base_model_yaw + sin(_anim_t * 0.62) * 0.10
	# 侧倾：`_orbit_dyaw` 是刚才这一帧的转向量（`_fly()` 里记的），转得越急倾得越多
	model.rotation.z = lerpf(model.rotation.z,
		clampf(-_orbit_dyaw * 6.0, -0.22, 0.22), clampf(delta * 5.0, 0.0, 1.0))
	_animate_bones(delta)


## 开火时的一下反冲：缩一下再弹回来（激光/炮弹都调）
func _kick() -> void:
	if model == null or _dead:
		return
	var tw := create_tween()
	tw.tween_property(model, "scale", _base_model_scale * 1.07, 0.06)
	tw.tween_property(model, "scale", _base_model_scale, 0.22) 		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# --- 程序化骨骼动画（待机 / 瞄准 / 开火）---------------------------------------
#
# 这份 FBX **没有动画剪辑**（164 骨、纯静态、连 AnimationPlayer 都没有），所以动画只能
# 直接扭骨头：每帧写 `Skeleton3D.set_bone_pose_rotation()`（pose 是**相对 rest** 的，
# 恒等 = 原姿势），全部用正弦叠加，没有任何关键帧资源。
#
# 挑的几组骨头（名字来自 `_probe_hod_bones.gd` 的导出）：
#   · `bone_center`        —— 整只的呼吸俯仰 / 侧摆
#   · `bone_Head_01/02`    —— 左右看、点头；瞄准时低头对准
#   · `bone_L/R_Lasergun`  —— 待机轻晃 / 瞄准抬起 / 开火反冲
#   · `bone_Body_Tentacle_{B,L,LB,R,RB}_00..11` —— 身上五排骨链，行波摆动
#   · `bone_Tentacle_{L,R}_00..15`             —— 两条主触手，更慢更大，开火时外张
#
# ⚠️ 幅度都写得很小（0.03 ~ 0.15 rad）：这是 6 m 高的 Boss，1° 的晃动在屏幕上已经很明显；
#    早期版本给 0.3 rad，远看像在抽搐。

var _skel: Skeleton3D
var _b_center := -1
var _b_head1 := -1
var _b_head2 := -1
var _b_gun_l := -1
var _b_gun_r := -1
var _chains_body: Array = []
var _chains_arm: Array = []
## 瞄准进度 0→1（激光预警段涨上去）、开火脉冲 1→0（0.2 s 内衰掉）
var _aim := 0.0
var _pulse := 0.0


func _setup_rig() -> void:
	if model == null:
		return
	var sk := model.find_children("*", "Skeleton3D", true, false)
	if sk.is_empty():
		return
	_skel = sk[0] as Skeleton3D
	_b_center = _skel.find_bone("bone_center")
	_b_head1 = _skel.find_bone("bone_Head_01")
	_b_head2 = _skel.find_bone("bone_Head_02")
	_b_gun_l = _skel.find_bone("bone_L_Lasergun")
	_b_gun_r = _skel.find_bone("bone_R_Lasergun")
	for pre in ["bone_Body_Tentacle_B_", "bone_Body_Tentacle_L_", "bone_Body_Tentacle_LB_",
			"bone_Body_Tentacle_R_", "bone_Body_Tentacle_RB_"]:
		var ch := _bones_with_prefix(pre)
		if ch.size() >= 3:
			_chains_body.append(ch)
	for pre in ["bone_Tentacle_L_", "bone_Tentacle_R_"]:
		var ch2 := _bones_with_prefix(pre)
		if ch2.size() >= 3:
			_chains_arm.append(ch2)
	print("[DarkBoss] 霍德骨骼动画就位：%d 排骨链 + %d 条主触手（骨架 %d 根）" % [
		_chains_body.size(), _chains_arm.size(), _skel.get_bone_count()])


## 按前缀收骨头，按名字排序（名字是 `_00 … _15` 两位补零，字典序就是链序）
func _bones_with_prefix(pre: String) -> Array:
	var out: Array = []
	for i in _skel.get_bone_count():
		if String(_skel.get_bone_name(i)).begins_with(pre):
			out.append(i)
	out.sort_custom(func(a, b):
		return String(_skel.get_bone_name(a)) < String(_skel.get_bone_name(b)))
	return out


func _pose(idx: int, q: Quaternion) -> void:
	if idx >= 0 and _skel != null:
		_skel.set_bone_pose_rotation(idx, q)


func _animate_bones(delta: float) -> void:
	if _skel == null:
		return
	var t := _anim_t
	_aim = move_toward(_aim, 1.0 if _laser_state == 1 else 0.0, delta * 4.0)
	_pulse = maxf(_pulse - delta * 5.0, 0.0)
	# 身体：呼吸（俯仰）+ 慢摇（侧摆）
	_pose(_b_center, Quaternion(Vector3.RIGHT, sin(t * 1.1) * 0.035)
		* Quaternion(Vector3.BACK, sin(t * 0.43) * 0.045))
	# 头：待机左右看；瞄准时低头对准目标
	_pose(_b_head1, Quaternion(Vector3.UP, sin(t * 0.31) * 0.16 * (1.0 - _aim))
		* Quaternion(Vector3.RIGHT, sin(t * 0.57 + 1.0) * 0.05 - 0.34 * _aim))
	_pose(_b_head2, Quaternion(Vector3.RIGHT, sin(t * 0.9 + 0.7) * 0.03 - 0.12 * _aim))
	# 两门激光炮：待机轻晃 / 瞄准抬起 / 开火反冲
	var gun_idle := sin(t * 0.83) * 0.03
	_pose(_b_gun_l, Quaternion(Vector3.RIGHT, gun_idle - 0.75 * _aim + 0.55 * _pulse))
	_pose(_b_gun_r, Quaternion(Vector3.RIGHT, -gun_idle - 0.75 * _aim + 0.55 * _pulse))
	# 身上五排骨链：行波，越靠链尾摆得越大
	for ch in _chains_body:
		var n: int = ch.size()
		for k in n:
			var ph := t * 1.25 - float(k) * 0.5
			var amp := 0.035 + 0.045 * float(k) / float(maxi(n - 1, 1))
			_pose(int(ch[k]), Quaternion(Vector3.RIGHT, sin(ph) * amp)
				* Quaternion(Vector3.BACK, cos(ph * 0.8) * amp * 0.7))
	# 两条主触手：更慢更大，开火时往外张
	for ch in _chains_arm:
		var n2: int = ch.size()
		for k in n2:
			var ph2 := t * 0.9 - float(k) * 0.42
			var amp2 := 0.07 + 0.06 * float(k) / float(maxi(n2 - 1, 1)) + 0.12 * _pulse
			_pose(int(ch[k]), Quaternion(Vector3.RIGHT, sin(ph2) * amp2)
				* Quaternion(Vector3.BACK, cos(ph2 * 0.75) * amp2))


func _physics_process(delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Player
	if _killed or _dead or _player == null:
		_tick_shells(delta)
		return
	var pc := _player_point()
	# 用户 2026-10-19：「如果比纳没打完，也会追过来的」——
	# **追击不看距离**：玩家跑过第 8 段、进了内存条市场，它照样跟着飞过去；
	# 只有**开火**看 `engage_range`（打不到的远处不浪费炮弹）。
	_fly(pc, delta)
	if global_position.distance_to(pc) > engage_range:
		_beam.visible = false
		_laser_state = 0
		_laser_timer = 0.0
		_tick_shells(delta)
		return
	_tick_laser(pc, delta)
	_tick_shells(delta)
	_t_shell -= delta
	if _t_shell <= 0.0:
		_t_shell = shell_interval
		_spawn_shell(pc)


## 绕着爱丽丝游走 —— 2026-10-21 用户：「不要一直在一个地方，要在爱丽丝附近到处飞来飞去」。
##
## 做法：把「位置」拆成三个**绑在玩家身上**的量 —— 方位角 `_orbit_angle`、半径
## `_orbit_radius`、高度偏移 `_orbit_dy`。每隔 `fly_retarget` 秒换一组随机值（整圈都去，
## 不是只在某一侧晃），每帧再拿**爱丽丝当前位置**算目标点，所以玩家一边跑它一边绕，
## 既不会掉队、也不会永远停在同一个方位。
## 速度按距离收敛（远了 18 m/s、近了减速）+ 速度平滑 + 转向侧倾 —— 这三层就是从
## 「贴着一个固定偏移平移」变成「飞」的关键。
func _fly(pc: Vector3, delta: float) -> void:
	_retarget -= delta
	if _retarget <= 0.0:
		_retarget = fly_retarget * randf_range(0.75, 1.35)
		_orbit_angle = randf() * TAU
		_orbit_radius = randf_range(fly_radius_min, fly_radius_max)
		_orbit_dy = randf_range(-1.0, 1.6)
	var r := _orbit_radius
	var want := Vector3(
		pc.x + cos(_orbit_angle) * r,
		pc.y + fly_height + _orbit_dy + sin(_anim_t * 1.7) * 0.5,
		pc.z + sin(_orbit_angle) * r)
	var to := want - global_position
	var d := to.length()
	var want_speed := clampf(d * 1.6, 0.0, fly_speed_max)
	_fly_speed = lerpf(_fly_speed, want_speed, clampf(delta * 3.5, 0.0, 1.0))
	if d > 0.001:
		global_position += to / d * minf(_fly_speed * delta, d)
	# 换到对面时它是**直线**飞过去的，会从爱丽丝脸前擦过（量到最近 2.9 m，糊镜头）。
	# 这里兜一道下限：水平距离一旦小于 `fly_radius_min − 1`，直接把它抵回去。
	var off := Vector3(global_position.x - pc.x, 0.0, global_position.z - pc.z)
	var hd := off.length()
	var min_r := maxf(fly_radius_min - 1.0, 0.5)
	if hd > 0.001 and hd < min_r:
		global_position += off / hd * (min_r - hd)
	# 面朝爱丽丝（模型正面 +Z）；同时记下这一帧转了多少，`_process` 拿它做侧倾
	var flat := Vector3(pc.x - global_position.x, 0.0, pc.z - global_position.z)
	if flat.length_squared() > 0.04:
		var before := rotation.y
		rotation.y = lerp_angle(rotation.y, atan2(flat.x, flat.z),
			clampf(delta * 5.0, 0.0, 1.0))
		_orbit_dyaw = wrapf(rotation.y - before, -PI, PI)
	else:
		_orbit_dyaw = 0.0


func _tick_laser(pc: Vector3, delta: float) -> void:
	_laser_timer -= delta
	match _laser_state:
		0:
			if _laser_timer <= 0.0:
				_laser_state = 1
				_laser_timer = laser_aim_time
				_aim_from = global_position + Vector3(0, -1.2, 0)
				_aim_to = pc
				_place_beam(_aim_from, _aim_to)
				_beam_mat.albedo_color = BEAM_WARN
				_beam.visible = true
		1:
			if _laser_timer <= 0.0:
				_laser_state = 2
				_laser_timer = laser_live_time
				_beam_mat.albedo_color = BEAM_ON
				_pulse = 1.0
				_kick()
				_hit_laser(pc)
		2:
			if _laser_timer <= 0.0:
				_laser_state = 0
				_laser_timer = laser_interval
				_beam.visible = false


func _place_beam(a: Vector3, b: Vector3) -> void:
	var len := maxf(a.distance_to(b), 0.1)
	_beam.global_position = (a + b) * 0.5
	_beam.look_at_from_position((a + b) * 0.5, b, Vector3.UP)
	_beam.scale = Vector3(0.26, 0.26, len)


func _hit_laser(pc: Vector3) -> void:
	var cp := Geometry3D.get_closest_point_to_segment(pc, _aim_from, _aim_to)
	if cp.distance_to(pc) <= laser_radius:
		_player.take_damage(laser_damage, _aim_from, 0.0)
		Sfx.play("ui_close", -6.0)


func _spawn_shell(pc: Vector3) -> void:
	_shots += 1
	_pulse = 1.0
	_kick()
	var mi := MeshInstance3D.new()
	mi.name = "Shell%d" % _shells.size()
	var sm := SphereMesh.new()
	sm.radius = 0.55
	sm.height = 1.1
	mi.mesh = sm
	mi.material_override = _shell_mat
	add_child(mi)
	var from := global_position + Vector3(0, -2.0, 0)
	var d := pc - from
	var t := maxf(d.length() / shell_speed, 0.25)
	# 上抛一点，看起来才像炮弹（不然是直线球）
	var v := d / t + Vector3(0, 0.5 * shell_gravity * t, 0)
	mi.global_position = from
	_shells.append({"node": mi, "v": v, "t": 0.0})


func _tick_shells(delta: float) -> void:
	var pc := _player_point()
	var keep: Array[Dictionary] = []
	for s in _shells:
		var n := s["node"] as Node3D
		if not is_instance_valid(n):
			continue
		var v: Vector3 = s["v"]
		v.y -= shell_gravity * delta
		s["v"] = v
		n.global_position += v * delta
		s["t"] = float(s["t"]) + delta
		var landed := n.global_position.y < 0.0 or float(s["t"]) > 4.5
		if n.global_position.distance_to(pc) < 1.0 and _player != null and not _killed:
			_player.take_damage(shell_damage, n.global_position, shell_knockback)
			Sfx.play("ui_toggle", -4.0)
			landed = true
		if landed:
			n.queue_free()
			continue
		keep.append(s)
	_shells = keep


func _player_point() -> Vector3:
	if _player == null:
		return global_position + Vector3(0, -6.0, 0)
	return _player.global_position + Vector3(0, 0.9, 0)


## 自检用：现在有几发炮弹在飞 / 激光是不是实体段
func shell_count() -> int:
	return _shells.size()


## 自检用：一共打出过几发（在飞的可能一瞬间就命中/落地，`shell_count` 会闪）
func shots_fired() -> int:
	return _shots


func laser_live() -> bool:
	return _laser_state == 2


func killed() -> bool:
	return _killed
