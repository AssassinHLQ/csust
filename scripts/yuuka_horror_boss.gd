extends Boss
## 最终 BOSS「优香-恐怖」（第二关校园，三只霸王龙倒下之后登场）。
##
## 用户 2026-11-13：「然后最终 boss 优香-恐怖登场！」
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
## ── 外观的演进史（别走回头路）──
##   ① tint 近黑红 + 全身自发光 1.15 + 红光 12 + 辉光 0.62
##      → 整个人是一坨纯红剪影，头发/脸/制服全糊掉（`_final_phase/6_boss.png`）。
##   ② tint 提亮到 (0.60, 0.30, 0.32)、自发光降到 0.15
##      → 看得出身形和光环了，但仍然是"红剪纸"：整块颜色均匀，没有明暗。
##   ③ 现在：材质换成 `horror_skin` 着色器 —— 贴图只乘一个偏暗的冷灰红，
##      红色只出现在**掠射角**（边缘一圈红）和一点点呼吸自发光上。
##      恐怖感来自「暗处一张看得清的脸」，不是红色剪纸。
##
## ── 打法（三招，都能躲）──
##   · 冲击波：脚下蓄力 0.9 s → 一圈红环从 6 m 扩到 34 m（12 m/s）。
##             **踩在地上**才会被扫到，跳起来（>0.9 m）可以躲过。
##   · 砸击：  落点预警圈（半径 = 伤害半径，和 `boss_attacker.gd` 同一条铁律），
##             6.5 m / 1.25 s —— 按玩家跑速 6.8 m/s 算，从圈心往外跑得出去。
##   · 弹幕：  预判 0.6 s 后的位置，甩出 3 发（二阶段 5 发）红色光球。
##   血量 ≤ 50% 进二阶段：节奏加快、光球变多、红边更亮。
##   设置页「Boss 攻击」关掉后只挨打不还手（和霸王龙同一个开关）。
##
## ── 三个必须注意的坑 ──
## ① `Boss._physics_process()` 里有骨骼碰撞盒跟随（`_sync_bone_collisions()`），
##    子类覆盖时必须 `super._physics_process(delta)`，否则碰撞盒钉死在原地。
## ② `Boss._ready()` 会走 `BootGate.when_near()`（近距离才建模型）。
##    最终 BOSS 是"当场登场"，不能等玩家走近 —— 这里 `_boot()` 直接建。
## ③ 动画：GLB 自带 `AnimationPlayer`，idle 要设成循环；一旦播了 one-shot
##    （攻击/死亡），要自己接回 idle，否则会停在最后一帧。

signal phase_changed(phase: int)

const SKIN_SHADER := preload("res://shaders/horror_skin.gdshader")
## 砸击预警圈（半透明 + 亮边；见 `shaders/telegraph_disc.gdshader` 文件头）
const DISC_SHADER := preload("res://shaders/telegraph_disc.gdshader")
const DISC_ALPHA := 0.26

## 冲击波
const SHOCK_MIN_R := 6.0
const SHOCK_MAX_R := 34.0
const SHOCK_SPEED := 12.0
const SHOCK_BAND := 1.8
const SHOCK_DAMAGE := 30.0
## 跳起来多高算躲过。
## ⚠️ 玩家跳跃顶点只有 **1.26 m**（`player.gd`：JUMP 7.1 / GRAVITY），
##    第一版写了 1.5 —— 等于这个"可以跳过去"的门槛游戏里根本跳不到，
##    属于骗人的机制。改成 0.9：**掐准时机跳**（或站在台阶/矮墙上）能躲。
const SHOCK_SAFE_HEIGHT := 0.9
const SHOCK_WINDUP := 0.9

## 砸击。
## ⚠️ 半径 vs 蓄力时间必须"跑得出去"：玩家跑速 6.8 m/s
##    （`player.gd::SPEED_RUN`），第一版 9 m / 1.0 s 要 9 m/s —— 站着必吃，
##    等于没有闪避。6.5 m / 1.25 s 只需 5.2 m/s，从圈心往外跑能活着出去。
const SLAM_RADIUS := 6.5
const SLAM_WINDUP := 1.25
const SLAM_DAMAGE := 36.0
const SLAM_KNOCKBACK := 18.0
const SLAM_MAX_HEIGHT := 4.0
## 起手距离：再远就只放冲击波 / 弹幕
const SLAM_RANGE := 26.0

## 弹幕
const ORB_SPEED := 26.0
const ORB_DAMAGE := 12.0
const ORB_HIT_R := 1.8
const ORB_LIFE := 6.0
const ORB_LEAD := 0.6

## 出招节奏
const INTERVAL_1 := 5.5
const INTERVAL_2 := 3.8
const INTRO_GRACE := 2.5
const TURN_SPEED := 45.0
const TURN_SPEED_2 := 75.0

const SKILL_NAMES := ["shock", "slam", "barrage"]

var _ap: AnimationPlayer
var _skin_mats: Array[ShaderMaterial] = []
var _aura_light: OmniLight3D
var _rings: Array[Dictionary] = []
var _aura_built := false

var _player: Node3D
var _t_skill := 0.0
var _skill_i := 0
var _busy := false
var _phase := 1
var _last_skill := ""
var _counts := {"shock": 0, "slam": 0, "barrage": 0}
## 实际命中次数（探针按它判定，不靠墙钟 sleep）
var _hits := {"shock": 0, "slam": 0, "barrage": 0}
## 扩散中的冲击波：{node, r, hit}
var _waves: Array[Dictionary] = []
## 飞着的光球：{node, dir, t}
var _orbs: Array[Dictionary] = []
var _slam_marks: Array[Node3D] = []
var _pulse := 0.0


func _init() -> void:
	display_name = "优香-恐怖"
	model_path = "res://models/companions/Yuuka.glb"
	# 校园里的楼最高 53 m，它站在操场上要"抬头看"才有压迫感
	height = 16.0
	# 玩家武器约 120~240 DPS：20000 要打 85~165 s，太长；14000 约 60~115 s
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


func _ready() -> void:
	super._ready()
	# 见文件头 ②：不等 BootGate，立刻建模型 + 碰撞
	_boot()
	_apply_skin()
	_setup_anim()
	_build_aura()
	_t_skill = INTRO_GRACE
	print("[YuukaHorror] 登场：身高 %.1f m，血量 %.0f，材质 %d 块，动画 %s" % [
		height, max_health, _skin_mats.size(),
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
				sm.set_shader_parameter("albedo_tex", src.albedo_texture)
				sm.set_shader_parameter("use_texture", src.albedo_texture != null)
				# 眼睛/嘴是 alpha scissor 材质，丢了这个会变成方块
				sm.set_shader_parameter("use_alpha",
					src.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED)
			else:
				sm.set_shader_parameter("use_texture", false)
			m.set_surface_override_material(s, sm)
			_skin_mats.append(sm)


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
	if _dead or not is_instance_valid(self):
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

	# 三圈细红环（⚠️ 上一版半径 0.30~0.42 × 16 m = 5~7 m，
	# 在远处看就是一根横在头顶的红色长条 —— 这次按腰宽给）
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
		# TorusMesh 默认躺在 XZ 平面（环轴 = Y）—— 正好是横向绕腰的环
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
	if _dead or not _boss_attack_enabled():
		return
	_t_skill -= delta
	if _t_skill > 0.0 or _busy:
		return
	_t_skill = INTERVAL_2 if _phase >= 2 else INTERVAL_1
	_cast_skill()


func _boss_attack_enabled() -> bool:
	# 和 `boss_attacker.gd` 同一个设置项（Esc 菜单「Boss 攻击」）
	return bool(GameSettings.value("boss_attack"))


func _spin_rings(delta: float) -> void:
	for r in _rings:
		var node: Node3D = r["node"]
		if node == null or not is_instance_valid(node):
			continue
		node.rotation.y += float(r["spin"]) * delta
	# 呼吸：二阶段更急、更亮
	var t := float(Time.get_ticks_msec()) * 0.001
	_pulse = (0.5 + 0.5 * sin(t * (2.6 if _phase >= 2 else 1.5))) \
		* (0.85 if _phase >= 2 else 0.45)
	for m in _skin_mats:
		if is_instance_valid(m):
			m.set_shader_parameter("pulse", _pulse)
	if _aura_light != null and is_instance_valid(_aura_light):
		var base := 3.5 + 1.2 * sin(t * 1.4)
		_aura_light.light_energy = base + (2.5 if _phase >= 2 else 0.0)


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

## 三招轮着放（顺序固定：保证三种都会出现，不靠随机）
func _cast_skill() -> void:
	var p := _find_player()
	if p == null:
		return
	_busy = true
	var pc := p.global_position
	var pick := String(SKILL_NAMES[_skill_i % SKILL_NAMES.size()])
	# 玩家离得远 → 砸击够不着，这一轮换成冲击波
	if pick == "slam" and global_position.distance_to(pc) > SLAM_RANGE:
		pick = "shock"
	_skill_i += 1
	_last_skill = pick
	_counts[pick] += 1
	print("[YuukaHorror] 出招：%s（第 %d 轮，阶段 %d）" % [pick, _skill_i, _phase])
	match pick:
		"slam":
			await _skill_slam(pc)
		"barrage":
			await _skill_barrage(pc)
		_:
			await _skill_shockwave()
	_busy = false


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
	var tm := TorusMesh.new()
	tm.inner_radius = 0.985
	tm.outer_radius = 1.0
	tm.rings = 128
	tm.ring_segments = 6
	ring.mesh = tm
	ring.material_override = _additive(Color(1.0, 0.20, 0.10, 0.95))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = Vector3(0.0, 0.35, 0.0)
	ring.scale = Vector3(SHOCK_MIN_R, 2.0, SHOCK_MIN_R)
	add_child(ring)
	_waves.append({"node": ring, "r": SHOCK_MIN_R, "hit": false})
	Sfx.play("ui_close", -4.0)


## 每帧把冲击波往外推；环带扫到玩家当下就结算一次。
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
		node.scale = Vector3(r, 2.0, r)
		if p != null and not bool(w["hit"]):
			var flat := Vector2(p.global_position.x - global_position.x,
				p.global_position.z - global_position.z).length()
			# ⚠️ **扫掠判定**，不是"当前半径 ± 带宽"：
			#    低帧率时环一帧能跳 2~3 m（12 m/s ÷ 5 fps），
			#    只看当前半径会**直接跨过**玩家（带泼溅出图那轮实测漏判）。
			#    取 [上一帧半径, 这一帧半径] 这一段，玩家落在段内就算被扫到。
			if flat >= r0 - SHOCK_BAND and flat <= r + SHOCK_BAND:
				# 高度按 **BOSS 脚下的地面**算（冲击波是贴地扫的）：
				#   头顶 1 m 以上的跳跃 / 站上 20 m 的楼顶 → 都不该被扫到。
				var dy := p.global_position.y - global_position.y
				if dy >= -1.0 and dy <= SHOCK_SAFE_HEIGHT and p.has_method("take_damage"):
					w["hit"] = true
					_hits["shock"] += 1
					p.call("take_damage", SHOCK_DAMAGE, global_position, 10.0)
					print("[YuukaHorror] 冲击波命中（距离 %.1f m，高出 %.2f m）" % [flat, dy])
		if r >= SHOCK_MAX_R:
			node.queue_free()
			continue
		w["r"] = r
		keep.append(w)
	_waves = keep


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
	_hit_area(center, SLAM_RADIUS, SLAM_DAMAGE, SLAM_KNOCKBACK)
	_flash_mark(disc, 1.4, 0.30)
	_slam_marks.erase(disc)
	await get_tree().create_timer(0.45).timeout


func _skill_barrage(pc: Vector3) -> void:
	_play_once("Stand_Attack_Start")
	Sfx.play("fire_beam", -10.0)
	var n := 5 if _phase >= 2 else 3
	var p := _find_player()
	var vel := (p as CharacterBody3D).velocity if p is CharacterBody3D else Vector3.ZERO
	var aim := pc + Vector3(vel.x, 0.0, vel.z) * ORB_LEAD
	print("[YuukaHorror] 弹幕：%d 发，目标 %s（玩家 %s）" % [n, str(aim.snappedf(0.1)),
		str(pc.snappedf(0.1))])
	for i in n:
		if _dead or not is_instance_valid(self):
			return
		var side := Vector3(aim.z - global_position.z, 0.0,
			-(aim.x - global_position.x))
		side = side.normalized() if side.length_squared() > 0.01 else Vector3.RIGHT
		var off := (float(i) - float(n - 1) * 0.5) * 2.4
		_spawn_orb(aim + side * off)
		await get_tree().create_timer(0.16).timeout
	await get_tree().create_timer(0.35).timeout


func _spawn_orb(target: Vector3) -> void:
	var orb := MeshInstance3D.new()
	orb.name = "HorrorOrb"
	var sm := SphereMesh.new()
	sm.radius = 1.1
	sm.height = 2.2
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
		+ facing() * height * 0.18
	add_child(orb)
	orb.global_position = from
	var dir := target - from
	dir = dir.normalized() if dir.length_squared() > 0.01 else Vector3.FORWARD
	_orbs.append({"node": orb, "dir": dir, "t": 0.0})


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
		if t > ORB_LIFE:
			node.queue_free()
			continue
		var prev := node.global_position
		var next := prev + (o["dir"] as Vector3) * ORB_SPEED * delta
		node.global_position = next
		if p != null and p.has_method("take_damage"):
			# ⚠️ 同样是**扫掠判定**：低帧率下一帧飞 2~3 m，
			#    只在端点比距离会从玩家边上"穿过去"（带泼溅那轮实测漏判）。
			var chest := p.global_position + Vector3.UP * 0.9
			var closest := Geometry3D.get_closest_point_to_segment(chest, prev, next)
			if closest.distance_to(chest) <= ORB_HIT_R:
				_hits["barrage"] += 1
				p.call("take_damage", ORB_DAMAGE, closest, 6.0)
				print("[YuukaHorror] 光球命中")
				node.queue_free()
				continue
		o["t"] = t
		keep.append(o)
	_orbs = keep


# ────────────────────────── 范围伤害 ──────────────────────────

## ⚠️ 铁律（`boss_attacker.gd` 文件头）：预警圈半径**就是**伤害半径。
func _hit_area(center: Vector3, radius: float, dmg: float, knock: float) -> void:
	var p := _find_player()
	if p == null or not p.has_method("take_damage"):
		return
	var at := p.global_position
	var flat := Vector2(at.x - center.x, at.z - center.z).length()
	if flat <= radius and absf(at.y - center.y) <= SLAM_MAX_HEIGHT:
		_hits["slam"] += 1
		p.call("take_damage", dmg, center, knock)
		print("[YuukaHorror] 砸击命中（%.1f m / %.0f m）" % [flat, radius])


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


func _flash_mark(mark: Node3D, grow: float, time: float) -> void:
	if not is_instance_valid(mark):
		return
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mark, "scale", mark.scale * grow, time)
	var mi := mark as MeshInstance3D
	if mi != null:
		var sh := mi.material_override as ShaderMaterial
		if sh != null:
			# 预警圈用的是 `telegraph_disc` 着色器 → 淡出它的 alpha
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


# ────────────────────────── 受击 / 死亡 ──────────────────────────

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


## 二阶段：血量 ≤ 50%。
func take_damage(amount: float, hit_pos := Vector3.ZERO, hit_dir := Vector3.ZERO) -> void:
	super.take_damage(amount, hit_pos, hit_dir)
	if not _dead and _phase == 1 and health <= max_health * 0.5:
		_enter_phase_2()


func _enter_phase_2() -> void:
	_phase = 2
	_t_skill = 1.2
	_play_once("Vital_Panic")
	phase_changed.emit(2)
	print("[YuukaHorror] 进入二阶段（血量 %.0f / %.0f）" % [health, max_health])


## 死亡自己接管：走 GLB 的 `Vital_Dying_Ing → Vital_Death`，
## **不用**基类那条"整只模型绕 X 轴向前扑倒"（会和动画打架，变成双重摔倒）。
func _die(by_damage: float) -> void:
	if _dead:
		return
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


## 探针 / 自检用：当前状态 + 各招放出次数
func status() -> Dictionary:
	return {
		"health": health,
		"max_health": max_health,
		"phase": _phase,
		"dead": _dead,
		"last_skill": _last_skill,
		"counts": _counts.duplicate(),
		"has_anim": _ap != null,
		"anim": _ap.current_animation if _ap != null else "",
		"skin_mats": _skin_mats.size(),
		"waves": _waves.size(),
		"orbs": _orbs.size(),
		"slam_marks": _slam_marks.size(),
		"busy": _busy,
		"hits": _hits.duplicate(),
	}


## 探针用：清掉场上所有特效残骸、把命中计数归零（招式之间互不干扰）
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
	_free_marks()
	for k in _hits.keys():
		_hits[k] = 0


## 探针用：无视节奏立刻放某一招（不等冷却、不看设置开关）
func debug_cast(kind: String) -> void:
	var p := _find_player()
	if p == null:
		return
	_busy = true
	await _debug_cast_inner(kind, p)
	_busy = false


func _debug_cast_inner(kind: String, p: Node3D) -> void:
	match kind:
		"slam":
			await _skill_slam(p.global_position)
		"barrage":
			await _skill_barrage(p.global_position)
		_:
			await _skill_shockwave()
