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
## 2026-11 用户：「变成宝藏丰富的危险黑市……代价是增强霍德，多做几个技能，激光不要了」
## → 黑市七块板从「固定 −0.8%」改成「固定 +1%」（见 make_flush_section.py），
##   霍德**删掉激光**，换成四个轮着放的技能：
##   · **弹幕**：两发炮弹，间隔 0.12 s，追着你落点打；
##   · **三连炮**：按你的速度预判，左中右三发覆盖跑道；
##   · **震地波**：脚下亮起 3.4 m 预警圈，0.9 s 后爆炸（16 伤 + 9 击退）；
##   · **触手砸击**：预判你 0.55 s 后的位置，青光柱从天上砸下来（24 伤 + 13 击退）。
##   真正的威胁仍然是**被击退掉下板**。
##
## ⚠️ 用户：「这个 boss 不会复活」→ 覆写 `_respawn()`：`_die()` 之后
##    模型前扑、碰撞关掉，躺 `vanish_delay` 秒后**淡出消失**（2026-10-19 用户：
##    「比纳死后过一段时间消失」），节点最后 `queue_free()`。
##
## ⚠️ 血量、名字在 `_init()` 里给默认值（场景里不写），这样场景只需要挂脚本 + 位置。

const SHELL_COL := Color(0.95, 0.35, 0.12)
const QUAKE_COL := Color(1.0, 0.52, 0.14, 0.55)
const SLAM_COL := Color(0.35, 0.92, 1.0, 0.55)

## 四个技能的名字（轮着放；自检按它核对）
const SKILL_NAMES := ["弹幕", "三连炮", "震地波", "触手砸击"]
const SKILL_COUNT := 4

## 技能节奏：每隔 skill_interval 秒放一个，第一次晚 skill_start_delay
@export var skill_interval := 2.2
@export var skill_start_delay := 1.5

## 炮弹：速度 / 重力 / 伤害 / 击退 / 弹幕两发之间的间隔
@export var shell_speed := 20.0
@export var shell_gravity := 12.0
@export var shell_damage := 18.0
@export var shell_knockback := 6.0
@export var shell_gap := 0.12

## 震地波：预警时长 / 半径 / 伤害 / 击退
@export var quake_warn := 0.9
@export var quake_radius := 3.4
@export var quake_damage := 16.0
@export var quake_knockback := 9.0

## 触手砸击：预警时长 / 半径 / 伤害 / 击退
@export var slam_warn := 1.1
@export var slam_radius := 2.2
@export var slam_damage := 24.0
@export var slam_knockback := 13.0

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

var _shell_mat: StandardMaterial3D
var _shells: Array[Dictionary] = []
## 预警圈 / 砸击柱：死亡时一起清掉，别在地上留一圈红印
var _marks: Array[Node3D] = []
var _shots := 0
var _player: Player
var _killed := false
var _t_skill := 0.0
var _skill_i := 0
var _last_skill := ""
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
	# 2026-11 增强走的是**技能**（四个轮放），血量维持 2200，别又变肉。
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
	# 第一次出手留一点反应时间：玩家刚进黑市时还在 DK1 上
	_t_skill = skill_start_delay


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
	for s in _shells:
		var n := s["node"] as Node3D
		if is_instance_valid(n):
			n.queue_free()
	_shells.clear()
	_clear_marks()
	print("[DarkBoss] 霍德被击败（不复活）")


func _clear_marks() -> void:
	# 只藏不删：预警圈/光柱身上还挂着 tween，硬删会让 tween 找不到目标；
	# 让它们（≤1.1 s 内）自己走完回调，回调里看到 `_killed` 会自行清掉。
	for m in _marks:
		if is_instance_valid(m):
			m.visible = false
	_marks.clear()


func _build_fx() -> void:
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


## 开火时的一下反冲：缩一下再弹回来（四个技能都调）
func _kick() -> void:
	if model == null or _dead:
		return
	var tw := create_tween()
	tw.tween_property(model, "scale", _base_model_scale * 1.07, 0.06)
	tw.tween_property(model, "scale", _base_model_scale, 0.22) 		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# --- 程序化骨骼动画（待机 / 施法 / 开火）---------------------------------------
#
# 这份 FBX **没有动画剪辑**（164 骨、纯静态、连 AnimationPlayer 都没有），所以动画只能
# 直接扭骨头：每帧写 `Skeleton3D.set_bone_pose_rotation()`（pose 是**相对 rest** 的，
# 恒等 = 原姿势），全部用正弦叠加，没有任何关键帧资源。
#
# 挑的几组骨头（名字来自 `_probe_hod_bones.gd` 的导出）：
#   · `bone_center`        —— 整只的呼吸俯仰 / 侧摆
#   · `bone_Head_01/02`    —— 左右看、点头
#   · `bone_L/R_Lasergun`  —— 待机轻晃 / 施法时抬起
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
## 施法脉冲 1→0（0.3 s 内衰掉，抬枪 / 触手外张都用它）
var _cast := 0.0
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
	_cast = maxf(_cast - delta * 3.0, 0.0)
	_pulse = maxf(_pulse - delta * 5.0, 0.0)
	# 身体：呼吸（俯仰）+ 慢摇（侧摆）
	_pose(_b_center, Quaternion(Vector3.RIGHT, sin(t * 1.1) * 0.035)
		* Quaternion(Vector3.BACK, sin(t * 0.43) * 0.045))
	# 头：待机左右看；施法时略微低头
	_pose(_b_head1, Quaternion(Vector3.UP, sin(t * 0.31) * 0.16 * (1.0 - _cast))
		* Quaternion(Vector3.RIGHT, sin(t * 0.57 + 1.0) * 0.05 - 0.20 * _cast))
	_pose(_b_head2, Quaternion(Vector3.RIGHT, sin(t * 0.9 + 0.7) * 0.03 - 0.08 * _cast))
	# 两门炮：待机轻晃 / 施法时抬起、开火反冲
	var gun_idle := sin(t * 0.83) * 0.03
	_pose(_b_gun_l, Quaternion(Vector3.RIGHT, gun_idle - 0.35 * _cast + 0.55 * _pulse))
	_pose(_b_gun_r, Quaternion(Vector3.RIGHT, -gun_idle - 0.35 * _cast + 0.55 * _pulse))
	# 身上五排骨链：行波，越靠链尾摆得越大
	for ch in _chains_body:
		var n: int = ch.size()
		for k in n:
			var ph := t * 1.25 - float(k) * 0.5
			var amp := 0.035 + 0.045 * float(k) / float(maxi(n - 1, 1))
			_pose(int(ch[k]), Quaternion(Vector3.RIGHT, sin(ph) * amp)
				* Quaternion(Vector3.BACK, cos(ph * 0.8) * amp * 0.7))
	# 两条主触手：更慢更大，施法时往外张
	for ch in _chains_arm:
		var n2: int = ch.size()
		for k in n2:
			var ph2 := t * 0.9 - float(k) * 0.42
			var amp2 := 0.07 + 0.06 * float(k) / float(maxi(n2 - 1, 1)) + 0.12 * _pulse
			_pose(int(ch[k]), Quaternion(Vector3.RIGHT, sin(ph2) * amp2)
				* Quaternion(Vector3.BACK, cos(ph2 * 0.75) * amp2))


func _physics_process(delta: float) -> void:
	# `Boss::_physics_process()` 负责**每帧按骨骼当前位置重算**骨骼切片的碰撞盒
	# （2026-11-11 修「霸王龙碰撞没跟着技能变」）。这里覆盖了它，必须显式调一次，
	# 否则本类一旦用 BOX_PARTS，盒子就会冻在 `_boot()` 那一刻。
	super._physics_process(delta)
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Player
	if _killed or _dead or _player == null:
		_tick_shells(delta)
		return
	var pc := _player_point()
	# 用户 2026-10-19：「如果比纳没打完，也会追过来的」——
	# **追击不看距离**：玩家跑过第 8 段、进了内存条市场，它照样跟着飞过去；
	# 只有**出手**看 `engage_range`（打不到的远处不浪费技能）。
	_fly(pc, delta)
	_tick_shells(delta)
	if global_position.distance_to(pc) > engage_range:
		_t_skill = maxf(_t_skill, 0.5)
		return
	_t_skill -= delta
	if _t_skill <= 0.0:
		_t_skill = skill_interval
		_cast_skill(_skill_i, pc)
		_skill_i += 1


## 四个技能轮着放（顺序固定，保证每种都会出现，不靠随机）
func _cast_skill(i: int, pc: Vector3) -> void:
	_last_skill = SKILL_NAMES[i % SKILL_COUNT]
	_cast = 1.0
	_pulse = 1.0
	_kick()
	print("[DarkBoss] 霍德放技能：%s" % _last_skill)
	match i % SKILL_COUNT:
		0:
			_skill_barrage(pc)
		1:
			_skill_triple(pc)
		2:
			_skill_quake(pc)
		_:
			_skill_slam(pc)


## 弹幕：两发炮弹，间隔 shell_gap；第二发追你**那时候**的位置
func _skill_barrage(pc: Vector3) -> void:
	_spawn_shell(pc)
	await get_tree().create_timer(shell_gap).timeout
	if _killed or _dead or not is_inside_tree():
		return
	_spawn_shell(_player_point())


## 三连炮：按速度预判 0.5 s，左中右三个落点同时落下
func _skill_triple(pc: Vector3) -> void:
	var vel := _player.velocity if _player != null else Vector3.ZERO
	var pred := pc + Vector3(vel.x, 0.0, vel.z) * 0.5
	var side := Vector3(pred.z - global_position.z, 0.0, -(pred.x - global_position.x))
	if side.length_squared() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	for k in [-1.7, 0.0, 1.7]:
		_spawn_shell(pred + side * float(k))


## 震地波：脚下预警圈 → 0.9 s 后爆炸
func _skill_quake(pc: Vector3) -> void:
	var center := Vector3(pc.x, _foot_y(pc.y), pc.z)
	var ring := _make_disc(center, quake_radius, QUAKE_COL)
	var tw := create_tween()
	tw.tween_property(ring, "scale", Vector3(quake_radius, 1.0, quake_radius), quake_warn) 		.from(Vector3(quake_radius * 0.25, 1.0, quake_radius * 0.25))
	tw.tween_callback(func() -> void:
		_resolve_quake(ring, center))


func _resolve_quake(ring: Node3D, center: Vector3) -> void:
	_marks.erase(ring)
	if _killed or _dead:
		if is_instance_valid(ring):
			ring.queue_free()
		return
	_hit_area(center, quake_radius, quake_damage, quake_knockback)
	_flash_mark(ring, 1.6, 0.28)


## 触手砸击：预判 0.55 s 后的落点，青光柱从天上砸下来
func _skill_slam(pc: Vector3) -> void:
	var vel := _player.velocity if _player != null else Vector3.ZERO
	var pred := pc + Vector3(vel.x, 0.0, vel.z) * 0.55
	var center := Vector3(pred.x, _foot_y(pred.y), pred.z)
	var disc := _make_disc(center, slam_radius, SLAM_COL)
	var pillar := _make_pillar(center + Vector3(0.0, 7.5, 0.0))
	var tw := create_tween()
	tw.tween_property(pillar, "global_position", center + Vector3(0.0, 3.9, 0.0),
		slam_warn).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		_resolve_slam(disc, pillar, center))


func _resolve_slam(disc: Node3D, pillar: Node3D, center: Vector3) -> void:
	_marks.erase(disc)
	_marks.erase(pillar)
	if _killed or _dead:
		if is_instance_valid(disc):
			disc.queue_free()
		if is_instance_valid(pillar):
			pillar.queue_free()
		return
	_hit_area(center, slam_radius, slam_damage, slam_knockback)
	Sfx.play("ui_close", -2.0)
	_flash_mark(disc, 1.4, 0.22)
	if is_instance_valid(pillar):
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(pillar, "scale", Vector3(0.2, 0.2, 0.2), 0.22)
		tw.tween_property(pillar, "global_position", pillar.global_position + Vector3(0, 2.0, 0), 0.22)
		tw.chain().tween_callback(pillar.queue_free)


## 预警圈在爆开后放大一点再淡掉
func _flash_mark(mark: Node3D, grow: float, time: float) -> void:
	if not is_instance_valid(mark):
		return
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mark, "scale", mark.scale * grow, time)
	var mat: StandardMaterial3D = null
	if mark is MeshInstance3D:
		mat = (mark as MeshInstance3D).material_override as StandardMaterial3D
	if mat != null:
		tw.tween_property(mat, "albedo_color:a", 0.0, time)
	tw.chain().tween_callback(mark.queue_free)


## 一块平放的预警圆盘（半径用 scale 控制；y 抬高 4 cm 免得和台面打架）
func _make_disc(center: Vector3, radius: float, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 0.06
	mesh.radial_segments = 32
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = col
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled = true
	mat.emission = Color(col.r, col.g, col.b)
	mat.emission_energy_multiplier = 1.6
	mi.material_override = mat
	mi.scale = Vector3(radius, 1.0, radius)
	mi.global_position = center + Vector3(0.0, 0.04, 0.0)
	add_child(mi)
	_marks.append(mi)
	return mi


## 砸击用的光柱（8 m 长，底部落到落点上）
func _make_pillar(top_center: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.55
	mesh.bottom_radius = 0.85
	mesh.height = 8.0
	mesh.radial_segments = 24
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = SLAM_COL
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled = true
	mat.emission = Color(SLAM_COL.r, SLAM_COL.g, SLAM_COL.b)
	mat.emission_energy_multiplier = 1.8
	mi.material_override = mat
	mi.global_position = top_center
	add_child(mi)
	_marks.append(mi)
	return mi


## 落点高度 = 玩家脚底（`pc` 是身体中心 +0.9，减回去再让出一点点）
func _foot_y(pc_y: float) -> float:
	return pc_y - 0.85


## 范围伤害：只认水平距离 + 一个宽松的竖直带（人站在板上、被弹起来都算）
func _hit_area(center: Vector3, radius: float, dmg: float, knock: float) -> void:
	if _player == null:
		return
	var p := _player.global_position
	var flat := Vector2(p.x - center.x, p.z - center.z).length()
	if flat <= radius and absf(p.y - center.y) <= 3.2:
		_player.take_damage(dmg, center, knock)
		Sfx.play("ui_toggle", -4.0)


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


## 自检用：现在有几发炮弹在飞 / 一共打出过几发
func shell_count() -> int:
	return _shells.size()


func shots_fired() -> int:
	return _shots


## 自检用：当前有几个预警圈/光柱
func mark_count() -> int:
	return _marks.size()


## 自检用：技能表 / 上一次放的技能
func skill_count() -> int:
	return SKILL_COUNT


func skill_name(i: int) -> String:
	return SKILL_NAMES[i % SKILL_COUNT]


func last_skill() -> String:
	return _last_skill


func killed() -> bool:
	return _killed
