extends Boss
## 最终 BOSS「优香-恐怖」（第二关校园，三只霸王龙倒下之后登场）。
##
## 用户 2026-11-13：「然后最终 boss 优香-恐怖登场！」
## 用户 2026-11-13 追加：「最终boss做十个技能，血量打完开始第二阶段」
##              → 「一阶段就放全 10 招，二阶段全部加强」
##              → 「血量逐渐回复到一半再开，获得 20 秒无敌，
##                  第二阶段防御力增加 50%，攻击力增加 200%，攻击速度增加 50%」
##
## ── 用哪个模型 ──
## `models/companions/Yuuka.glb`（游戏里那位同伴优香）。理由：
##   · 「优香-恐怖」是**优香本人**被侵蚀的形态，不是又一只恐龙 —— 用人的模型才对；
##   · 这只 GLB 带骨架、贴图和 **38 条动作**（`_diag_yuuka_horror.gd` 实测），
##     `Boss` 基类的「按骨架量包围盒 → 归一到 height」那条路直接能用。
##
## ⚠️ 本项目**没有**官方的「恐怖优香」素材。所以"恐怖"是拼出来的：
##   原贴图压暗 + 菲涅尔红边（`shaders/horror_skin.gdshader`）+ 红环 + 红光。
##   它是"暗黑风格的优香"，不是原作那套建模 —— 这一点必须如实记着。
##
## ── 十个技能（一阶段全放，按顺序轮转，一轮 10 招）──
##   ⚠️ 玩家有机甲形态、**会飞**（`player.gd::SPEED_FLY = 11`，加力 19）。
##      用户 2026-11-13：「因为机甲是天上飞的，技能更多要大范围可以对空
##      或者精准小范围对空的。」所以每招都标了它对空靠什么：
##
##   1 冲击波    **竖直能量墙**：6→34 m 横扫，从地面到 44 m 全在墙里。
##              【大范围对空】躲法只有"跑出 34 m"或"待在墙外"。
##   2 砸击      **落点球** 6.5 m（球心=玩家当时的坐标，含高度），1.25 s。
##              【精准对空】飞着不动就吃，飞走就躲开。
##   3 弹幕      预判 0.6 s 的直线光球 ×3（本来就是三维直线）。【对空】
##   4 激光扫射  刀刃绕身 60°/s 扫 180°，**刀高 60 m**。【大范围对空】
##   5 陨石雨    玩家周围 5 个落点，陨石**从玩家上空砸下来**。【对空】
##   6 血刺      **竖直刺柱**：水平半径 2.6 m、从地面**窜到玩家高度**。
##              【精准对空】飞到 30 m 也照样从下面顶上来。
##   7 近身爆震  **球形**爆震半径 16 m（球心抬到 6 m）。【大范围对空】
##   8 幻影冲锋  3 个幻影**三维追踪**玩家坐标，撞上就炸。【精准对空】
##   9 追踪光箭  慢速三维追踪（转向 75°/s），绕圈能甩掉。【精准对空】
##   10 引力井    10 m 的井，**三维吸附**（把天上的往井心拽），3 s 后爆。
##              【大范围对空】
##
## ── 数值都按"跑得出去 / 飞得出去"倒推 ──
## 玩家跑速 6.8 m/s、飞行 11 m/s（加力 19）。每招的预警时间 × 半径都保证
## 留出这个余量；改数字前先算一遍，别把"可以躲"改成"站着必吃"
## （`boss_attacker.gd` 文件头那条铁律）。
##
## ── 二阶段（血量打空后）──
##   ① 20 s 无敌，血量从 0 **逐渐回到一半**（7000），血条跟着涨；
##   ② 无敌结束才开打：攻击 ×3（+200%）、出招间隔 ÷1.5（+50%）、
##      受到的伤害 ×0.5（防御 +50%）、弹幕/陨石/幻影/光箭各加 1~2 个。
##   ⚠️ "防御力 +50%" 这里按**受到的伤害减半**实现（玩家口语里最接近的意思），
##      不是"除以 1.5"。要改就改 `P2_DEFENSE` 一处。
##
## ── 三个必须注意的坑 ──
## ① `Boss._physics_process()` 里有骨骼碰撞盒跟随（`_sync_bone_collisions()`），
##    子类覆盖时必须 `super._physics_process(delta)`，否则碰撞盒钉死在原地。
## ② `Boss._ready()` 会走 `BootGate.when_near()`（近距离才建模型）。
##    最终 BOSS 是"当场登场"，不能等玩家走近 —— 这里 `_boot()` 直接建。
## ③ 动画：GLB 自带 `AnimationPlayer`，idle 要设成循环；一旦播了 one-shot
##    （攻击/死亡），要自己接回 idle，否则会停在最后一帧。

signal phase_changed(phase: int)
## 血量打空、开始"回血 + 无敌"的复活演出
signal revive_started

const SKIN_SHADER := preload("res://shaders/horror_skin.gdshader")
## 恐怖版静态眼睛/嘴：**只换这一个 boss**。普通优香（同伴、剧情里那位）继续用原图，
## 所以原 `Yuuka_Yuuka_Original_EyeMouth.png` 一个字节都不动。
## 用资源路径认表面：模型里 7 张口型贴图叫 `Yuuka_Character_Mouth_*`，不会被误换。
## ⚠️ 用 `load()` 而不是 `preload`：模型/贴图目录不进仓库（只有 `.import` 入库），
##    硬 `preload` 在缺这张图的机器上会让整份脚本解析失败。
const HORROR_EYE_MOUTH_PATH := "res://models/companions/Yuuka_Horror_EyeMouth.png"
const EYE_MOUTH_TEX_PATH := "res://models/companions/Yuuka_Yuuka_Original_EyeMouth.png"
## 眼睛自发光白光（只作用于眼嘴那一面，见 `horror_skin.gdshader` 的 `eye_emit`）。
## 着色器拿贴图亮度当遮罩：眼白烧白，瞳孔那条暗缝保持不发光。
const EYE_EMIT := 2.6
const EYE_EMIT_COLOR := Color(1.0, 0.97, 0.93)
## 砸击/陨石/引力井的地面圈（半透明 + 亮边；见该 shader 文件头）
const DISC_SHADER := preload("res://shaders/telegraph_disc.gdshader")
const DISC_ALPHA := 0.26

## 冲击波
## 冲击波墙的高度（对空上限）。用户要"大范围对空"，所以这不是贴地环，
## 而是一道竖直的能量墙：水平距离被扫到，从地面到 44 m 全在墙里。
const SHOCK_TOP := 44.0
const SHOCK_MIN_R := 6.0
const SHOCK_MAX_R := 34.0
const SHOCK_SPEED := 12.0
const SHOCK_BAND := 1.8
const SHOCK_DAMAGE := 30.0
const SHOCK_WINDUP := 0.9

## 砸击
## ⚠️ 半径 vs 蓄力时间必须"跑得出去"：玩家跑速 6.8 m/s。
##    9 m / 1.0 s 要 9 m/s —— 站着必吃；6.5 m / 1.25 s 只需 5.2 m/s。
const SLAM_RADIUS := 6.5
const SLAM_WINDUP := 1.25
const SLAM_DAMAGE := 36.0
const SLAM_KNOCKBACK := 18.0
const SLAM_RANGE := 26.0

## 弹幕
const ORB_SPEED := 26.0
const ORB_DAMAGE := 12.0
const ORB_HIT_R := 1.8
const ORB_LIFE := 6.0
const ORB_LEAD := 0.6

## 激光扫射
const SWEEP_WARN := 1.2
const SWEEP_TIME := 3.0
const SWEEP_SPAN := PI          # 扫 180°
const SWEEP_TOL := 1.3          # 到刀线的垂直容差（m）
const SWEEP_MIN_R := 3.0
const SWEEP_MAX_R := 60.0
const SWEEP_DAMAGE := 34.0
## 刀刃高度（对空）：从地面到 60 m，飞到天上的机甲一样被扫到
const SWEEP_HEIGHT := 60.0

## 陨石雨
const METEOR_COUNT := 5
const METEOR_RADIUS := 4.5
const METEOR_WARN := 1.3
const METEOR_FALL := 0.45
const METEOR_DAMAGE := 28.0
const METEOR_KNOCK := 12.0

## 血刺
const SPIKE_COUNT := 6
const SPIKE_GAP := 4.5
const SPIKE_FIRST := 5.0
const SPIKE_HIT_R := 2.6
const SPIKE_WARN := 0.9
const SPIKE_DAMAGE := 24.0

## 近身爆震
const NOVA_RADIUS := 16.0
const NOVA_WARN := 2.2
const NOVA_DAMAGE := 42.0
const NOVA_KNOCK := 26.0
const NOVA_RANGE := 26.0

## 幻影冲锋
const GHOST_COUNT := 3
const GHOST_SPEED := 14.0
const GHOST_BLAST_R := 4.5
const GHOST_DAMAGE := 24.0
const GHOST_LIFE := 4.0

## 追踪光箭
const HOMING_COUNT := 2
const HOMING_SPEED := 13.0
const HOMING_TURN := 75.0      # 度/秒
const HOMING_DAMAGE := 16.0
const HOMING_LIFE := 6.0

## 引力井
const WELL_RADIUS := 10.0
const WELL_TIME := 3.0
const WELL_PULL := 2.6         # 每秒往中心拽的位移（m/s），远小于跑速 6.8
const WELL_DAMAGE := 32.0

## ── EX 护盾（优香原作是**护盾角色**，用户 2026-11-13 点名要）──
## 给自己套一层护盾 + 提高闪避率；护盾吸收完就碎。
const SHIELD_HP := 2200.0
const SHIELD_TIME := 18.0
const SHIELD_EVASION := 0.35      # 护盾在时 35% 概率直接闪掉这次伤害
const SHIELD_COOLDOWN := 26.0

## ── 跪射 / 跳砸 / 蓄力炮 / 召唤 ──
const KNEEL_COUNT := 4
const KNEEL_DAMAGE := 10.0
const LEAP_RADIUS := 9.0
const LEAP_WARN := 1.1
const LEAP_DAMAGE := 44.0
const LEAP_KNOCK := 20.0
const BEAM_WARN := 1.3
const BEAM_LEN := 90.0
const BEAM_HALF_WIDTH := 2.2
const BEAM_TOP := 44.0
const BEAM_DAMAGE := 46.0
const SUMMON_COUNT := 4

## 冲锋枪扫射：射速极快、单发伤害低（用户 2026-11-13「冲锋枪普通攻击但速度特别快」）
const RAPID_SHOTS := 20
const RAPID_INTERVAL := 0.05
const RAPID_DAMAGE := 5.0
const RAPID_SPEED := 36.0
const RAPID_SPREAD := 0.7
const RAPID_SIZE := 0.42

## 召唤：3 只会飞的飞猪优香（用户 2026-11-13「召唤 3 飞猪优香，这次真的是飞的」）
const PIG_SCRIPT := preload("res://scripts/flying_pig_yuuka.gd")
const PIG_COUNT := 3

## 分身：10 个假身围住玩家，**只有本体放技能**，分身只会追着普攻
const CLONE_SCRIPT := preload("res://scripts/horror_clone.gd")
const CLONE_COUNT := 10
const CLONE_RING := 10.0
const CLONE_CD := 34.0

## 追击：离得远就走过去（用户 2026-11-13「现在一动不动 boss 需要追击」）
const CHASE_SPEED := 4.5
const CHASE_FAR := 17.0
const CHASE_STEP_MAX := 3.0

## 闪现：长冷却、闪现到**玩家身后**
const BLINK_CD := 20.0
const BLINK_MIN_DIST := 22.0
const BLINK_BEHIND := 7.0

## 出招节奏（秒）。二阶段 ÷ P2_SPEED。
const INTERVAL_1 := 5.5
const INTRO_GRACE := 2.5
const TURN_SPEED := 45.0
const TURN_SPEED_2 := 75.0

## 二阶段三项加成（用户 2026-11-13 指定）
const P2_DEFENSE := 0.5        # 受到的伤害 ×0.5（"防御力 +50%"）
const P2_DAMAGE := 3.0         # 攻击"增加 200%" → ×3
const P2_SPEED := 1.5          # 攻速"增加 50%" → 间隔 ÷1.5
const REVIVE_TIME := 20.0      # 无敌 20 s
const REVIVE_HEAL_TIME := 3.0  # 前 3 s 回血到一半，回完立刻开打
const REVIVE_TO := 0.5         # 回到一半血

## 15 招：前 10 招是"攻击"，后 5 招用 GLB 里另外几段动作
## （`Exs_Cutin` / `Kneel_Attack_*` / `Move_Jump` / `Normal_Reload` / `Normal_Callsign`）
const SKILL_NAMES := ["shock", "slam", "barrage", "sweep", "meteor",
	"spikes", "nova", "phantom", "homing", "gravity",
	"shield", "kneel", "leapslam", "beam", "summon", "rapid", "pigs",
	"clones"]

var _ap: AnimationPlayer
var _skin_mats: Array[ShaderMaterial] = []
var _horror_eye_tried := false
var _horror_eye_tex_cache: Texture2D = null
var _aura_light: OmniLight3D
var _rings: Array[Dictionary] = []
var _aura_built := false

var _player: Node3D
var _t_skill := 0.0
var _skill_i := 0
var _busy := false
var _phase := 1
var _last_skill := ""
## 放出次数 / 实际命中次数（探针按它判定，不靠墙钟 sleep）
var _counts := {}
var _hits := {}
## 各种进行中的东西
var _waves: Array[Dictionary] = []      # 冲击波
var _orbs: Array[Dictionary] = []       # 直线 / 追踪光球
var _sweeps: Array[Dictionary] = []     # 激光刀刃
var _wells: Array[Dictionary] = []      # 引力井
var _phantoms: Array[Dictionary] = []   # 幻影
var _slam_marks: Array[Node3D] = []

## 复活演出：血量打空 → 20 s 无敌；前 REVIVE_HEAL_TIME 秒回血到一半，
## 回完**立刻开打**（剩下 17 s 仍然无敌）
var _reviving := false
var _invuln := false
var _revive_t := 0.0
var _heal_t := 0.0
var _phase2_live := false
var _shield_t := 0.0
var _pulse := 0.0

## EX 护盾：剩余护盾量 / 剩余时间 / 冷却 / 视觉节点
var _shield_hp := 0.0
var _shield_left := 0.0
var _shield_cd := 0.0
var _shield_fx: Array[Node3D] = []
## 召唤出来的飞猪（挂在 ArenaLock 下，不是 BOSS 的子节点 —— 否则会跟着转身绕圈）
var _pigs: Array[Node3D] = []
## 分身（同上，挂在 ArenaLock 下）
var _clones: Array[Node3D] = []
var _clone_cd := 0.0
var _blink_cd := 9.0
var _blinks := 0
var _chase_blocked := 0
var _chase_on := true
## 探针用：>=0 时强制这个闪避率（默认 -1 = 用护盾自带的值）
var _evasion_fixed := -1.0


func _init() -> void:
	display_name = "优香-恐怖"
	model_path = "res://models/companions/Yuuka.glb"
	# 校园里的楼最高 53 m，它站在操场上要"抬头看"才有压迫感
	height = 16.0
	# 两条血：第一阶段 14000 打完 → 无敌 20 s 回到 7000 → 第二阶段再打 7000
	# （二阶段防御 ×0.5，等效要打 14000 伤害）
	max_health = 14000.0
	respawn_on_death = false
	drop_yuan = 0
	# 着色器会接管颜色（见 `_apply_skin()`），这两个只给基类建模型/参考用
	tint = Color(0.62, 0.42, 0.44)
	flash_color = Color(1.0, 0.45, 0.40)
	# 蒙皮模型走「每根骨一个盒子」那条路（和霸王龙同一套，已验证）
	collision_mode = Boss.CollisionMode.BOX_PARTS
	boot_distance = 0.0
	boot_max_wait = 0.0
	for n in SKILL_NAMES:
		_counts[n] = 0
		_hits[n] = 0


func _ready() -> void:
	super._ready()
	# 见文件头 ②：不等 BootGate，立刻建模型 + 碰撞
	_boot()
	_apply_skin()
	_setup_anim()
	_build_aura()
	_t_skill = INTRO_GRACE
	print("[YuukaHorror] 登场：身高 %.1f m，血量 %.0f，%d 个技能，动画 %s" % [
		height, max_health, SKILL_NAMES.size(),
		("有（%d 条）" % _ap.get_animation_list().size()) if _ap != null else "无"])


# ────────────────────────── 外观 ──────────────────────────

## 把每个表面换成 `horror_skin`：保留原贴图，只压暗 + 加红边。
func _apply_skin() -> void:
	if model == null:
		return
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		if m.mesh == null or not (m.mesh is ArrayMesh):
			continue
		var am := m.mesh as ArrayMesh
		for s in am.get_surface_count():
			var src := am.surface_get_material(s) as StandardMaterial3D
			var sm := ShaderMaterial.new()
			sm.shader = SKIN_SHADER
			if src != null:
				var tex: Texture2D = src.albedo_texture
				var is_eye := tex != null and tex.resource_path == EYE_MOUTH_TEX_PATH
				if is_eye:
					var horror_tex := _horror_eye_tex()
					if horror_tex != null:
						tex = horror_tex
				sm.set_shader_parameter("albedo_tex", tex)
				sm.set_shader_parameter("use_texture", tex != null)
				if is_eye:
					sm.set_shader_parameter("eye_emit", EYE_EMIT)
					sm.set_shader_parameter("eye_emit_color", EYE_EMIT_COLOR)
				# 眼睛/嘴是 alpha scissor 材质，丢了这个会变成方块
				sm.set_shader_parameter("use_alpha",
					src.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED)
			else:
				sm.set_shader_parameter("use_texture", false)
			m.set_surface_override_material(s, sm)
			_skin_mats.append(sm)


## 恐怖版眼贴图；缺文件只警告一次并退回原图（模型目录不入库）。
func _horror_eye_tex() -> Texture2D:
	if not _horror_eye_tried:
		_horror_eye_tried = true
		if ResourceLoader.exists(HORROR_EYE_MOUTH_PATH):
			_horror_eye_tex_cache = load(HORROR_EYE_MOUTH_PATH) as Texture2D
		if _horror_eye_tex_cache == null:
			push_warning("[YuukaHorror] 缺 %s，眼睛退回原图" % HORROR_EYE_MOUTH_PATH)
	return _horror_eye_tex_cache


func _setup_anim() -> void:
	if model == null:
		return
	for n in model.find_children("*", "AnimationPlayer", true, false):
		_ap = n as AnimationPlayer
		break
	if _ap == null:
		push_warning("[YuukaHorror] GLB 里没有 AnimationPlayer，只能当静态雕像")
		return
	# idle 必须循环；其余 one-shot 用默认的 no-loop
	var idle := _ap.get_animation("Normal_Idle")
	if idle != null:
		idle.loop_mode = Animation.LOOP_LINEAR
	_ap.play("Normal_Idle")


## 播一段 one-shot；不是出招中就接回 idle。
func _play_once(clip: String, fade := 0.18) -> void:
	if _ap == null or not _ap.has_animation(clip):
		return
	_ap.play(clip, fade)
	_ap.speed_scale = 1.0
	await _ap.animation_finished
	if _dead or _reviving or not is_instance_valid(self):
		return
	if not _busy:
		_ap.play("Normal_Idle", 0.25)


func _build_aura() -> void:
	if _aura_built:
		return
	_aura_built = true

	_aura_light = OmniLight3D.new()
	_aura_light.name = "AuraLight"
	_aura_light.light_color = Color(1.0, 0.16, 0.10)
	_aura_light.light_energy = 3.5
	_aura_light.omni_range = height * 3.2
	_aura_light.omni_attenuation = 1.3
	_aura_light.position = Vector3(0.0, height * 0.55, 0.0)
	add_child(_aura_light)

	# 三圈细红环（⚠️ 半径按腰宽给；上一版 0.30~0.42 × 16 m = 5~7 m，
	# 在远处看就是一根横在头顶的红色长条）
	var spec := [
		{"y": 0.28, "r": 0.115, "spin": 0.55},
		{"y": 0.50, "r": 0.135, "spin": -0.40},
		{"y": 0.78, "r": 0.100, "spin": 0.70},
	]
	for s in spec:
		var ring := MeshInstance3D.new()
		ring.name = "AuraRing"
		var tm := TorusMesh.new()
		tm.inner_radius = 0.975
		tm.outer_radius = 1.0
		tm.rings = 72
		tm.ring_segments = 5
		ring.mesh = tm
		ring.material_override = _additive(Color(1.0, 0.14, 0.09, 0.85))
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.position = Vector3(0.0, float(s["y"]) * height, 0.0)
		var r := float(s["r"]) * height
		ring.scale = Vector3(r, maxf(height * 0.035, 0.35), r)
		add_child(ring)
		_rings.append({"node": ring, "spin": float(s["spin"])})

	# 脚下一圈细红环，标出「别站太近」
	var ground := MeshInstance3D.new()
	ground.name = "AuraGround"
	var gt := TorusMesh.new()
	gt.inner_radius = 0.99
	gt.outer_radius = 1.0
	gt.rings = 96
	gt.ring_segments = 4
	ground.mesh = gt
	ground.material_override = _additive(Color(1.0, 0.20, 0.10, 0.55))
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.position = Vector3(0.0, 0.25, 0.0)
	ground.scale = Vector3(14.0, 1.5, 14.0)
	add_child(ground)


func _additive(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = col
	return m


# ────────────────────────── 每帧 ──────────────────────────

func _physics_process(delta: float) -> void:
	# ⚠️ 见文件头 ①：骨骼碰撞盒必须继续跟随
	super._physics_process(delta)
	if not _aura_built:
		return
	_spin_rings(delta)
	_turn_to_player(delta)
	_tick_waves(delta)
	_tick_orbs(delta)
	_tick_sweeps(delta)
	_tick_wells(delta)
	_tick_phantoms(delta)
	_tick_shield(delta)
	if _dead:
		return
	# 追击 / 闪现：出招、复活演出期间不走
	if not _reviving and not _busy:
		_chase(delta)
		_tick_blink(delta)
	if _clone_cd > 0.0:
		_clone_cd = maxf(_clone_cd - delta, 0.0)
	if _reviving:
		# 用户 2026-11-13：「一阶段结束无敌 20 秒，先 3 秒复活回复到一半血量，
		# 复活完 boss 直接开始攻击」——前 3 s 回血，回完立刻开打，
		# 但**仍然无敌**，剩下的 17 s 就是"她边打你边打不动她"。
		_revive_t = maxf(_revive_t - delta, 0.0)
		if _heal_t > 0.0:
			_heal_t = maxf(_heal_t - delta, 0.0)
			var k := 1.0 - _heal_t / REVIVE_HEAL_TIME
			health = max_health * REVIVE_TO * clampf(k, 0.0, 1.0)
			health_changed.emit(health, max_health)
			if _heal_t <= 0.0:
				_start_phase2()
		if _revive_t <= 0.0:
			_end_invuln()
	if not _boss_attack_enabled():
		return
	_t_skill -= delta
	if _t_skill > 0.0 or _busy:
		return
	_t_skill = _interval()
	_cast_skill()


func _boss_attack_enabled() -> bool:
	# 和 `boss_attacker.gd` 同一个设置项（Esc 菜单「Boss 攻击」）
	return bool(GameSettings.value("boss_attack"))


## 二阶段的出招间隔（"攻速 +50%" = 间隔 ÷1.5）
func _interval() -> float:
	return INTERVAL_1 / P2_SPEED if _phase >= 2 else INTERVAL_1


## 二阶段的伤害（"攻击力 +200%" = ×3）
func _dmg(base: float) -> float:
	return base * P2_DAMAGE if _phase >= 2 else base


func _spin_rings(delta: float) -> void:
	for r in _rings:
		var node: Node3D = r["node"]
		if node == null or not is_instance_valid(node):
			continue
		node.rotation.y += float(r["spin"]) * delta
	# 呼吸：二阶段更急、更亮；无敌期间再亮一档
	var t := float(Time.get_ticks_msec()) * 0.001
	var amp := 0.85 if _phase >= 2 else 0.45
	if _invuln:
		amp = 1.2
	_pulse = (0.5 + 0.5 * sin(t * (2.6 if _phase >= 2 else 1.5))) * amp
	for m in _skin_mats:
		if is_instance_valid(m):
			m.set_shader_parameter("pulse", _pulse)
	if _aura_light != null and is_instance_valid(_aura_light):
		var base := 3.5 + 1.2 * sin(t * 1.4)
		_aura_light.light_energy = base + (2.5 if _phase >= 2 else 0.0) \
			+ (4.0 if _invuln else 0.0)
	_shield_t = maxf(_shield_t - delta, 0.0)


func _turn_to_player(delta: float) -> void:
	var p := _find_player()
	if p == null:
		return
	var d := p.global_position - global_position
	if Vector2(d.x, d.z).length() < 0.5:
		return
	var want := atan2(d.x, d.z)          # 脸朝 +Z 的约定
	var cur := rotation.y
	var diff := wrapf(want - cur, -PI, PI)
	var spd := TURN_SPEED_2 if _phase >= 2 else TURN_SPEED
	rotation.y = cur + clampf(diff, -deg_to_rad(spd) * delta, deg_to_rad(spd) * delta)


func _find_player() -> Node3D:
	if _player != null and is_instance_valid(_player):
		return _player
	_player = get_tree().get_first_node_in_group("player") as Node3D
	return _player


# ────────────────────────── 出招 ──────────────────────────

## 10 招按顺序轮转（一轮 55 s，玩家能摸清节奏；二阶段同一套但更凶）
func _cast_skill() -> void:
	var p := _find_player()
	if p == null:
		return
	_busy = true
	var pc := p.global_position
	var pick := String(SKILL_NAMES[_skill_i % SKILL_NAMES.size()])
	_skill_i += 1
	# 近身技够不着 → 换成不需要距离的那招，别对着空气放
	var dist := global_position.distance_to(pc)
	if ((pick == "slam" and dist > SLAM_RANGE)
			or (pick == "nova" and dist > NOVA_RANGE)):
		pick = "sweep"
	_last_skill = pick
	_counts[pick] += 1
	print("[YuukaHorror] 出招：%s（第 %d 轮，阶段 %d，距离 %.0f m）" % [
		pick, _skill_i, _phase, dist])
	match pick:
		"slam":
			await _skill_slam(pc)
		"barrage":
			await _skill_barrage(pc)
		"sweep":
			await _skill_sweep(pc)
		"meteor":
			await _skill_meteor(pc)
		"spikes":
			await _skill_spikes(pc)
		"nova":
			await _skill_nova()
		"phantom":
			await _skill_phantom(pc)
		"homing":
			await _skill_homing(pc)
		"gravity":
			await _skill_gravity(pc)
		"shield":
			await _skill_shield()
		"kneel":
			await _skill_kneel(pc)
		"leapslam":
			await _skill_leapslam(pc)
		"beam":
			await _skill_beam(pc)
		"summon":
			await _skill_summon(pc)
		"rapid":
			await _skill_rapid(pc)
		"pigs":
			await _skill_pigs()
		"clones":
			await _skill_clones()
		_:
			await _skill_shockwave()
	_busy = false


# ── 1 冲击波 ──

func _skill_shockwave() -> void:
	_play_once("Exs")
	Sfx.play("ex_fire", -6.0)
	# 蓄力：脚下一圈红环涨到 SHOCK_MIN_R 再炸开
	var warn := MeshInstance3D.new()
	var wt := TorusMesh.new()
	wt.inner_radius = 0.94
	wt.outer_radius = 1.0
	wt.rings = 96
	wt.ring_segments = 6
	warn.mesh = wt
	warn.material_override = _additive(Color(1.0, 0.18, 0.08, 0.75))
	warn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	warn.position = Vector3(0.0, 0.3, 0.0)
	warn.scale = Vector3(SHOCK_MIN_R * 0.35, 2.0, SHOCK_MIN_R * 0.35)
	add_child(warn)
	var tw := create_tween()
	tw.tween_property(warn, "scale",
		Vector3(SHOCK_MIN_R, 2.0, SHOCK_MIN_R), SHOCK_WINDUP)
	await tw.finished
	if _dead or not is_instance_valid(self):
		if is_instance_valid(warn):
			warn.queue_free()
		return
	warn.queue_free()
	_spawn_wave()


func _spawn_wave() -> void:
	var ring := MeshInstance3D.new()
	ring.name = "Shockwave"
	# 圆筒墙（无盖）：从地面往上 SHOCK_TOP 米 —— 和判定一致
	var cmesh := CylinderMesh.new()
	cmesh.top_radius = 1.0
	cmesh.bottom_radius = 1.0
	cmesh.height = SHOCK_TOP
	cmesh.radial_segments = 96
	cmesh.rings = 1
	cmesh.cap_top = false
	cmesh.cap_bottom = false
	ring.mesh = cmesh
	ring.material_override = _additive(Color(1.0, 0.20, 0.10, 0.95))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = Vector3(0.0, SHOCK_TOP * 0.5, 0.0)
	ring.scale = Vector3(SHOCK_MIN_R, 1.0, SHOCK_MIN_R)
	add_child(ring)
	_waves.append({"node": ring, "r": SHOCK_MIN_R, "hit": false})
	Sfx.play("ui_close", -4.0)


## 每帧把冲击波往外推；**扫掠**判定（取上一帧到这一帧的半径段），低帧率不会跨过玩家。
func _tick_waves(delta: float) -> void:
	if _waves.is_empty():
		return
	var p := _find_player()
	var keep: Array[Dictionary] = []
	for w in _waves:
		var node: MeshInstance3D = w["node"]
		if node == null or not is_instance_valid(node):
			continue
		var r0 := float(w["r"])
		var r := r0 + SHOCK_SPEED * delta
		node.scale = Vector3(r, 1.0, r)
		if p != null and not bool(w["hit"]):
			var flat := Vector2(p.global_position.x - global_position.x,
				p.global_position.z - global_position.z).length()
			if flat >= r0 - SHOCK_BAND and flat <= r + SHOCK_BAND:
				# 竖直墙：从地面往上 SHOCK_TOP 米都算在墙里（对空大范围）。
				# 想躲只能**往外跑出 34 m**，或者被墙扫过时刚好在墙外。
				var dy := p.global_position.y - global_position.y
				if dy >= -2.0 and dy <= SHOCK_TOP and p.has_method("take_damage"):
					w["hit"] = true
					_hits["shock"] += 1
					p.call("take_damage", _dmg(SHOCK_DAMAGE), global_position, 10.0)
					Vfx.impact(self, p.global_position + Vector3.UP, Color(1.0, 0.30, 0.18),
						1.2, 0.0)
					Vfx.shake(0.9, 0.4)
					print("[YuukaHorror] 冲击波命中（水平 %.1f m，高 %.1f m）" % [flat, dy])
		if r >= SHOCK_MAX_R:
			node.queue_free()
			continue
		w["r"] = r
		keep.append(w)
	_waves = keep


# ── 2 砸击 ──

func _skill_slam(pc: Vector3) -> void:
	_play_once("Normal_Attack_Start")
	Sfx.play("fire_beam", -6.0)
	# 预判 0.55 s 后的落点（和 `dark_boss.gd` 砸击同一套）
	var p := _find_player()
	var vel := (p as CharacterBody3D).velocity if p is CharacterBody3D else Vector3.ZERO
	var pred := pc + Vector3(vel.x, 0.0, vel.z) * 0.55
	# 玩家节点的原点是**脚底**（`player.tscn` 胶囊中心在 +0.75），所以落点就是 pc.y
	var center := Vector3(pred.x, pc.y, pred.z)

	var disc := _make_disc(center, SLAM_RADIUS, Color(1.0, 0.16, 0.10, 0.42))
	_slam_marks.append(disc)
	var tw := create_tween()
	tw.tween_property(disc, "scale", Vector3(SLAM_RADIUS, 1.0, SLAM_RADIUS), SLAM_WINDUP) \
		.from(Vector3(SLAM_RADIUS * 0.25, 1.0, SLAM_RADIUS * 0.25))
	await tw.finished
	if _dead or not is_instance_valid(self):
		_free_marks()
		return
	_play_once("Normal_Attack_Ing", 0.08)
	Sfx.play("ui_close", -1.0)
	_hit_area(center, SLAM_RADIUS, _dmg(SLAM_DAMAGE), SLAM_KNOCKBACK, "slam")
	_flash_mark(disc, 1.4, 0.30)
	_slam_marks.erase(disc)
	await get_tree().create_timer(0.45).timeout


# ── 3 弹幕 ──

func _skill_barrage(pc: Vector3) -> void:
	_play_once("Stand_Attack_Start")
	Sfx.play("fire_beam", -10.0)
	var n := 5 if _phase >= 2 else 3
	var p := _find_player()
	var vel := (p as CharacterBody3D).velocity if p is CharacterBody3D else Vector3.ZERO
	var aim := pc + Vector3(vel.x, 0.0, vel.z) * ORB_LEAD
	print("[YuukaHorror] 弹幕：%d 发，目标 %s" % [n, str(aim.snappedf(0.1))])
	for i in n:
		if _dead or not is_instance_valid(self):
			return
		var side := Vector3(aim.z - global_position.z, 0.0,
			-(aim.x - global_position.x))
		side = side.normalized() if side.length_squared() > 0.01 else Vector3.RIGHT
		var off := (float(i) - float(n - 1) * 0.5) * 2.4
		_spawn_orb(aim + side * off, "barrage")
		await get_tree().create_timer(0.16).timeout
	await get_tree().create_timer(0.35).timeout


# ── 4 激光扫射 ──

func _skill_sweep(pc: Vector3) -> void:
	_play_once("Stand_Attack_Start")
	Sfx.play("fire_beam", -4.0)
	var yaw0 := atan2(pc.x - global_position.x, pc.z - global_position.z)
	# 刀刃挂在一个绕 Y 转的支点上：支点在 BOSS 原点，刀身在 +Z 方向伸出去
	var pivot := Node3D.new()
	pivot.name = "SweepPivot"
	pivot.top_level = true
	# ⚠️ 先进树再设 global_position（不然坐标被丢掉，刀刃会从世界原点扫）
	add_child(pivot)
	pivot.global_position = global_position
	pivot.rotation.y = yaw0
	var blade := MeshInstance3D.new()
	var bm := BoxMesh.new()
	# 刀身长度 = 伤害射程（60 m），别画得比打得到的更远
	bm.size = Vector3(0.5, SWEEP_HEIGHT, SWEEP_MAX_R)
	blade.mesh = bm
	# ⚠️ 刀刃用**普通 alpha 混合**而不是加色：
	#    加色 + 辉光在"镜头正好在刀刃里"时会把整屏烧成白橙色（实测截图）。
	#    alpha 混合只是一层红色薄雾，贴脸也不会致盲。
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.18, 0.10, 0.0)
	blade.material_override = mat
	blade.position = Vector3(0.0, SWEEP_HEIGHT * 0.5, SWEEP_MAX_R * 0.5)
	blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(blade)
	# 起手：刀刃先半透明亮起来，转不转一眼能看出来
	var tw0 := create_tween()
	tw0.tween_property(mat, "albedo_color:a", 0.22, SWEEP_WARN)
	await tw0.finished
	if _dead or not is_instance_valid(self):
		if is_instance_valid(pivot):
			pivot.queue_free()
		return
	# 扫 180°，速度二阶段快 50%
	var span := SWEEP_SPAN * (P2_SPEED if _phase >= 2 else 1.0)
	var dur := SWEEP_TIME / (P2_SPEED if _phase >= 2 else 1.0)
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.42, 0.1)
	tw.tween_property(pivot, "rotation:y", yaw0 + span, dur) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var s := {"node": pivot, "t": dur, "hit": false}
	_sweeps.append(s)
	await tw.finished
	_sweeps.erase(s)
	if is_instance_valid(pivot):
		var tw2 := create_tween()
		tw2.tween_property(mat, "albedo_color:a", 0.0, 0.25)
		tw2.tween_callback(pivot.queue_free)


## 激光刀刃：判定用**到刀线的垂直距离**（角度再换算成米），不是角度本身 ——
## 远处一点点角度差就是几十米，近处同样是 1° 却只有半米。
func _tick_sweeps(delta: float) -> void:
	if _sweeps.is_empty():
		return
	var p := _find_player()
	var keep: Array[Dictionary] = []
	for s in _sweeps:
		var pivot: Node3D = s["node"]
		if pivot == null or not is_instance_valid(pivot):
			continue
		var t := float(s["t"]) - delta
		s["t"] = t
		if p != null and not bool(s["hit"]):
			var d := p.global_position - global_position
			var flat := Vector2(d.x, d.z)
			var dist := flat.length()
			var in_range: bool = (dist >= SWEEP_MIN_R and dist <= SWEEP_MAX_R
				and d.y >= -4.0 and d.y <= SWEEP_HEIGHT)
			if in_range:
				var ang := atan2(flat.x, flat.y)
				var diff := wrapf(ang - pivot.rotation.y, -PI, PI)
				if dist * absf(sin(diff)) <= SWEEP_TOL and p.has_method("take_damage"):
					s["hit"] = true
					_hits["sweep"] += 1
					p.call("take_damage", _dmg(SWEEP_DAMAGE), global_position, 14.0)
					Vfx.impact(self, p.global_position + Vector3.UP, Color(1.0, 0.55, 0.35),
						1.3, 0.0)
					Vfx.shake(1.0, 0.45)
					print("[YuukaHorror] 激光扫中（距离 %.1f m）" % dist)
		if t > 0.0:
			keep.append(s)
	_sweeps = keep


# ── 5 陨石雨 ──

func _skill_meteor(pc: Vector3) -> void:
	_play_once("Exs")
	Sfx.play("ex_fire", -8.0)
	var n := METEOR_COUNT + (2 if _phase >= 2 else 0)
	# 落点：以玩家为中心散开一圈（半径 3~20 m），圈与圈之间留缝
	for i in n:
		if _dead or not is_instance_valid(self):
			return
		var ang := TAU * float(i) / float(n) + randf_range(-0.25, 0.25)
		var r := randf_range(3.0, 20.0)
		var at := Vector3(pc.x + cos(ang) * r, pc.y, pc.z + sin(ang) * r)
		_spawn_meteor(at)
		await get_tree().create_timer(0.08).timeout
	await get_tree().create_timer(METEOR_WARN + METEOR_FALL).timeout


func _spawn_meteor(at: Vector3) -> void:
	var disc := _make_disc(at, METEOR_RADIUS, Color(1.0, 0.14, 0.06, 0.38))
	_slam_marks.append(disc)
	var tw := create_tween()
	tw.tween_property(disc, "scale", Vector3(METEOR_RADIUS, 1.0, METEOR_RADIUS), METEOR_WARN) \
		.from(Vector3(METEOR_RADIUS * 0.3, 1.0, METEOR_RADIUS * 0.3))
	await tw.finished
	if _dead or not is_instance_valid(self):
		if is_instance_valid(disc):
			_slam_marks.erase(disc)
			disc.queue_free()
		return
	# 陨石本体：从 45 m 高处砸下来（只做视觉，判定在落地那一帧）
	var rock := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 2.2
	sm.height = 4.4
	sm.radial_segments = 12
	sm.rings = 6
	rock.mesh = sm
	rock.material_override = _additive(Color(1.0, 0.30, 0.10, 0.9))
	rock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rock.top_level = true
	add_child(rock)
	rock.global_position = at + Vector3(0.0, 45.0, 0.0)
	var tw2 := create_tween()
	tw2.tween_property(rock, "global_position", at + Vector3(0.0, 1.0, 0.0),
		METEOR_FALL).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw2.finished
	if is_instance_valid(rock):
		rock.queue_free()
	_hit_area(at, METEOR_RADIUS, _dmg(METEOR_DAMAGE), METEOR_KNOCK, "meteor")
	Sfx.play("ui_close", -3.0)
	_flash_mark(disc, 1.35, 0.28)
	_slam_marks.erase(disc)


# ── 6 血刺 ──

func _skill_spikes(pc: Vector3) -> void:
	_play_once("Normal_Attack_Ing")
	Sfx.play("fire_beam", -8.0)
	var n := SPIKE_COUNT + (2 if _phase >= 2 else 0)
	var dir := pc - global_position
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 1.0 else facing()
	for i in n:
		if _dead or not is_instance_valid(self):
			return
		var at := global_position + dir * (SPIKE_FIRST + SPIKE_GAP * float(i))
		# 水平位置沿用"她→玩家"的方向；高度上限取玩家当时的高度（对空）
		_spawn_spike(Vector3(at.x, pc.y, at.z))
		await get_tree().create_timer(0.07).timeout
	await get_tree().create_timer(SPIKE_WARN + 0.45).timeout


## 一根从地里窜起来、够到玩家高度的血刺。
##
## 判定是**竖直的柱子**（水平半径 2.6 m、从地面到刺尖），不是圆球：
## 用户要"对空"，玩家飞到 30 m 时刺就该窜到 30 m 去够他 ——
## 而站在地上的玩家仍然要被地面那一截打到。
func _spawn_spike(at: Vector3) -> void:
	var gy := _ground_below(at)
	var top := maxf(gy + 9.0, at.y + 4.0)
	var disc := _make_disc(Vector3(at.x, gy, at.z), SPIKE_HIT_R,
		Color(1.0, 0.10, 0.12, 0.42))
	_slam_marks.append(disc)
	var tw := create_tween()
	tw.tween_property(disc, "scale", Vector3(SPIKE_HIT_R, 1.0, SPIKE_HIT_R), SPIKE_WARN) 		.from(Vector3(SPIKE_HIT_R * 0.2, 1.0, SPIKE_HIT_R * 0.2))
	await tw.finished
	if _dead or not is_instance_valid(self):
		if is_instance_valid(disc):
			_slam_marks.erase(disc)
			disc.queue_free()
		return
	# 刺本体：从地里窜出来的细长圆锥，长度刚好到 top
	var spike := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.06
	cm.bottom_radius = 1.6
	cm.height = top - gy
	cm.radial_segments = 8
	spike.mesh = cm
	spike.material_override = _additive(Color(1.0, 0.18, 0.12, 0.95))
	spike.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spike.top_level = true
	add_child(spike)
	var mid := Vector3(at.x, (gy + top) * 0.5, at.z)
	spike.global_position = mid - Vector3(0.0, (top - gy) * 0.5 + 4.0, 0.0)
	var tw2 := create_tween()
	tw2.tween_property(spike, "global_position", mid, 0.16) 		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tw2.finished
	_spike_hit(at, gy, top)
	_flash_mark(disc, 1.2, 0.25)
	_slam_marks.erase(disc)
	var tw3 := create_tween()
	tw3.tween_interval(0.45)
	tw3.tween_property(spike, "global_position",
		mid - Vector3(0.0, (top - gy) * 0.5 + 4.0, 0.0), 0.3)
	tw3.tween_callback(spike.queue_free)


## 竖直柱判定：水平半径内、且高度落在 [地面, 刺尖] 之间
func _spike_hit(at: Vector3, gy: float, top: float) -> void:
	var p := _find_player()
	if p == null or not p.has_method("take_damage"):
		return
	var chest := p.global_position + Vector3.UP * 0.9
	var flat := Vector2(chest.x - at.x, chest.z - at.z).length()
	if flat <= SPIKE_HIT_R and chest.y >= gy - 1.0 and chest.y <= top + 0.6:
		_hits["spikes"] += 1
		p.call("take_damage", _dmg(SPIKE_DAMAGE), Vector3(at.x, chest.y, at.z), 8.0)
		print("[YuukaHorror] spikes 命中（水平 %.1f m，高度 %.1f / %.1f m）" % [
			flat, chest.y, top])


## 从某点向下打一条射线找地面（给血刺定"从哪儿长出来"）
func _ground_below(at: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	if space == null:
		return at.y - 2.0
	var q := PhysicsRayQueryParameters3D.create(
		at + Vector3.UP * 200.0, at + Vector3.DOWN * 200.0)
	q.collision_mask = 1
	# ⚠️ 排除自己：射线从头顶打下来会先撞到自己身上的碰撞盒
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return at.y - 2.0
	var gy := (hit["position"] as Vector3).y
	# ⚠️ 校园碰撞网格**有洞**：打穿了会一路掉到 y=−100.9 的兜底板。
	#    这种"地面"不能用，一律当没打到。
	if gy < -20.0 or gy > at.y + 80.0:
		return at.y - 2.0
	return gy


# ── 7 近身爆震 ──

func _skill_nova() -> void:
	_play_once("Vital_Panic")
	Sfx.play("ex_fire", -3.0)
	# 收束预警：一圈大红环从 18 m 缩到 3 m —— "它要炸了"
	var warn := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.97
	tm.outer_radius = 1.0
	tm.rings = 128
	tm.ring_segments = 6
	warn.mesh = tm
	warn.material_override = _additive(Color(1.0, 0.16, 0.08, 0.85))
	warn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	warn.position = Vector3(0.0, 0.4, 0.0)
	warn.scale = Vector3(NOVA_RADIUS, 2.0, NOVA_RADIUS)
	add_child(warn)
	var tw := create_tween()
	tw.tween_property(warn, "scale", Vector3(2.5, 2.0, 2.5), NOVA_WARN) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	if _dead or not is_instance_valid(self):
		if is_instance_valid(warn):
			warn.queue_free()
		return
	warn.queue_free()
	# 炸开
	var ring := MeshInstance3D.new()
	var tm2 := TorusMesh.new()
	tm2.inner_radius = 0.94
	tm2.outer_radius = 1.0
	tm2.rings = 128
	tm2.ring_segments = 6
	ring.mesh = tm2
	ring.material_override = _additive(Color(1.0, 0.26, 0.12, 0.95))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = Vector3(0.0, 0.4, 0.0)
	ring.scale = Vector3(2.0, 2.0, 2.0)
	add_child(ring)
	var tw2 := create_tween()
	tw2.tween_property(ring, "scale", Vector3(NOVA_RADIUS, 2.0, NOVA_RADIUS), 0.45)
	tw2.tween_callback(ring.queue_free)
	# 球心放在身体中段：脚下 0 m 的球罩不到天上，抬到 6 m 才能"对空"
	var nova_at := global_position + Vector3.UP * 6.0
	Vfx.big_burst(self, nova_at, Color(1.0, 0.35, 0.18), 2.2)
	Vfx.flash(Color(1.0, 0.35, 0.2), 0.35, 0.35)
	_hit_area(nova_at, NOVA_RADIUS, _dmg(NOVA_DAMAGE), NOVA_KNOCK, "nova")
	Sfx.play("ex_fire", -1.0)


# ── 8 幻影冲锋 ──

func _skill_phantom(pc: Vector3) -> void:
	_play_once("Vital_Callsign" if _ap != null and _ap.has_animation("Vital_Callsign") \
		else "Stand_Attack_Start")
	Sfx.play("fire_beam", -6.0)
	var n := GHOST_COUNT + (1 if _phase >= 2 else 0)
	for i in n:
		if _dead or not is_instance_valid(self):
			return
		var ang := TAU * float(i) / float(n)
		var off := Vector3(cos(ang), 0.0, sin(ang)) * 6.0
		_spawn_ghost(global_position + off, pc)
		await get_tree().create_timer(0.12).timeout


## 幻影：一团红色的"优香轮廓"（胶囊 + 头部球），直线扑向目标点，到了就炸。
func _spawn_ghost(from: Vector3, target: Vector3, kind := "phantom") -> void:
	var g := Node3D.new()
	g.name = "Phantom"
	g.top_level = true
	add_child(g)
	g.global_position = from
	var body := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 1.4
	cm.height = 6.0
	body.mesh = cm
	body.material_override = _additive(Color(1.0, 0.12, 0.10, 0.55))
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.position = Vector3(0.0, 3.0, 0.0)
	g.add_child(body)
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.1
	sm.height = 2.2
	head.mesh = sm
	head.material_override = _additive(Color(1.0, 0.30, 0.20, 0.7))
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.position = Vector3(0.0, 7.2, 0.0)
	g.add_child(head)
	# 三维方向：玩家飞在天上时幻影会爬升追上去（对空）
	var dir := target - from
	dir = dir.normalized() if dir.length() > 0.5 else facing()
	_phantoms.append({"node": g, "dir": dir, "t": GHOST_LIFE, "kind": kind})


func _tick_phantoms(delta: float) -> void:
	if _phantoms.is_empty():
		return
	var keep: Array[Dictionary] = []
	for e in _phantoms:
		var n: Node3D = e["node"]
		if n == null or not is_instance_valid(n):
			continue
		var t := float(e["t"]) - delta
		e["t"] = t
		var prev := n.global_position
		n.global_position = prev + (e["dir"] as Vector3) * GHOST_SPEED * delta
		# 撞到玩家 / 超时就炸。
		# ⚠️ 用**线段**判定：低帧率下一帧能飞 2~3 m，只看端点会从人身上穿过去。
		var done := t <= 0.0
		var p := _find_player()
		if p != null:
			# 用"线段到玩家身体"的最近距离（3D）：幻影会爬升，天上的玩家也算命中。
			# 半径给 3.0 —— 幻影本体是 ~5 m 高、2.8 m 粗的柱子。
			var chest := p.global_position + Vector3.UP * 2.0
			var closest := Geometry3D.get_closest_point_to_segment(
				chest, prev, n.global_position)
			if closest.distance_to(chest) < 3.0:
				done = true
				n.global_position = closest
		if done:
			Vfx.burst(self, n.global_position + Vector3.UP * 2.0,
				Color(1.0, 0.25, 0.45), 34, 1.6, 16.0, 0.5, -3.0)
			_hit_area(n.global_position, GHOST_BLAST_R, _dmg(GHOST_DAMAGE), 14.0,
				String(e.get("kind", "phantom")))
			_blast_fx(n.global_position)
			n.queue_free()
			continue
		keep.append(e)
	_phantoms = keep


func _blast_fx(at: Vector3) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.0
	tm.rings = 64
	tm.ring_segments = 5
	ring.mesh = tm
	var mat := _additive(Color(1.0, 0.24, 0.12, 0.9))
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.top_level = true
	add_child(ring)
	ring.global_position = at + Vector3(0.0, 0.5, 0.0)
	ring.scale = Vector3(1.5, 2.0, 1.5)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(GHOST_BLAST_R, 2.0, GHOST_BLAST_R), 0.4)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.5)
	tw.chain().tween_callback(ring.queue_free)
	Sfx.play("ui_close", -5.0)


# ── 9 追踪光箭 ──

func _skill_homing(pc: Vector3) -> void:
	_play_once("Stand_Attack_Start")
	Sfx.play("fire_beam", -8.0)
	var n := HOMING_COUNT + (1 if _phase >= 2 else 0)
	for i in n:
		if _dead or not is_instance_valid(self):
			return
		var off := Vector3(cos(TAU * float(i) / float(n)), 0.0,
			sin(TAU * float(i) / float(n))) * 4.0
		_spawn_orb(pc + off * 0.2, "homing", off * 0.5)
		await get_tree().create_timer(0.2).timeout


# ── 10 引力井 ──

func _skill_gravity(pc: Vector3) -> void:
	_play_once("Normal_Attack_Ing")
	Sfx.play("ui_open", -4.0)
	var at := Vector3(pc.x, pc.y, pc.z)
	var disc := _make_disc(at, WELL_RADIUS, Color(1.0, 0.06, 0.10, 0.30))
	_wells.append({"node": disc, "t": WELL_TIME, "center": at})
	print("[YuukaHorror] 引力井：%s（半径 %.0f m，%.1f s）" % [
		str(at.snappedf(0.1)), WELL_RADIUS, WELL_TIME])


## 井里每秒往中心拽 2.6 m/s 的**位移**（远小于跑速 6.8，能走出去）；
## 时间到就炸一下。
func _tick_wells(delta: float) -> void:
	if _wells.is_empty():
		return
	var p := _find_player()
	var keep: Array[Dictionary] = []
	for w in _wells:
		var node: MeshInstance3D = w["node"]
		if node == null or not is_instance_valid(node):
			continue
		var center: Vector3 = w["center"]
		var t := float(w["t"]) - delta
		w["t"] = t
		if p != null:
			# 三维吸附：飞到井上空也会被往下拽（对空）
			var d := (p.global_position + Vector3.UP * 0.9) - center
			if d.length() <= WELL_RADIUS and d.length() > 0.4:
				p.global_position -= d.normalized() * WELL_PULL * delta
		if t <= 0.0:
			var pp := _find_player()
			print("[YuukaHorror] 引力井爆炸（玩家距井心 %.1f m，高差 %.1f m）" % [
				(pp.global_position - center).length() if pp != null else -1.0,
				(pp.global_position.y - center.y) if pp != null else -1.0])
			Vfx.big_burst(self, center + Vector3.UP * 1.0, Color(1.0, 0.18, 0.30), 1.5)
			_hit_area(center, WELL_RADIUS, _dmg(WELL_DAMAGE), 14.0, "gravity")
			_flash_mark(node, 1.25, 0.3)
			continue
		keep.append(w)
	_wells = keep


# ── 11 EX 护盾（优香原作是护盾角色）──

func _skill_shield() -> void:
	_play_once("Exs_Cutin", 0.2)
	Sfx.play("ex_fire", -8.0)
	await get_tree().create_timer(0.7).timeout
	if _dead or not is_instance_valid(self):
		return
	_raise_shield()


## 上盾：护盾值 + 闪避率，持续 SHIELD_TIME
func _raise_shield() -> void:
	_shield_hp = SHIELD_HP * (1.6 if _phase >= 2 else 1.0)
	_shield_left = SHIELD_TIME
	_shield_cd = SHIELD_COOLDOWN
	_build_shield_fx()
	Vfx.ring(self, global_position + Vector3.UP * height * 0.42,
		Color(1.0, 0.3, 0.2, 0.9), 13.0, 0.5, false)
	Vfx.flash(Color(1.0, 0.5, 0.4), 0.18, 0.25)
	Sfx.play("ui_open", -3.0)
	print("[YuukaHorror] EX 护盾：%.0f 点，闪避 %.0f%%，%.0f s" % [
		_shield_hp, _evasion() * 100.0, SHIELD_TIME])


## 当前闪避率（只在护盾存在时生效；探针可以用 `debug_set_evasion` 固定）
func _evasion() -> float:
	if _evasion_fixed >= 0.0:
		return _evasion_fixed
	return SHIELD_EVASION if _shield_hp > 0.0 else 0.0


func _build_shield_fx() -> void:
	_clear_shield_fx()
	# 一层半透明球壳 + 两圈环，挂在 BOSS 身上（跟着她动）
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 11.0
	sm.height = 22.0
	sm.radial_segments = 32
	sm.rings = 16
	ball.mesh = sm
	ball.material_override = _additive(Color(1.0, 0.10, 0.12, 0.12))
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ball.position = Vector3(0.0, height * 0.42, 0.0)
	add_child(ball)
	_shield_fx.append(ball)
	for spec in [[0.0, 0.0], [PI * 0.5, 0.0]]:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.985
		tm.outer_radius = 1.0
		tm.rings = 96
		tm.ring_segments = 4
		ring.mesh = tm
		ring.material_override = _additive(Color(1.0, 0.22, 0.14, 0.45))
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.position = Vector3(0.0, height * 0.42, 0.0)
		ring.rotation.x = float(spec[0])
		ring.scale = Vector3(11.0, 2.0, 11.0)
		add_child(ring)
		_shield_fx.append(ring)


func _clear_shield_fx() -> void:
	for n in _shield_fx:
		if is_instance_valid(n):
			n.queue_free()
	_shield_fx.clear()


func _tick_shield(delta: float) -> void:
	_shield_cd = maxf(_shield_cd - delta, 0.0)
	if _shield_hp <= 0.0:
		return
	_shield_left -= delta
	var t := float(Time.get_ticks_msec()) * 0.001
	var a := 0.10 + 0.05 * (0.5 + 0.5 * sin(t * 3.2))
	for n in _shield_fx:
		var mi := n as MeshInstance3D
		if mi == null or not is_instance_valid(mi):
			continue
		var m := mi.material_override as StandardMaterial3D
		if m != null:
			m.albedo_color.a = a
	if _shield_left <= 0.0:
		_break_shield(false, "时间到")


func _break_shield(explode := true, why := "?") -> void:
	print("[YuukaHorror] 护盾碎了（%s｜剩 %.2f s / %.0f 点）" % [why, _shield_left,
		_shield_hp])
	_shield_hp = 0.0
	_shield_left = 0.0
	_clear_shield_fx()
	if explode:
		_blast_fx(global_position + Vector3.UP * height * 0.42)
		Vfx.big_burst(self, global_position + Vector3.UP * height * 0.42,
			Color(1.0, 0.35, 0.3), 1.4)
		Vfx.shake(1.2, 0.4)
		Sfx.play("ui_close", -3.0)


## 被打到护盾：闪一下盾壳
func _shield_hit_fx() -> void:
	for n in _shield_fx:
		var mi := n as MeshInstance3D
		if mi == null or not is_instance_valid(mi):
			continue
		var m := mi.material_override as StandardMaterial3D
		if m == null:
			continue
		m.albedo_color.a = 0.55
		var tw := create_tween()
		tw.tween_property(m, "albedo_color:a", 0.12, 0.25)


## 闪避：一声轻响 + 身上闪一下
func _dodge_fx() -> void:
	Sfx.play("ui_toggle", -8.0)
	_flash_shield()


# ── 12 跪射 ──

func _skill_kneel(pc: Vector3) -> void:
	_play_once("Kneel_Attack_Start", 0.12)
	Sfx.play("fire_beam", -10.0)
	await get_tree().create_timer(0.35).timeout
	if _dead or not is_instance_valid(self):
		return
	_play_once("Kneel_Attack_Ing", 0.08)
	var n := KNEEL_COUNT + (2 if _phase >= 2 else 0)
	var p := _find_player()
	var vel := (p as CharacterBody3D).velocity if p is CharacterBody3D else Vector3.ZERO
	var aim := pc + Vector3(vel.x, 0.0, vel.z) * 0.35
	var flat := aim - global_position
	flat.y = 0.0
	flat = flat.normalized() if flat.length() > 0.5 else facing()
	var side := Vector3(flat.z, 0.0, -flat.x)
	for i in n:
		if _dead or not is_instance_valid(self):
			return
		var off := (float(i) - float(n - 1) * 0.5) * 2.0
		_spawn_orb(aim + side * off, "kneel", Vector3.ZERO, KNEEL_DAMAGE,
			ORB_SPEED * 1.15)
		await get_tree().create_timer(0.09).timeout


# ── 13 跳砸 ──

func _skill_leapslam(pc: Vector3) -> void:
	_play_once("Move_Jump", 0.12)
	Sfx.play("fire_beam", -6.0)
	var center := Vector3(pc.x, pc.y, pc.z)
	var disc := _make_disc(center, LEAP_RADIUS, Color(1.0, 0.16, 0.10, 0.45))
	_slam_marks.append(disc)
	var tw := create_tween()
	tw.tween_property(disc, "scale", Vector3(LEAP_RADIUS, 1.0, LEAP_RADIUS), LEAP_WARN) \
		.from(Vector3(LEAP_RADIUS * 0.25, 1.0, LEAP_RADIUS * 0.25))
	# 视觉：整个人往上一跃再砸下来（只动 model，不动碰撞盒）
	if model != null:
		var base_y := model.position.y
		var hop := create_tween()
		hop.tween_property(model, "position:y", base_y + 8.0, 0.45) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		hop.tween_property(model, "position:y", base_y, maxf(LEAP_WARN - 0.45, 0.2)) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	if _dead or not is_instance_valid(self):
		_free_marks()
		return
	Vfx.big_burst(self, center, Color(1.0, 0.42, 0.22), 1.6)
	Vfx.shake(1.6, 0.55)
	_hit_area(center, LEAP_RADIUS, _dmg(LEAP_DAMAGE), LEAP_KNOCK, "leapslam")
	Sfx.play("ui_close", -1.0)
	_flash_mark(disc, 1.3, 0.3)
	_slam_marks.erase(disc)
	await get_tree().create_timer(0.3).timeout


# ── 14 蓄力炮（装填 → 一炮）──

func _skill_beam(pc: Vector3) -> void:
	_play_once("Normal_Reload", 0.15)
	Sfx.play("ui_open", -6.0)
	var dir := pc - global_position
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 1.0 else facing()
	var pivot := Node3D.new()
	pivot.name = "BeamPivot"
	pivot.top_level = true
	add_child(pivot)
	pivot.global_position = global_position
	pivot.rotation.y = atan2(dir.x, dir.z)
	var blade := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.6, BEAM_TOP, BEAM_LEN)
	blade.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.18, 0.10, 0.0)
	blade.material_override = mat
	blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blade.position = Vector3(0.0, BEAM_TOP * 0.5, BEAM_LEN * 0.5)
	pivot.add_child(blade)
	# 蓄力：细红线越来越亮
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.28, BEAM_WARN)
	await tw.finished
	if _dead or not is_instance_valid(self):
		if is_instance_valid(pivot):
			pivot.queue_free()
		return
	# 开火：炮身加粗，判定一次
	bm.size = Vector3(BEAM_HALF_WIDTH * 2.0, BEAM_TOP, BEAM_LEN)
	var tw2 := create_tween()
	tw2.tween_property(mat, "albedo_color:a", 0.60, 0.07)
	await get_tree().create_timer(0.3).timeout
	_beam_hit(dir)
	Vfx.flash(Color(1.0, 0.5, 0.35), 0.30, 0.28)
	Vfx.shake(1.3, 0.4)
	Sfx.play("ex_fire", -3.0)
	await get_tree().create_timer(0.25).timeout
	if is_instance_valid(pivot):
		var tw3 := create_tween()
		tw3.tween_property(mat, "albedo_color:a", 0.0, 0.35)
		tw3.tween_callback(pivot.queue_free)


func _beam_hit(dir: Vector3) -> void:
	var p := _find_player()
	if p == null or not p.has_method("take_damage"):
		return
	var chest := p.global_position + Vector3.UP * 0.9
	var from := global_position + Vector3.UP * 2.0
	var closest := Geometry3D.get_closest_point_to_segment(
		chest, from, from + dir * BEAM_LEN)
	var dy := chest.y - global_position.y
	if closest.distance_to(chest) <= BEAM_HALF_WIDTH and dy >= -2.0 and dy <= BEAM_TOP:
		_hits["beam"] += 1
		p.call("take_damage", _dmg(BEAM_DAMAGE), from, 18.0)
		Vfx.impact(self, chest, Color(1.0, 0.55, 0.35), 1.6, 0.0)
		Vfx.shake(1.4, 0.5)
		print("[YuukaHorror] beam 命中（偏离 %.1f m）" % closest.distance_to(chest))


# ── 15 召唤（呼号 → 一群幻影）──

func _skill_summon(pc: Vector3) -> void:
	_play_once("Normal_Callsign", 0.15)
	Sfx.play("ui_open", -5.0)
	await get_tree().create_timer(0.6).timeout
	if _dead or not is_instance_valid(self):
		return
	var n := SUMMON_COUNT + (1 if _phase >= 2 else 0)
	for i in n:
		if _dead or not is_instance_valid(self):
			return
		var ang := TAU * float(i) / float(n)
		var off := Vector3(cos(ang), 0.0, sin(ang)) * 5.0
		var tgt := pc + Vector3(cos(ang * 2.0), 0.0, sin(ang * 2.0)) * 3.0
		_spawn_ghost(global_position + off, tgt, "summon")
		await get_tree().create_timer(0.1).timeout


# ── 16 冲锋枪扫射 ──
##
## 用户 2026-11-13：「要一个快速冲锋枪扫射技能，就是冲锋枪普通攻击但是速度特别快」。
## 射速 20 发/秒（间隔 0.05 s）、单发只有 5 点，但带 0.7 m 的随机散布 ——
## 站桩会被糊一脸，边跑边打就只剩零星几发。
## 弹速 36 m/s、弹体 42%（视觉上像曳光弹），判定仍然是三点一线的扫掠球。

func _skill_rapid(pc: Vector3) -> void:
	_play_once("Stand_Attack_Ing", 0.08)
	Sfx.play("fire", -12.0)
	var n := RAPID_SHOTS + (10 if _phase >= 2 else 0)
	for i in n:
		if _dead or not is_instance_valid(self):
			return
		var p := _find_player()
		var target := pc
		if p != null:
			var vel := (p as CharacterBody3D).velocity if p is CharacterBody3D else Vector3.ZERO
			target = p.global_position + Vector3.UP * 0.9 + vel * 0.12
		target += Vector3(randf_range(-1.0, 1.0), randf_range(-0.6, 0.9),
			randf_range(-1.0, 1.0)) * RAPID_SPREAD
		_spawn_orb(target, "rapid", Vector3.ZERO, RAPID_DAMAGE, RAPID_SPEED, RAPID_SIZE)
		# 每 4 发补一声枪响（Sfx 自己还有 gap 节流，不会糊成噪音）
		if i % 4 == 0:
			Sfx.play("fire", -14.0)
		await get_tree().create_timer(RAPID_INTERVAL).timeout
	await get_tree().create_timer(0.25).timeout


# ── 17 召唤飞猪优香 ──
##
## 用户 2026-11-13：「还要加召唤类技能，召唤 3 飞猪优香，这次真的是飞的，
## 而且飞猪优香也有更多技能了」。
## 召唤物见 `scripts/flying_pig_yuuka.gd`：悬停绕圈 + 俯冲撞击 / 三连飞弹 / 俯冲轰炸。
## 最多同场 3 只；已经 3 只时这一招只做"呼号"动作，不叠加。

func _skill_pigs() -> void:
	_play_once("Normal_Callsign", 0.15)
	Sfx.play("ui_open", -3.0)
	await get_tree().create_timer(0.5).timeout
	if _dead or not is_instance_valid(self):
		return
	# 先清掉已经死了的引用
	var alive: Array[Node3D] = []
	for pg in _pigs:
		if is_instance_valid(pg) and not bool(pg.get("_dead")):
			alive.append(pg)
	_pigs = alive
	var need := PIG_COUNT - _pigs.size()
	if need <= 0:
		print("[YuukaHorror] 场上已有 %d 只飞猪，这次不再召唤" % _pigs.size())
		return
	var host := get_parent() if get_parent() != null else get_tree().root
	var who := _find_player()
	for i in need:
		if _dead or not is_instance_valid(self):
			return
		var ang := TAU * float(i) / float(maxi(need, 1)) + randf_range(-0.2, 0.2)
		var at := global_position + Vector3(cos(ang), 0.0, sin(ang)) * 10.0 \
			+ Vector3.UP * height * 0.7
		var pig := PIG_SCRIPT.new() as Node3D
		if pig == null:
			continue
		host.add_child(pig)
		pig.global_position = at
		if pig.has_method("setup"):
			pig.call("setup", who)
		_pigs.append(pig)
		Vfx.ring(self, Vector3(at.x, at.y - height * 0.7 + 0.1, at.z),
			Color(0.85, 0.35, 1.0, 0.9), 8.0, 0.6)
		Vfx.burst(self, at, Color(0.85, 0.3, 1.0), 30, 1.6, 14.0, 0.5, -2.0)
		Sfx.play("ui_toggle", -8.0)
		await get_tree().create_timer(0.15).timeout
	print("[YuukaHorror] 召唤飞猪优香 %d 只（在场 %d）" % [need, _pigs.size()])


## 飞猪离场（BOSS 真死时把召唤物一起收掉）
func _expire_pigs() -> void:
	for pg in _pigs:
		if is_instance_valid(pg) and pg.has_method("expire"):
			pg.call("expire")
	_pigs.clear()


# ────────────────────────── 光球 ──────────────────────────

## `kind` 只用于统计（barrage / homing / kneel）；`side` 给追踪弹一点出生偏移；
## `dmg_now` / `speed_now` 让不同技能用同一套光球但手感不同。
func _spawn_orb(target: Vector3, kind: String, side := Vector3.ZERO,
		dmg_now := ORB_DAMAGE, speed_now := ORB_SPEED, size_scale := 1.0) -> void:
	var orb := MeshInstance3D.new()
	orb.name = "HorrorOrb"
	var sm := SphereMesh.new()
	sm.radius = 1.1 * size_scale
	sm.height = 2.2 * size_scale
	sm.radial_segments = 16
	sm.rings = 8
	orb.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.22, 0.12, 0.95)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.16, 0.08)
	mat.emission_energy_multiplier = 2.4
	orb.material_override = mat
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 从胸口高度甩出去（⚠️ 先进树再设 global_position，理由同 `_make_disc()`）
	var from := global_position + Vector3(0.0, height * 0.62, 0.0) \
		+ facing() * height * 0.18 + side
	orb.top_level = true
	add_child(orb)
	orb.global_position = from
	var dir := target - from
	dir = dir.normalized() if dir.length_squared() > 0.01 else Vector3.FORWARD
	_orbs.append({
		"node": orb, "dir": dir, "t": 0.0, "kind": kind,
		"homing": kind == "homing",
		"life": HOMING_LIFE if kind == "homing" else ORB_LIFE,
		"dmg": HOMING_DAMAGE if kind == "homing" else dmg_now,
		"speed": HOMING_SPEED if kind == "homing" else speed_now,
	})


## 光球推进。直线弹走 ORB_SPEED；追踪弹有**转向上限**（HOMING_TURN），
## 速度低、寿命长 —— 绕圈能甩掉。
## 命中用**扫掠**：取这一段位移到玩家胸口的最近距离，低帧率不会穿过去。
func _tick_orbs(delta: float) -> void:
	if _orbs.is_empty():
		return
	var p := _find_player()
	var keep: Array[Dictionary] = []
	for o in _orbs:
		var node: MeshInstance3D = o["node"]
		if node == null or not is_instance_valid(node):
			continue
		var t := float(o["t"]) + delta
		if t > float(o["life"]):
			node.queue_free()
			continue
		var dir: Vector3 = o["dir"]
		var speed := float(o.get("speed", ORB_SPEED))
		if bool(o["homing"]):
			speed = HOMING_SPEED
			if p != null:
				# ⚠️ 必须**三维**转向：第一版只转 yaw（`want.y = 0`），
				#    光球从胸口（+9.9 m）甩出来以后永远平飞，打不到地上的人
				#    （探针实测 0 命中）。
				var want := (p.global_position + Vector3.UP * 0.9) - node.global_position
				if want.length_squared() > 0.01:
					want = want.normalized()
					var max_turn := deg_to_rad(HOMING_TURN) * delta
					var ang := dir.angle_to(want)
					var k := 1.0 if ang < 0.0001 else clampf(max_turn / ang, 0.0, 1.0)
					dir = dir.slerp(want, k).normalized()
					o["dir"] = dir
		var prev := node.global_position
		var next := prev + dir * speed * delta
		node.global_position = next
		if p != null and p.has_method("take_damage"):
			var chest := p.global_position + Vector3.UP * 0.9
			var closest := Geometry3D.get_closest_point_to_segment(chest, prev, next)
			if closest.distance_to(chest) <= ORB_HIT_R:
				var kind := String(o["kind"])
				_hits[kind] = int(_hits.get(kind, 0)) + 1
				p.call("take_damage", _dmg(float(o.get("dmg", ORB_DAMAGE))), closest, 6.0)
				Vfx.burst(self, closest, Color(1.0, 0.32, 0.22), 16, 0.9, 10.0, 0.35, -2.0)
				Vfx.shake(0.35, 0.18)
				print("[YuukaHorror] %s 命中" % kind)
				node.queue_free()
				continue
		o["t"] = t
		keep.append(o)
	_orbs = keep


# ────────────────────────── 范围伤害 / 地面圈 ──────────────────────────

## ⚠️ 铁律（`boss_attacker.gd` 文件头）：预警半径**就是**伤害半径。
## ⚠️ 判定是**球（3D 距离）**，不是"水平圆 + 高度带"：
##    玩家有机甲形态、**会飞**（`player.gd::SPEED_FLY = 11 m/s`，加力 19）。
##    用户 2026-11-13：「因为机甲是天上飞的，技能更多要大范围可以对空或者精准小范围对空的。」
##    所以这里的半径既管地上也管天上 —— 圈画在玩家脚下，飞起来一样被罩住。
func _hit_area(center: Vector3, radius: float, dmg: float, knock: float,
		kind := "") -> void:
	var p := _find_player()
	if p == null or not p.has_method("take_damage"):
		return
	var chest := p.global_position + Vector3.UP * 0.9
	var d := chest.distance_to(center)
	if d <= radius:
		if kind != "":
			_hits[kind] = int(_hits.get(kind, 0)) + 1
		p.call("take_damage", dmg, center, knock)
		Vfx.impact(self, center, Color(1.0, 0.30, 0.20), 1.1, d)
		print("[YuukaHorror] %s 命中（%.1f m / %.1f m）" % [kind, d, radius])


func _make_disc(center: Vector3, radius: float, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	# PlaneMesh 默认躺在 XZ 平面，UV 正好是 0~1 的方块 → 着色器里裁成圆
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(2.0, 2.0)
	mi.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = DISC_SHADER
	mat.set_shader_parameter("color", col)
	mat.set_shader_parameter("alpha", DISC_ALPHA)
	mat.set_shader_parameter("pulse", 0.0)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3(radius, 1.0, radius)
	# ⚠️ top_level：BOSS 每帧都在朝玩家转身，普通子节点会被**带着绕它的原点转**
	#    （实测幻影沿弧线飞、落点圈飘走）。特效一律脱离父变换。
	mi.top_level = true
	# ⚠️ 必须**先进树再设 global_position**：不在树里的 Node3D 没有全局变换，
	#    先设会被丢弃（返回 Transform3D()），圈就落在世界原点了（实测踩过）。
	add_child(mi)
	mi.global_position = Vector3(center.x, center.y + 0.06, center.z)
	# 蓄力期间让圈"呼吸"，玩家更容易注意到脚下亮起来了
	var tw := create_tween()
	tw.set_loops(0)
	tw.bind_node(mi)      # 圈被回收时这个循环自己停掉，不会越攒越多
	tw.tween_method(func(v: float) -> void:
		if is_instance_valid(mat):
			mat.set_shader_parameter("pulse", v), 0.0, 1.0, 0.45)
	tw.tween_method(func(v: float) -> void:
		if is_instance_valid(mat):
			mat.set_shader_parameter("pulse", v), 1.0, 0.0, 0.45)
	return mi


## ⚠️ 参数**不要**写 `mark: Node3D`：技能是异步的，`debug_reset()` / `_free_marks()`
##    可能已经把圈清了，后面再传一个已释放的对象进来会在**类型检查**阶段就报错
##    （`The Object-derived class of argument 1 (previously freed)…`）。
func _flash_mark(mark, grow: float, time: float) -> void:
	if mark == null or not is_instance_valid(mark):
		return
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mark, "scale", mark.scale * grow, time)
	var mi := mark as MeshInstance3D
	if mi != null:
		var sh := mi.material_override as ShaderMaterial
		if sh != null:
			# 地面圈用的是 `telegraph_disc` 着色器 → 淡出它的 alpha
			tw.tween_method(func(v: float) -> void:
				if is_instance_valid(sh):
					sh.set_shader_parameter("alpha", v), DISC_ALPHA * 2.4, 0.0, time)
		else:
			var std := mi.material_override as StandardMaterial3D
			if std != null:
				tw.tween_property(std, "albedo_color:a", 0.0, time)
	tw.chain().tween_callback(mark.queue_free)


func _free_marks() -> void:
	for m in _slam_marks:
		if is_instance_valid(m):
			m.queue_free()
	_slam_marks.clear()


# ────────────────────────── 受击 / 阶段 / 死亡 ──────────────────────────

func _flash() -> void:
	# 材质已经换成 ShaderMaterial（基类 `_materials` 里那份不再挂在表面上），
	# 所以闪白走着色器的 `flash` 参数，而不是基类的 albedo tween。
	for m in _skin_mats:
		if not is_instance_valid(m):
			continue
		m.set_shader_parameter("flash", 1.0)
		var tw := create_tween()
		tw.tween_method(func(v: float) -> void:
			if is_instance_valid(m):
				m.set_shader_parameter("flash", v), 1.0, 0.0, 0.18)


## 无敌期间挨打：不扣血，只在身上闪一下"打不进去"的亮光。
func _flash_shield() -> void:
	if _shield_t > 0.0:
		return
	_shield_t = 0.25
	Sfx.play("ui_toggle", -6.0)
	for m in _skin_mats:
		if not is_instance_valid(m):
			continue
		m.set_shader_parameter("flash", 0.55)
		var tw := create_tween()
		tw.tween_method(func(v: float) -> void:
			if is_instance_valid(m):
				m.set_shader_parameter("flash", v), 0.55, 0.0, 0.22)


func take_damage(amount: float, hit_pos := Vector3.ZERO, hit_dir := Vector3.ZERO) -> void:
	if _dead:
		return
	if _invuln:
		# 复活演出的 20 s：枪打得再准也不掉血
		_flash_shield()
		return
	# ── EX 护盾：先按闪避率骰一次，再吃护盾，最后才扣血 ──
	if _shield_hp > 0.0:
		if randf() < _evasion():
			_dodge_fx()
			return
		var absorbed := minf(_shield_hp, amount)
		_shield_hp -= absorbed
		amount -= absorbed
		_shield_hit_fx()
		if _shield_hp <= 0.0:
			_break_shield(true, "被打碎")
		if amount <= 0.0:
			_flash_shield()
			return
	# 二阶段"防御力 +50%" = 受到的伤害减半
	var dmg := amount * (1.0 - P2_DEFENSE) if _phase >= 2 else amount
	super.take_damage(dmg, hit_pos, hit_dir)


## 血量打空 → 不是死，是**复活演出**：20 s 无敌 + 血量逐渐回到一半。
func _die(by_damage: float) -> void:
	if _dead:
		return
	if _phase == 1 and not _reviving:
		_begin_revive()
		return
	_real_death(by_damage)


func _begin_revive() -> void:
	_reviving = true
	_invuln = true
	_revive_t = REVIVE_TIME
	_heal_t = REVIVE_HEAL_TIME
	_phase2_live = false
	health = 0.0
	health_changed.emit(health, max_health)
	_t_skill = REVIVE_TIME + 0.5
	Sfx.play("ex_fire", -1.0)
	Vfx.big_burst(self, global_position + Vector3.UP * height * 0.45,
		Color(1.0, 0.12, 0.10), 2.6)
	Vfx.flash(Color(1.0, 0.1, 0.08), 0.45, 0.5)
	Vfx.shake(2.4, 0.9)
	_play_once("Vital_Dying_Ing")
	revive_started.emit()
	print("[YuukaHorror] 血量打空 → 复活演出（%.0f s 无敌，回血到 %.0f）" % [
		REVIVE_TIME, max_health * REVIVE_TO])
	# 先跪 1.2 s，再"挣扎着站起来"
	await get_tree().create_timer(1.2).timeout
	if not is_instance_valid(self) or _dead:
		return
	_play_once("Vital_Panic")
	await get_tree().create_timer(1.4).timeout
	if not is_instance_valid(self) or _dead:
		return
	_play_once("Victory_Start")


## 3 s 回血结束 → **立刻开打**（用户：无敌时间里她就开始攻击）。
## 注意：这里**不解无敌**，`_invuln` 还要再挂 17 s。
func _start_phase2() -> void:
	if _phase2_live:
		return
	_phase2_live = true
	_phase = 2
	health = max_health * REVIVE_TO
	health_changed.emit(health, max_health)
	_t_skill = 0.8          # 回血一结束就出招，不留空档
	_skill_i = 0
	phase_changed.emit(2)
	Vfx.big_burst(self, global_position + Vector3.UP * height * 0.45,
		Color(1.0, 0.25, 0.15), 2.4)
	Vfx.flash(Color(1.0, 0.25, 0.15), 0.40, 0.55)
	Vfx.shake(2.0, 0.8)
	Sfx.play("ui_open", -2.0)
	_play_once("Victory_End")
	# 护盾角色：进二阶段先给自己上盾（玩家在这 17 s 里打不动她，但能看清盾在掉）
	_raise_shield()
	print("[YuukaHorror] 回血完成 → 二阶段开打（仍无敌）：血量 %.0f，攻击 ×%.1f，间隔 %.2f s，受伤 ×%.2f" % [
		health, P2_DAMAGE, _interval(), 1.0 - P2_DEFENSE])


## 20 s 到点：无敌解除
func _end_invuln() -> void:
	if not _reviving and not _invuln:
		return
	_reviving = false
	_invuln = false
	print("[YuukaHorror] 复活无敌结束（可以打了）")


## 二阶段的真死：走 GLB 的 Vital_Dying_Ing → Vital_Death（不用基类的整体扑倒）
func _real_death(by_damage: float) -> void:
	_dead = true
	died.emit(by_damage)
	for c in _collisions:
		if is_instance_valid(c):
			c.set_deferred("disabled", true)
	_free_marks()
	for w in _waves:
		var n: Node3D = w["node"]
		if is_instance_valid(n):
			n.queue_free()
	_waves.clear()
	for o in _orbs:
		var n2: Node3D = o["node"]
		if is_instance_valid(n2):
			n2.queue_free()
	_orbs.clear()
	for s in _sweeps:
		var n3: Node3D = s["node"]
		if is_instance_valid(n3):
			n3.queue_free()
	_sweeps.clear()
	for w2 in _wells:
		var n4: Node3D = w2["node"]
		if is_instance_valid(n4):
			n4.queue_free()
	_wells.clear()
	for e in _phantoms:
		var n5: Node3D = e["node"]
		if is_instance_valid(n5):
			n5.queue_free()
	_phantoms.clear()
	_expire_pigs()
	_expire_clones()
	Vfx.big_burst(self, global_position + Vector3.UP * height * 0.45,
		Color(1.0, 0.15, 0.10), 3.0)
	Vfx.flash(Color(1.0, 0.25, 0.2), 0.55, 0.8)
	Vfx.shake(2.6, 1.0)
	_death_fx()


func _death_fx() -> void:
	Sfx.play("ex_fire", -2.0)
	if _ap != null and _ap.has_animation("Vital_Dying_Ing"):
		_ap.play("Vital_Dying_Ing", 0.15)
		await get_tree().create_timer(1.15).timeout
	for m in _skin_mats:
		if is_instance_valid(m):
			m.set_shader_parameter("rim_amount", 4.0)
	if _ap != null and _ap.has_animation("Vital_Death"):
		_ap.play("Vital_Death", 0.15)
	if _aura_light != null and is_instance_valid(_aura_light):
		var tw := create_tween()
		tw.tween_property(_aura_light, "light_energy", 0.0, 2.4)
	for r in _rings:
		var node: Node3D = r["node"]
		if not is_instance_valid(node):
			continue
		var m2 := (node as MeshInstance3D).material_override as StandardMaterial3D
		if m2 != null:
			create_tween().tween_property(m2, "albedo_color:a", 0.0, 1.2)
	print("[YuukaHorror] 已倒下")


# ────────────────────────── 探针 / 自检接口 ──────────────────────────

func status() -> Dictionary:
	return {
		"health": health,
		"max_health": max_health,
		"phase": _phase,
		"dead": _dead,
		"reviving": _reviving,
		"revive_t": _revive_t,
		"heal_t": _heal_t,
		"phase2_live": _phase2_live,
		"invuln": _invuln,
		"shield_hp": _shield_hp,
		"shield_left": _shield_left,
		"evasion": _evasion(),
		"damage_scale": P2_DAMAGE if _phase >= 2 else 1.0,
		"take_scale": 1.0 - P2_DEFENSE if _phase >= 2 else 1.0,
		"interval": _interval(),
		"last_skill": _last_skill,
		"counts": _counts.duplicate(),
		"hits": _hits.duplicate(),
		"has_anim": _ap != null,
		"anim": _ap.current_animation if _ap != null else "",
		"skin_mats": _skin_mats.size(),
		"waves": _waves.size(),
		"orbs": _orbs.size(),
		"sweeps": _sweeps.size(),
		"wells": _wells.size(),
		"phantoms": _phantoms.size(),
		"slam_marks": _slam_marks.size(),
		"busy": _busy,
		"pigs": _alive_pigs(),
		"pig_min_alt": _pig_min_alt(),
		"pig_hits": _pig_hits(),
		"clones": _alive_clones(),
		"clone_hits": _clone_hits(),
		"blink_cd": _blink_cd,
		"blinks": _blinks,
		"chase_blocked": _chase_blocked,
	}


## 探针用：清掉场上所有特效残骸、把计数归零（招式之间互不干扰）
# ────────────────────────── 追击 / 闪现 / 分身 ──────────────────────────

## 追玩家：只用"地面射线跟脚 + 前方 3 m 探墙"，不做完整寻路。
## 校园碰撞是烘焙 trimesh，真正的寻路要 NavMesh；这里只求"会走过来"。
func _chase(delta: float) -> void:
	if not _chase_on:
		return
	var p := _find_player()
	if p == null:
		return
	var d := p.global_position - global_position
	var flat := Vector2(d.x, d.z)
	if flat.length() <= CHASE_FAR:
		return
	var dir := Vector3(flat.normalized().x, 0.0, flat.normalized().y)
	# 直线被挡就左右偏一点绕（校园里树和楼的碰撞到处都是；
	# 真寻路要 NavMesh，这里只要"别站着不动"）
	for ang in [0.0, 25.0, -25.0, 50.0, -50.0, 80.0, -80.0]:
		var d2 := dir.rotated(Vector3.UP, deg_to_rad(float(ang)))
		if _walk_step(d2, delta):
			return
	# 七个方向全被挡（贴墙 / 卡在树缝里）：**保持高度直接平移**。
	# 宁可擦着墙走，也不要钉在原地 —— 用户明确说了「现在一动不动」。
	_chase_blocked += 1
	global_position += Vector3(dir.x, 0.0, dir.z) * CHASE_SPEED * delta


## 试走一步：前方 4.5 m 没墙、下一格地面高差 ≤ CHASE_STEP_MAX 才走
func _walk_step(dir: Vector3, delta: float) -> bool:
	var space := get_world_3d().direct_space_state
	# ⚠️ 探墙射线放在 **2 m 低处、只探 2.5 m**：
	#    放在胸口高度会被树冠误判成"前面有墙"，实测整只钉在原地。
	var from := global_position + Vector3.UP * 2.0
	if space != null:
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 2.5)
		q.collision_mask = 1
		q.exclude = [get_rid()]
		if not space.intersect_ray(q).is_empty():
			return false
	var step := CHASE_SPEED * delta
	var nx := global_position.x + dir.x * step
	var nz := global_position.z + dir.z * step
	var gy := _sample_ground(nx, nz)
	if is_nan(gy):
		# 校园碰撞网格有洞、采样不到地面 → **保持当前高度**先走过去，
		# 别因为"量不出地面"就整只钉在原地（实测被挡 2788 帧）。
		global_position = Vector3(nx, global_position.y, nz)
		return true
	if absf(gy - global_position.y) > CHASE_STEP_MAX:
		return false
	global_position = Vector3(nx, gy + 0.05, nz)
	return true


## 采样 (x,z) 的地面高度；不可信（打穿了校园网格）时返回 NAN
func _sample_ground(x: float, z: float) -> float:
	var space := get_world_3d().direct_space_state
	if space == null:
		return NAN
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(x, global_position.y + 200.0, z),
		Vector3(x, global_position.y - 200.0, z))
	q.collision_mask = 1
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return NAN
	var gy := (hit["position"] as Vector3).y
	if gy < -20.0:
		return NAN
	return gy


## 闪现：长冷却；玩家跑远了她直接出现在**背后**
func _tick_blink(delta: float) -> void:
	_blink_cd = maxf(_blink_cd - delta, 0.0)
	if _blink_cd > 0.0 or _invuln:
		return
	var p := _find_player()
	if p == null:
		return
	if global_position.distance_to(p.global_position) < BLINK_MIN_DIST:
		return
	_blink_cd = BLINK_CD
	_blinks += 1
	_do_blink(p)


func _do_blink(p: Node3D) -> void:
	# 玩家脸朝 = (sin(_facing_yaw), 0, cos(_facing_yaw))（见 `player.gd` 注释）
	var yaw := float(p.get("_facing_yaw")) if p.get("_facing_yaw") != null else p.rotation.y
	var facing := Vector3(sin(yaw), 0.0, cos(yaw))
	var behind := p.global_position - facing * BLINK_BEHIND
	var gy := _ground_below(Vector3(behind.x, p.global_position.y, behind.z))
	# 落点地面不可信（打穿了）→ 直接贴玩家那一层，别闪到地底去
	if absf(gy - p.global_position.y) > 8.0:
		gy = p.global_position.y - 0.9
	var at := Vector3(behind.x, gy + 0.05, behind.z)
	_blast_fx(global_position + Vector3.UP * height * 0.45)
	Vfx.burst(self, global_position + Vector3.UP * height * 0.45,
		Color(1.0, 0.2, 0.3), 40, 2.0, 20.0, 0.5, 0.0)
	global_position = at
	_blast_fx(at + Vector3.UP * height * 0.45)
	Vfx.burst(self, at + Vector3.UP * height * 0.45, Color(1.0, 0.2, 0.3), 55, 2.2,
		24.0, 0.55, 0.0)
	Vfx.ring(self, at + Vector3.UP * 0.4, Color(1.0, 0.25, 0.3, 0.9), 16.0, 0.5)
	Vfx.flash(Color(0.65, 0.05, 0.10), 0.30, 0.30)
	Vfx.shake(1.5, 0.45)
	rotation.y = atan2(p.global_position.x - at.x, p.global_position.z - at.z)
	Sfx.play("ui_toggle", -3.0)
	# 落地就接一招，别让闪现只当位移
	_t_skill = minf(_t_skill, 0.4)
	print("[YuukaHorror] 闪现到玩家身后：%s（第 %d 次）" % [str(at.snappedf(0.1)), _blinks])


## 召唤 10 个分身围住玩家；只有本体放技能，分身只会普攻
func _skill_clones() -> void:
	_play_once("Normal_Callsign", 0.15)
	Sfx.play("ui_open", -3.0)
	await get_tree().create_timer(0.5).timeout
	if _dead or not is_instance_valid(self):
		return
	_prune_clones()
	if _clone_cd > 0.0:
		print("[YuukaHorror] 分身冷却中（剩 %.1f s），这轮不召唤" % _clone_cd)
		return
	_clone_cd = CLONE_CD
	var p := _find_player()
	if p == null:
		return
	var host := get_parent() if get_parent() != null else get_tree().root
	var center := p.global_position
	for i in CLONE_COUNT:
		if _dead or not is_instance_valid(self):
			return
		var ang := TAU * float(i) / float(CLONE_COUNT)
		var x := center.x + cos(ang) * CLONE_RING
		var z := center.z + sin(ang) * CLONE_RING
		var gy := _ground_below(Vector3(x, center.y, z))
		var clone := CLONE_SCRIPT.new() as Node3D
		if clone == null:
			continue
		host.add_child(clone)
		clone.global_position = Vector3(x, gy + 0.05, z)
		if clone.has_method("setup"):
			clone.call("setup", p)
		_clones.append(clone)
		Vfx.ring(self, Vector3(x, gy + 0.1, z), Color(1.0, 0.2, 0.3, 0.9), 7.0, 0.55)
		Vfx.burst(self, Vector3(x, gy + 1.5, z), Color(1.0, 0.18, 0.25), 26, 1.4,
			12.0, 0.5, -3.0)
	print("[YuukaHorror] 分身 ×%d 围住玩家（只有本体放技能）" % CLONE_COUNT)


func _prune_clones() -> void:
	var alive: Array[Node3D] = []
	for c in _clones:
		if is_instance_valid(c) and not bool(c.get("_dead")):
			alive.append(c)
	_clones = alive


func _expire_clones() -> void:
	for c in _clones:
		if is_instance_valid(c) and c.has_method("expire"):
			c.call("expire")
	_clones.clear()


func _alive_clones() -> int:
	_prune_clones()
	return _clones.size()


func _clone_hits() -> int:
	var n := 0
	for c in _clones:
		if is_instance_valid(c):
			n += int(c.call("status").get("hits", 0))
	return n


## 探针用：把闪现冷却清零，下一帧就会闪
func debug_force_blink() -> void:
	_blink_cd = 0.0


## 探针用：直接设定闪现冷却（999 = 测试期间别乱闪）
func debug_set_blink_cd(v: float) -> void:
	_blink_cd = v


## 探针用：开关追击（测"站桩伤害判定"时要关掉，否则她会自己走进圈里）
func debug_set_chase(on: bool) -> void:
	_chase_on = on


## 场上还活着的飞猪数量
func _alive_pigs() -> int:
	var n := 0
	for pg in _pigs:
		if is_instance_valid(pg) and not bool(pg.get("_dead")):
			n += 1
	return n


## 飞猪里最低的那只离地多高（验证"真的在飞"）
func _pig_min_alt() -> float:
	var best := INF
	for pg in _pigs:
		if not is_instance_valid(pg) or bool(pg.get("_dead")):
			continue
		var st: Dictionary = pg.call("status")
		best = minf(best, float(st.get("altitude", 0.0)))
	return 0.0 if best == INF else best


## 三只飞猪加起来打中了多少次
func _pig_hits() -> int:
	var n := 0
	for pg in _pigs:
		if is_instance_valid(pg) and pg.has_method("total_hits"):
			n += int(pg.call("total_hits"))
	return n


## 探针用：把闪避率固定成 v（0 = 必中，方便测护盾吸收）
func debug_set_evasion(v: float) -> void:
	_evasion_fixed = v


func debug_reset() -> void:
	for w in _waves:
		var n: Node3D = w["node"]
		if is_instance_valid(n):
			n.queue_free()
	_waves.clear()
	for o in _orbs:
		var n2: Node3D = o["node"]
		if is_instance_valid(n2):
			n2.queue_free()
	_orbs.clear()
	for s in _sweeps:
		var n3: Node3D = s["node"]
		if is_instance_valid(n3):
			n3.queue_free()
	_sweeps.clear()
	for w2 in _wells:
		var n4: Node3D = w2["node"]
		if is_instance_valid(n4):
			n4.queue_free()
	_wells.clear()
	for e in _phantoms:
		var n5: Node3D = e["node"]
		if is_instance_valid(n5):
			n5.queue_free()
	_phantoms.clear()
	_free_marks()
	for k in _hits.keys():
		_hits[k] = 0


## 探针用：无视节奏立刻放某一招（不等冷却、不看设置开关）
func debug_cast(kind: String) -> void:
	var p := _find_player()
	if p == null:
		return
	_busy = true
	_counts[kind] = int(_counts.get(kind, 0)) + 1
	await _debug_cast_inner(kind, p)
	_busy = false


func _debug_cast_inner(kind: String, p: Node3D) -> void:
	var pc := p.global_position
	match kind:
		"slam":
			await _skill_slam(pc)
		"barrage":
			await _skill_barrage(pc)
		"sweep":
			await _skill_sweep(pc)
		"meteor":
			await _skill_meteor(pc)
		"spikes":
			await _skill_spikes(pc)
		"nova":
			await _skill_nova()
		"phantom":
			await _skill_phantom(pc)
		"homing":
			await _skill_homing(pc)
		"gravity":
			await _skill_gravity(pc)
		"shield":
			await _skill_shield()
		"kneel":
			await _skill_kneel(pc)
		"leapslam":
			await _skill_leapslam(pc)
		"beam":
			await _skill_beam(pc)
		"summon":
			await _skill_summon(pc)
		"rapid":
			await _skill_rapid(pc)
		"pigs":
			await _skill_pigs()
		"clones":
			await _skill_clones()
		_:
			await _skill_shockwave()


## 探针用：跳过 20 s 的最短等待，直接结算复活演出
func debug_finish_revive() -> void:
	# 直接跳到"回血完成 + 无敌结束"
	_heal_t = 0.0
	_revive_t = 0.0
	if _reviving:
		_start_phase2()
	_end_invuln()
