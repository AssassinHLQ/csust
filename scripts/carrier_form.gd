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

# ── 巡航者模式 + 能量条（用户 2026-11-08）──────────────────────────────────
#
# 用户原话拆条：
#   · 「按 T 启动巡航者模式，关闭武器能够更快飞行」→ 按 T 切换：武器关闭 + 飞行加速
#   · 「累计飞行（包括巡航）3km 积攒满能量条」     → 每 3000 m 满 1 条
#   · 「最多五条」                                 → 上限 5
#   · 「按 R 启动一个能量条，5 秒内攻速再翻倍」     → 每条 5 秒
#   · 「5 条可以同时用，按一次启动一条，时间独立计算，也可以分多次使用」
#   · 「每启用一条，攻速就增加，增加量是基础攻速那么多」→ 倍率 = 1 + 已启用条数
#        即 1 条=×2、2 条=×3、3 条=×4……第一条到点就从 ×4 掉回 ×3
#   · 「开启期间还是可以飞行积攒能量条的」          → 攒条与加速互不阻塞
const CRUISE_KEY := KEY_T
const ENERGY_KEY := KEY_R
## 头部朝向的闭环补偿（用户 2026-11-08：「飞行还是仰视没修好」）。
##
## ── 为什么上轮那个「机身俯仰」没用 ──
## 本喵上轮量的是**脊梁**（胯→头）的夹角，修到 +1.91° 就以为平视了。
## 这次换了量法（`_diag_carrier_head.gd`）：先在地面待机下自标定出「头骨哪根
## 局部轴 = 脸朝前」，结果是 **local Y**（在 `Idle` / `Walk` 下它的前向分量
## 正好 +1.000、仰角 +1.4°，即站定时脸正对前方）。然后拿它去量各条动画：
##
##     Idle              +1.46°      Walk   +1.30°       ← 正常
##     Move_Ing         +45.99°      ← **飞行时播的就是这条，脸朝上 46 度**
##     Normal_Attack_Ing −11.64°
##
## 也就是那 46° 的仰头**是动画自带的**，脊梁平不平根本管不着它。
##
## ── 做法：闭环，而不是写死一个角度 ──
## 每帧量出「脸」当前的仰角，然后绕**水平横轴**把它掰回 0。
## 写死 −46° 只对 `Move_Ing` 成立，而飞行在借不到 `Move_Ing` 时会退回 `Walk`
## （那时脸本来就是平的，硬掰 −46° 就变成低头看脚）。闭环对任何动画都自洽。
##
## ⚠️ 只在**飞行中**生效：地面待机 `Normal_Idle` 实测 −18.6°（低头，是动画的
##    表演），站定/走路的头部动作不该被本喵抹平。
const HEAD_FIX_ENABLE := true
## 补偿力度：1.0 = 完全掰平
const HEAD_FIX_GAIN := 1.0
## 单帧最大补偿角（度），防止某个畸形帧把脖子拧断
const HEAD_FIX_MAX_DEG := 60.0
## 用来量「脸」的头骨与它 local Y 轴 = 脸朝前（实测，见上）
const HEAD_BONE := "Bip001 Head"
##
## 用户 2026-11-08：「巡航者太慢了」。原来写 1.6（巡航 11 → 17.6 m/s，
## 加力 19 → 30.4 m/s）。提到 **2.6** 后：巡航 **28.6**、加力 **49.4 m/s**
## —— 「关掉武器换速度」要有明显体感，不然玩家不会想按 T。
const CRUISE_SPEED_SCALE := 2.6
## 每条能量条需要累计多少米飞行
##
## ⚠️ 用户 2026-11-08 改的：3000 → **500**（「把 3km 更改 1km」→「不对,500m」）。
##    500 m 在校园里飞一圈就到了，攒条不再需要长途跋涉。
const ENERGY_PER_BAR_M := 500.0
## 暴露给自检 / HUD 的「每条要多少米」。`const` 不能用 `get()` 读到，
## 所以这里给一个函数（探针里改成读它，以后再调距离探针不用跟着改）。
func energy_per_bar_m() -> float:
	return ENERGY_PER_BAR_M
const MAX_BARS := 5
## 每条能量条的持续时间（秒）
const BAR_SECONDS := 5.0

## 巡航者模式开着吗
var cruise := false
## 本局累计飞行距离（米，不扣减；用来显示进度）
##
## ⚠️ 统计的是**三维空间位移量**（用户 2026-11-08：「上升下降也要算，
##    不能只算水平的位移，算空间的移动量绝对值」）。见 `_update_power()`：
##    取的是每帧 `global_position` 的位移长度，而不是「水平速度 × dt」——
##    前者连上升 / 下降 / 斜着飞都算进去，而且**被墙挡住时位移是 0、不会白算**。
var fly_distance_m := 0.0
## 上一帧的位置（算空间位移用）。`_has_last_pos` 为假时跳过一帧，避免刚起飞那一帧
## 拿旧位置算出一个巨大的假位移。
var _last_pos := Vector3.ZERO
var _has_last_pos := false
## 攒好的能量条数（0~5）
var energy_bars := 0
## 每条**已启用**能量条各自的剩余秒数（独立计时）
var _bar_timers: Array[float] = []
## 当前攻速倍率（= 1 + 已启用条数），暴露给 HUD / 自检
var rate_scale := 1.0
## HUD 上那行能量条（运行时自己建，不动 `hud.tscn`）
var _power_layer: CanvasLayer
var _power_label: Label

# ── 飞行机身俯仰（2026-11-08 用户：「飞行姿势为什么这么奇怪，仰头，应该平视前方」）──
#
# ⚠️ 本喵**先量后改**，量法见 `_diag_carrier_pose.gd`：脊梁（胯→头）相对
#    「正前方 / 正上方」的夹角。飞行时播的 `Move_Ing` 在载具骨架上量出来是
#    **−7.31°**（头在胯的**后方**）—— 也就是动画自带一个后仰。
#    顺带量了别的：载具自带 `Idle` −6.60°、`Walk` −4.32°、
#    只有地面待机 `Normal_Idle` 是 +2.01°。
#
# ⚠️ 而且旧版有一段**死代码**：`_lean` 每帧算出来、存进去，却**从来没有被应用到
#    任何地方**（全文件只写不读）。所以「前倾」这个特性从第一版起就没生效过，
#    玩家看到的一直是动画自带的姿势。这次把它真正接上。
#
# 补偿量 = 把动画那个 −7.31° 压平（+7.31°），再加一点「飞行该有的」前倾。
const POSE_BACK_LEAN_DEG := 7.31
## 悬停时的净前倾（度）。= 压平动画后仰 + 一点点，让头真正平视前方。
const FLY_PITCH_LEVEL_DEG := 7.31 + 1.5
## 每 1 m/s 额外加的前倾（度）
const FLY_PITCH_PER_SPEED := 0.40
## 速度带来的额外前倾上限（度）。别加太多 —— 用户要的是「平视」，不是俯冲。
## 实测（`_verify_carrier_pitch.gd`）：0.55/11.0 时加力 19 m/s 会把脊梁压到 +12.5°，
## 对「平视」来说太狠了；0.40/9.0 大约是巡航 +5.9°、加力 +9.1°，像「前冲」而不像俯冲。
const FLY_PITCH_EXTRA_MAX_DEG := 9.0

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
##
## ⚠️ 2026-11-08 提到 **1.6**：出图（`_probe_carrier_fx.gd` 的 2_climb）里焰只有
##    腿下一小团，「粗糙」感有一半来自**太短**。配合三层新的长宽比
##    （0.55 / 0.95 / 1.40），满推力时最长的芯焰是 1.6 × 1.40 ≈ **2.24 m**。
const FLAME_LEN := 1.6

@export var toggle_key: Key = KEY_G
## 起飞 / 上升键。`Space` 与 `Q` 都能用（用户报过「空格偶尔没反应」，见 `player.gd`
## 的 `JUMP_BUFFER_MS` 那段：跑酷落脚板上 `is_on_floor()` 会逐帧抖动）。
@export var rise_key: Key = KEY_Q
## 载具模型相对本体的额外偏航（度）。
##
## ✅ **实测值 = 0**（2026-11-08 用 `_diag_carrier_face.gd` 的**对照出图**定出来的）。
##
## ── 这里踩过一个很贵的坑，别再把 180 加回来 ──
## 上一版是 180，依据是「相机摆在角色 +Z 正前方时看到光环 + 背包（背面），
## 说明载具 glb 脸朝 −Z，而本工程约定脸朝 +Z，所以要再转 180°」。
## 那一步推理漏了一件事实：**那次出图时 `Arisu.rotation.y` 已经是 PI**。
## 也就是说载具看到的「背面」是**转完之后**的结果 —— `PI + 0` 正好把 glb 的
## 原生 −Z 脸翻到世界 +Z（背对 +Z 机位），本来就对。再加 180 就转成 −Z，
## 于是她从「背对镜头」变成「正脸看镜头」，玩家看到的就是「人反了」。
##
## 正确的判据是**拿本体当对照**，而不是靠记忆里的「约定」：
## 同一台相机（+Z 侧）分别拍本体与机甲 —— 本体出后背、机甲也该出后背。
## 实测的对照结果：
##   · `facing_yaw_deg = 180` → 机甲出**正脸**（错）
##   · `facing_yaw_deg = 0`   → 机甲出**后背**，和本体一致（对）
## 顺带：机甲的两门肩炮方向也跟着这个偏航走，转错 180° 时炮口是朝身后的。
@export var facing_yaw_deg := 0.0

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
## 开火动作的名字（要叠上半身的就是这一条）
const ATTACK_CLIP := "Normal_Attack_Ing"
## 「下半身」的判据 —— 和 `anim_driver.gd` 的 `LOWER_KEYWORDS` 同一套
## （两边是同一个 145 骨 BA 骨架，骨名一致）。
const LOWER_KEYWORDS := ["thigh", "calf", "foot", "toe", "leg", "pelvis", "hip",
	"root", "skirt"]
## 「躯干」的判据。开火动作的躯干是按**站桩**摆的，而飞行时基础层是 `Move_Ing`
## （前倾）—— 不滤会在开火那一瞬间把躯干弹成站姿。
## `anim_driver.gd` 那边实测这个差值是 **65°**（`_probe_fire_lean.gd`）。
const TRUNK_KEYWORDS := ["spine", "chest", "neck", "head"]
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


## ── 开火动作：只叠**上半身**（用户 2026-11-09 选定方案 A）──
##
## 病根（用户：「爱丽丝机甲攻击动画为什么僵硬」）：
##   `Normal_Attack_Ing` 是**整身**动作（从人体 glb 借来的），而载具**没有叠加层**，
##   所以它只能独占播放 —— `_process()` 在 `_oneshot_left` 期间直接 `return`，
##   移动 / 飞行动画停止刷新，人被锁成一个姿势 **1.07 s**。
##   再叠上 0.10 s 一发的射速（`beam_fire_interval`）：
##   **10 发里 9 发只有炮口闪光、身体一动不动** —— 这就是「僵硬」的来源。
##
## 做法照 `anim_driver.gd::_setup_upper_layer()`（同一个骨架构、同一套关键字）：
##   · 另建一个 `AnimationPlayer` 当**兄弟节点**，`root_node` 指同一个根；
##   · 里面装一份**滤掉下半身 + 躯干**的副本；
##   · `process_priority` 比基础层大 1 ⇒ 同一帧后写赢 ⇒ 腿归基础层、上半身归这层。
##
## ⚠️ 为什么连**躯干**一起滤：开火动作的脊椎是按「站桩」摆的，飞行时基础层是
##    `Move_Ing`（前倾）。不滤的话开火那一瞬间躯干会弹成站姿 —— `anim_driver`
##    那边实测差 **65°**，是「一开枪就像被掰直」的元凶。
##    所以本层只让**手臂 / 武器 / 头发 / 挂饰**随开火动。
func _setup_upper_layer() -> void:
	if _ap == null:
		return
	var host := _ap.get_parent()
	if host == null:
		push_warning("[Carrier] AnimationPlayer 没有父节点，叠加层做不了")
		return
	if not _ap.has_animation(ATTACK_CLIP):
		push_warning("[Carrier] 没有 %s，开火动作退回整身独占" % ATTACK_CLIP)
		return
	var ov := AnimationPlayer.new()
	ov.name = "UpperAttack"
	# 轨道路径相对 `root_node`，两层必须指向同一个根
	ov.root_node = _ap.root_node
	# 比基础层大 1 ⇒ 后写赢（本节点自己是 10，仍然在两层之后跑）
	ov.process_priority = _ap.process_priority + 1
	var lib := AnimationLibrary.new()
	var a: Animation = _ap.get_animation(ATTACK_CLIP).duplicate(true)
	var removed := 0
	for t in range(a.get_track_count() - 1, -1, -1):
		var path_s := String(a.track_get_path(t))
		# ⚠️ **节点轨道**（路径里没有 `:`）= 模型根节点自己的 position / rotation。
		#    它们会把整个模型按开火姿势再转一遍（基础层已经管了），必须丢。
		if not path_s.contains(":"):
			a.remove_track(t)
			removed += 1
			continue
		var bone := _bone_of_track(path_s)
		if _in_kw(bone, LOWER_KEYWORDS) or _in_kw(bone, TRUNK_KEYWORDS):
			a.remove_track(t)
			removed += 1
	lib.add_animation(ATTACK_CLIP, a)
	ov.add_animation_library(&"", lib)
	# ⚠️ **必须延后一帧加进树**：`_build()` 期间父节点还在装自己的孩子，
	#    直接 `add_child()` 会失败，而且失败是**静默的**（不在树里 ⇒ 一帧都不更新
	#    ⇒ 上半身根本没叠上去）。这个坑 `anim_driver.gd` 里记过一次。
	host.add_child.call_deferred(ov)
	_upper = ov
	upper_tracks_removed = removed
	print("[Carrier] 开火叠加层就位：%s 滤掉 %d 条轨道（剩 %d 条：上半身）｜优先级 %d > 基础层 %d" % [
		ATTACK_CLIP, upper_tracks_removed, a.get_track_count(),
		ov.process_priority, _ap.process_priority])


## 轨道路径（`Node/Path:bone_name`）取出骨名；节点轨道返回空串
func _bone_of_track(path: String) -> String:
	var i := path.rfind(":")
	return path.substr(i + 1) if i >= 0 else ""


func _in_kw(bone: String, kws: Array) -> bool:
	if bone.is_empty():
		return false
	var low := bone.to_lower()
	for k in kws:
		if low.contains(String(k)):
			return true
	return false


## 载具模型整体缩放（先用 1.0，看着不对再调）
@export var carrier_scale := 1.0

var _player: CharacterBody3D
var _model: Node3D
var _carrier: Node3D
var _ap: AnimationPlayer
var _skel: Skeleton3D
var _on := false
var _cur_anim := ""
## 上半身叠加层（开火用）。见 `_setup_upper_layer()`。
var _upper: AnimationPlayer
## 这一发是「只叠上半身」还是「整身独占」。
## 开火 = 叠加（`false`，腿继续飞）；其余一次性动作 = 整身（`true`，挡住移动动画）。
var _oneshot_full := true
## 叠加层滤掉了多少条轨道（自检 / 控制台用）
var upper_tracks_removed := 0

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
## 肩翼 / 导弹荚上的**小喷口**（不是推进器，只是装饰性的短焰）
var _aux_fx: Array = []
## 推进器喷口往外 / 往后的偏移（米）。
## 见 `_run_effects()` 里那段实测说明：推进器骨几乎在中线上，
## 不推开的话两道焰并排从腿中间插出来，像两把刀。
const BOOST_OUT_OFFSET := 0.10
const BOOST_BACK_OFFSET := 0.06

## 肩翼 / 导弹荚的骨名（小喷口挂点）。
##
## ✅ 骨名是**实测**的（`_diag_carrier_bones.gd` 列了载体 191 根骨）：
##   86  bone_gear_wing_L   107 bone_gear_wing_R    ← 翼根
##   103 bone_missilepod_L  124 bone_missilepod_R   ← 导弹荚
##   87~94 / 108~115  bone_wing_LDL_01 … bone_wing_RUL_02  ← 8 片翼叶
## ⚠️ `bone_gearboost_L/R` **不在这个列表里** —— 本喵上一版以为推进器叫
##    `bone_gearboost_*`，其实它挂在别处（`BOOST_BONES` 那两根能找到，
##    但上面的名字过滤没列出来，说明名字不完全是 gearboost）。不用纠结。
##
## 选**翼根**（`bone_gear_wing_*`）而不是翼叶：翼叶 8 片太碎、每片一个喷口
## 会变成「一堆小火苗」；翼根一个喷口、导弹荚一个，正好是四个配角。
const AUX_NOZZLE_BONES := [
	"bone_gear_wing_L", "bone_gear_wing_R",
	"bone_missilepod_L", "bone_missilepod_R",
]

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
	# 头部补偿写在 `_process` 里，必须晚于 `AnimationPlayer`（默认 priority 0）
	process_priority = 10
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
	# 告诉 `player.gd`「现在是机甲形态」——它据此决定**地上也走飞行速度那一档**
	# （用户 2026-11-09：「在地上怎么飞这么慢，不应该也是飞吗」）。见 `_carrier_on`。
	if _player != null and _player.has_method("set_carrier_form"):
		_player.call("set_carrier_form", on)
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
		# 变回本体：巡航者模式必须一起关掉 —— 否则 `player.gd` 的飞行加速
		# （`set_flight_speed_scale`）和武器的 `disabled` 会**留到本体形态**，
		# 表现就是「变回来以后跑得飞快、而且开不了枪」。
		if cruise:
			set_cruise(false)
		# ⚠️ 2026-11-10 修：机甲的「能量条 HUD」必须在这里显式隐藏。
		#
		# 用户：「变回普通爱丽丝为什么还有机甲爱丽丝的hud」。
		# 真因：`_update_power_hud()` 里虽然有 `if not _on: hide`，
		# 但那个函数**只在 `_update_power()` 里被调**，
		# 而 `_update_power()` 又只在机甲形态的 `_process` 里跑 ——
		# 变回本体后 `set_process(false)`，这条隐藏逻辑永远执行不到。
		# 实测（`_diag_carrier_hud_pitch.gd`）：变回后 visible 仍然是 true，
		# 屏幕上就留着一行「◆◆◆◆◆ 5/5 进度 100% 巡航者模式」。
		# 结论：**隐藏要写在状态切换处，不能依赖每帧更新**。
		_hide_power_hud()
		# 变回本体：如果还在空中，把垂直速度留给 `player.gd` 的重力去接（它自己会掉下来）；
		# 这里只把「飞行接管」的标志清掉，不动位置。
		_airborne = false
		_vert_want = 0.0
		_hold_y = -9000.0
		_thrust = 0.0
		_lean = 0.0
		# 变回本体：把开火叠加层停掉（留着会继续写那几根上半身骨）
		if _upper != null:
			_upper.stop()
		_oneshot_left = 0.0
		_oneshot_full = true
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
		_build_extra_fx()
		_borrow_anims()
		_setup_upper_layer()
		print("[Carrier] 机甲硬件就位：推进器 %d 根｜肩翼 %d 根｜炮 %d 根｜炮口焰 %d 个｜动作 %d 条" % [
			_boost_fx.size(), _found_wing_bones(), _found_cannon_bones(), cannon_fx_count,
			_ap.get_animation_list().size() if _ap != null else 0])
	else:
		push_warning("[Carrier] 载具模型里没找到 Skeleton3D，飞行特效不会出现")
	return true


## 装饰特效层（2026-11-10，用户：「总感觉不够多不够炫丽」）。
##
## 五样纯装饰：等离子光带 / 能量环阵列 / 速度气流线 / 翼尖光点 / 加力尾焰。
## 拆到 `carrier_fx_extra.gd` 是因为本文件已经 2000+ 行 —— 再塞进来没法维护，
## 而且那一层出问题（掉帧/穿模）可以整体关掉，不影响飞行本身。
var _fx_extra: Node3D = null
const FxExtra := preload("res://scripts/carrier_fx_extra.gd")


func _build_extra_fx() -> void:
	if _fx_extra != null:
		return
	if _skel == null or _carrier == null:
		return
	_fx_extra = FxExtra.new() as Node3D
	if _fx_extra == null:
		return
	_fx_extra.name = "ExtraFx"
	_carrier.add_child(_fx_extra)
	_fx_extra.call("build", _carrier, _skel, _player)


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
		# ── 三层锥体：**长宽比必须拉开**，否则叠起来还是一个硬边三角 ──
		#
		# 用户 2026-11-08：「飞行特效太粗糙两个三角形」。
		# 旧值是 0.20/1.00、0.14/0.82、0.08/0.62 —— 三个锥的长宽比几乎一样
		# （1:5、1:6、1:8），叠在一起轮廓还是**一个三角**，只是亮了一点。
		# 现在改成三种**不同的形状**：
		#   · 外层：又宽又短（裙摆）→ 负责轮廓的「胖」
		#   · 中层：中等
		#   · 芯层：又细又长     → 负责「尖」
		# 1:1.8 / 1:5.6 / 1:18 三种比例叠起来才有火焰的体积感。
		var specs := [
			{"mat": mat_outer, "r": 0.26, "len": 0.70},
			{"mat": mat_mid, "r": 0.17, "len": 1.05},
			{"mat": mat_core, "r": 0.10, "len": 1.35},
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

		# ── 喷口激波环（2026-11-10 新增）──
		#
		# 真实喷气口后面会一圈圈"推"出激波环（马赫环 / shock diamonds 的视觉简化）。
		# 旧版三层锥 + 柔光斑还是"静态的两根焰"，缺的就是这个**周期性的动**。
		#
		# 做法：一个细圆环（TorusMesh），沿 −Y 不断外扩 + 淡出，循环。
		# 之所以用独立节点而不是粒子：环要**保持正圆且垂直于喷流**，
		# 粒子会被 spread/重力带歪，读起来是"雾"不是"激波"。
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.72
		torus.outer_radius = 1.0
		torus.rings = 16
		torus.ring_segments = 8
		ring.mesh = torus
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.layers = 1
		var ring_mat := StandardMaterial3D.new()
		ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		ring_mat.albedo_color = Color(0.62, 0.88, 1.00, 0.55)
		ring_mat.emission_enabled = true
		ring_mat.emission = Color(0.50, 0.80, 1.00)
		ring_mat.emission_energy_multiplier = 3.5
		ring_mat.disable_receive_shadows = true
		ring.material_override = ring_mat
		# TorusMesh 默认躺在 XZ 平面（环轴 = Y），喷流沿 −Y ⇒ 正好垂直，不用转
		ring.scale = Vector3(0.22, 0.10, 0.22)
		holder.add_child(ring)

		# 再补一个错相的环：两个环一前一后，读起来是"连续推出去的"
		var ring2 := MeshInstance3D.new()
		ring2.mesh = torus
		ring2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring2.layers = 1
		var ring_mat2 := ring_mat.duplicate() as StandardMaterial3D
		ring2.material_override = ring_mat2
		ring2.scale = Vector3(0.15, 0.08, 0.15)
		holder.add_child(ring2)

		# 喷口处一片**面向相机的柔光**。
		# 硬边三角的另一半原因是「喷口只有锥体」——锥体的底边是一条直线，
		# 从侧面看就是一条硬边。加一层软圆斑之后，喷口读起来是
		# 「一团光往外喷」而不是「一个角」。
		# ⚠️ **必须用带径向渐变的贴图，不能用裸 QuadMesh**：
		#    本喵第一版直接用 `QuadMesh` + billboard 材质，出图上就是
		#    **两个硬边蓝色方块**贴在机甲身上（`_probe_carrier_fx.gd` 的 2_climb）。
		#    纯色 billboard 没有边缘衰减 = 一个实心方片。
		var glow := MeshInstance3D.new()
		glow.mesh = _make_glow_quad()
		glow.material_override = _make_glow_mat()
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glow.layers = 1
		glow.position = Vector3(0.0, -0.10, 0.0)
		holder.add_child(glow)

		# 喷气粒子
		var gp := GPUParticles3D.new()
		# ── 从「一团雾」改成「一条尾迹」（用户 2026-11-08）──
		# 原来是 amount 72 / lifetime 0.34 / 初速 1.6~4.2 / 阻尼 3~6：
		# 粒子刚出去就被阻尼刹住，堆在喷口附近 = 一团雾，看不出「在飞」。
		# 现在拉长寿命、提高初速、减小阻尼 —— 粒子会**拖着一条尾巴走**。
		gp.amount = 96
		gp.lifetime = 0.5
		gp.local_coords = false
		gp.emitting = false
		gp.visibility_aabb = AABB(Vector3(-4, -8, -4), Vector3(8, 12, 8))
		gp.draw_pass_1 = particle_mesh
		gp.material_override = particle_mat
		var pm := ParticleProcessMaterial.new()
		# ⚠️ 粒子方向必须是**挂点局部**的：挂点跟着骨走，骨的 local −Y 就是朝下
		#    （实测 `bone_gearboost_L` 的 localY·上 = +0.90 ⇒ −Y 朝下）。
		#    本喵第二版把它写成 `(0,-1,0)` 却忘了挂点被 `Basis(RIGHT, PI)` 翻过，
		#    粒子就朝天上跑了 —— 出图里完全看不到尾迹。
		pm.direction = Vector3(0.0, -1.0, 0.0)
		pm.spread = 8.0
		pm.initial_velocity_min = 3.0
		pm.initial_velocity_max = 8.0
		pm.gravity = Vector3(0.0, -3.0, 0.0)
		pm.scale_min = 0.30
		pm.scale_max = 0.80
		pm.color = Color(0.30, 0.58, 1.00, 0.30)
		pm.damping_min = 1.5
		pm.damping_max = 3.5
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
			"glow": glow,
			"rings": [ring, ring2],
			"ring_mats": [ring_mat, ring_mat2],
		})
	boost_dot_count = _boost_fx.size()
	_build_aux_fx()


## 肩翼 / 导弹荚上的**小喷口**：短而小的蓝焰，只在飞行时冒一点。
##
## 为什么加这个（用户 2026-11-08：「飞行特效太粗糙两个三角形」）：
## 只有腿上两个大推进器在喷，画面上就是「两团火」；肩翼和导弹荚一点动静都没有，
## 整机看着像「屁股上装了俩喷气头」。给它们各加一个小喷口，视觉上才是
## 「全身在推进」。
##
## 刻意做得**小**（半径 0.09、长度 0.35）而且只给 35% 的亮度 —— 它们是配角，
## 抢了主推进器的戏就会变成「四个大喷口」。
func _build_aux_fx() -> void:
	_aux_fx.clear()
	if _skel == null:
		return
	var cone := _make_flame_mesh()
	for bn in AUX_NOZZLE_BONES:
		var bi := _skel.find_bone(bn)
		if bi < 0:
			continue
		var holder := Node3D.new()
		holder.name = "AuxFX_%d" % bi
		holder.visible = false
		_carrier.add_child(holder)
		var mi := MeshInstance3D.new()
		mi.mesh = cone
		mi.material_override = _make_flame_mat(FLAME_MID)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = 1
		mi.scale = Vector3(0.09, 0.35, 0.09)
		holder.add_child(mi)
		# 也加一片柔光，让喷口读起来是「一团小焰」而不是一根小刺
		var aglow := MeshInstance3D.new()
		aglow.mesh = _make_glow_quad()
		aglow.material_override = _make_glow_mat()
		aglow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		aglow.layers = 1
		aglow.scale = Vector3(0.5, 0.5, 0.5)
		holder.add_child(aglow)
		_aux_fx.append({"bone": bi, "holder": holder, "mesh": mi, "glow": aglow})


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
##
## ── 2026-11-08：尖锥改成「喷焰形」（不再是刀）──
## 出图（`_probe_carrier_fx.gd` 的 3_cruise）里两道焰是**细长的尖锥**，
## 从腿下插出来像两把刀。真正的喷气火焰是：
##   · **靠近喷口最粗**（喷口大、焰从那儿出来）
##   · 往远处**逐渐收细但不断尖**
##   · 末端**钝圆**（不是针尖）
## 所以这里不再用 `CylinderMesh`（它是「底圆 + 尖点」的直锥），
## 改成**自建一圈圈圆环**：半径按 `r(t) = (1-t)^0.55` 收（比线性收得快，
## 前段粗、后段细），末端半径留 0.18 不归零（钝圆）。
## 顶点数：8 段圆环 × 12 边 = 96 个顶点，很轻。
func _make_flame_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	# ⚠️ **`begin()` 不能少！** 本喵第一版自建这个网格时忘了调它，
	#    结果 `commit()` 出来是个**空网格**（AABB = (0,0,0)）——
	#    出图上只看得见柔光那层（它是独立节点），焰本体压根不存在。
	#    是 `_diag_carrier_fxsize.gd` 量出来的：scale.y 明明是 1.587，
	#    但网格自己的 AABB 是 0。
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 12          # 每圈多少边
	var rings := 8          # 多少圈
	var r0 := 1.0           # 根部半径（缩放前）
	# ⚠️ 末端半径 **0.55**（不是 0.18）：0.18 太接近针尖，出图上是两根针
	#    （`_probe_carrier_fx.gd` 的 4_side）。0.55 = 焰尾仍然有明显的粗度。
	var r_end := 0.55       # 末端半径（**不归零** → 钝圆，不是针尖）
	# 参数 t：0 = 根部（喷口），1 = 末端（焰尾）
	# 半径曲线：前段粗、后段收得快
	for ri in rings:
		var t0 := float(ri) / float(rings)
		var t1 := float(ri + 1) / float(rings)
		var rr0 := lerpf(r0, r_end, pow(t0, 0.55))
		var rr1 := lerpf(r0, r_end, pow(t1, 0.55))
		var y0 := -t0        # 朝 −Y
		var y1 := -t1
		for si in segs:
			var a0 := TAU * float(si) / float(segs)
			var a1 := TAU * float(si + 1) / float(segs)
			var p00 := Vector3(cos(a0) * rr0, y0, sin(a0) * rr0)
			var p10 := Vector3(cos(a1) * rr0, y0, sin(a1) * rr0)
			var p01 := Vector3(cos(a0) * rr1, y1, sin(a0) * rr1)
			var p11 := Vector3(cos(a1) * rr1, y1, sin(a1) * rr1)
			st.set_color(Color(1, 1, 1, 1))
			st.add_vertex(p00)
			st.add_vertex(p10)
			st.add_vertex(p11)
			st.add_vertex(p00)
			st.add_vertex(p11)
			st.add_vertex(p01)
	st.generate_normals()
	return st.commit()


## 加色混合的火焰材质。`blend_mode = ADD` + 不写深度 ⇒ 多层叠起来就是发光的蓝焰。
##
## ── 2026-11-10 细化（用户：「继续细化飞行特效」）──
##
## 旧材质是**纯色光面**：锥体侧面亮度均匀，看起来像一块塑料片在发光，
## 没有「在燃烧」的细节。现在贴一张**程序化噪声图**，沿 Y 轴流动：
##   · 噪声给表面加了明暗起伏 → 有焰舌的斑驳感
##   · 用 `uv1_scale` 把噪声在 Y 方向拉长（1×3），读起来是**竖向的火舌**
##   · 滚动靠 `_run_effects()` 里每帧改 `albedo_texture` 的偏移不行（会整体走样），
##     所以改用 **材质自发光能量 + 顶点噪声图**：噪声是静态的，但每层相位不同，
##     三层错开后视觉上就在"翻动"（加色混合放大差异）。
func _make_flame_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.disable_receive_shadows = true
	m.albedo_color = c
	# 噪声贴图：让表面有斑驳的火舌质感（纯色太"塑料"）
	m.albedo_texture = _flame_noise_tex_or_make()
	m.uv1_scale = Vector3(1.0, 3.0, 1.0)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 3.0
	return m


## 焰面噪声贴图（128×128）。**只用红通道**当亮度调制：
## 中心区域亮、边缘暗，叠一层高频斑点 —— 贴到锥体上就像焰舌在翻。
##
## 为什么自己生成而不是引资源：项目里没有合适的无缝噪声贴图，
## 而这张 128×128（64 KB）开销可以忽略，且**确定性**（同一 seed 每次一样，
## 出图对比不会因为噪声随机而误判）。
static var _flame_noise_tex: ImageTexture = null


func _flame_noise_tex_or_make() -> ImageTexture:
	if _flame_noise_tex != null:
		return _flame_noise_tex
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	# 固定种子：出图对比要可复现
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5EED
	# 两层叠加：粗斑（低频）+ 细斑（高频），比单层纯随机更像"火焰"
	var coarse := []
	var fine := []
	for i in 64:
		coarse.append(rng.randf())
	for i in 256:
		fine.append(rng.randf())
	for y in n:
		for x in n:
			var u := float(x) / float(n)
			var v := float(y) / float(n)
			# 低频：8×8 格之间双线性插值
			var cu := u * 8.0
			var cv := v * 8.0
			var ci := int(cu) % 8
			var cj := int(cv) % 8
			var fx := cu - float(int(cu))
			var fy := cv - float(int(cv))
			var c00: float = coarse[cj * 8 + ci]
			var c10: float = coarse[cj * 8 + (ci + 1) % 8]
			var c01: float = coarse[((cj + 1) % 8) * 8 + ci]
			var c11: float = coarse[((cj + 1) % 8) * 8 + (ci + 1) % 8]
			var top := lerpf(c00, c10, fx)
			var bot := lerpf(c01, c11, fx)
			var low := lerpf(top, bot, fy)
			# 高频：16×16
			var hi: float = fine[((int(v * 16.0) * 16 + int(u * 16.0)) % 256)]
			# 混合：低频为主（0.72），高频提细节（0.28）
			var t := low * 0.72 + hi * 0.28
			# 收一下对比度：太散会把焰拉花
			t = clampf(0.35 + t * 0.85, 0.0, 1.0)
			# 边缘稍微暗一点（让锥体的轮廓更明确）
			var edge := 1.0 - absf(v - 0.5) * 0.35
			t *= edge
			img.set_pixel(x, y, Color(t, t, t, 1.0))
	_flame_noise_tex = ImageTexture.create_from_image(img)
	return _flame_noise_tex


func _make_particle_mesh() -> QuadMesh:
	# ⚠️ 0.26 太大、而且 `billboard_keep_scale` 一开就变成「一片片带透视的方块」，
	#    出图上像故障贴图而不是喷气（见 `_probe_carrier_shot.gd` 的 2_hover/3_side）。
	#    0.09 是肉眼看起来「颗粒」的大小；靠数量（amount）而不是靠尺寸堆出体积感。
	# ⚠️ 贴图用**软圆斑**：纯色方片在加色混合下会变成一片片硬边方块
	#    （第一版就是这样，出图上像「方块瀑布」）。带径向渐变才像雾。
	var q := QuadMesh.new()
	q.size = Vector2(0.11, 0.11)
	# ⚠️ 这里**不挂材质**：`GPUParticles3D.material_override` 会覆盖网格自带的材质，
	#    而真正带软圆斑贴图的是 `particle_mat`（见 `_make_particle_mat()`）。
	#    本喵第一版两边都挂，结果生成两份材质、还多了一份没贴图的。
	return q


## 喷口柔光用的**软圆斑**网格（带径向渐变的贴图）。
##
## ⚠️ 不能用裸 `QuadMesh`：纯色 billboard 没有边缘衰减，出图就是硬边方块。
## 这里生成一张 64×64 的径向渐变贴图（中心亮、边缘透明），贴到方片上。
static var _glow_tex: ImageTexture = null


func _make_glow_quad() -> QuadMesh:
	if _glow_tex == null:
		_glow_tex = _build_glow_texture()
	var q := QuadMesh.new()
	q.size = Vector2(0.85, 0.85)
	q.material = _make_glow_mat()
	return q


## 径向渐变贴图：中心 1.0 → 边缘 0.0，**带一点陡度**（不是线性，
## 否则边缘还是能看出方片的轮廓）。
func _build_glow_texture() -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (float(x) + 0.5) / float(n) * 2.0 - 1.0
			var v := (float(y) + 0.5) / float(n) * 2.0 - 1.0
			var d := sqrt(u * u + v * v)
			# smoothstep(1.0 → 0.0)：中心 1、边缘 0
			var t := clampf(1.0 - d, 0.0, 1.0)
			t = t * t * (3.0 - 2.0 * t)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, t))
	return ImageTexture.create_from_image(img)


## 柔光的材质：加色混合 + 顶点色当遮罩 + billboard。
func _make_glow_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = false
	# ⚠️ **不要开 `vertex_color_use_as_albedo`**。
	#    开了之后 alpha 会被**顶点色**乘掉，而 QuadMesh 的顶点色默认是白的，
	#    贴图里的径向衰减就被「抹平」了 —— 出图上又变回硬边方块
	#    （`_probe_carrier_fx.gd` 的 2_climb 就是这么废的）。
	#    现在改成：贴图负责衰减，`albedo_color` 只管颜色和整体亮度。
	m.albedo_texture = _glow_tex_or_make()
	m.albedo_color = Color(0.45, 0.72, 1.0, 0.75)
	m.emission_enabled = true
	m.emission = Color(0.40, 0.70, 1.0)
	m.emission_energy_multiplier = 2.0
	m.disable_receive_shadows = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## 拿共享的软圆斑贴图（没有就建一张）。
func _glow_tex_or_make() -> ImageTexture:
	if _glow_tex == null:
		_glow_tex = _build_glow_texture()
	return _glow_tex


func _make_particle_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	# ⚠️ 关掉 `keep_scale`：开着的话相机的远近会放大方块，远处变成一大片白斑。
	m.billboard_keep_scale = false
	# ⚠️ 同样**不要开** `vertex_color_use_as_albedo`（理由见 `_make_glow_mat()`）。
	#    粒子的颜色/透明度用 `ParticleProcessMaterial.color` 控制（它走顶点色，
	#    但那是在 CPU 侧生成顶点色，和这里的开关不是一回事）。
	m.albedo_texture = _glow_tex_or_make()
	# 偏蓝：粒子的职责是「雾」，真正的「焰」由三层锥体负责。
	# ⚠️ alpha 留 1.0 —— 衰减由贴图负责，这里再乘一次会把边缘压没。
	m.albedo_color = Color(0.28, 0.55, 1.00, 1.0)
	m.emission_enabled = true
	m.emission = Color(0.35, 0.62, 1.0)
	m.emission_energy_multiplier = 1.4
	m.disable_receive_shadows = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
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

	# ── 机身俯仰：把动画自带的后仰压平，再按速度加一点前倾 ──
	#
	# ⚠️ 放在这里（`_sync_face()` 之前、`_run_effects()` 之前）有两个原因：
	#    ① `_run_effects()` 开头有 `if _boost_fx.is_empty(): return`，
	#       推进器骨找不到时整段特效都不跑 —— 俯仰不能跟着一起消失；
	#    ② 同一帧里 `_sync_face()` 要用 `_lean`，写晚了就慢一帧、转向时看得出来。
	_update_power(delta)
	_update_lean(delta)

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

	# 水平：**不在这里动**。`player.gd` 的加速 / 摩擦 / 速度判定每帧照常跑，
	# 所以飞起来仍能按 Shift 加力、仍能贴着墙调整落点。
	# ⚠️ 速度档在 `player.gd`：飞行是 `SPEED_FLY 11` / `SPEED_FLY_BOOST 19`；
	#    （这里原来写着「仍能按 Shift 冲到 6.8 m/s」，那是加 `_flight_lock` 分支之前的注释，
	#      早就不是这个数了。）
	# 唯一要做的额外事是「空中刹车比地面软」——那由 `player.gd` 的 `FRICTION_FLY` 管，
	# 这里不重复实现（重复实现会和它互相覆盖）。
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
	# 机身俯仰 + 偏航一起写。
	#
	# ── 为什么俯仰用**节点变换**而不是骨姿势 ──
	# `AnimationPlayer` 默认在 **idle** 阶段写骨头，而本脚本的叠加写在
	# **physics** 阶段 —— 一帧里 physics 在前、idle 在后，所以凡是用
	# `set_bone_pose_rotation()` 写的叠加，都会被同一帧的动画**覆盖掉**。
	# 节点变换没有别人抢，写进去就稳。
	#
	# ⚠️ 这条不是推测，是量出来的（`_diag_carrier_tracks.gd`）：
	#    `Move_Ing` 里有 **37 条 bone_wing / 22 条 bone_gear_cannon /
	#    4 条 bone_gearboost / 1 条 Bip001 Pelvis** 轨道，
	#    而 `_run_effects()` 里那三处「肩翼张开 / 推进器呼吸 / 炮口后坐」
	#    正是往这些骨上写 pose —— 所以它们**一次都没显示出来过**，是死代码。
	#    要修得换成节点变换，或者把 AnimationPlayer 的 `process_callback`
	#    改成 physics（本节点在 Model 之后处理，就能压住它）。
	#
	# ⚠️ Godot 的欧拉顺序是 **YXZ**（R = Ry·Rx·Rz），所以这里
	#    `rotation = Vector3(pitch, yaw, 0)` 的语义正是
	#    「先按 yaw 转过去，再在**机身自己的坐标系**里低头/抬头」——
	#    而不是在世界 X 轴上翻。这正是要的效果。
	#
	# 符号：模型正面是节点 **+Z**（`facing_yaw_deg` 那段推出的约定）。
	#   绕 X 轴转 +θ 会把 +Z 送到 (0, −sinθ, cosθ)，即**机头下压 = 前倾**。
	#   所以要补偿「动画的 −7.31° 后仰」，这里是**正的**。
	_carrier.rotation = Vector3(
		_lean, _model.rotation.y + deg_to_rad(facing_yaw_deg), 0.0)


## 巡航者模式：武器关闭 + 飞得更快。可由 `_input` 的 T 键或自检直接调。
func set_cruise(on: bool) -> void:
	if on == cruise:
		return
	cruise = on
	if _player != null and _player.has_method("set_flight_speed_scale"):
		_player.call("set_flight_speed_scale", CRUISE_SPEED_SCALE if on else 1.0)
	var wpn := _weapon()
	if wpn != null:
		wpn.call("set_disabled", on)
	print("[Carrier] 巡航者模式 → %s" % ("开（武器关闭 / 飞得更快）" if on else "关"))
	Sfx.play("ui_toggle", -3.0)


## 启用一条能量条（按 R）。成功返回 true；没有存条时返回 false。
##
## 「时间独立计算」= 每条各记各的剩余秒数（`_bar_timers` 里一个元素一条），
## 所以第一条到点后攻速会从 ×4 掉回 ×3，而不是五条一起清空。
func use_energy_bar() -> bool:
	if energy_bars <= 0:
		return false
	energy_bars -= 1
	_bar_timers.append(BAR_SECONDS)
	print("[Carrier] 启用能量条：剩 %d 条，攻速 ×%.1f（%d 条在计时）"
		% [energy_bars, 1.0 + float(_bar_timers.size()), _bar_timers.size()])
	Sfx.play("ui_toggle", -1.0)
	return true


## 能量条 / 飞行的每帧维护。**必须在 `_tick_flight()` 里、`_sync_face()` 附近调**。
func _update_power(delta: float) -> void:
	# ① 已启用条数各自倒计时（独立），到点就丢
	if not _bar_timers.is_empty():
		var alive: Array[float] = []
		for t in _bar_timers:
			var left := t - delta
			if left > 0.0:
				alive.append(left)
		if alive.size() != _bar_timers.size():
			print("[Carrier] 一条能量条到期 → 剩 %d 条在计时（攻速 ×%.1f）"
				% [alive.size(), 1.0 + float(alive.size())])
		_bar_timers = alive

	# ② 累计飞行距离 → 攒条（普通飞行和巡航**都算**；已满 5 条就不再攒）
	if _on and _player != null and _airborne:
		# ⚠️ **满条就停止累计，不是「继续涨再夹在 3000」**。
		#    本喵第一版是后者（而且夹取还写在 `if energy_bars < MAX_BARS` 里面，
		#    满了根本走不到），自检打红两条：进度涨到 3008.5 不封顶，而且
		#    「花掉一条 → 下一帧立刻用那 8.5 m 的溢出补回来」——能量条白攒。
		#    现在满了就冻住进度，花掉一条后要**重新飞**才攒得回来。
		#
		# ⚠️ 位移口径：**每帧真实位移的长度**（三维），不是「水平速度 × dt」。
		#    用户 2026-11-08：「上升下降也要算……算空间的移动量绝对值」。
		#    用位移而不是速度还有个好处：**贴墙推着走的时候位移是 0**，
		#    不会因为「速度表上很快」而白攒能量。
		var p := _player.global_position
		if _has_last_pos:
			var step_len := (p - _last_pos).length()
			# 单帧位移异常大 = 被传送 / 重生 / 场景切换，不计入
			if step_len <= 5.0 and energy_bars < MAX_BARS:
				fly_distance_m += step_len
				while fly_distance_m >= ENERGY_PER_BAR_M and energy_bars < MAX_BARS:
					fly_distance_m -= ENERGY_PER_BAR_M
					energy_bars += 1
					print("[Carrier] 攒满一条能量条：%d / %d" % [energy_bars, MAX_BARS])
					Sfx.play("ui_toggle", -2.0)
		_last_pos = p
		_has_last_pos = true
	else:
		# 落地 / 变形回去：下一趟起飞重新取基准，不要跨状态算位移
		_has_last_pos = false

	# ③ 攻速倍率 = 1 + 已启用条数，喂给武器
	rate_scale = 1.0 + float(_bar_timers.size())
	var wpn := _weapon()
	if wpn != null:
		wpn.call("set_rate_scale", rate_scale)
		wpn.call("set_disabled", cruise)

	# ④ HUD
	_update_power_hud()


## 能量条 HUD：**运行时自己建**一个 CanvasLayer + Label。
##
## 为什么不写进 `hud.tscn`：那是别的会话也在碰的场景文件，而且这里只是几行字，
## 自己建能保证「机甲这套东西」都在本文件里，改动不外溢。
func _ensure_power_hud() -> void:
	if _power_layer != null and is_instance_valid(_power_layer):
		return
	_power_layer = CanvasLayer.new()
	_power_layer.name = "CarrierPowerHUD"
	_power_layer.layer = 50
	add_child(_power_layer)
	_power_label = Label.new()
	_power_label.add_theme_font_size_override("font_size", 26)
	_power_label.add_theme_color_override("font_color", Color(0.75, 0.92, 1.0))
	_power_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_power_label.add_theme_constant_override("outline_size", 6)
	_power_label.position = Vector2(40, 0)
	_power_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_power_label.offset_left = 40
	_power_label.offset_top = -150
	_power_layer.add_child(_power_label)


## 藏掉机甲能量条 HUD。**状态切换处要直接调**，别指望 `_update_power_hud()`
## 每帧兜底 —— 那个函数只在机甲形态的 `_process` 里跑（见 `set_form(false)` 的注释）。
func _hide_power_hud() -> void:
	if _power_layer != null and is_instance_valid(_power_layer):
		_power_layer.visible = false


func _update_power_hud() -> void:
	if not _on:
		_hide_power_hud()
		return
	_ensure_power_hud()
	_power_layer.visible = true
	var filled := ""
	for i in MAX_BARS:
		filled += "◆" if i < energy_bars else "◇"
	var active := ""
	for i in _bar_timers.size():
		active += "★"
	if active == "":
		active = "—"
	# 满条时进度显示 100%（实际累计已冻结，见 `_update_power`）
	var pct := 100 if energy_bars >= MAX_BARS \
		else int(clampf(fly_distance_m / ENERGY_PER_BAR_M, 0.0, 1.0) * 100.0)
	_power_label.text = "%s  %d/%d   进度 %d%%   攻速 ×%.1f   %s%s" % [
		filled, energy_bars, MAX_BARS, pct,
		rate_scale, ("巡航者模式（武器关闭） " if cruise else ""), active]



##
## 保留 `_lean` 这个名字与存储，是为了不要去动已经引用它的地方；
## 真正的行为这次才接上（见 `POSE_BACK_LEAN_DEG` 那段：旧版只写不读）。
## 机身俯仰补偿角（度）。**正值 = 机头下压（前倾），负值 = 抬头。**
##
## ⚠️ 这个值是**标定出来的**，不是算出来的。来历见 `_update_lean()` 那段长注释：
##    旧代码以为「动画自带 −7.31° 后仰」，于是补 +7.31°，
##    但 `_diag_lean_calibrate.gd` 实测发现**补偿 0° 时脊梁已经是 +3.49°（前倾）**，
##    那个 7.31 的假设是错的 ⇒ 补过头 ⇒ 玩家看到的就是"仰头"。
##
## 做成 `var` 而不是 `const`：标定探针要能直接改它、走真实流程量结果。
## （`const` 在 GDScript 里改不了，逼得上一版探针只能手写 rotation，量出来是假数据。）
var lean_comp_deg := 7.3


func _update_lean(delta: float) -> void:
	# ── 2026-11-10 最终标定：**完全不要仰头** ──
	#
	# 用户第三次报姿态问题：「完全不要仰头,好丑」。
	# 前两次本喵都在**猜**（第一次调基准、第二次把方向改反），这次**扫参数实测**：
	#
	# `_diag_lean_calibrate.gd` 把补偿角从 −6° 扫到 +1°，
	# 同时量「胯骨→头骨」这条向量相对水平的真实俯仰（正 = 前倾）：
	#
	#   补偿角   悬停脊梁    全速 19m/s 脊梁
	#   −6.00°   −1.90° 仰   −2.17° 仰
	#   −4.00°   −0.14° 仰   −0.42° 仰
	#   −3.00°   **+0.72°**  **+0.44°**   ← 取这个
	#   −2.00°   +1.59°      +1.29°
	#    0.00°   +3.38°      +3.00°
	#   +7.31°   +9.95°      ——   ← **旧值，一直在仰头的原因**
	#   +12.0°   +14.27°     ——
	#
	# ⚠️ 关键发现：**补偿角 0° 时脊梁已经是 +3.49°（前倾）**，
	#    根本不是注释里那个「动画自带 −7.31° 后仰」。
	#    所以旧代码按「+7.31 抵消后仰」去补，实际是**把机身又往前压了 7° 多**，
	#    叠加后到了 +10°~+14° —— 那才是玩家看到的"仰头"。
	#    （本喵前两次修错方向，根源就是照抄了这个从没被实测验证过的 7.31。）
	#
	# 现在：固定 **−3°** 起步，实测再微调（见 `LEAN_COMP_DEG` 那段）。
	# **不做任何"速度加成"** —— 用户要的是不仰头，速度越快越仰更是反的。
	var want := 0.0
	if _airborne:
		want = deg_to_rad(lean_comp_deg)
	_lean = lerpf(_lean, want, clampf(6.0 * delta, 0.0, 1.0))


## 每帧把「脸」掰回水平（只在飞行中）。原理与实测数据见 `HEAD_FIX_ENABLE` 那段。
func _fix_head_face() -> void:
	if not HEAD_FIX_ENABLE or _skel == null or _model == null:
		return
	if not _on or not _airborne:
		return
	var hi := _skel.find_bone(HEAD_BONE)
	if hi < 0:
		return
	# 头骨的**世界**基（实测 local Y = 脸朝前）
	var xf := _skel.global_transform * _skel.get_bone_global_pose(hi)
	var dir := xf.basis.y.normalized()
	# 模型水平正面（`_model` 是 `Arisu` 节点，`player.gd` 每帧写它的 yaw）
	var fwd := _model.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 1e-6:
		return
	fwd = fwd.normalized()
	var face := dir.dot(fwd)
	# 仰角：用 atan2(竖直分量, 水平前向分量)。
	# ⚠️ 不能只看 `dir.y`：`Move_Ing` 里脸既朝上、又偏到侧面 45°
	#    （前向分量 0.694），所以必须带上前向分量一起算，否则角度会偏大。
	var elev := atan2(dir.y, absf(face))
	# ⚠️ 符号是**实测**定的，不是推出来的：本喵第一版写成 `-elev`，
	#    结果验收量到 +72.33°（比修前的 46° 还大）—— 正好是「补偿量加了两次」，
	#    说明旋转方向与推导相反。改成 `+elev` 后闭环收敛到 0。
	var want := clampf(elev * HEAD_FIX_GAIN, -deg_to_rad(HEAD_FIX_MAX_DEG),
		deg_to_rad(HEAD_FIX_MAX_DEG))
	if absf(want) < deg_to_rad(0.3):
		return
	# 绕「水平横轴」转。`UP × fwd` 对 fwd = +Z 是 +X，配合上面的符号即可掰平。
	var ax_world := Vector3.UP.cross(fwd)
	if ax_world.length_squared() < 1e-6:
		return
	# 世界轴 → 头骨局部轴（骨骼姿势是局部的，必须换过去再乘）
	var ax_local := (xf.basis.inverse() * ax_world.normalized()).normalized()
	var cur := _skel.get_bone_pose_rotation(hi)
	# ⚠️ 读的是**动画刚写进去的**当前姿势，再乘补偿 —— 不能读静止姿势，
	#    那样每帧都会从绑定姿势重算，动画本身的动作就被抹掉了。
	_skel.set_bone_pose_rotation(hi, Quaternion(ax_local, want) * cur)


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

	# ── 前倾：已经搬到 `_update_lean()` 里了（在 `_sync_face()` 之前算）──
	# ⚠️ 别把这段搬回来：`_run_effects()` 开头有 `if _boost_fx.is_empty(): return`，
	#    推进器骨找不到时整段都不跑，俯仰会跟着一起失效。见 `_update_lean()`。

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

	# ── 肩翼 / 导弹荚的小喷口：跟着骨走，飞行时冒一点 ──
	for aux in _aux_fx:
		var abi: int = aux["bone"]
		var aholder: Node3D = aux["holder"]
		var ami: MeshInstance3D = aux["mesh"]
		if abi < 0:
			continue
		# 挂点跟着骨走（世界变换 → 载具局部）
		var bone_xf := _skel.global_transform * _skel.get_bone_global_pose(abi)
		aholder.global_transform = bone_xf
		# 小喷口是**朝下**的：网格尖朝 −Y，而肩翼的局部 Y 未必朝下，
		# 所以这里按骨自己的轴摆一下 —— 取骨基的 −Y（多数情况就是朝下）。
		var basis_fix := Basis(Vector3.RIGHT, PI)
		aholder.global_transform = Transform3D(
			bone_xf.basis * basis_fix, bone_xf.origin)
		var t := clampf(_thrust, 0.0, 1.2)
		var aflick := 0.85 + 0.15 * sin(_wing_phase * 4.1)
		aholder.visible = t > 0.12
		ami.scale = Vector3(0.09, 0.35, 0.09) * lerpf(0.4, 1.0, t) * aflick
		var am := ami.material_override as StandardMaterial3D
		if am != null:
			am.emission_energy_multiplier = lerpf(0.3, 1.8, t)
			am.albedo_color.a = clampf(0.15 + 0.45 * t, 0.0, 1.0)
		var aglow := aux.get("glow") as MeshInstance3D
		if aglow != null:
			aglow.scale = Vector3.ONE * lerpf(0.3, 0.75, t) * aflick
			var agm := aglow.material_override as StandardMaterial3D
			if agm != null:
				agm.albedo_color.a = clampf(0.08 + 0.40 * t, 0.0, 1.0)
				agm.emission_energy_multiplier = lerpf(0.4, 2.0, t)

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
			# ── 把喷口往**外侧**推，别挤在中线上 ──
			# 实测（`_diag_carrier_nozzle.gd`）：两个推进器骨相对胯骨的「右」分量
			# 只有 −0.07 / +0.10 —— 几乎在身体中线上，两道焰并排从腿中间插出来，
			# 出图上像**两把交叉的刀**（`_probe_carrier_fx.gd` 的 3_cruise）。
			# 真实推进器应该在腿的**外后侧**。这里按骨名判断左右，各自往外推。
			var side := 1.0 if String(_skel.get_bone_name(bone_i)).ends_with("_R") else -1.0
			var out_dir := _carrier.global_transform.basis.x * side
			# 往外 0.16 m、往后 0.10 m（推进器在腿后侧，不是正外侧）
			var back_dir := -_carrier.global_transform.basis.z
			holder.global_transform = Transform3D(
				bone_xf.basis,
				bone_xf.origin + out_dir * BOOST_OUT_OFFSET + back_dir * BOOST_BACK_OFFSET)
		var t := clampf(_thrust, 0.0, 1.2)
		# ── 焰柱**摆动**：不能是两根死掉的锥体 ──
		# 出图（`_probe_carrier_fx.gd`）里两道焰直挺挺地插着，像两把刀。
		# 真实的推进器焰会随气流抖。这里给每束焰一个**相位不同**的摆动
		# （左右两束不同相，看起来是「两台发动机」，不是「一根杆子」），
		# 摆动量随推力增大 —— 推力越大、发动机越不稳。
		var wobble_phase := _wing_phase * 1.9 + float(bone_i) * 0.7
		var wob_amt: float = deg_to_rad(4.5) * t
		var wob_axis := holder.global_transform.basis.x.normalized()
		holder.global_transform = Transform3D(
			Basis(wob_axis, sin(wobble_phase) * wob_amt)
				* holder.global_transform.basis,
			holder.global_transform.origin)
		var layers: Array = fx["layers"]
		# 上升时整束焰柱再长 35%（喷得猛），但**半径不变**，只拉长度
		var len_mul := 1.0 + (0.35 if _vert_want > 0.5 else 0.0)
		for li in layers.size():
			var mi := layers[li] as MeshInstance3D
			var br: float = float(mi.get_meta("base_radius", 0.15))
			var bl: float = float(mi.get_meta("base_len", 0.8))
			# 推力小时「短而钝」，推力大时「长而尖」：半径也跟着略收，不然低速像根柱子
			# ⚠️ 下限 0.45：三层在加色混合下会互相加亮，下限太高就叠成一坨圆球光晕
			#    （出图 `_probe_carrier_fx.gd` 的 2_climb 试过 0.55，就是那样）。
			var growth := lerpf(0.45, 1.0, t) * flick
			mi.scale = Vector3(br * lerpf(0.75, 1.0, t), FLAME_LEN * bl * growth * len_mul,
				br * lerpf(0.75, 1.0, t))
			mi.visible = t > 0.03
			var m := mi.material_override as StandardMaterial3D
			if m != null:
				# ── 三层的亮度必须**明显不同**，否则加色混合下叠成一坨 ──
				# 出图试过：三层亮度接近时整个焰是一个圆球光晕、没有焰形。
				# 现在：外层最暗（它是「晕」）、中层中、芯最亮（它是「焰芯」）。
				var emul: float = [1.0, 2.6, 6.0][li]
				m.emission_energy_multiplier = lerpf(0.3, emul, t)
				# 注意：加色混合下改 alpha 就是改亮度（不是改透明度），
				# 所以这里用「亮度」的语义去写，别当成透明度理解。
				m.albedo_color.a = clampf(0.18 + 0.55 * t, 0.0, 1.0) * [1.0, 0.85, 0.7][li]
		var light := fx["light"] as OmniLight3D
		light.light_energy = lerpf(0.0, 2.6, t) * flick
		light.omni_range = lerpf(2.4, 5.0, t)
		var gp := fx["particles"] as GPUParticles3D
		gp.emitting = t > 0.25
		gp.speed_scale = lerpf(0.6, 1.8, t)
		# 喷口柔光：跟着推力长出来，中心亮、边缘散。
		# ⚠️ 这一层是「硬边三角」变「一团喷焰」的关键：锥体底边是直线，
		#    光晕把那条直线糊掉。
		var glow := fx.get("glow") as MeshInstance3D
		if glow != null:
			var gm := glow.material_override as StandardMaterial3D
			glow.scale = Vector3.ONE * lerpf(0.35, 1.25, t) * flick
			glow.visible = t > 0.03
			if gm != null:
				gm.albedo_color.a = clampf(0.10 + 0.55 * t, 0.0, 1.0)
				gm.emission_energy_multiplier = lerpf(0.5, 3.0, t)

		# ── 激波环：沿喷流方向周期性外扩 + 淡出（2026-11-10 新增）──
		#
		# 两个环相位差 0.5，各自跑一个 0→1 的循环：
		#   p = 0  → 贴着喷口、小而亮
		#   p = 1  → 往下游推出去、变大变淡
		# 位移给到 −Y * FLAME_LEN * 0.85（跟着焰柱长度走，焰长环也推得远）。
		# 推力不足时环整个隐藏（不然悬停时喷口下面挂两个亮圈，很怪）。
		var rings: Array = fx.get("rings", [])
		var ring_mats: Array = fx.get("ring_mats", [])
		if rings.size() >= 2:
			# 环的循环速度随推力加快：喷得猛时激波推得快
			var ring_speed := lerpf(0.9, 2.6, t)
			for ri in rings.size():
				var rm := rings[ri] as MeshInstance3D
				var rmat := ring_mats[ri] as StandardMaterial3D
				# 第二环错开半个周期
				var phase := fmod(_wing_phase * ring_speed + float(ri) * 0.5, 1.0)
				# 半径随 phase 变大（0.22 → 1.0 倍基准），同时越远越暗
				var grow := lerpf(0.55, 2.1, phase)
				var alpha := (1.0 - phase) * clampf(t, 0.0, 1.0)
				# 厚度在扩散时变薄（激波越远越薄）
				var thick := lerpf(1.0, 0.35, phase)
				rm.scale = Vector3(0.22 * grow, 0.10 * thick, 0.22 * grow)
				# 沿 −Y 推出去（holder 的局部 −Y 就是喷流方向）
				rm.position = Vector3(0.0, -FLAME_LEN * 0.85 * phase * t, 0.0)
				rm.visible = t > 0.12 and alpha > 0.02
				if rmat != null:
					rmat.albedo_color.a = clampf(alpha * 0.75, 0.0, 1.0)
					rmat.emission_energy_multiplier = lerpf(4.5, 1.2, phase)

	# ── 装饰特效层（2026-11-10）──
	# 推力/速度/加力三件事喂给它，剩下全在 `carrier_fx_extra.gd` 里。
	# 速度归一：`SPEED_FLY` 11 / `SPEED_FLY_BOOST` 19（见 `player.gd`），
	# 用 12 当「满速」参考点 —— 超过就按 1 封顶。
	if _fx_extra != null:
		_fx_extra.set("thrust", clampf(_thrust, 0.0, 1.2))
		var spd := 0.0
		if _player != null:
			spd = Vector3(_player.velocity.x, 0.0, _player.velocity.z).length()
		_fx_extra.set("speed01", clampf(spd / 12.0, 0.0, 1.0))
		_fx_extra.set("boosting", _thrust > 0.92)
		_fx_extra.call("tick", delta)


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
	# ⚠️ 头部补偿必须在**这里**（idle 阶段）做，不能放 `_physics_process`：
	#    `AnimationPlayer` 默认也在 idle 写骨头，而一帧里 physics 在 idle 之前，
	#    写在 physics 的骨姿势会被同一帧的动画覆盖掉。本节点的 `process_priority`
	#    设成 10，保证在动画器（默认 0）之后跑。
	_fix_head_face()
	var v := _player.velocity
	var speed := Vector2(v.x, v.z).length()

	# ── 一次性动作在演的时候 ──
	# ⚠️ 只有**整身**的（`_oneshot_full`，即换弹 / 受击 / 必杀）才让路；
	#    开火走叠加层，腿必须继续由下面的移动逻辑刷新，否则又变成「锁成站桩」
	#    —— 那正是用户 2026-11-09 报的「攻击动画僵硬」。
	if _oneshot_left > 0.0:
		_oneshot_left = maxf(_oneshot_left - delta, 0.0)
		if _oneshot_full:
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
## ⚠️ 分两类：
##   · **开火** → 走「叠加层」`_upper`（只含上半身轨道），**基础层的移动动画照常刷**
##     —— 腿继续飞、身体不再被锁成站桩 1.07 s（用户 2026-11-09 选定的方案 A）；
##   · **其余**（换弹 / 受击 / 必杀）→ 仍然整身独占，因为那些动作本身就是全身的，
##     叠一半反而怪。`_oneshot_full` 决定 `_process()` 要不要让路。
func _play_oneshot(clip: String, speed: float = 1.0) -> bool:
	if _ap == null or not _ap.has_animation(clip):
		return false
	_cur_anim = clip
	# ── 开火：叠上半身 ──
	if clip == ATTACK_CLIP and _upper != null and _upper.has_animation(clip):
		_upper.speed_scale = speed
		_upper.play(clip, 0.06, 1.0)
		_oneshot_left = _upper.get_animation(clip).length / maxf(speed, 0.01)
		_oneshot_full = false          # ← 别挡住移动动画
		return true
	# ── 其余：整身独占 ──
	_ap.speed_scale = speed
	_ap.play(clip, 0.06, 1.0)
	_oneshot_left = _ap.get_animation(clip).length / maxf(speed, 0.01)
	_oneshot_full = true
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
	# 对话/菜单暂停世界时不响应
	if get_tree().paused:
		return
	# ── 机甲形态专属：T 切巡航者、R 启用一条能量条 ──
	# ⚠️ 只在 `_on` 时才吃 R：本体形态下 R 是**换弹**（`player.gd` 里那段），
	#    机甲本来就不换弹（无限子弹），所以 R 在这里是空的，正好给能量条。
	if _on:
		if k.keycode == CRUISE_KEY:
			set_cruise(not cruise)
			get_viewport().set_input_as_handled()
			return
		if k.keycode == ENERGY_KEY:
			if use_energy_bar():
				get_viewport().set_input_as_handled()
			return
	if k.keycode != toggle_key:
		return
	# 在空中按 G 变回本体 → 交给 `player.gd` 的重力（它会自己掉下来）
	if toggle():
		get_viewport().set_input_as_handled()
