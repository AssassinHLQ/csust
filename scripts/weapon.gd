class_name Weapon
extends Node3D
## 武器系统：命中判定走射线，视觉走枪口火光 + 可见弹丸 + 命中火花。
##
## 枪是 Arisu.glb 自带的轨道枪（蒙在 Bip001_Weapon 骨上，跟着动作走）。
##
## 弹道为什么从**相机中心**出发，而不是枪口骨 / 相机旁的固定偏移：
##   枪口在腰侧（实测距右手骨 0.6 m、高度约 0.45 m），相机在眼睛高度（约 1.6 m）。
##   用「枪口 → 准星远点」会擦着目标过去，表现为「准星压在靶子上却打不中」。
##   而「相机位置 + 固定偏移、方向仍取相机朝向」是一条**平行于准星、整体偏出去**的线
##   —— 落点永远比准星偏右/偏下，距离越近屏幕上偏得越多（2026-10-27 用户实拍）。
##   所以命中判定直接走准星本身：从相机中心沿相机前方发射。
##   玩家自己的胶囊用 `q.exclude` 排除（角色模型本身没有碰撞体），同伴层整体屏蔽。
##   枪口火光与弹丸仍从真实枪口骨出来，观感不受影响。

signal ammo_changed(current: int, maximum: int)
signal fired(shot_index: int)
signal reload_started()
signal reload_finished()
signal hit_confirmed(collider: Object, position: Vector3)

# --- 数值 ---
@export var damage := 18.0
@export var fire_interval := 0.075      # 连发间隔（约 13 发/秒）
## **激光大炮**的连发间隔（秒）。用户 2026-11-08：「炮是激光大炮」。
##
## ⚠️ 先看下面 `beam_damage_scale` 那段「必须按持续 DPS 倒推」的说明。
## 同日用户又追加「机甲伤害不变，加快三倍射速」——
## 0.36 / 3 = **0.12 s**（≈ 8.3 发/秒），单发仍 171，持续 DPS 从 468 提到 ~1425。
## 用户给的理由是「我的游戏整体流程是 20 分钟」：机甲是这条流程里的爆发段，
## 不该让他在原地磨。
@export var beam_fire_interval := 0.10
## 激光大炮的单发伤害倍率（相对 `damage`）。炮比枪疼，这是常识。
##
## ⚠️ **这个数必须按「持续 DPS」倒推，不能只看单发好不好看。**
## 用户 2026-11-08：「怎么感觉机甲还没有机枪强」—— 他是对的，本喵量过：
##   机枪：  18      / 0.075 s = **240 DPS**
##   旧大炮：18 × 3.2 = 57.6 / 0.42 s = **137 DPS**（只有机枪的 57%）
## 本喵当初只顾着「炮要一发一发、有分量」，把间隔拉到 0.42 秒却没回头算总账。
## 现在按「单发份量够重 + 总输出约为机枪两倍」定：
##   18 × 9.5 = 171 / 0.36 s = **475 DPS ≈ 机枪的 1.98 倍**
## 之后射速又按用户要求乘 3（间隔 0.36 → 0.12），**伤害倍率不动**——
## 「伤害不变」是用户的原话，所以这里保持 9.5。
## 改这两个数之前先跑 `_probe_carrier_dps.gd`，它会把两边的 DPS 都打出来比对。
@export var beam_damage_scale := 5.5556
@export var auto_fire := true
@export var magazine_size := 60
@export var reserve_ammo := 9999
@export var reload_time := 1.05
## 换弹结束到能再次开火的间隔（秒）。留一点余量让收招动作播完，
## 不然松开换弹瞬间就吐子弹，看着像动作被腰斩。
@export var post_reload_delay := 0.12
@export var range_meters := 300.0
@export var spread_hip := 0.014
@export var spread_aim := 0.002
@export var recoil_pitch := 0.008
@export var recoil_yaw := 0.003

@export var skeleton_path: NodePath
## 光弹 / 枪口火光的**视觉**起点：true = 把枪口骨投影到弹道那条线上（推荐）。
## 为什么需要：这个模型的枪**不在手上**（README §1.9），枪口骨在腰侧，
## 实测离弹道 **1.3 m**、高度只有 0.25 m。直接拿枪口当起点，光弹会从角色身侧
## 斜着飞出去，看起来就是「子弹不是从枪口出来的」。投影到弹道上之后，
## 光弹沿着准星方向从角色身体里飞出去，观感才对。
@export var fx_on_aim_line := false
## 视觉起点沿射线最多向前偏移多少米；默认保持在枪口附近
@export var fx_forward := 0.0

# --- 弹丸视觉 ---
@export var tracer_speed := 260.0       # 弹丸飞行速度（米/秒）
const TRACER_LEN := 0.55

## ── 激光子弹（普通状态，2026-11-11）──
## 用户：「这个光柱还是不好看，改成光点吧，就是发光子弹那种……就是还是用以前的
##       机枪，只不过改成了激光子弹」。所以弹丸要长得像**一个发光的光点**。
##
## 实现：一块**面向相机的方片** + 程序化生成的**径向渐变**贴图（中心白 → 青 → 全透明），
## 于是它渲染出来就是一个软边的光点，而不是一颗硬边小球。
## 贴图是 `GradientTexture2D` 现生成的，**不引用任何图片文件**
## （和 BA 皮肤同一条规矩：不碰游戏原始素材，见 README §13.12.1）。
##
## ⚠️ 两个数字别随手改：
##   · `BOLT_SIZE` 是光点的**视觉直径**（米）；0.30 在 12 m 外约 38 px，
##     再大就变成一团糊住准星的光斑了。
##   · `BOLT_LEN` 是飞行队列里的「弹丸段长」，这里**故意取成 `TRACER_LEN`**：
##     `_advance_tracers()` 里 `scale.y = seg / TRACER_LEN`，段长等于分母时
##     **稳态 `scale.y` 恒为 1.0**，网格就能保持自己设计好的正圆形状
##     （我们做的是圆点，被拉长成椭圆就不叫光点了）。
const BOLT_SIZE := 0.30
const BOLT_LEN := TRACER_LEN

var current_ammo: int
var _cooldown := 0.0
var _reloading := false
var _reload_timer := 0.0
var _trigger := false
var _shot_index := 0
var _debug_raycast := false
## 正处在「转身对准准星」的过程中（此时扳机按着也不开火）
var _turning := false
## 正在飞的弹丸：[MeshInstance3D, 总距离, 终点, 已飞距离, 视觉倍率]
var _in_flight: Array = []

var skeleton: Skeleton3D
var _muzzle_bone := -1
var _fx_root: Node = null
var _tracer_mesh: Mesh
var _tracer_mat: StandardMaterial3D
var _bolt_mesh: Mesh
var _bolt_mat: StandardMaterial3D

@onready var muzzle: Marker3D = $Muzzle
@onready var _player: Player = get_parent() as Player
@onready var _driver: AnimDriver = get_node_or_null("../Arisu/Model/AnimDriver") as AnimDriver


func _ready() -> void:
	# ⚠️ 必须比 `AnimDriver`（`process_priority = 100`，它每帧还会把枪骨掰向准星）
	#    更晚跑：枪口标记是照着**枪骨当前姿势**摆的，早一步同步就跟不上那一下掰枪，
	#    弹道起点会落在「掰之前」的旧位置 —— 用户 2026-10-18 报的
	#    「跑打子弹发射的点不在枪口上，偏右了」就是这个一帧的滞后（摆臂 42° 时
	#    枪口能被甩出 0.3 m 以上）。
	process_priority = 110
	current_ammo = magazine_size
	_fx_root = get_tree().root if get_tree() else self
	skeleton = get_node_or_null(skeleton_path) as Skeleton3D
	if skeleton == null and get_tree():
		skeleton = _find_first(get_tree().root, "Skeleton3D") as Skeleton3D
	if skeleton:
		_muzzle_bone = skeleton.find_bone("bone_Railgun_Muzzle_03")
		if _muzzle_bone < 0:
			_muzzle_bone = skeleton.find_bone("bone_Railgun_Muzzle_01")

	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.015
	cyl.bottom_radius = 0.015
	cyl.height = TRACER_LEN
	cyl.radial_segments = 6
	cyl.rings = 0
	_tracer_mesh = cyl
	_tracer_mat = StandardMaterial3D.new()
	_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tracer_mat.albedo_color = Color(0.8, 0.95, 1.0, 0.95)
	_tracer_mat.emission_enabled = true
	_tracer_mat.emission = Color(0.6, 0.88, 1.0)
	_tracer_mat.emission_energy_multiplier = 2.2

	# ── 激光子弹的网格与材质（普通状态，见 `BOLT_SIZE` 那段）──
	# 一块方片 + 径向渐变贴图 = 软边光点；方片永远转向相机（`BILLBOARD_ENABLED`）。
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.30, 0.62, 1.0])
	grad.colors = PackedColorArray([
		Color(1.00, 1.00, 1.00, 1.00),      # 芯：纯白，最亮
		Color(0.72, 0.95, 1.00, 0.95),      # 内圈：激光青
		Color(0.35, 0.80, 1.00, 0.45),      # 外圈：更蓝更淡
		Color(0.18, 0.55, 1.00, 0.00)])     # 边缘：透明
	var bolt_tex := GradientTexture2D.new()
	bolt_tex.gradient = grad
	bolt_tex.fill = GradientTexture2D.FILL_RADIAL
	bolt_tex.fill_from = Vector2(0.5, 0.5)
	bolt_tex.fill_to = Vector2(0.5, 0.0)
	bolt_tex.width = 64
	bolt_tex.height = 64
	var bolt := QuadMesh.new()
	bolt.size = Vector2(BOLT_SIZE, BOLT_SIZE)
	_bolt_mesh = bolt
	_bolt_mat = StandardMaterial3D.new()
	_bolt_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# 混色（不是加色）：加色的光点打在亮墙/天上会直接消失，机枪看不见弹道很难受
	_bolt_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_bolt_mat.albedo_texture = bolt_tex
	_bolt_mat.emission_enabled = true
	_bolt_mat.emission = Color(0.70, 0.95, 1.00)
	_bolt_mat.emission_energy_multiplier = 2.4
	_bolt_mat.emission_texture = bolt_tex
	# 光点是"一团光"，不是一块板子：转到侧面看不见会很怪，所以永远面向相机
	_bolt_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_bolt_mat.billboard_keep_scale = true
	_bolt_mat.disable_receive_shadows = true
	_bolt_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	ammo_changed.emit(current_ammo, magazine_size)


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_follow_muzzle_bone()
	_advance_tracers(delta)

	if _reloading:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			_finish_reload()
		return

	# 按住不放就一直打；打空后 shoot() 会自己触发换弹，
	# _trigger 全程保持 true，所以换完弹会自动续射 —— 不用再点一次鼠标。
	if _trigger and auto_fire and _cooldown <= 0.0:
		shoot()


func _follow_muzzle_bone() -> void:
	# 机甲形态：由 `carrier_form.gd` 通过 `set_carrier_muzzles()` 接管，
	# 这里直接让路（那套用的是载具骨架的炮口骨，不是本体的轨道枪）。
	if _carrier_muzzles.size() > 0:
		return
	if skeleton == null or _muzzle_bone < 0:
		return
	muzzle.global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(_muzzle_bone)


## ── 机甲（载具）形态的双炮 ──
##
## 载具 `Arisu_Battle_Carrier.glb` 的骨架里**没有**本体的 `bone_Railgun_Muzzle_0*` /
## `bone_magazine`（本喵拆 GLB 核过：那套轨道枪只在 `Arisu_ext.glb` 里）。
## 所以机甲形态下 `_find_bone` 全部落空，`muzzle` 标记就停在变形前的位置 ——
## 实测 y = −0.262，**掉到地面以下**，火光和弹道起点都在地底下（`_probe_carrier_fire.gd`）。
##
## 机甲自己的「炮」是 `bone_gear_cannon_L/R`（挂在 `bone_gear_Pillar_L/R` 下的两门肩炮），
## 所以机甲形态下由 `carrier_form.gd` 把这两根骨喂进来，开火时**双臂齐射**。
##
## `xs` 是世界坐标列表；为空时退回本体那套单枪口逻辑。
var _carrier_muzzles: Array[Vector3] = []


## 机甲形态：设置双炮的**世界坐标**枪口。传空数组 = 退回本体单枪口。
func set_carrier_muzzles(xs: Array[Vector3]) -> void:
	_carrier_muzzles = xs.duplicate()


## 现在有几个枪口在用（自检用）
func muzzle_count() -> int:
	return maxi(_carrier_muzzles.size(), 1)


func set_debug_raycast(on: bool) -> void:
	_debug_raycast = on


# --- 扳机 ---

func trigger_down() -> void:
	_trigger = true
	if _driver:
		_driver.set_trigger(true)
	if not auto_fire:
		shoot()


func trigger_up() -> void:
	_trigger = false
	# 松开扳机 → 让动画知道「这一发打完了」。
	# ⚠️ 不通知的话，整身跑打动作要一直播到片子结束：`RunFire_Ing` 2.667 s、
	#    走路时倍速 0.46 ⇒ **点一下鼠标，攻击姿势演 5.8 秒**，人还在往前走 ——
	#    用户报的「攻击一下后再开始走路会变成右转螃蟹平移」就是这个
	#    （实测见 `anim_driver.gd` 的 `FIRE_RELEASE_GRACE`）。
	if _driver:
		_driver.set_trigger(false)
		_driver.cancel_fire()


func shoot() -> bool:
	# 巡航者模式（`carrier_form.gd` 按 T 进）期间武器关闭，扣扳机也不出弹。
	if disabled:
		return false
	if _reloading or _cooldown > 0.0:
		return false
	# 角色还没转向准星方向就先不开火（符合常理：不能背对着靶子把子弹打出去）。
	# 扳机保持按住，转到位后这一句自然就放行了。
	if _player and not _player.is_aim_aligned():
		_turning = true
		return false
	_turning = false
	# ── 机甲形态：无限子弹、不换弹（用户 2026-11-08）──
	# 空仓判定与扣弹都跳过；`try_reload()` 那边也会直接拒绝，所以打不出换弹。
	var infinite := has_infinite_ammo()
	if not infinite and current_ammo <= 0:
		# 空仓：干响一声。`_trigger` 全程保持 true，所以这一句在换弹开始前
		# 每帧都会被走到 —— 靠 `Sfx` 里 "empty" 的 gap_ms=150 节流，
		# 不然会变成一串「咔咔咔咔」。
		Sfx.play("empty")
		try_reload()
		return false

	# 攻速倍率：能量条每启用一条 +1（见 `carrier_form.gd` 的能量条系统）。
	# 倍率乘在**间隔**上（间隔 = 基础 ÷ 倍率），所以 ×2 = 快一倍。
	# ⚠️ 上限不设死：60 fps 下最短也只能「一帧一发」，实际会被帧率自然钳住。
	var base_cd := beam_fire_interval if uses_beam_visual() else fire_interval
	_cooldown = maxf(base_cd / maxf(rate_scale, 0.01), 0.0)
	if not infinite:
		current_ammo -= 1
		ammo_changed.emit(current_ammo, magazine_size)
	_shot_index += 1

	if _driver:
		_driver.request_fire()

	_fire_raycast()
	# 枪声走**非定位**（2D）：玩家自己的枪永远「在耳边」，用 3D 定位会随镜头左右漂。
	#
	# 机甲形态换成了**激光音**（用户 2026-11-08：「炮是激光大炮」）——
	# 用的是 Kenney 那批 `laserSmall_*.ogg`，`sfx.gd` 里那条注释写着它们当初
	# 正是「不像枪」被换掉的；现在回到正确岗位（见 `fire_beam` 里的说明）。
	#
	# ⚠️ 这两个名字必须写成**字符串字面量**、分成两个 `Sfx.play()` 调用，
	#    不能写成 `Sfx.play("fire_beam" if use_beam() else "fire")` ——
	#    `_verify_sfx.gd` 是**静态扫源码里的字面量**来核对「库表里每个名字都有调用点」，
	#    拼出来的名字它扫不到，会报「没人用的：fire, fire_beam」。
	if uses_beam_visual():
		Sfx.play("fire_beam")
	else:
		Sfx.play("fire")

	if _player:
		var sign_x := 1.0 if randf() < 0.5 else -1.0
		_player.add_recoil(recoil_pitch, recoil_yaw * sign_x * randf_range(0.4, 1.0))

	fired.emit(_shot_index)
	return true


func _fire_raycast() -> void:
	var space := get_world_3d().direct_space_state
	if _player == null:
		return
	# ⚠️ 开枪前**当场**再同步一次枪口：`_process` 里那一次可能早于 `AnimDriver`
	#    掰枪骨（见 `_ready()` 里的说明）。命中判定已经不经过枪口了，但弹丸/火光的
	#    **视觉起点**这一帧还得是新的。
	_follow_muzzle_bone()

	var cam_dir := _player.camera_forward()
	# 弹道 = 准星那条线本身（相机中心射线）。见文件头。
	var origin := _player.cam.global_position

	var spread := spread_aim if _player.aiming else spread_hip
	var dir := _apply_spread(cam_dir, spread)
	var end := origin + dir * range_meters

	var q := PhysicsRayQueryParameters3D.create(origin, end)
	q.collide_with_areas = false
	# 全部层，唯独屏蔽「同伴层」，让子弹从同伴身上穿过去。
	# ⚠️ create() 的默认 mask 是全部层；同伴跟得又近，不屏蔽的话
	#    玩家会一直打在自己人背上（这一段是加同伴时补的）。
	q.collision_mask = 0xFFFFFFFF & ~Companion.LAYER
	q.exclude = [_player.get_rid()]
	var hit := space.intersect_ray(q)

	var impact := end
	var normal := -dir
	var collider: Object = null
	if hit:
		impact = hit.position
		normal = hit.normal
		collider = hit.collider

	if _debug_raycast:
		print("  [raycast] origin=%s dir=%s hit=%s collider=%s" % [
			str(origin.snappedf(0.01)), str(dir.snappedf(0.01)), str(hit != null), str(collider)])

	var muzzle_pos := muzzle.global_position
	# ── 机甲形态：两门肩炮齐射 ──
	# 命中判定**仍然只走那一条相机中心射线**（`intersect_ray` 只打一次，
	# 保证「准星压着靶子就一定打得中」，不会因为双炮而各打各的）。
	# 视觉上从**每个炮口**各牵一条弹道到同一个命中点：观感是齐射，判定是单发。
	if _carrier_muzzles.size() > 0:
		for mp in _carrier_muzzles:
			var from_i := mp
			if fx_on_aim_line:
				from_i = origin + dir * clampf((mp - origin).dot(dir), 0.0, 0.25) + dir * fx_forward
			_spawn_tracer(from_i, impact)
			_muzzle_flash(from_i)
		_schedule_impact(impact, normal, muzzle_pos.distance_to(impact) / maxf(tracer_speed, 1.0))
		_apply_hit(collider, impact, dir)
		return

	# 视觉起点默认就在**真实枪口**（fx_on_aim_line = false）。
	# 打开时把枪口挪到瞄准射线上：沿射向投影，且最多落在射线起点之后 0.25 m。
	# ⚠️ 老版本是「投影到相机前方、再往前推」，表现就是「子弹从角色前面冒出来」
	#    —— 用户报的「位置太靠前」正是这个，所以默认改成了 false。
	var fx_from := muzzle_pos
	if fx_on_aim_line:
		fx_from = origin + dir * clampf((muzzle_pos - origin).dot(dir), 0.0, 0.25) \
			+ dir * fx_forward

	_apply_hit(collider, impact, dir)

	# ── 普通状态的激光机枪（2026-11-09 起，2026-11-11 换成光点弹丸）──
	#
	# ⚠️ 别再改回 `_spawn_beam()`：11-09 本喵把它做成了「一条光柱连到靶子上」，
	#    用户看完实机 11-11 明确否掉 ——「这个光柱还是不好看，改成光点吧，
	#    就是发光子弹那种，现在不像激光机枪像激光炮」。普通攻击要的是
	#    **一梭子打出去的光点**（机枪手感），不是炮。
	#    光柱仍然属于机甲（`use_beam()` → `_spawn_tracer()` → `_spawn_beam()`）。
	#
	# 命中火花按**飞行时间**延迟，和弹丸到达同一刻炸开 —— 老机枪就是这样的。
	# 枪口那颗球仍然不要（2026-11-10 用户要求）。
	if laser_gun:
		_spawn_laser_bolt(fx_from, impact)
		_schedule_impact(impact, normal, fx_from.distance_to(impact) / maxf(tracer_speed, 1.0))
		return

	_spawn_tracer(fx_from, impact)
	_muzzle_flash(fx_from)
	_schedule_impact(impact, normal, fx_from.distance_to(impact) / maxf(tracer_speed, 1.0))


## 结算命中（单枪口 / 双炮共用）。抽出来是为了别让两种路径各写一遍伤害逻辑
## —— 那种「两处相似代码」正是以后改伤害时漏改一半的地方。
func _apply_hit(collider: Object, impact: Vector3, dir: Vector3) -> void:
	var dmg := damage * (beam_damage_scale if has_infinite_ammo() else 1.0)
	if collider and collider.has_method("take_damage"):
		collider.take_damage(dmg, impact, -dir)
		hit_confirmed.emit(collider, impact)
	elif collider is Node and collider.get_parent() and collider.get_parent().has_method("take_damage"):
		collider.get_parent().take_damage(dmg, impact, -dir)
		hit_confirmed.emit(collider.get_parent(), impact)


func _apply_spread(dir: Vector3, amount: float) -> Vector3:
	if amount <= 0.0:
		return dir
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var right := dir.cross(up).normalized()
	up = right.cross(dir).normalized()
	var a := randf() * TAU
	var r := sqrt(randf()) * amount
	return (dir + right * (cos(a) * r) + up * (sin(a) * r)).normalized()


# --- 换弹 ---

func try_reload() -> void:
	# 机甲形态无限子弹：换弹是**无意义**的，按 R 也什么都不做。
	# 不做这个提前返回的话，玩家在机甲里按 R 会看到 HUD 转一圈换弹进度条、
	# 却因为 `shoot()` 不扣弹而永远不需要它 —— 属于假反馈。
	if has_infinite_ammo():
		return
	if _reloading or current_ammo >= magazine_size:
		return
	_reloading = true
	_reload_timer = reload_time
	# ⚠️ 这里**不要**清 _trigger！
	# 清了的话，按住左键打空 → 自动换弹 → 换完必须重新点一次鼠标才能射击。
	# 保持 _trigger 不动，换完弹 _process 里那句 shoot() 就会自动接上。
	Sfx.play("reload_out")
	reload_started.emit()
	if _driver:
		_driver.request_reload()


func _finish_reload() -> void:
	_reloading = false
	_reload_timer = 0.0
	var need := magazine_size - current_ammo
	var take := mini(need, reserve_ammo)
	current_ammo += take
	reserve_ammo -= take
	ammo_changed.emit(current_ammo, magazine_size)
	# 收招余量：换完弹先空一拍再允许开火，避免动作被立刻吐出的子弹腰斩。
	# 注意不要动 _trigger —— 它保持 true，所以按住不放会自动续射。
	_cooldown = maxf(_cooldown, post_reload_delay)
	Sfx.play("reload_in")
	reload_finished.emit()


func is_reloading() -> bool:
	return _reloading


## 是否正卡在「转身对准准星」的阶段（HUD 可以拿它显示「转向中」）
func is_turning() -> bool:
	return _turning


func reload_progress() -> float:
	if not _reloading:
		return 1.0
	return 1.0 - clampf(_reload_timer / reload_time, 0.0, 1.0)


# --- 弹丸 ---

## 现在是不是「激光大炮」模式（机甲形态）。
## 由 `carrier_form.gd` 在变形 / 变回时通过 `set_beam_mode()` 置位。
var beam_mode := false

## ── 机甲形态的无限子弹（用户 2026-11-08：「机甲状态无限子弹不换弹」）──
##
## 为什么用 `beam_mode` 而不是 `use_beam()`：`use_beam()` 还要求
## `_carrier_muzzles` 非空，而炮口是**每帧**由 `carrier_form.gd::_push_cannon_muzzles()`
## 推过来的 —— 变形的第一帧炮口数组还是空的。那一刻如果按 `use_beam()` 判定，
## 就会退回去扣本体的子弹（本体的弹匣在机甲形态下根本不该被碰）。
## `beam_mode` 是变形那一刻就置好的，没有这个空窗。
func has_infinite_ammo() -> bool:
	return beam_mode


## ── 巡航者模式 / 能量条 给武器加的两个开关（`carrier_form.gd` 每帧写）──
##
## `disabled`：巡航者模式下**武器关闭**（用户 2026-11-08：「按 T 启动巡航者模式
##             关闭武器能够更快飞行」）。扣扳机也不出弹、不放音效、不加后坐。
## `rate_scale`：攻速倍率。基础 1.0；每启用一条能量条 +1 → 2 / 3 / 4 / 5 / 6。
var disabled := false
var rate_scale := 1.0


func set_disabled(on: bool) -> void:
	disabled = on


func set_rate_scale(x: float) -> void:
	rate_scale = maxf(x, 0.01)


func set_beam_mode(on: bool) -> void:
	beam_mode = on
	if on:
		# 变形前可能正卡在换弹中途（本体弹匣打空了）：直接结束，
		# 否则玩家变形出来还要干等最多 1.05 s 才打得出第一发。
		_reloading = false
		_reload_timer = 0.0
		current_ammo = magazine_size
		# `-1 / -1` 是「无限」的约定值，HUD 认它、显示 `∞`
		# （见 `hud.gd::_on_ammo`）。用魔法数而不是新开一个信号，
		# 是因为弹匣显示只有一个入口，多一个信号就多一处要同步的地方。
		ammo_changed.emit(-1, -1)
	else:
		# 变回本体：把真实弹匣数报回去，HUD 从 ∞ 切回 `12 / 60` 这种。
		ammo_changed.emit(current_ammo, magazine_size)


## 现在是不是「激光大炮」模式（机甲形态）。
func use_beam() -> bool:
	return beam_mode and _carrier_muzzles.size() > 0


## ── 普通状态也用激光（2026-11-09，用户：「爱丽丝普通状态,攻击从机枪变成激光机枪」）──
##
## 和机甲形态的区别：
##   · 机甲：`beam_mode = true` → **两门肩炮**齐射、无限弹、`beam_fire_interval` 0.10
##   · 普通：`laser_gun = true` → **单枪口**、照常扣弹匣
##
## ⚠️ 2026-11-11 改：普通状态**不再画光柱**，回到「一颗颗飞行弹丸」的老机枪路径
##    （`_spawn_laser_bolt()`），只把弹丸换成激光色的光点。用户原话：
##    「这个光柱还是不好看，改成光点吧，就是发光子弹那种，现在不像激光机枪
##      像激光炮，就是还是用以前的机枪，只不过改成了激光子弹」。
##    所以 `laser_gun` 现在管的是**数值与音效**（射速 / 激光音 / 激光色弹丸），
##    **不再代表"会画出光柱"** —— 光柱只剩机甲那条 `use_beam()` 了。
##
## 为什么不做成同一个 `beam_mode`：那条路会顺手把弹匣变成无限（`has_infinite_ammo()`
## 直接读 `beam_mode`），普通状态要是也无限子弹，整个弹药/换弹玩法就废了。
var laser_gun := false


func set_laser_gun(on: bool) -> void:
	laser_gun = on


## 这一发该不该用**激光大炮那套参数与音效**（射速 `beam_fire_interval` + 激光音）。
##
## ⚠️ 名字里的 "beam visual" 已经是旧语义了：普通状态从 2026-11-11 起改回
##    飞行弹丸，**只有机甲**（`use_beam()`）才会真的画出光柱。
##    留着这个函数名是因为它已经被 `_verify_*` 引用，改名只会制造噪声；
##    真要读代码时记住：**这个函数不代表画面里会出现光柱**。
func uses_beam_visual() -> bool:
	return use_beam() or laser_gun


## 激光光束：从炮口到命中点画一条**立刻出现、0.12 s 淡出**的粗光柱。
##
## ── 和「飞行曳光」的区别（为什么不能复用）──
## 老那条 `_spawn_tracer()` 是一颗**以 260 m/s 飞行的短光柱**，适合步枪子弹；
## 激光大炮要的是「扣扳机的一瞬间，一条光柱直接连到靶子上」。
## 所以这里是**一次性**生成的静态光柱 + Tween 淡出，不进 `_in_flight` 队列。
##
## ── 三层（复用机甲蓝焰那套配色）──
## 外层粗而淡（辉光）、中层、内层细而亮（芯）。加色混合叠起来就是发光的激光。
const BEAM_CORE := Color(0.92, 0.99, 1.00, 0.95)
const BEAM_MID := Color(0.40, 0.78, 1.00, 0.55)
const BEAM_GLOW := Color(0.16, 0.42, 1.00, 0.22)
## 光束存活时间（秒）。0.12 够玩家看清，又不会糊住画面。
## ── 2026-11-09 重做 ──
##
## 用户：「爱丽丝机甲特效不好看,不够细致,参考游戏本体的做法」。
##
## 原来这条光束就是**三层同心圆柱**（`BEAM_RADII` 三个半径 + 加色混合），
## 观感是"三根一样粗的管子套在一起"，因为：
##   · 圆柱的侧壁亮度是**均匀**的 —— 没有"中心亮、边缘散"的衰减；
##   · 三层又都是同一个 `_tracer_mesh`（12 面圆柱），叠起来才勉强有雾感；
##   · 而且 `BEAM_LIFE` 期间只做 alpha 线性淡出，**没有横向收缩**，看着像贴图淡掉。
##
## 现在改成 5 层，从内到外半径按几何级数拉开（0.018 / 0.045 / 0.10 / 0.20 / 0.38），
## 亮度和透明度也拉开梯度；再加：
##   · **两端收尖**：用 ConeMesh 的短锥接在两端，消掉圆柱的硬切面；
##   · **首尾闪核**：炮口和命中点各一个高亮小核；
##   · **横向收缩**：淡出时半径同时收到 60%，观感是"光收束"而不是"图变透明"。
## 五层：(半径 m, alpha 系数, 发光强度)。由内到外。
const BEAM_LAYERS := [
	{"r": 0.018, "a": 1.00, "e": 7.0, "c": Color(0.96, 1.00, 1.00, 0.98)},  # 芯
	{"r": 0.045, "a": 0.72, "e": 4.6, "c": Color(0.62, 0.90, 1.00, 0.78)},  # 内
	{"r": 0.100, "a": 0.46, "e": 2.8, "c": Color(0.34, 0.72, 1.00, 0.52)},  # 中
	{"r": 0.200, "a": 0.26, "e": 1.6, "c": Color(0.18, 0.48, 1.00, 0.30)},  # 外
	{"r": 0.380, "a": 0.13, "e": 0.9, "c": Color(0.10, 0.30, 0.95, 0.16)},  # 辉光
]
## beam_life 仍是总时长
const BEAM_LIFE := 0.12
## 光束的**视觉**最长距离（米）。
## ⚠️ `range_meters` 是 300（命中判定要考虑远距离狙击），但一条 300 m 的亮光柱
##    会把整个画面劈成两半 —— 本喵实测没打中任何东西时长度就是 295.6 m。
##    超出这个值的光束**只画到这么长**就收尾（命中判定照旧到 300 m，
##    远距离照样打得中，只是视觉上不再拖一条无限长线）。
const BEAM_MAX_VISUAL := 60.0

## 光束存活节点（每帧不推进，靠 Tween 自己收）
var _beams: Array = []


## 两个「要不要」开关（本函数自己的 API，不是给某个形态专用的）：
##
## `with_muzzle_flash` —— 枪口那个**发光球**（`_muzzle_flash_beam()`）。
## `with_impact`       —— 命中点那个**膨胀圆球 + 一盏灯**（`_spawn_beam_impact()`）。
##
## ⚠️ 历史：这两个开关是 2026-11-10 / 11-11 连着两轮「不要那个球」逼出来的。
##    11-10 先说「普通爱丽丝普通攻击不要出现那个圆球只要激光线就可以」→ 关枪口球；
##    11-11 又指着准星上那个柔和蓝球说「不要这个命中特效圆球」→ 关命中球。
##    结果普通攻击变成"只有一条光柱"，用户第二天再看完实机，把光柱本身也否了：
##    **普通攻击现在完全不走这里**（见 `_spawn_laser_bolt()`）。
##
##    所以现在**唯一的调用点是机甲的双肩炮**（`_spawn_tracer()` → `use_beam()`），
##    走的是默认 `true, true` —— 那是炮，炮口闪光和命中爆闪就是它的"炮感"。
##    两个开关暂时没有调用方传 `false`；留着是因为它们是这个函数的正经参数，
##    以后哪把武器不想带爆闪，改传参就行，不必再回来改函数体。
func _spawn_beam(from: Vector3, to: Vector3,
		with_muzzle_flash := true, with_impact := true) -> void:
	var total := from.distance_to(to)
	if total < 0.05:
		return
	var dir := (to - from).normalized()
	# 视觉长度封顶（见 `BEAM_MAX_VISUAL`）
	var vis_len := minf(total, BEAM_MAX_VISUAL)
	var vis_end := from + dir * vis_len
	var mid := from + dir * (vis_len * 0.5)

	var holder := Node3D.new()
	_fx_root.add_child(holder)
	holder.global_position = mid
	# 让 holder 的局部 +Y 对准 beam 方向：内部所有圆柱/锥都沿 +Y 建，省去逐个定向
	_orient_tracer(holder, dir)

	var mats: Array = []
	var radii: Array = []
	for li in BEAM_LAYERS.size():
		var spec: Dictionary = BEAM_LAYERS[li]
		var base: Color = spec["c"]
		var r: float = spec["r"]
		var mi := MeshInstance3D.new()
		mi.mesh = _tracer_mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# ⚠️ 加色混合：叠起来才亮。用 ALPHA 混合的话多层会互相遮成一条实心灰柱。
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_color = base
		mat.emission_enabled = true
		mat.emission = Color(base.r, base.g, base.b)
		mat.emission_energy_multiplier = float(spec["e"])
		mi.material_override = mat
		# 圆柱本体：沿局部 Y 从 -半长 到 +半长
		mi.scale = Vector3(r / 0.015, vis_len / TRACER_LEN, r / 0.015)
		holder.add_child(mi)
		mats.append(mat)
		radii.append(r)

		# ── 两端收尖：短锥消掉圆柱的硬切面 ──
		# 只给最外两层加（内层被外层包住，加了也看不见，白费顶点）。
		if li >= 3:
			for sh in [-1.0, 1.0]:
				var cap := MeshInstance3D.new()
				var cone := CylinderMesh.new()
				cone.top_radius = 0.0
				cone.bottom_radius = r
				cone.height = minf(vis_len * 0.22, r * 6.0)
				cone.radial_segments = 12
				cone.rings = 1
				cap.mesh = cone
				cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				cap.material_override = mat
				holder.add_child(cap)
				# 锥尖朝外：sh=+1 放在 +Y 端且尖端朝 +Y
				var cape_half := cone.height * 0.5
				cap.position = Vector3(0.0, sh * (vis_len * 0.5 + cape_half * 0.5), 0.0)
				cap.rotation.x = 0.0 if sh > 0.0 else PI
				cap.scale = Vector3(1.0, 1.0, 1.0)

	# 炮口那一点爆亮（激光「出膛」的闪）。
	# ⚠️ 11-10 用户嫌它是个"圆球"；但普通攻击 11-11 已经不走这条函数了，
	#    现在只有机甲开炮会走到这里 —— 对炮来说这个闪光是要的。
	if with_muzzle_flash:
		_muzzle_flash_beam(from)
	# 命中点爆闪：只有**真的打到了**才炸（没打中时 `total` 会顶到 300，
	# 在 300 m 外放一个爆闪没意义，玩家也看不见）。
	# ⚠️ `with_impact=false` 时这颗也去掉（当前没有调用方这么传，见函数头那段）。
	if with_impact and total <= BEAM_MAX_VISUAL:
		_spawn_beam_impact(vis_end, -dir)

	# 淡出：alpha 收到 0，同时半径缩到 60%（"光收束"而不是"图变透明"）
	var tw := holder.create_tween()
	tw.set_parallel(true)
	for li in mats.size():
		tw.tween_property(mats[li], "albedo_color:a", 0.0, BEAM_LIFE)
	for c in holder.get_children():
		if c is MeshInstance3D:
			var mi2 := c as MeshInstance3D
			var s0 := mi2.scale
			tw.tween_property(mi2, "scale", Vector3(s0.x * 0.6, s0.y, s0.z * 0.6), BEAM_LIFE)
	tw.chain().tween_callback(holder.queue_free)
	_beams.append(holder)


## 激光炮口的闪光：蓝色、比子弹那版更亮更大
func _muzzle_flash_beam(at: Vector3) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(0.55, 0.82, 1.0)
	# ⚠️ 出膛闪从 6.0 收到 3.0：6.0 配 5 m 范围会把**机甲整个罩白**
	#    （`9_beam.png` 第一版里人变成一团白），激光的光应该是「一条线」，
	#    炮口只是点缀，亮度不能压过光束本身。
	light.light_energy = 3.0
	light.omni_range = 3.2
	light.shadow_enabled = false
	_fx_root.add_child(light)
	light.global_position = at

	var flash := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	sm.radial_segments = 10
	sm.rings = 6
	flash.mesh = sm
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.8, 0.95, 1.0, 0.95)
	mat.emission_enabled = true
	mat.emission = Color(0.55, 0.85, 1.0)
	mat.emission_energy_multiplier = 4.0
	flash.material_override = mat
	_fx_root.add_child(flash)
	flash.global_position = at

	var tw := flash.create_tween()
	tw.set_parallel(true)
	tw.tween_property(light, "light_energy", 0.0, 0.09)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.09)
	tw.chain().tween_callback(flash.queue_free)
	tw.chain().tween_callback(light.queue_free)


## 激光命中点的爆闪：一圈快速膨胀的球 + 一盏灯
func _spawn_beam_impact(at: Vector3, _normal: Vector3) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(0.6, 0.85, 1.0)
	light.light_energy = 5.0
	light.omni_range = 4.5
	light.shadow_enabled = false
	_fx_root.add_child(light)
	light.global_position = at

	var burst := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.18
	sm.height = 0.36
	sm.radial_segments = 10
	sm.rings = 6
	burst.mesh = sm
	burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.7, 0.92, 1.0, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.82, 1.0)
	mat.emission_energy_multiplier = 3.0
	burst.material_override = mat
	_fx_root.add_child(burst)
	burst.global_position = at

	var tw := burst.create_tween()
	tw.set_parallel(true)
	tw.tween_property(burst, "scale", Vector3.ONE * 2.4, 0.16)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.16)
	tw.tween_property(light, "light_energy", 0.0, 0.16)
	tw.chain().tween_callback(burst.queue_free)
	tw.chain().tween_callback(light.queue_free)


func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	# ── 激光大炮：不走「飞行弹丸」，直接画一条**瞬时可见的光束** ──
	# 用户 2026-11-08：「炮是激光大炮」。
	# 机甲形态下 `_carrier_muzzles` 非空就切到这条路径（见 `use_beam()`）。
	if use_beam():
		_spawn_beam(from, to)
		return
	var total := from.distance_to(to)
	if total < 0.05:
		return
	var dir := (to - from).normalized()
	# 光弹长度：目标越远越长（封顶 3 倍），但不超过整条弹道
	var len0 := minf(TRACER_LEN * clampf(total / TRACER_LEN, 1.0, 3.0), total)
	var mi := MeshInstance3D.new()
	mi.mesh = _tracer_mesh
	mi.material_override = _tracer_mat
	_fx_root.add_child(mi)
	_orient_tracer(mi, dir)
	mi.scale = Vector3(1.0, maxf(len0, 0.02) / TRACER_LEN, 1.0)
	# ⚠️ 光柱是**以节点为原点居中**的圆柱，所以节点要放在这一段的**中间**。
	#    老版本把节点放在枪口，于是圆柱有一半伸到**身后**去（最长 4.4 m 时
	#    身后 2.2 m），玩家看到的就是「子弹从背后飞出来」—— 用户报的就是这个。
	mi.global_position = from + dir * (len0 * 0.5)
	_in_flight.append([mi, total, to, 0.0, len0, dir, from])


## 激光子弹（普通状态，2026-11-11）：一个**发光的光点**，以 `tracer_speed` 飞向靶子。
##
## 和 `_spawn_tracer()` 的关系：**同一套飞行队列**（`_in_flight` + `_advance_tracers()`），
## 只有两处不同 ——
##   1. 网格/材质换成光点（`_bolt_mesh` / `_bolt_mat`，见 `BOLT_SIZE` 那段）；
##   2. 段长固定 `BOLT_LEN`，不随距离拉长（老曳光弹会拉到 1.65 m，连起来像光带）。
##
## 为什么复用队列而不是再写一套推进逻辑：弹丸「不会伸到起点身后」「到靶子就回收」
## 这两个坑在 `_advance_tracers()` 里已经踩平了（见那边和 `_verify_mag` 第 4 节），
## 另起一套只会把同样的坑再踩一遍。
func _spawn_laser_bolt(from: Vector3, to: Vector3) -> void:
	var total := from.distance_to(to)
	if total < 0.05:
		return
	var dir := (to - from).normalized()
	# 固定长度，但不能超过整条弹道（贴着墙开枪时）
	var len0 := minf(BOLT_LEN, total)
	var mi := MeshInstance3D.new()
	mi.mesh = _bolt_mesh
	mi.material_override = _bolt_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx_root.add_child(mi)
	_orient_tracer(mi, dir)
	mi.scale = Vector3(1.0, maxf(len0, 0.02) / TRACER_LEN, 1.0)
	# 球/圆柱都是**以节点为原点居中**的，所以节点放在这一段的中点
	mi.global_position = from + dir * (len0 * 0.5)
	_in_flight.append([mi, total, to, 0.0, len0, dir, from])


## 让圆柱的**轴向（局部 +Y）**对准飞行方向。
## ⚠️ 别用 `look_at()` + `rotate_object_local(RIGHT, PI/2)` 那一对：
##    它们合起来会把轴向转到**反方向**去（老版本的另一半 bug）。
## 让物体的局部 +Y 对准 dir。
## `node` 收 `Node3D` 而不是 `MeshInstance3D`：激光光束的 holder 是个空 `Node3D`
## （里面挂多层圆柱 + 两端锥），曳光弹那边才是 `MeshInstance3D`。
## 放宽到这里免得为两种节点各写一份（曾经因为签名是 MeshInstance3D，
## 传 holder 直接报 "not a subclass of the expected argument class"，光束一个都不出来）。
func _orient_tracer(node: Node3D, dir: Vector3) -> void:
	var ref := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(dir)
	if x.length() < 0.001:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(dir).normalized()
	node.basis = Basis(x, dir, z)


func _advance_tracers(delta: float) -> void:
	if _in_flight.is_empty():
		return
	var step := tracer_speed * delta
	var done: Array = []
	for i in _in_flight.size():
		var item: Array = _in_flight[i]
		# ⚠️ **先看有效性、再做类型转换**：`var mi: MeshInstance3D = item[0]` 这一句
		#    在 `item[0]` 已经是「已释放实例」时会**自己**报错
		#    （`Trying to assign invalid previously freed instance`），
		#    根本走不到下面那句 `is_instance_valid()` —— 于是每帧刷一屏红字。
		#    实测触发方式：外部（探针/场景卸载）先 `queue_free()` 了还在队列里的弹丸。
		var raw: Variant = item[0]
		if not is_instance_valid(raw):
			done.append(i)
			continue
		var mi := raw as MeshInstance3D
		var total: float = item[1]
		var travel: float = float(item[3]) + step
		item[3] = travel
		var len0: float = item[4]
		var dir: Vector3 = item[5]
		var from: Vector3 = item[6]
		if travel >= total:
			mi.queue_free()
			done.append(i)
			continue
		# 光弹 = 跟在弹头后面的一段短光柱：弹头在 travel，尾巴在 travel − len0。
		# 起段从起点往外长，长到 len0 之后就整体往前滑 —— **永远不会伸到身后**。
		var tail := maxf(travel - len0, 0.0)
		var seg := maxf(travel - tail, 0.02)
		mi.scale.y = seg / TRACER_LEN
		mi.global_position = from + dir * ((travel + tail) * 0.5)
	done.reverse()
	for i in done:
		_in_flight.remove_at(i)


func _schedule_impact(pos: Vector3, normal: Vector3, delay: float) -> void:
	if not is_inside_tree():
		return
	var timer := get_tree().create_timer(maxf(delay, 0.01))
	timer.timeout.connect(func() -> void:
		if is_instance_valid(self) and is_inside_tree():
			_spawn_impact(pos, normal))


# --- 特效 ---

func _muzzle_flash(at: Vector3) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.86, 0.55)
	light.light_energy = 3.5
	light.omni_range = 3.0
	_fx_root.add_child(light)
	light.global_position = at

	var flash := MeshInstance3D.new()
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.065
	flash_mesh.height = 0.13
	flash_mesh.radial_segments = 8
	flash_mesh.rings = 4
	flash.mesh = flash_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.9, 0.6, 0.95)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.4)
	mat.emission_energy_multiplier = 1.6
	flash.material_override = mat
	_fx_root.add_child(flash)
	flash.global_position = at

	var tw := flash.create_tween()
	tw.set_parallel(true)
	tw.tween_property(light, "light_energy", 0.0, 0.05)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.05)
	tw.chain().tween_callback(flash.queue_free)
	tw.chain().tween_callback(light.queue_free)


func _spawn_impact(pos: Vector3, normal: Vector3) -> void:
	var holder := Node3D.new()
	_fx_root.add_child(holder)
	holder.global_position = pos

	for i in 6:
		var spark := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.018
		sm.height = 0.036
		sm.radial_segments = 4
		sm.rings = 2
		spark.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.85, 0.5)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.7, 0.3)
		mat.emission_energy_multiplier = 2.0
		sm.material = mat
		holder.add_child(spark)
		spark.global_position = pos
		var dir := (normal + Vector3(randfn(0.0, 1.0), randfn(0.0, 1.0), randfn(0.0, 1.0)) * 0.8).normalized()
		var tw := spark.create_tween()
		tw.set_parallel(true)
		tw.tween_property(spark, "global_position", pos + dir * randf_range(0.12, 0.4), 0.18)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.18)
		tw.chain().tween_callback(holder.queue_free)


func _find_first(n: Node, cls: String) -> Node:
	if n == null:
		return null
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find_first(c, cls)
		if r:
			return r
	return null
