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
## 悬停时每秒往下掉多少（速度单位）。**不是 0**：0 会让悬停像挂在钉子上的贴图，
## 给一点点「重力感」，玩家才觉得机甲的推进器在**托着**它。
## ⚠️ 这个值原来写 0.45，实测 0.5 秒就往下掉 0.78 m（太飘，根本不算「停住」）——
##    0.12 的体感是「0.5 秒掉 6 cm」，肉眼只看到轻微呼吸。
const HOVER_SINK := 0.12
## 跳跃 / 起落用的缓冲（和 `player.gd` 的 `JUMP_BUFFER_MS` 同一套思路）
const JUMP_BUFFER_MS := 180.0
## 按空格长按多久算「持续上升」（毫秒）
const HOLD_RISE_MS := 140.0
## 离地 / 离地前几十毫秒内按空格仍然算数（土狼时间）
const COYOTE_MS := 110.0

## 悬停高度保持：往回补高度的刚度（1/秒）。越大越「黏」，越小越飘。
const HOLD_STIFFNESS := 3.0

# ── 特效数值 ───────────────────────────────────────────────────────────────
## 蓝色火焰的三层颜色（从芯到边），越外越淡越蓝。
## ⚠️ 原来外层写了 `alpha = 0.22`，配上加色混合后整体偏紫、发灰 ——
##    加色混合下 alpha 的降低 = 亮度降低，不是「更透明」，所以外层要**更蓝更亮**才好看。
##    现在外层是「深蓝一点但亮度不低」，靠 `emission_energy_multiplier` 区分层次。
const FLAME_CORE := Color(0.85, 0.96, 1.00, 0.95)
const FLAME_MID := Color(0.35, 0.68, 1.00, 0.75)
const FLAME_OUTER := Color(0.10, 0.32, 0.95, 0.45)
## 喷气粒子颜色
const JET_PARTICLE := Color(0.35, 0.72, 1.00, 0.75)
## 火焰在局部 +Y 方向的基准长度（米）—— 之后按推力伸缩
const FLAME_LEN := 0.85

@export var toggle_key: Key = KEY_G
## 起飞 / 上升键。`Space` 与 `Q` 都能用（用户报过「空格偶尔没反应」，见 `player.gd`
## 的 `JUMP_BUFFER_MS` 那段：跑酷落脚板上 `is_on_floor()` 会逐帧抖动）。
@export var rise_key: Key = KEY_Q
## 载具模型相对本体的额外偏航（度）。
##
## ⚠️ **实测值 = 180**（`_probe_carrier_shot.gd` 的 `5_ground_front.png` 定出来的）：
##    相机摆在角色 **+Z 正前方** 时，看到的是**光环 + 背包**（背面）——
##    说明载具 glb 自己的「脸」朝 **−Z**，而本工程约定「脸朝 +Z」（见 `player.gd` 里
##    `model_root.rotation.y = 0 → 脸朝世界 +Z` 那段铁证）。所以这里要再转 180°。
##    不转的话，游戏里人看着在倒着走 / 背对移动方向。
@export var facing_yaw_deg := 180.0

## ── 从本体 glb 借战斗动作 ──
##
## `Arisu_Battle_Carrier.glb` 只有 `Idle` / `Walk` 两条（BA 素材里载具形态就是
## 「过场精简版」）。但 `Arisu (Battle).glb` 有 35 条完整战斗动作，而且**同一套骨架**：
## 本喵拆 GLB 核过 —— 两边都是 145 关节的 skin，Carrier 只多 3 个网格节点，
## 动作里唯一的差异是 10 根 `Mouth_*`（口型网格，不是骨骼）。
##
## 所以启动时把需要的动作搬进机甲的 `AnimationPlayer`（换轨道前缀），
## 运行时几毫秒，不需要 Blender 重导。搬哪些由用户 2026-11-08 指定：
##   · 战斗：Idle / Move / 攻击 / 换弹
##   · 受击：死亡 / 濒死 / 恐慌 / 撤退
##   · 必杀：Exs01 / Exs02 / Cutin
## `Recorded` 那三条是录制空壳（13 轨道 / 命中 2 根骨），不要。
const BORROW_GLB := "res://models/Arisu_Battle.glb"
const BORROW_CLIPS := [
	# 战斗
	"Normal_Idle", "Move_Ing", "Normal_Attack_Ing", "Normal_Reload",
	"Normal_Attack_Start", "Normal_Attack_Delay", "Normal_Attack_End",
	# 受击
	"Vital_Death", "Vital_Dying_Ing", "Vital_Panic", "Vital_Retreat",
	# 必杀
	"Exs01", "Exs02_01", "Exs02_02",
	"Exs01_Cutin_01", "Exs01_Cutin_02", "Exs02_Cutin_01", "Exs02_Cutin_02",
]
## 借来的动作要不要循环（只有这几条是循环的，其余都是一次性）
const BORROW_LOOP := ["Normal_Idle", "Move_Ing", "Cafe_Idle", "Cafe_Walk"]
## 开火动作的播放倍速（和本体 `AnimDriver.FIRE_SPEED` 同一个数：
## `Normal_Attack_Ing` 原长 2.67 s，原速播「一次射击要演 2.67 秒」，手感卡）
const FIRE_SPEED := 2.5
## 借动作的报告（自检 / 控制台用）
var borrow_report := {}
## 从 `BORROW_GLB` 借战斗 / 受击 / 必杀动作，搬进机甲自己的 `AnimationPlayer`。
##
## 只搬一次（`_ap` 上有 meta 守着）：`_build()` 每个进程只会跑一次，
## 但探针里可能反复 `set_form()`，重复搬会白花时间。
func _borrow_anims() -> void:
	if _ap == null:
		return
	if _ap.has_meta("carrier_borrowed"):
		return
	_ap.set_meta("carrier_borrowed", true)
	if not ResourceLoader.exists(BORROW_GLB):
		push_warning("[Carrier] 没有 %s，机甲只有 Idle/Walk（无法借战斗动作）" % BORROW_GLB)
		return
	borrow_report = AnimExtra.merge_glb_multi(_ap, BORROW_GLB, {}, _skel, BORROW_CLIPS)
	if not bool(borrow_report.get("ok", false)):
		push_warning("[Carrier] 借动作失败：%s" % str(borrow_report.get("error", "")))
		return
	# 循环模式：借来的 `Normal_Idle` / `Move_Ing` 必须设成循环，否则播一次就停住
	for clip in BORROW_LOOP:
		if _ap.has_animation(clip):
			_ap.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	var merged: Array = borrow_report["merged"]
	var names: Array = []
	for m in merged:
		names.append(String(m["to"]))
	print("[Carrier] 借到 %d 条战斗动作（前缀 %s）：%s" % [
		merged.size(), str(borrow_report.get("head_to", "")), ", ".join(names)])
	var miss: Dictionary = borrow_report.get("missing_bones", {})
	if not miss.is_empty():
		print("[Carrier] 目标骨架没有的骨（已删掉那些轨道）：%s" % str(miss.keys()))


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
## 上一帧上升键是不是按着（用来自己判「刚按下」的边沿，见 `_physics_process()`）
var _rise_held := false
## 这一次「按下」有没有已经被起飞消费掉（松开前不再起飞第二次）
var _jump_consumed := false
var _air_since := -99999.0
## 悬停时要保持的高度（`_hold_y` 起点用 −9000 表示「还没飞过」）
var _hold_y := -9000.0
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
## 炮口**开枪点**的骨：两门肩炮的「出口」。
## 每门炮挂在 `bone_gear_Pillar_*` 下，链是 cannon → cannon_out → outletB / outletU。
## 取 `outletB_*`（下口）当枪口：它的姿态与炮管同向，且不会和 `outletU` 打架。
const CANNON_MUZZLE_BONES := ["bone_gear_cannon_outletB_L", "bone_gear_cannon_outletB_R"]

## 每根推进器骨上的特效挂点：{bone_index: [flames...]}
var _boost_fx: Array = []
## 推进器骨在**绑定姿势**下的局部位姿（每帧在它之上叠加，不被上次的写入污染）
var _boost_rest: Dictionary = {}
var _wing_rest: Dictionary = {}

# ── 双炮开火 ──
## 炮口闪光节点（每门炮一个），平时隐藏
var _cannon_fx: Array = []
## 开火后坐脉冲 0→1，按指数衰减
var _cannon_recoil := 0.0
## 上一帧从 `Weapon` 拿到的 `_shot_index`，用来判「刚开了一枪」
var _last_shot_index := 0
## 连发时焰尖抖动的相位
var _cannon_phase := 0.0
## 一次性动作还剩多少秒（> 0 时 `_process()` 不切移动动作）
var _oneshot_left := 0.0
## 上一帧的 `Weapon._shot_index`（判「刚开了一枪」）
var _last_shot_index_seen := 0

# ── 数值暴露给自检 / HUD ──
var flight_speed := 0.0
var boost_dot_count := 0
var cannon_fx_count := 0


func _ready() -> void:
	# ⚠️ 节点层级是 `Player / Arisu / CarrierForm`（见 `scenes/player.tscn`），
	#    所以只要**往上走 1 层**就是 `Player`。
	#    原来写 `get_parent().get_parent()` 是错的：那会取到 `Player` 的父节点
	#    （整个场景根），于是 `_player` 永远为 null、`_ready` 里的 `set_form` 一飞就空引用。
	#    这个坑是 `_probe_carrier_fly.gd` 抓出来的（起飞后 vy 一直是 0）。
	_player = get_parent() as CharacterBody3D
	if _player == null:
		_player = _find_player_up(self)
	_model = get_node_or_null("../Model")
	set_process(false)
	# 载具形态下由本脚本接管垂直运动；平时不接管（`player.gd` 照常）。
	set_physics_process(true)


## 兜底：往上找第一个 `CharacterBody3D`（场景结构被改动时也不至于直接崩）。
func _find_player_up(n: Node) -> CharacterBody3D:
	var cur := n.get_parent()
	while cur != null:
		if cur is CharacterBody3D:
			return cur as CharacterBody3D
		cur = cur.get_parent()
	return null


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
		_last_shot_index = int(_weapon().get("_shot_index")) if _weapon() != null else 0
		# **激光大炮**：机甲形态下 `Weapon` 走光束路径（不是飞行子弹）
		if _weapon() != null:
			_weapon().call("set_beam_mode", true)
		if _player != null:
			_sync_face()
	else:
		# 变回本体：如果还在空中，把垂直速度留给 `player.gd` 的重力去接（它自己会掉下来）；
		# 这里只把「飞行接管」的标志清掉，不动位置。
		_airborne = false
		_vert_want = 0.0
		_hold_y = -9000.0
		_thrust = 0.0
		_lean = 0.0
		# 变回本体：**务必交还垂直方向**，否则 `player.gd` 的重力一直是关的，
		# 人会像灯神一样永远浮在原地。
		if _player != null and _player.has_method("set_flight_lock"):
			_player.call("set_flight_lock", false)
		# 清掉机甲的炮口，`Weapon` 退回本体那套「轨道枪口」逻辑
		# （不清的话会后一套过期的世界坐标一直喂给 `Weapon`，本体开枪就从半空打光）。
		var wpn := _weapon()
		if wpn != null:
			wpn.call("set_carrier_muzzles", [] as Array[Vector3])
			wpn.call("set_beam_mode", false)
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
		_build_cannon_fx()
		_borrow_anims()
		print("[Carrier] 机甲硬件就位：推进器 %d 根｜肩翼 %d 根｜炮 %d 根｜炮口焰 %d 个｜动作 %d 条" % [
			_boost_fx.size(), _found_wing_bones(), _found_cannon_bones(), cannon_fx_count,
			_ap.get_animation_list().size() if _ap != null else 0])
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

		# 三层锥体：同轴、从内到外依次更细更长。
		# 网格已归一化（底半径 1、长度 1、底心在原点），所以：
		#   scale.x / scale.z = 底半径（米）
		#   scale.y           = 长度（米）
		# ⚠️ 不要再在 `rotation` 上动刀：网格本身就是「尖朝 −Y」，
		#    推进器挂在腿上、朝下喷，正好对上。上一版在这里又绕 X 转了 PI，
		#    结果喷口朝上、从背后看是一张扁掉的蓝扇子（见探针出图 3_side）。
		var layers: Array[MeshInstance3D] = []
		var specs := [
			{"mat": mat_outer, "r": 0.20, "len": 1.00},
			{"mat": mat_mid, "r": 0.14, "len": 0.82},
			{"mat": mat_core, "r": 0.08, "len": 0.62},
		]
		for sp in specs:
			var mi := MeshInstance3D.new()
			mi.mesh = cone_mesh
			mi.material_override = sp["mat"]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.layers = 1
			mi.set_meta("base_radius", float(sp["r"]))
			mi.set_meta("base_len", float(sp["len"]))
			mi.scale = Vector3(sp["r"], sp["len"], sp["r"])
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
		# amount 72 + lifetime 0.34：够密、又不会拖成一条长尾巴。
		# 原来 48 / 0.55 配上 0.26 的大方块，出图上是「一条方块瀑布」（见探针出图）。
		gp.amount = 72
		gp.lifetime = 0.34
		gp.local_coords = false
		gp.emitting = false
		gp.visibility_aabb = AABB(Vector3(-3, -6, -3), Vector3(6, 8, 6))
		gp.draw_pass_1 = particle_mesh
		gp.material_override = particle_mat
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0.0, -1.0, 0.0)
		pm.spread = 10.0
		pm.initial_velocity_min = 1.6
		pm.initial_velocity_max = 4.2
		pm.gravity = Vector3(0.0, -4.0, 0.0)
		pm.scale_min = 0.55
		pm.scale_max = 1.25
		pm.color = Color(0.28, 0.55, 1.00, 0.34)
		pm.damping_min = 3.0
		pm.damping_max = 6.0
		# 从喷口往下逐渐缩小 + 淡出（不然尾巴断得很硬）
		var curve := Curve.new()
		curve.add_point(Vector2(0.0, 1.0))
		curve.add_point(Vector2(1.0, 0.05))
		var curve_tex := CurveTexture.new()
		curve_tex.curve = curve
		pm.scale_curve = curve_tex
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


## 一个「底在原点、尖朝 **−Y**、长度 1 m、底半径 1」的火焰锥。
##
## ⚠️ 三条都是踩出来的（`_probe_carrier_shot.gd` 出图对照）：
##   ① **底半径设 1.0、高度设 1.0**，让网格本身是「单位尺寸」——
##      缩放全靠 `MeshInstance3D.scale`，这样 `scale.y` 就严格等于「长度（米）」，
##      不会再出现「锥体被压成一块扁蓝扇面」。
##   ② 网格原点就放在**底心**（不靠 `Transform3D` 平移），
##      `add_child` 后直接挂到骨上，位置就是喷口。
##   ③ 尖朝 −Y：Godot 的 `CylinderMesh` 本来就 `top_radius`→+Y、`bottom_radius`→−Y，
##      所以要「向上喷」就再转 180°；但推进器是**朝下**喷的，本来就该是 −Y，
##      **不需要转**。上一版绕 X 转了 PI，等于让它朝上喷 —— 这就是那块「向上的一张蓝扇」。
func _make_flame_mesh() -> ArrayMesh:
	# CylinderMesh 自身坐标：**中心在原点**，`top_radius` 在 +Y 半边，`bottom_radius` 在 −Y 半边。
	# 我们要的火焰：**底（粗）在原点，尖朝 −Y，长度 1、底半径 1**。
	#
	# 于是：让「bottom_radius（粗）」成为 +Y 那一端 → 设 bottom_radius 为大、top_radius 为 0，
	# 再把整块绕 X 翻 180°（粗端从 −Y 转到 +Y），最后下移 0.5
	# 让「粗端的截面」正好落在原点 —— 此时尖在 y = −1。
	#
	# 换一个等价、更好读的写法：直接构造「尖朝 −Y」的 Basis，再把原点抬到底面。
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0          # 尖
	cyl.bottom_radius = 1.0       # 粗端，半径 1 ⇒ 直径 2
	cyl.height = 1.0
	cyl.radial_segments = 16
	cyl.rings = 3
	cyl.cap_bottom = false        # 底面不封口：加色混合下封口会显示成一个亮圆盘
	cyl.cap_top = false

	var st := SurfaceTool.new()
	# 绕 X 转 180°：尖从 +Y 翻到 −Y，粗端从 −Y 翻到 +Y。
	var flip := Basis(Vector3.RIGHT, PI)
	# 翻转后中心仍在原点，所以粗端截面在 y = +0.5。下移 0.5 ⇒ 粗端截面落在 y = 0（原点），
	# 尖落在 y = −1。缩放到「底半径 FLAME_RADIUS、长度 L」就靠 `MeshInstance3D.scale`。
	var xf := Transform3D(flip, Vector3(0.0, -0.5, 0.0))
	st.append_from(cyl, 0, xf)
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
	# ⚠️ 0.26 太大、而且 `billboard_keep_scale` 一开就变成「一片片带透视的方块」，
	#    出图上像故障贴图而不是喷气（见 `_probe_carrier_shot.gd` 的 2_hover/3_side）。
	#    0.09 是肉眼看起来「颗粒」的大小；靠数量（amount 72）而不是靠尺寸堆出体积感。
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	return q


func _make_particle_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	# ⚠️ 关掉 `keep_scale`：开着的话相机的远近会放大方块，远处变成一大片白斑。
	m.billboard_keep_scale = false
	m.vertex_color_use_as_albedo = true
	# 偏蓝、透明度低一点：粒子的职责是「雾」，真正的「焰」由三层锥体负责
	m.albedo_color = Color(0.28, 0.55, 1.00, 0.34)
	m.disable_receive_shadows = true
	return m


# ── 主循环 ─────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	_tick_flight(delta)
	_was_on_floor = _player.is_on_floor() if _player != null else true


## 飞行主逻辑。**单独拆出来是为了能被探针直接调用** ——
## `_physics_process()` 里的 `_was_on_floor = ...` 求值在调用 `_tick_flight()` 之前，
## 探针自己调 `_physics_process()` 时拿不到上一趟的真实值（`_was_on_floor` 永远是
## 上一帧的假值），会测出假结果。所以测试走这个函数。
func _tick_flight(delta: float) -> void:
	if not _on or _player == null:
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
		_jump_consumed = false          # 新的一次按下：允许再次起飞
	_rise_held = rise_now
	var hold_ms := now_ms - _rise_pressed_at
	if not on_floor and _was_on_floor:
		_air_since = now_ms
	var grounded_grace := on_floor or (now_ms - _air_since) <= COYOTE_MS

	# 起飞：在地面（或刚离地）按了一下上升键
	#
	# ⚠️ **不要把 `_rise_pressed_at` 清掉**（原来写的是 `= -99999.0`）：
	#    它同时被下面「按住够久 = 持续上升」用着。清掉之后按住空格一路飞，
	#    `hold_ms` 每帧都从 0 重算、永远到不了 `HOLD_RISE_MS` ——
	#    表现就是「起飞了但爬不上去」，只有那一下 `LIFT_KICK` 的初速。
	#    这个坑是 `_probe_carrier_fly.gd` 打逐帧 `vert` 打出来的（一直是 +0.0）。
	#    起飞只需要保证「这一次按下已经消费掉」，用 `_jump_consumed` 单独记。
	if not _airborne and grounded_grace and hold_ms <= JUMP_BUFFER_MS and not _jump_consumed:
		_take_off()
		_jump_consumed = true

	# ── 垂直意图 ──
	#
	# 按住多久才算「持续上升」：`hold_ms` 用的是**墙钟**（`Time.get_ticks_msec()`），
	# 不是帧数 —— 这一条决定了「点一下就起飞然后停住」和「按住一路飞上去」的区别。
	#
	# ⚠️ 这里**不判 `rise_now` 的边沿**，只看「现在按着 + hold 够久」：
	#    边沿判定（`_rise_held`）只为 `_rise_pressed_at` 服务，两者职责分开。
	#    混在一起写过一版，表现是「按住上升键完全不响应」——`_rise_held` 被
	#    起飞那一帧清掉了，后面 `hold_ms` 永远从 0 重新算。
	var rise_val := Input.get_action_raw_strength("jump")
	var key_held := Input.is_physical_key_pressed(rise_key)
	var holding := rise_now or key_held
	if _airborne:
		if holding and hold_ms >= HOLD_RISE_MS:
			_vert_want = 1.0
		elif Input.is_action_pressed("crouch"):
			_vert_want = -1.0
		else:
			_vert_want = 0.0
		_apply_flight(delta, on_floor)
	else:
		_vert_want = 0.0

	# ── 悬停高度保持：把「按住上升键一路升上去」的峰值高度记下来，
	#    松开键后**缓慢向那个高度回弹**（阻尼弹簧，不振荡）。
	#    没有这一段的话，一松开上升键就开始匀速下沉，玩家会觉得「扶不住」。
	if _airborne and _vert_want > 0.5:
		_hold_y = _player.global_position.y
	elif _airborne and _vert_want == 0.0 and _hold_y > -9000.0:
		var dy := _hold_y - _player.global_position.y
		# 只在「掉下去」时往回补，且力度随落差增大但封顶 —— 不要把人往上顶出画面
		if dy > 0.02:
			var v := _player.velocity
			v.y = move_toward(v.y, clampf(dy * HOLD_STIFFNESS, 0.0, 2.2), VERT_ACCEL * delta)
			_player.set("velocity", v)

	# ── 朝向（变形后仍由 `player.gd` 管移动方向；这里只在需要时对齐模型）──
	_sync_face()

	# ── 特效 ──
	_run_effects(delta)


## 起飞：给一下上推 + 进入飞行态
func _take_off() -> void:
	if _player == null:
		return
	_airborne = true
	_air_since = float(Time.get_ticks_msec())
	_hold_y = _player.global_position.y
	var v := _player.velocity
	v.y = maxf(v.y, LIFT_KICK)
	_player.set("velocity", v)
	# 接管垂直方向：`player.gd` 那边停止施加重力与跳跃（见那里的 `_flight_lock`）。
	# ⚠️ 不调 `set_ride_lock(true)`：那是火箭「连位置都不归自己管」的锁，
	#    会把水平输入一起吃掉；机甲飞行只交垂直方向。
	if _player.has_method("set_flight_lock"):
		_player.call("set_flight_lock", true)
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
	_hold_y = -9000.0
	_jump_consumed = true          # 落地这一下不算「新按下」，得松开再按才起飞
	# 交还垂直方向：`player.gd` 重新施加重力与跳跃
	if _player != null and _player.has_method("set_flight_lock"):
		_player.call("set_flight_lock", false)
	print("[Carrier] 落地")
	Sfx.play("ui_toggle", -6.0)


## 激光加速（按住 Shift 时给一点点向前的额外推力）—— 目前**不接**
## 用户的原始要求是「灵活起落 + 喷气 + 蓝焰」，没有要超级加速；
## 这里保留一个函数位，想加的时候在 `_apply_flight()` 里调一下即可。
func _apply_afterburner(_delta: float) -> void:
	if _player == null:
		return


## 朝向：载具是 `Player/Arisu/CarrierForm` 下的独立节点，**不在 `Arisu` 的模型子树里**，
## 所以要自己把朝向同步成 `Arisu` 的朝向。
##
## ⚠️ 取 **`_model`（就是 `../Model`）的 `rotation.y`**，不是 `_player.rotation.y`：
##    `player.gd` 每帧写的是 `model_root`（= `Arisu` 节点）的 `rotation.y`（见
##    `player.gd::_physics_process()` 里 `model_root.rotation.y = _lerp_angle_smooth(...)`），
##    而 `Player` 本体自己的 `rotation.y` **一直是 0**（它从不写自己的朝向）。
##    本喵第一版取的就是 `_player.rotation.y`，出图一看机甲整个侧躺着 —— 那是 0°，
##    而模型的「脸朝 +Z」约定要求 `Arisu` 上那个 yaw。
##
## 再叠加 `facing_yaw_deg`：这是给「载具模型的脸和本体模型不一致」留的旋钮。
## ⚠️ `Arisu` 节点本身带着一个 **−180°（绕 Y）的基变换**（`player.tscn` 里
##    `transform = Transform3D(-1,0,-8.7e-8, 0,1,0, 8.7e-8,0,-1, ...)`，是给
##    `Arisu_ext.glb` 校正用的）。载具 glb 是**另一份素材**，它自己可能已经是正的 ——
##    所以这里**只取 yaw 标量**、不继承那个 -1 的基，靠 `facing_yaw_deg` 单独校准。
func _sync_face() -> void:
	if _carrier == null or _model == null:
		return
	_carrier.rotation.y = _model.rotation.y + deg_to_rad(facing_yaw_deg)


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

	# ── 炮口：悬停时轻微机械呼吸；**开火时**由 `Weapon.fired` 信号触发一个后坐脉冲 ──
	for bn in CANNON_BONES:
		var bi := _skel.find_bone(bn)
		if bi < 0:
			continue
		var base_rot := _skel.get_bone_pose_rotation(bi)
		# `_cannon_recoil` 在开火那一帧被拉满，然后按指数衰减 —— 炮会后挫一下再回位
		var kick := Quaternion(Vector3.RIGHT, _cannon_recoil * 0.16)
		var jig := Quaternion(Vector3.UP, 0.012 * sin(_fire_phase) * (1.0 - wing_t))
		_skel.set_bone_pose_rotation(bi, kick * jig * base_rot)
	_cannon_recoil = move_toward(_cannon_recoil, 0.0, 6.0 * delta)

	# ── 机甲形态：把两门炮的世界坐标喂给 `Weapon`，让它从炮口打光 ──
	# ⚠️ 每帧都要推：炮口跟着骨骼动（肩翼会开合、炮会呼吸），只在开火时算会滞后一帧。
	_push_cannon_muzzles()

	# ── 炮口蓝焰：开火瞬间闪一下（独立的短寿命锥体，和腿上的推进器分开）──
	_run_cannon_flash(delta)

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
		# 上升时整束焰柱再长 35%（喷得猛），但**半径不变**，只拉长度
		var len_mul := 1.0 + (0.35 if _vert_want > 0.5 else 0.0)
		for li in layers.size():
			var mi := layers[li] as MeshInstance3D
			var br: float = float(mi.get_meta("base_radius", 0.15))
			var bl: float = float(mi.get_meta("base_len", 0.8))
			# 推力小时「短而钝」，推力大时「长而尖」：半径也跟着略收，不然低速像根柱子
			var growth := lerpf(0.30, 1.0, t) * flick
			mi.scale = Vector3(br * lerpf(0.75, 1.0, t), FLAME_LEN * bl * growth * len_mul,
				br * lerpf(0.75, 1.0, t))
			mi.visible = t > 0.03
			var m := mi.material_override as StandardMaterial3D
			if m != null:
				m.emission_energy_multiplier = lerpf(0.4, 6.0, t)
				# 注意：加色混合下改 alpha 就是改亮度（不是改透明度），
				# 所以这里用「亮度」的语义去写，别当成透明度理解。
				m.albedo_color.a = clampf(0.25 + 0.75 * t, 0.0, 1.0) * [1.0, 0.85, 0.7][li]
		var light := fx["light"] as OmniLight3D
		light.light_energy = lerpf(0.0, 2.6, t) * flick
		light.omni_range = lerpf(2.4, 5.0, t)
		var gp := fx["particles"] as GPUParticles3D
		gp.emitting = t > 0.25
		gp.speed_scale = lerpf(0.6, 1.8, t)


# ── 双炮开火 ───────────────────────────────────────────────────────────────

## 把两门炮的**世界坐标**推给 `Weapon`，让它从炮口而不是（找不到的）轨道枪口打光。
##
## 为什么必须每帧推：炮口骨在 `bone_gear_Pillar_*` → `cannon_rot` → `cannon_pos` 这条链
## 下面，而本脚本每帧都在改 `bone_gear_wing_*` 和炮口的旋转（肩翼开合、开火后坐），
## 炮口世界位置一直在动 —— 只在开火那一帧算会差出十几厘米。
func _push_cannon_muzzles() -> void:
	var wpn := _weapon()
	if wpn == null:
		return
	var xs: Array[Vector3] = []
	for bn in CANNON_MUZZLE_BONES:
		var bi := _skel.find_bone(bn)
		if bi < 0:
			continue
		xs.append((_skel.global_transform * _skel.get_bone_global_pose(bi)).origin)
	if xs.is_empty():
		# 载具模型换了 / 骨名变了 → 退回单枪口，至少不会掉到地底下
		wpn.call("set_carrier_muzzles", [] as Array[Vector3])
		return
	wpn.call("set_carrier_muzzles", xs)


## 找 `Weapon`：它是 `Player` 的直接子节点（见 `scenes/player.tscn`）。
func _weapon() -> Weapon:
	if _player == null:
		return null
	return _player.get_node_or_null("Weapon") as Weapon


## 建两门炮的焰口节点（每门一组：三层锥体 + 一盏灯），平时隐藏，开火时闪。
## 复用的就是推进器那套网格和材质 —— 同一个 `_make_flame_mesh()`，「蓝焰」在机甲上
## 应该长得一样，不该出现两套美术。
func _build_cannon_fx() -> void:
	cannon_fx_count = 0
	if _skel == null:
		return
	var cone := _make_flame_mesh()
	# 三层锥体：同轴、从内到外依次更细更长。
	# 复用推进器那套「底半径 + 长度」约定（网格已归一化）。
	#
	# ⚠️ 半径从 0.16/0.10/0.05 提到 0.30/0.19/0.10：
	#    0.16 m 的焰口放在肩高、又被肩甲翼片夹着，出图（`7_fire_front.png`）上
	#    只剩一小圈蓝晕，玩家正常视角根本看不见。炮口焰是「开火有反馈」的主要视觉，
	#    宁可比真实比例夸张一点。长度也跟着从 0.95 提到 1.25。
	var specs := [
		{"mat": _make_flame_mat(FLAME_OUTER), "r": 0.30, "len": 1.25},
		{"mat": _make_flame_mat(FLAME_MID), "r": 0.19, "len": 1.00},
		{"mat": _make_flame_mat(FLAME_CORE), "r": 0.10, "len": 0.72},
	]
	for bn in CANNON_MUZZLE_BONES:
		var bi := _skel.find_bone(bn)
		if bi < 0:
			continue
		var holder := Node3D.new()
		holder.name = "CannonFX_%d" % bi
		holder.visible = false
		_carrier.add_child(holder)
		var layers: Array[MeshInstance3D] = []
		for sp in specs:
			var mi := MeshInstance3D.new()
			mi.mesh = cone
			mi.material_override = sp["mat"]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.layers = 1
			mi.set_meta("base_radius", float(sp["r"]))
			mi.set_meta("base_len", float(sp["len"]))
			mi.scale = Vector3(sp["r"], sp["len"], sp["r"])
			holder.add_child(mi)
			layers.append(mi)
		var light := OmniLight3D.new()
		light.light_color = Color(0.45, 0.75, 1.0)
		light.omni_range = 5.0
		light.light_energy = 0.0
		light.shadow_enabled = false
		holder.add_child(light)
		_cannon_fx.append({
			"bone": bi,
			"holder": holder,
			"layers": layers,
			"light": light,
			## 这一门还剩几秒的「亮着」时间
			"left": 0.0,
		})
		cannon_fx_count += 1


## 每帧：跟在炮口骨上；开火时把 `left` 拉满，然后按指数衰减。
##
## ── 焰口朝向：不要硬编码旋转，用骨骼自己的「前向轴」 ──
##
## 实测（`_diag_cannon_fx.gd`）：`bone_gear_cannon_outletB_L` 的 basis 是
##   X=(0.97, 0.17, -0.18)  Y=(-0.07, -0.51, -0.86)  Z=(-0.24, 0.85, -0.48)
## 也就是**骨骼的 +Y 朝下后方**（美术把炮骨摆成这样了），而 `_make_flame_mesh()`
## 做的是「尖朝 −Y」。所以直接把网格挂上去，火焰是朝**下后方**喷的 ——
## 本喵第一版就是这么写的，出图上肩炮那里什么都看不见（`7_fire_side.png`）。
##
## 正确做法：**用骨骼的 Z 轴当前向**（这个模型里骨骼 Z ≈ 模型前向），
## 再用 `Basis.looking_at(前向, 上)` 重新架一个坐标系，让网格的 −Y 对到这根 Z 上。
## 不写死角度：换一具骨架、骨名相同但美术姿势变了，也不会再错。
func _run_cannon_flash(delta: float) -> void:
	if _cannon_fx.is_empty() or _skel == null:
		return
	# 开火检测：`Weapon._shot_index` 每发 +1。用它而不是信号，
	# 因为 `Weapon` 的 `fired` 信号是 `shot_index: int`，接起来要多一处跨脚本连接；
	# 而这里每帧本来就在跑，读一个 int 最省事、也不会漏（连发 13 发/秒远低于帧率）。
	var wpn := _weapon()
	if wpn != null:
		var si: int = int(wpn.get("_shot_index"))
		if si > _last_shot_index:
			_last_shot_index = si
			_cannon_recoil = 1.0
			for fx in _cannon_fx:
				fx["left"] = 0.085        # ≈ 两帧多一点，连发时看起来是持续闪
			# 开火动作：只在**没有一次性动作在演的时候**起手，
			# 否则连发会把动画一帧一帧重启（看起来像抽搐）。
			# 连发间隔 0.075 s，动作 2.67 s / FIRE_SPEED 2.5 ≈ 1.07 s，
			# 所以这里是「播完一轮再起手下一轮」，和本体 `AnimDriver` 的节奏一致。
			if _oneshot_left <= 0.0:
				_play_oneshot("Normal_Attack_Ing", FIRE_SPEED)
	_cannon_phase += delta * 40.0
	for fx in _cannon_fx:
		var bi: int = fx["bone"]
		var holder: Node3D = fx["holder"]
		var bone_gt := _skel.global_transform * _skel.get_bone_global_pose(bi)
		# 骨骼的 Z 轴 = 炮管前向（实测这段数据里 Z ≈ 模型前方）
		var fwd := bone_gt.basis.z.normalized()
		# 网格的尖朝 −Y ⇒ 我们要让「−Y」对到 `fwd`，即「+Y」对到 `−fwd`。
		# 用一个绕 X 的 180° 把网格翻过来，再用 `looking_at` 架坐标系：
		#   `looking_at(dir)` 让 +Z 对到 dir，于是我们要让它对到 `−fwd`，
		#   之后再绕 X 转 180°，网格的 −Y 就落在 `fwd` 上了。
		var up := Vector3.UP
		if absf(fwd.dot(up)) > 0.98:
			up = Vector3.FORWARD
		var b := Basis.looking_at(-fwd, up) * Basis(Vector3.RIGHT, PI)
		holder.global_transform = Transform3D(b, bone_gt.origin)
		var left: float = float(fx["left"])
		if left > 0.0:
			fx["left"] = maxf(left - delta, 0.0)
		var on := left > 0.0
		holder.visible = on
		if not on:
			(fx["light"] as OmniLight3D).light_energy = 0.0
			continue
		# 越接近熄灭越短，看起来像「闪一下」
		var t := clampf(left / 0.085, 0.0, 1.0)
		var jitter := 0.85 + 0.15 * sin(_cannon_phase)
		var layers: Array = fx["layers"]
		for mi in layers:
			var m := (mi as MeshInstance3D)
			var br: float = float(m.get_meta("base_radius", 0.1))
			var bl: float = float(m.get_meta("base_len", 0.7))
			var g := lerpf(0.45, 1.0, t) * jitter
			m.scale = Vector3(br * g, bl * g, br * g)
			var mat := m.material_override as StandardMaterial3D
			if mat != null:
				mat.emission_energy_multiplier = lerpf(1.0, 7.0, t)
		(fx["light"] as OmniLight3D).light_energy = 3.2 * t * jitter


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

	# ── 一次性动作（开火 / 换弹 / 受击）在演的时候，不要被移动逻辑顶掉 ──
	if _oneshot_left > 0.0:
		_oneshot_left = maxf(_oneshot_left - delta, 0.0)
		return

	if _airborne:
		# 飞行时用 Move_Ing（有战斗移动姿势，比慢走更像「推进中」），
		# 没借到就退回 Walk
		if _has_clip("Move_Ing"):
			_play("Move_Ing", false)
			_ap.speed_scale = clampf(speed / 5.2, 0.7, 2.0)
		else:
			_play("Walk", false)
			_ap.speed_scale = clampf(speed / FLY_WALK_REF, 0.7, WALK_SPEED_SCALE_MAX)
	elif speed > WALK_SPEED:
		# 地上移动：借到 Move_Ing 就用它（战斗姿势，两只手在枪上），
		# 否则退回载具自带的 Walk
		if _has_clip("Move_Ing"):
			_play("Move_Ing", false)
			_ap.speed_scale = clampf(speed / 5.2, 0.8, 2.0)
		else:
			_play("Walk", false)
			_ap.speed_scale = clampf(speed / FLY_WALK_REF, 0.8, WALK_SPEED_SCALE_MAX)
	else:
		if _has_clip("Normal_Idle"):
			_play("Normal_Idle", false)
		else:
			_play("Idle", false)
		_ap.speed_scale = 1.0


func _has_clip(name_: String) -> bool:
	return _ap != null and _ap.has_animation(name_)


## 播一次一次性动作（开火 / 换弹 / 受击 / 必杀），播完回到移动态。
##
## ⚠️ 用 `_oneshot_left` 挡着 `_process()`：载具的动作是**整身**的（不像本体有
##    上半身叠加层），所以开火动画必须独占播放，否则下一帧就被 `Move_Ing` 顶掉，
##    看起来是「按了开枪但什么都没演」。
func _play_oneshot(clip: String, speed: float = 1.0) -> bool:
	if _ap == null or not _ap.has_animation(clip):
		return false
	_cur_anim = clip
	_ap.speed_scale = speed
	_ap.play(clip, 0.06, 1.0)
	_oneshot_left = _ap.get_animation(clip).length / maxf(speed, 0.01)
	return true


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
