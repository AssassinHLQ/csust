extends Node3D
## 阿比·埃舒（**载具形态 / 飞行形态**）：按 G 在「爱丽丝本体」和「载具」之间变形；
## 载具形态下按空格（或 Q）起落、按住 Shift 加力。
##
## 用户 2026-11-05：在第二场景**花钱找凯伊改装**之后要能真的用上。
## 用户 2026-11-07：「需要飞的爱丽丝机甲，灵活起落，喷气与蓝色火焰推进」——
##   所以本文件从「只能走路的载具」升级成「会飞的机甲」：
##   · 空格 / Q 起落（带缓升缓降和一键落地）
##   · 喷气（粒子）+ 蓝色火焰（多层发光锥体 + 推进器自发光）
##   · 推力随输入变化，喷口大小 / 亮度 / 火焰长度都跟着动
##
## ── 为什么不做成「换皮肤」──
## `Arisu_Battle_Carrier.glb` 只有 **Idle / Walk 两条动作**（过场精简版，
## 实测：211 节点 / 7 网格 / 4 皮肤，动作 `Idle` 3.733 s、`Walk` 2.533 s）。
## 拿它替掉玩家模型的话，`AnimDriver` 要的 `Normal_Idle` / `Normal_Attack_Ing` /
## `Move_Ing` 一条都没有 —— 所以这里**不接 AnimDriver**，自己做状态机：
##   地面：按水平速度在 Idle / Walk 之间交叉淡化
##   飞行：程序化叠加（推进器喷口呼吸 + 全身前倾 + 翼面扑动 + 开火时炮口抖动）
##
## ── 模型自带的硬件（本喵拆 GLB 数出来的，不是猜的）──
## 机件全在 `CH0334_Arms_Body` 这个网格的 skin 里（145 根骨，同时含身体与机甲）：
##   双肩翼 8 片  `bone_wing_LDL/LUL/LDR/LUR_01~02`、`bone_wing_RDR/RUR/RDL/RUL_01~02`
##                （挂在 `bone_gear_wing_L/R` 下）
##   四门炮       `bone_gear_cannon_L/R` + `cannon_out_*` + `outletB/U_*`
##                （挂在 `bone_gear_Pillar_L/R` 下）
##   导弹荚 ×2    `bone_missilepod_L/R`
##   腰翼         `bone_wingwaist_*`（8 根）
##   **腿部推进器** `bone_gearboost_L/R`（挂在大腿上）← 飞行特效就插在这里
##   武器骨       `Bip001_Weapon` → `buttstack` / `energypack_01~02` / `fire_01`
##
## ⚠️ 朝向：载具模型的脸朝哪一侧本喵没在窗口里看过，所以留 `facing_yaw_deg`
##    这个导出参数（默认 0）。要是看到它是倒着走的，把它改成 180 就行。
##
## ── 优雅降级 ──
## 模型是本地素材（`models/*.glb` 已被 gitignore，不进仓库）：文件不在时
## 按 G 只打一条 warning，**不崩、也不影响本体**。

const MechState := preload("res://scripts/mech_state.gd")

const CARRIER_GLB := "res://models/Arisu_Battle_Carrier.glb"
## 交叉淡化时长（秒）
const FADE := 0.18
## 超过这个水平速度就播 Walk
const WALK_SPEED := 0.6
## 飞行时 Walk 的播放倍速基准：载具的 Walk 是慢步（2.533 s / 周期），
## 按 2.6 m/s 为 1.0 倍算，飞起来才不至于「脚在地上划水」。
const FLY_WALK_REF := 2.6
## Walk 的播放倍速上限。原来写死 1.8，跑起来脚就追不上地面 → 「滑行」。
const WALK_SPEED_SCALE_MAX := 4.0

# ── 飞行数值（米 / 秒）──────────────────────────────────────────────────────
## 起飞时给的一下初始上推（瞬间离地的手感，平缓但明确）
const LIFT_KICK := 2.4
## 上升 / 下降的最大垂直速度
const RISE_SPEED := 7.0
const FALL_SPEED := 8.5
## 垂直加速度（越小越飘，这是「灵活起落」的主要手感旋钮）
const VERT_ACCEL := 26.0
## 飞行中的水平加速度 / 摩擦（比地面低一档：空中要更飘）
const FLY_ACCEL := 14.0
const FLY_FRICTION := 6.0
## 悬停时每秒下沉多少（速度单位）—— 不是真的掉高度，是给一点「重力感」
const HOVER_SINK := 0.45
## 跳跃 / 起落用的缓冲（和 `player.gd` 的 `JUMP_BUFFER_MS` 同一套思路）
const JUMP_BUFFER_MS := 180.0
## 按空格长按多久算「持续上升」（毫秒）
const HOLD_RISE_MS := 140.0
## 离地 / 离地前几十毫秒内按空格仍然算数（土狼时间）
const COYOTE_MS := 110.0

# ── 特效数值 ───────────────────────────────────────────────────────────────
## 蓝色火焰的三层颜色（从芯到边），越外越淡越蓝
const FLAME_CORE := Color(0.72, 0.92, 1.00, 0.95)
const FLAME_MID := Color(0.22, 0.58, 1.00, 0.60)
const FLAME_OUTER := Color(0.08, 0.22, 0.85, 0.22)
## 喷气粒子颜色
const JET_PARTICLE := Color(0.35, 0.72, 1.00, 0.75)
## 火焰在局部 +Y 方向的基准长度（米）—— 之后按推力伸缩
const FLAME_LEN := 0.85

@export var toggle_key: Key = KEY_G
## 起飞 / 上升键。`Space` 与 `Q` 都能用（用户报过「空格偶尔没反应」，见 `player.gd`
## 的 `JUMP_BUFFER_MS` 那段：跑酷落脚板上 `is_on_floor()` 会逐帧抖动）。
@export var rise_key: Key = KEY_Q
## 载具模型相对本体的额外偏航（度）。看到倒着走就改 180。
@export var facing_yaw_deg := 0.0
## 载具模型整体缩放（先用 1.0，看着不对再调）
@export var carrier_scale := 1.0

var _player: CharacterBody3D
var _model: Node3D
var _carrier: Node3D
var _ap: AnimationPlayer
var _skel: Skeleton3D
var _on := false
var _cur_anim := ""

# ── 飞行状态 ──
var _airborne := false
## 这一帧想要的垂直方向：+1 上升 / −1 下降 / 0 悬停
var _vert_want := 0.0
## 上一帧的 `_player.is_on_floor()`（落地判定用，见 `_land()`）
var _was_on_floor := true
var _rise_pressed_at := -99999.0
var _air_since := -99999.0
## 推进器推力 0~1（特效强度、火焰长度都跟它走）
var _thrust := 0.0
## 全身前倾角（弧度），飞行时按水平速度插值
var _lean := 0.0
## 翼面扑动相位 / 炮口抖动相位
var _wing_phase := 0.0
var _fire_phase := 0.0

## 两根腿部推进器骨的名字（拆 GLB 确认在 `CH0334_Arms_Body` 的 skin 里）
const BOOST_BONES := ["bone_gearboost_L", "bone_gearboost_R"]
## 肩翼：飞行时轻轻向上张开（按骨名认，找不到就跳过）
const SHOULDER_WING_BONES := [
	"bone_wing_LDL_01", "bone_wing_LUL_01", "bone_wing_LDR_01", "bone_wing_LUR_01",
	"bone_wing_RDR_01", "bone_wing_RUR_01", "bone_wing_RDL_01", "bone_wing_RUL_01",
]
## 炮口骨：开火时抖一下（用户没说要做，但机甲形态下这不是它的武器系统，
## 所以这里**只做视觉抖动**，不会真的发子弹；命中判定仍是 `Weapon` 那套）
const CANNON_BONES := ["bone_gear_cannon_L", "bone_gear_cannon_R"]

## 每根推进器骨上的特效挂点：{bone_index: [flames...]}
var _boost_fx: Array = []
## 推进器骨在**绑定姿势**下的局部位姿（每帧在它之上叠加，不被上次的写入污染）
var _boost_rest: Dictionary = {}
var _wing_rest: Dictionary = {}

# ── 数值暴露给自检 / HUD ──
var flight_speed := 0.0
var boost_dot_count := 0


func _ready() -> void:
	_player = get_parent().get_parent() as CharacterBody3D   # Arisu → Player
	_model = get_node_or_null("../Model")
	set_process(false)
	# 载具形态下由本脚本接管垂直运动；平时不接管（`player.gd` 照常）。
	set_physics_process(true)


## 变形能不能用（解锁了 + 模型在）
func available() -> bool:
	return MechState.carrier_unlocked() and ResourceLoader.exists(CARRIER_GLB)


func is_on() -> bool:
	return _on


## 当前是不是在飞（自检 / HUD 用）
func is_flying() -> bool:
	return _on and _airborne


## 切到 / 切回。返回切换后是不是载具形态。
func set_form(on: bool) -> bool:
	if on == _on:
		return _on
	if on:
		if not MechState.carrier_unlocked():
			push_warning("[Carrier] 还没解锁（先在第二场景找凯伊改装）")
			return false
		if _carrier == null and not _build():
			return false
	_on = on
	if _model != null:
		_model.visible = not on
	if _carrier != null:
		_carrier.visible = on
	set_process(on)
	if on:
		_play("Idle", true)
		# 变形出来的那一刻是站着的（地面形态），先不飞
		_airborne = false
		_vert_want = 0.0
		if _player != null:
			_sync_face()
	else:
		# 变回本体：如果还在空中，把垂直速度留给 `player.gd` 的重力去接（它自己会掉下来）；
		# 这里只把「飞行接管」的标志清掉，不动位置。
		_airborne = false
		_vert_want = 0.0
		_thrust = 0.0
		_lean = 0.0
		_restore_bones()
	print("[Carrier] 变形 → %s" % ("阿比·埃舒（载具）" if on else "爱丽丝本体"))
	return _on


func toggle() -> bool:
	return set_form(not _on)


## 建载具实例：模型 + 脚底对齐 + 找 AnimationPlayer / Skeleton3D + 装推进器特效
func _build() -> bool:
	if not ResourceLoader.exists(CARRIER_GLB):
		push_warning("[Carrier] 没有载具模型：%s（本地素材，不随仓库分发）" % CARRIER_GLB)
		return false
	var ps := load(CARRIER_GLB) as PackedScene
	if ps == null:
		push_error("[Carrier] %s 不是有效的场景" % CARRIER_GLB)
		return false
	_carrier = ps.instantiate() as Node3D
	_carrier.visible = false
	add_child(_carrier)
	_align_feet()
	_carrier.rotation.y = deg_to_rad(facing_yaw_deg)
	_ap = _find_anim_player(_carrier)
	if _ap == null:
		# 没有 AnimationPlayer 也能用（只是站着不动），但要说一声
		push_warning("[Carrier] 载具模型里没找到 AnimationPlayer，只能静态显示")
	else:
		print("[Carrier] 载具就位：%s｜动作 %s" % [
			CARRIER_GLB.get_file(), str(_ap.get_animation_list())])
	_skel = _find_skeleton(_carrier)
	if _skel != null:
		_snapshot_rest()
		_build_boost_fx()
		print("[Carrier] 机甲硬件就位：推进器 %d 根｜肩翼 %d 根｜炮 %d 根" % [
			_boost_fx.size(), _found_wing_bones(), _found_cannon_bones()])
	else:
		push_warning("[Carrier] 载具模型里没找到 Skeleton3D，飞行特效不会出现")
	return true


## 把模型脚底挪到节点原点（本体胶囊站在 y=0 上，模型也得对齐）
func _align_feet() -> void:
	var lo := INF
	var found := false
	for m in _meshes(_carrier):
		var aabb: AABB = (m as MeshInstance3D).get_aabb()
		# 用 8 个角在**局部**空间里取最低点（父链只有平移/旋转，够用）
		for i in 8:
			var p: Vector3 = m.transform * aabb.get_endpoint(i)
			lo = minf(lo, p.y)
			found = true
	if found:
		_carrier.position.y -= lo
	_carrier.scale = Vector3.ONE * carrier_scale


func _meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_meshes(c))
	return out


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer and not node.get_animation_list().is_empty():
		return node
	for c in node.get_children():
		var got := _find_anim_player(c)
		if got != null:
			return got
	return null


## 载具里**同时带机件**的那具骨架。
## ⚠️ 不能取「树里第一个 Skeleton3D」：这个 glb 有 4 个 skin
##    （73 / 4 / 145 / 42 根），其中只有 **145 根那具**同时含身体与机件
##    —— 所以按「骨头最多」来认（和 `_probe_companion_row.gd` 里记的凯伊那个坑同源）。
func _find_skeleton(node: Node) -> Skeleton3D:
	var best: Skeleton3D = null
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Skeleton3D:
			var s := n as Skeleton3D
			if best == null or s.get_bone_count() > best.get_bone_count():
				best = s
		for c in n.get_children():
			stack.append(c)
	return best


## 记下要叠加的骨在**绑定姿势**下的局部位姿。
## 飞行特效是「每帧在静止姿势上叠加」，不这样的话姿态会一帧一帧累积漂走。
func _snapshot_rest() -> void:
	for bn in BOOST_BONES:
		var i := _skel.find_bone(bn)
		if i >= 0:
			_boost_rest[i] = {
				"p": _skel.get_bone_pose_position(i),
				"r": _skel.get_bone_pose_rotation(i),
				"s": _skel.get_bone_pose_scale(i),
			}
	for bn in SHOULDER_WING_BONES:
		var i := _skel.find_bone(bn)
		if i >= 0:
			_wing_rest[i] = _skel.get_bone_pose_rotation(i)
	if _boost_rest.is_empty():
		push_warning("[Carrier] 找不到推进器骨 %s —— 蓝焰会挂到模型根上" % str(BOOST_BONES))


func _found_wing_bones() -> int:
	return _wing_rest.size()


func _found_cannon_bones() -> int:
	var n := 0
	for bn in CANNON_BONES:
		if _skel.find_bone(bn) >= 0:
			n += 1
	return n


# ── 推进器特效 ─────────────────────────────────────────────────────────────

## 每根推进器骨上挂一个挂点（Node3D），挂点里放：
##   · 三层发光锥体（蓝色火焰：芯 / 中 / 外）
##   · 一盏 OmniLight3D（照亮脚下地面，飞行时最抓眼）
##   · 一个 GPUParticles3D（喷气拖尾）
##   · 一个 OmniLight 的**开关**由推力控制
func _build_boost_fx() -> void:
	var targets: Array[int] = []
	for bn in BOOST_BONES:
		var i := _skel.find_bone(bn)
		if i >= 0:
			targets.append(i)
	if targets.is_empty():
		return

	var cone_mesh := _make_flame_mesh()
	var mat_core := _make_flame_mat(FLAME_CORE)
	var mat_mid := _make_flame_mat(FLAME_MID)
	var mat_outer := _make_flame_mat(FLAME_OUTER)
	var particle_mesh := _make_particle_mesh()
	var particle_mat := _make_particle_mat()

	for bi in targets:
		var holder := Node3D.new()
		holder.name = "BoostFX_%d" % bi
		_carrier.add_child(holder)

		# 三层锥体：同轴、从内到外依次更细更长
		var layers: Array[MeshInstance3D] = []
		var specs := [
			{"mat": mat_outer, "scale": 1.00, "len": 1.00, "r": 1.00},
			{"mat": mat_mid, "scale": 0.72, "len": 0.82, "r": 0.72},
			{"mat": mat_core, "scale": 0.42, "len": 0.62, "r": 0.42},
		]
		for sp in specs:
			var mi := MeshInstance3D.new()
			mi.mesh = cone_mesh
			mi.material_override = sp["mat"]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# 锥体在网格里是「尖朝 −Y、底在原点」，绕 X 翻 180° 让尖朝 +Y（喷口向下）
			mi.rotation.x = PI
			mi.scale = Vector3(sp["r"], sp["len"], sp["r"]) * float(sp["scale"])
			mi.layers = 1
			holder.add_child(mi)
			layers.append(mi)

		# 推进器自发光（照自己的腿和地面）
		var light := OmniLight3D.new()
		light.light_color = Color(0.35, 0.68, 1.0)
		light.omni_range = 4.2
		light.light_energy = 0.0
		light.shadow_enabled = false
		light.position = Vector3(0.0, -0.18, 0.0)
		holder.add_child(light)

		# 喷气粒子
		var gp := GPUParticles3D.new()
		gp.amount = 48
		gp.lifetime = 0.55
		gp.local_coords = false
		gp.emitting = false
		gp.visibility_aabb = AABB(Vector3(-3, -6, -3), Vector3(6, 8, 6))
		gp.draw_pass_1 = particle_mesh
		gp.material_override = particle_mat
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0.0, -1.0, 0.0)
		pm.spread = 14.0
		pm.initial_velocity_min = 3.0
		pm.initial_velocity_max = 7.0
		pm.gravity = Vector3(0.0, -2.5, 0.0)
		pm.scale_min = 0.35
		pm.scale_max = 0.95
		pm.color = JET_PARTICLE
		pm.damping_min = 2.0
		pm.damping_max = 5.0
		gp.process_material = pm
		holder.add_child(gp)

		_boost_fx.append({
			"bone": bi,
			"holder": holder,
			"layers": layers,
			"light": light,
			"particles": gp,
		})
	boost_dot_count = _boost_fx.size()


## 一个「尖朝 −Y、底在原点、长度 1 m」的锥体（火焰基准形状）。
## 单位化后用 `scale.y` 拉长 —— 长度完全由推力控制。
func _make_flame_mesh() -> ArrayMesh:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.001
	cyl.bottom_radius = 0.16
	cyl.height = 1.0
	cyl.radial_segments = 12
	cyl.rings = 1
	cyl.cap_bottom = false
	cyl.cap_top = false
	var st := SurfaceTool.new()
	st.append_from(cyl, 0, Transform3D(Basis(), Vector3(0.0, -0.5, 0.0)))
	# 上面那句把柱体中心挪到 −0.5 ⇒ 底面（半径最大那头）正好落在原点、尖朝 −Y
	return st.commit()


## 加色混合的火焰材质。`blend_mode = ADD` + 不写深度 ⇒ 多层叠起来就是发光的蓝焰。
func _make_flame_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.disable_receive_shadows = true
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 3.0
	return m


func _make_particle_mesh() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(0.26, 0.26)
	return q


func _make_particle_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_color = JET_PARTICLE
	m.disable_receive_shadows = true
	return m


# ── 主循环 ─────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if not _on or _player == null:
		_was_on_floor = _player.is_on_floor() if _player != null else true
		return

	var on_floor := _player.is_on_floor()
	var now_ms := float(Time.get_ticks_msec())

	# ── 起落输入（带缓冲 / 土狼时间，抄 `player.gd` 那套：单帧脉冲不可靠）──
	#
	# 两路都认：`Space`（走 `jump` 这个 InputMap 动作，和跑酷共用）
	# 和 `Q`（物理键码，`Input.is_key_pressed` 对物理键码同样有效）。
	# ⚠️ 不能用 `is_physical_key_just_pressed` —— Godot 4.7 的 `Input` 里**没有**
	#    这个方法（只有 `is_key_pressed` / `is_physical_key_pressed` 这两个状态查询，
	#    「刚按下」的边沿必须走 InputMap 动作或用 `_input` 自己记）。
	var rise_now := Input.is_physical_key_pressed(rise_key) or Input.is_action_pressed("jump")
	if rise_now and not _rise_held:
		_rise_pressed_at = now_ms
	_rise_held = rise_now
	var hold_ms := now_ms - _rise_pressed_at
	if not on_floor and _was_on_floor:
		_air_since = now_ms
	var grounded_grace := on_floor or (now_ms - _air_since) <= COYOTE_MS

	# 起飞：在地面（或刚离地）按了一下上升键
	if not _airborne and grounded_grace and hold_ms <= JUMP_BUFFER_MS:
		_take_off()
		_rise_pressed_at = -99999.0
		hold_ms = 0.0

	# ── 垂直意图 ──
	if _airborne:
		if Input.is_physical_key_pressed(rise_key) and hold_ms >= HOLD_RISE_MS:
			_vert_want = 1.0
		elif Input.is_action_pressed("jump") and hold_ms >= HOLD_RISE_MS:
			_vert_want = 1.0
		elif Input.is_action_pressed("crouch"):
			_vert_want = -1.0
		else:
			_vert_want = 0.0
		_apply_flight(delta, on_floor)
	else:
		_vert_want = 0.0

	# ── 朝向（变形后仍由 `player.gd` 管移动方向；这里只在需要时对齐模型）──
	_sync_face()

	# ── 特效 ──
	_run_effects(delta)
	_was_on_floor = on_floor


## 起飞：给一下上推 + 进入飞行态
func _take_off() -> void:
	if _player == null:
		return
	_airborne = true
	_air_since = float(Time.get_ticks_msec())
	var v := _player.velocity
	v.y = maxf(v.y, LIFT_KICK)
	_player.set("velocity", v)
	if _player.has_method("set_ride_lock"):
		# 不在 `set_ride_lock(true)` 那条路上：那是火箭强制接管位置的锁，
		# 这里只是**接管垂直方向**，水平仍然让 `player.gd` 跑（所以不调它）。
		pass
	print("[Carrier] 起飞")
	Sfx.play("ui_toggle", -3.0)


## 飞行中的垂直 + 水平修正。
## ⚠️ 只改 `velocity`，**不动位置** —— `player.gd` 的 `move_and_slide()` 照常跑，
##    所以水平碰撞、上台阶、卡角自救全都还在，飞起来也能贴墙、也能落在平台上。
func _apply_flight(delta: float, _on_floor: bool) -> void:
	if _player == null:
		return
	var v := _player.velocity

	var want_v := 0.0
	if _vert_want > 0.5:
		want_v = RISE_SPEED
	elif _vert_want < -0.5:
		want_v = -FALL_SPEED
	else:
		# 悬停：给一点极小的下沉，飞行手感才「有重量」而不是飘在真空里
		want_v = -HOVER_SINK
	v.y = move_toward(v.y, want_v, VERT_ACCEL * delta)

	# 水平：**不在这里动**。`player.gd` 的加速 / 摩擦 / 跑速判定每帧照常跑，
	# 所以飞起来仍能按 Shift 冲到 6.8 m/s、仍能贴着墙调整落点。
	# 唯一要做的额外事是「空中没有地面摩擦那么大的刹车」——那由 `player.gd`
	# 的 `ACCEL_AIR` 管，这里不重复实现（重复实现会和它互相覆盖）。
	_player.set("velocity", v)

	# 触底 → 落地（`player.gd` 会把它压回地面）
	if _player.is_on_floor() and v.y <= 0.0 and _vert_want <= 0.0:
		_land()


## 落地：退出飞行态、把推力清零、播一次「落地」
func _land() -> void:
	if not _airborne:
		return
	_airborne = false
	_vert_want = 0.0
	print("[Carrier] 落地")
	Sfx.play("ui_toggle", -6.0)


## 激光加速（按住 Shift 时给一点点向前的额外推力）—— 目前**不接**
## 用户的原始要求是「灵活起落 + 喷气 + 蓝焰」，没有要超级加速；
## 这里保留一个函数位，想加的时候在 `_apply_flight()` 里调一下即可。
func _apply_afterburner(_delta: float) -> void:
	if _player == null:
		return


## 朝向：载具的模型根是 `Arisu` 的子节点，本体的 `model_root.rotation.y`
## 由 `player.gd` 每帧写。载具是 `Arisu/CarrierForm` 下的独立节点，
## 所以只要把「载具本体的 yaw」设成和 `Arisu` 一致就行（多一次 `facing_yaw_deg`）。
func _sync_face() -> void:
	if _carrier == null:
		return
	var yaw := _player.rotation.y if _player != null else 0.0
	# `Arisu` 节点自己的朝向才是「脸朝哪」——`player.gd` 写的是 `model_root`（就是 `Arisu`）
	_carrier.rotation.y = yaw + deg_to_rad(facing_yaw_deg)


## 每帧：推力 → 火焰长度 / 亮度 / 粒子 / 骨姿态
func _run_effects(delta: float) -> void:
	if _boost_fx.is_empty():
		return

	# ── 推力：飞行时按垂直意图和水平速度算；地面上 = 0（只剩待机的一点余温）──
	var target := 0.0
	if _airborne:
		target = 0.55
		if _vert_want > 0.5:
			target = 1.0
		elif _vert_want < -0.5:
			target = 0.75
		# 水平越快，喷得越足
		var hs := Vector2(_player.velocity.x, _player.velocity.z).length()
		target = clampf(target + hs / 21.0, 0.0, 1.2)
	else:
		# 站地上：微微烘着（不是零，不然像「关了发动机」）
		target = 0.10
	_thrust = move_toward(_thrust, target, 3.2 * delta)
	flight_speed = Vector2(_player.velocity.x, _player.velocity.z).length()

	# ── 前倾：飞得越快头越低（弧度）。地面姿态永远是 0 ──
	var want_lean := 0.0
	if _airborne:
		want_lean = deg_to_rad(clampf(flight_speed * 2.4, 0.0, 26.0))
	_lean = lerpf(_lean, want_lean, clampf(6.0 * delta, 0.0, 1.0))

	# ── 相位 ──
	_wing_phase += delta * lerpf(1.4, 4.2, clampf(_thrust, 0.0, 1.0))
	_fire_phase += delta * 9.0

	# ── 推进器骨：喷口随推力微张（scale）+ 呼吸旋转 ──
	for bi in _boost_rest.keys():
		var rest: Dictionary = _boost_rest[bi]
		var pulse := 1.0 + 0.10 * sin(_wing_phase * 2.0)
		_skel.set_bone_pose_scale(bi, rest["s"] * Vector3(1.0, 1.0, pulse))
		var r: Quaternion = rest["r"]
		var wob := Quaternion(Vector3.RIGHT, 0.035 * sin(_wing_phase * 1.7) * _thrust)
		_skel.set_bone_pose_rotation(bi, wob * r)

	# ── 肩翼：飞行时向上张开一点（旋转在静止姿势上叠加）──
	var wing_t := clampf(clampf(_thrust, 0.0, 1.0) * clampf(flight_speed / 6.0, 0.0, 1.0), 0.0, 1.0)
	for bi in _wing_rest.keys():
		var r0: Quaternion = _wing_rest[bi]
		var flutter := 0.03 * sin(_wing_phase * 3.1)
		var spread := Quaternion(Vector3.FORWARD, (0.10 * wing_t) + flutter * wing_t)
		_skel.set_bone_pose_rotation(bi, spread * r0)

	# ── 炮口：开火瞬间抖一下（`Weapon` 没有直接暴露「刚开火」的布尔，用 HUD 信号太绕；
	#    这里改成「推力越大炮口越稳、悬停时轻微机械呼吸」，省一个跨脚本耦合）──
	for bn in CANNON_BONES:
		var bi := _skel.find_bone(bn)
		if bi < 0:
			continue
		var base_rot := _skel.get_bone_pose_rotation(bi)
		var jig := Quaternion(Vector3.UP, 0.012 * sin(_fire_phase) * (1.0 - wing_t))
		_skel.set_bone_pose_rotation(bi, jig * base_rot)

	# ── 火焰长度 / 亮度：推力 → 大小 ──
	var flick := 0.85 + 0.15 * sin(_wing_phase * 5.3)
	for fx in _boost_fx:
		var bone_i: int = fx["bone"]
		var holder: Node3D = fx["holder"]
		# 挂点跟着骨走：取骨的**全局**变换，换算回载具节点的局部空间
		if _skel != null and bone_i >= 0:
			var bone_xf := _skel.global_transform * _skel.get_bone_global_pose(bone_i)
			holder.global_transform = bone_xf
		var layers: Array = fx["layers"]
		var t := clampf(_thrust, 0.0, 1.2)
		var LENS: Array[float] = [1.00, 0.82, 0.62]
		var ALPHA_MUL: Array[float] = [1.0, 0.85, 0.7]
		for li in layers.size():
			var mi := layers[li] as MeshInstance3D
			var lens: float = LENS[li]
			var lens_scale: float = lens * lerpf(0.25, 1.0, t) * flick
			mi.scale.y = FLAME_LEN * lens_scale * (1.0 + (0.35 if _vert_want > 0.5 else 0.0))
			mi.visible = t > 0.03
			var m := mi.material_override as StandardMaterial3D
			if m != null:
				m.emission_energy_multiplier = lerpf(0.4, 6.0, t)
				m.albedo_color.a = clampf(0.25 + 0.75 * t, 0.0, 1.0) * [1.0, 0.85, 0.7][li]
		var light := fx["light"] as OmniLight3D
		light.light_energy = lerpf(0.0, 2.6, t) * flick
		light.omni_range = lerpf(2.4, 5.0, t)
		var gp := fx["particles"] as GPUParticles3D
		gp.emitting = t > 0.25
		gp.speed_scale = lerpf(0.6, 1.8, t)


## 变回本体时把被特效改过的骨还原（不然下次变形出来是歪的）
func _restore_bones() -> void:
	if _skel == null:
		return
	for bi in _boost_rest.keys():
		var rest: Dictionary = _boost_rest[bi]
		_skel.set_bone_pose_position(bi, rest["p"])
		_skel.set_bone_pose_rotation(bi, rest["r"])
		_skel.set_bone_pose_scale(bi, rest["s"])


# ── 动画 ───────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _ap == null or _player == null:
		return
	var v := _player.velocity
	var speed := Vector2(v.x, v.z).length()
	if _airborne:
		# 飞行时也走 Walk（腿在动，看着像推进中的腾空），但倍速按「飞行速度」算
		_play("Walk", false)
		_ap.speed_scale = clampf(speed / FLY_WALK_REF, 0.7, WALK_SPEED_SCALE_MAX)
	elif speed > WALK_SPEED:
		_play("Walk", false)
		# ⚠️ 上限从 1.8 放到 4.0：跑 6.8 m/s 时原来只能到 1.8，脚追不上地面 = 滑行
		_ap.speed_scale = clampf(speed / FLY_WALK_REF, 0.8, WALK_SPEED_SCALE_MAX)
	else:
		_play("Idle", false)
		_ap.speed_scale = 1.0


func _play(name_: String, force: bool) -> void:
	if _ap == null or (not force and _cur_anim == name_):
		return
	if not _ap.has_animation(name_):
		return
	_cur_anim = name_
	_ap.speed_scale = 1.0
	_ap.play(name_, FADE)


func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode != toggle_key:
		return
	# 对话/菜单暂停世界时不响应
	if get_tree().paused:
		return
	# 在空中按 G 变回本体 → 交给 `player.gd` 的重力（它会自己掉下来）
	if toggle():
		get_viewport().set_input_as_handled()
