class_name CompanionGun
extends Node3D
## 同伴的枪：**自己**选目标（靶子 / Boss）开火帮玩家打，不需要玩家下指令。
##
## 三条硬约束（都是踩过或算过的）：
##   1. **不打自己人。** 射线 mask 去掉朋友层（`Companion.LAYER` = 2），
##      再把玩家 RID 加进 `exclude` —— 玩家在层 1，光靠 mask 屏蔽不掉。
##   2. **不隔墙打。** 扣血以**射线真正命中的那个目标**为准，而不是「预测命中」：
##      预测和开火之间隔了一帧、目标还会动，靠预测就会出现「隔着墙掉血」。
##   3. **不为开火而乱转身。** 只有目标已经在同伴**正前方 ±25°** 内才开火；
##      否则同伴会为了瞄准而东倒西歪，破坏「一队人朝同一个方向」的观感
##      （`companion.gd` 的朝向逻辑正是按这个设计的）。
##
## 视觉上刻意**不用**玩家那种「飞行光弹」，而是打一条瞬间出现、0.08 s 淡出的枪线：
## 多名同伴同时开火时，飞行光弹会把玩家自己的子弹淹掉，也分不清是谁打的。
##
## 技能（用户 2026-11-14：「全部队友加强攻速，加技能，攻击力不变」）：
##   每人一个**大冷却**技能，伤害独立于普通射击，攻击力（55/发）保持不变。
##   小桃=三连榴弹、小绿=狙击、柚子=霰弹扫射、凯伊=轨道炮。
##   技能和普通射击共用同一套「射线命中才算数」的规则（文件头第 2 条）。

signal fired(target: Node3D)
signal skill_cast(kind: String)

## 技能种类。场景里按人配（`game.tscn` / `next_level.gd` 的 PARTY）。
enum Skill { NONE, GRENADE, SNIPE, SHRED, RAIL }

const SKILL_NAMES := ["none", "grenade", "snipe", "shred", "rail"]
## 小桃：三连榴弹（落点小范围）
const GRENADE_COUNT := 3
const GRENADE_DAMAGE := 90.0
const GRENADE_RADIUS := 3.8
const GRENADE_RANGE := 46.0
## 小绿：单发狙击
const SNIPE_DAMAGE := 240.0
const SNIPE_RANGE := 70.0
## 柚子：霰弹扫射（近距离一梭子）
const SHRED_PELLETS := 12
const SHRED_DAMAGE := 20.0
const SHRED_RANGE := 26.0
const SHRED_SPREAD_DEG := 9.0
## 凯伊：轨道炮（穿一条线）
const RAIL_DAMAGE := 220.0
const RAIL_RANGE := 80.0
const RAIL_WIDTH := 1.5
## 轨道炮蓄力时长（秒）：聚能球长大 → 再打出光柱
const RAIL_CHARGE := 0.28
## 目标缓存多久重扫一次（秒）：BOSS 会中途召分身/飞猪，只扫一次就看不见新目标
const TARGET_REFRESH := 2.0

@export var enabled := true
## 两次射击的间隔（秒）
## 用户 2026-11-14：「这也太恐怖了，加强主角团」——
## 原来是 1.8 s 一发、12 伤害（≈6.7 DPS），对着 14000 血的最终 BOSS
## 等于挠痒。先改成 0.55 s 一发、55 伤害（≈100 DPS/人）；
## 同日再要求「全部队友加强攻速，攻击力不变」→ 0.30 s 一发（≈183 DPS/人）。
@export var attack_interval := 0.30
## 进场后隔多久开始射击（秒）
@export var attack_start_delay := 0.6
@export var attack_range := 48.0
@export var attack_damage := 55.0
## 目标必须在这个半角内才会开火（度），见文件头第 3 条
@export_range(1.0, 90.0, 1.0) var aim_half_angle_degrees := 25.0
## 枪口：同伴节点上方多高、正前方多远。
## 模型是运行时加载的、也没有枪口骨可用（和玩家不同），所以只能用固定偏移。
@export var muzzle_height := 1.15
@export var muzzle_forward := 0.35
@export var tracer_color := Color(0.55, 0.85, 1.0)
@export var tracer_width := 0.012
## 技能（见文件头）。NONE = 只会普通射击。
@export var skill: Skill = Skill.NONE
## 技能冷却（秒）
@export var skill_interval := 10.0
## 进场后隔多久放第一个技能（秒）
@export var skill_first_delay := 4.0

var _cooldown := 0.0
var _skill_t := 0.0
var _refresh_t := 0.0
var _companion: Companion
var _targets: Array[Node3D] = []
var _fx_root: Node3D
var _shots := 0
var _skills_cast := 0
var _last_skill := ""
## 设置页里的「同伴开火」开关。与 `enabled` 分开存，理由见 `_is_active()`
var _settings_enabled := true


func _ready() -> void:
	_companion = get_parent() as Companion
	if _companion == null:
		push_warning("[CompanionGun] 父节点不是 Companion，这把枪不会工作")
		return
	_cooldown = attack_start_delay
	# 四个人错开半秒，别让四个技能同一帧一起炸
	_skill_t = skill_first_delay + randf() * 0.6
	# 设置（Esc 菜单）：同伴到底开不开火，由玩家说了算
	GameSettings.listen(_on_setting_changed)
	_apply_settings()


## 特效挂到**场景根**下（与同伴平级、自身没有变换）：
## 挂在同伴下面的话，光柱会跟着同伴的旋转/缩放一起变形。
##
## ⚠️ 特意**延迟到第一次开火时**才建：在 `_ready()` 里往父节点 `add_child()` 会撞上
##    「Parent node is busy setting up children」—— 那一刻父节点还在装自己的孩子
##    （当年 7 名同伴一次性报 7 条 ERROR）。放到 `_process` 里建就没这个问题。
func _ensure_fx_root() -> void:
	if _fx_root != null:
		return
	var host: Node = _companion.get_parent()
	if host is Node3D and host.is_inside_tree():
		_fx_root = Node3D.new()
		_fx_root.name = "CompanionGunFx_%s" % _companion.name
		host.add_child(_fx_root)
	else:
		_fx_root = _companion


func _process(delta: float) -> void:
	if not _is_active() or _companion == null:
		return
	_ensure_fx_root()
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_collect_targets()
		_refresh_t = TARGET_REFRESH
	_skill_t -= delta
	if _skill_t <= 0.0:
		var st := _pick_skill_target(_skill_range())
		if st != null:
			_cast_skill(st)
			_skill_t = skill_interval
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	var target := _pick_target()
	if target == null:
		return
	_fire(target)


## 目标 = 可击毁靶子（`targets` 组）+ 所有 Boss（`bosses` 组）。
## 每 2 s 重扫一次：BOSS 会在战斗中召分身 / 飞猪，只扫一次的话新目标永远进不来。
## 「死亡」只是内部标记 + 重生，节点本身一直在（见 `Target._die()` / `Boss._die()`），
## 所以阵亡的目标仍然靠 `_is_dead()` 过滤，不需要在重扫时剔除。
func _collect_targets() -> void:
	_targets.clear()
	for n in get_tree().get_nodes_in_group("targets"):
		if n is Node3D:
			_targets.append(n as Node3D)
	for n in get_tree().get_nodes_in_group("bosses"):
		if n is Node3D:
			_targets.append(n as Node3D)


func _pick_target() -> Node3D:
	var best: Node3D = null
	var best_dist := INF
	var eye := muzzle_position()
	var face := _face_dir()
	var limit := cos(deg_to_rad(aim_half_angle_degrees))
	for t in _targets:
		if not is_instance_valid(t) or _is_dead(t):
			continue
		var to_target := _aim_point(t) - eye
		var dist := to_target.length()
		if dist > attack_range or dist < 1.0:
			continue
		var flat := Vector3(to_target.x, 0.0, to_target.z)
		if flat.length_squared() < 0.0001:
			continue
		if face.dot(flat.normalized()) < limit:
			continue
		if not _has_line_of_sight(t):
			continue
		if dist < best_dist:
			best_dist = dist
			best = t
	return best


## 瞄准点：沿身高试几个高度，**取第一个射线真能打中的**。
##
## 为什么不能固定一个高度：优香-恐怖 16 m 高、碰撞是「每根骨一个盒子」（BOX_PARTS），
## 0.375 身高（6 m）正好落在两条大腿之间 —— 从脚下往上打的射线直接从裆下穿过去，
## 榴弹 / 轨道炮实测全打空（探针日志 `hit=空`）。换个射手站位又可能刚好擦到腿盒，
## 结果就变成「四个人有时打中有时不中」。
##
## 靶子没有 `height` 属性，仍然用原来的 +0.6 m（和以前完全一致）。
const AIM_FRACTIONS := [0.7, 0.55, 0.4, 0.85]

func _aim_point(t: Node3D) -> Vector3:
	var h: Variant = t.get("height")
	if h == null:
		return t.global_position + Vector3.UP * 0.6
	var top := clampf(float(h), 1.2, 20.0)
	var from := muzzle_position()
	for f in AIM_FRACTIONS:
		var p := t.global_position + Vector3.UP * (top * float(f))
		var hit := _ray(from, p)
		if not hit.is_empty() and _is_same_target(hit.get("collider"), t):
			return p
	return t.global_position + Vector3.UP * (top * 0.55)


## 同伴的脸朝向。模型本体朝 +Z（见 companion.gd 文件头），所以 +Z 就是脸。
func _face_dir() -> Vector3:
	if _companion == null:
		return Vector3.FORWARD
	return Vector3(sin(_companion.rotation.y), 0.0, cos(_companion.rotation.y))


func muzzle_position() -> Vector3:
	if _companion == null:
		return global_position
	return _companion.global_position \
		+ Vector3.UP * muzzle_height + _face_dir() * muzzle_forward


## 已经死掉（倒地等重生）的目标不再挨打。`_dead` 在 Target 和 Boss 上都有。
func _is_dead(t: Node3D) -> bool:
	var dead: Variant = t.get("_dead")
	return dead != null and bool(dead)


func _excludes() -> Array[RID]:
	var out: Array[RID] = []
	if _companion != null:
		out.append(_companion.get_rid())
	var player := _find_player()
	if player != null:
		out.append(player.get_rid())
	return out


func _find_player() -> Player:
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		return players[0] as Player
	return null


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	# 朋友层整层屏蔽：子弹穿透同伴，同伴之间也不会互相挡枪（与 weapon.gd 同一套理由）
	q.collision_mask = 0xFFFFFFFF & ~Companion.LAYER
	q.exclude = _excludes()
	return get_world_3d().direct_space_state.intersect_ray(q)


func _has_line_of_sight(t: Node3D) -> bool:
	var hit := _ray(muzzle_position(), _aim_point(t))
	if hit.is_empty():
		return false
	return _is_same_target(hit.get("collider"), t)


func _is_same_target(collider: Variant, t: Node3D) -> bool:
	if collider == t:
		return true
	return collider is Node and (collider as Node).get_parent() == t


## 开火：**以射线结果为准**决定是否扣血（见文件头第 2 条）
func _fire(target: Node3D) -> void:
	_cooldown = attack_interval
	var from := muzzle_position()
	var to := _aim_point(target)
	var hit := _ray(from, to)
	var impact := to
	var victim: Node3D = null
	if not hit.is_empty():
		impact = hit.get("position", to)
		if _is_same_target(hit.get("collider"), target):
			victim = target
	if victim != null and victim.has_method("take_damage"):
		victim.take_damage(attack_damage, impact, (from - impact).normalized())
	_spawn_tracer(from, impact)
	# 枪口焰 + 命中火花：不加的话只有一条细线，连射看着像「空气在掉血」
	_muzzle_flash(tracer_color, 0.22 + tracer_width * 6.0)
	_impact_spark(impact, tracer_color, 0.16)
	_play_attack()
	_shots += 1
	fired.emit(target)


# ────────────────────────── 技能 ──────────────────────────

func skill_name() -> String:
	var i := int(skill)
	return String(SKILL_NAMES[i]) if i >= 0 and i < SKILL_NAMES.size() else "none"


func _skill_range() -> float:
	match skill:
		Skill.GRENADE:
			return GRENADE_RANGE
		Skill.SNIPE:
			return SNIPE_RANGE
		Skill.SHRED:
			return SHRED_RANGE
		Skill.RAIL:
			return RAIL_RANGE
	return 0.0


## 技能选目标：比普通射击宽 —— 不要求「目标在正前方 ±25° 内」，
## 只要在技能射程内、有视线就打（技能本来就该是队友主动放的大招）。
func _pick_skill_target(max_dist: float) -> Node3D:
	if skill == Skill.NONE:
		return null
	var best: Node3D = null
	var best_dist := INF
	var eye := muzzle_position()
	for t in _targets:
		if not is_instance_valid(t) or _is_dead(t):
			continue
		var dist := eye.distance_to(_aim_point(t))
		if dist > max_dist or dist < 1.0:
			continue
		if not _has_line_of_sight(t):
			continue
		if dist < best_dist:
			best_dist = dist
			best = t
	return best


func _cast_skill(target: Node3D) -> void:
	if _companion == null or skill == Skill.NONE:
		return
	_ensure_fx_root()
	# 技能里榴弹 / 霰弹 / 轨道炮都要遍历 `_targets`；枪被关掉时 `_process` 不跑，
	# 不能指望每 2 s 那次重扫，所以放技能时自己再收一次。
	_collect_targets()
	var kind := skill_name()
	var from := muzzle_position()
	match skill:
		Skill.GRENADE:
			_skill_grenade(from, target)
		Skill.SNIPE:
			_skill_snipe(from, target)
		Skill.SHRED:
			_skill_shred(from, target)
		Skill.RAIL:
			_skill_rail(from, target)
		_:
			return
	_play_attack()
	_skills_cast += 1
	_last_skill = kind
	skill_cast.emit(kind)


## 开火 / 放技能时让同伴**真的抬枪打**（用户：「怎么没有播放攻击动画」）。
## 走 `AnimDriver.request_fire()`：它是 `Normal_Attack_Ing` 叠上半身的那一套，
## 而且「一次性动作播到一半不打断」—— 0.3 s 一发的连射不会把动作反复重启，
## 表现约为每秒一次完整的开火收招，正好配连发。
func _play_attack() -> void:
	if _companion == null:
		return
	var a: Variant = _companion.anim
	if a != null and is_instance_valid(a) and (a as Node).has_method("request_fire"):
		a.call("request_fire")


## 小桃：往目标脚下抛三颗榴弹，落地小范围爆炸
func _skill_grenade(from: Vector3, target: Node3D) -> void:
	var base := target.global_position + Vector3.UP * 0.4
	var col := Color(1.0, 0.7, 0.35)
	_muzzle_flash(col, 0.32)
	Vfx.flash_light(_fx_root, from, col, 3.0, 0.18, 8.0)
	for i in GRENADE_COUNT:
		# 散布压到 0.6 倍半径：再大就有落点到了爆炸圈边缘、三颗里有一颗白扔
		var r := GRENADE_RADIUS * 0.6
		var off := Vector3(randf_range(-r, r), 0.0, randf_range(-r, r))
		_throw_grenade(from, base + off, 0.55 + 0.08 * float(i))


func _throw_grenade(from: Vector3, land: Vector3, flight: float) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.17
	sm.height = 0.34
	mi.mesh = sm
	mi.material_override = _glow_mat(Color(1.0, 0.62, 0.25))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx_root.add_child(mi)
	mi.top_level = true
	mi.global_position = from
	# 拖尾：不给榴弹加尾迹的话，远看就是三个不动的橙点
	_attach_trail(mi, Color(1.0, 0.6, 0.25))
	var arc := maxf(2.0, from.distance_to(land) * 0.22)
	var tw := mi.create_tween()
	tw.tween_method(func(k: float) -> void:
		if is_instance_valid(mi):
			var p := from.lerp(land, k)
			p.y += sin(k * PI) * arc
			mi.global_position = p,
		0.0, 1.0, flight)
	tw.tween_callback(func() -> void:
		if is_instance_valid(mi):
			mi.queue_free()
		_explode(land, GRENADE_RADIUS, GRENADE_DAMAGE, Color(1.0, 0.62, 0.25), 1.15))


## 爆炸结算：按**水平距离 + 竖直容差**判定（和 BOSS 的冲击波同一套思路）。
## 只按 3D 球心算的话，10 m 高的目标身上会「炸脚下反而够不着」。
func _explode(center: Vector3, radius: float, dmg: float, col: Color, scale_ := 1.0) -> void:
	if _fx_root == null or not is_instance_valid(_fx_root):
		return
	var dist := 0.0
	if _companion != null:
		dist = _companion.global_position.distance_to(center)
	Vfx.impact(_fx_root, center, col, scale_, dist)
	for t in _targets:
		if not is_instance_valid(t) or _is_dead(t):
			continue
		# 按**脚底**结算，不按躯干中心：优香 16 m 高，躯干在 9~14 m 上，
		# 拿躯干算竖直距离的话一颗贴脚炸开的榴弹反而不算命中。
		var base := t.global_position
		var flat := Vector2(base.x - center.x, base.z - center.z).length()
		if flat > radius + 0.6 or absf(base.y - center.y) > 2.5:
			continue
		# 这里**不加视线射线**：爆炸中心就在目标脚边（半径 3.8 m），
		# 而从地面往躯干打的射线会从两腿之间穿过去、或者一出发就埋进地皮里
		# （优香 16 m 高，实测 `hit=空`，三颗榴弹全白扔）。这个距离上不存在「隔墙」。
		_damage(t, dmg, _aim_point(t))


## 小绿：单发狙击，命中处一团绿色闪光
func _skill_snipe(from: Vector3, target: Node3D) -> void:
	var aim := _aim_point(target)
	var hit := _ray(from, aim)
	var at := aim
	if not hit.is_empty():
		at = hit.get("position", aim)
	var col := Color(0.45, 1.0, 0.78)
	_muzzle_flash(col, 0.3)
	_beam(from, at, 0.055, col, 0.22, 3.4)
	Vfx.flash_light(_fx_root, at, col, 5.0, 0.25, 12.0)
	Vfx.burst(_fx_root, at, col, 18, 1.0, 10.0, 0.4, -4.0)
	Vfx.ring(_fx_root, at, Color(col.r, col.g, col.b, 0.85), 3.2, 0.28, false)
	if not hit.is_empty() and _is_same_target(hit.get("collider"), target):
		_damage(target, SNIPE_DAMAGE, at)
	Vfx.shake(0.3, 0.16)


## 柚子：近距离霰弹扫射，一梭子 12 发
func _skill_shred(from: Vector3, target: Node3D) -> void:
	var base := (_aim_point(target) - from).normalized()
	var total := 0.0
	_muzzle_flash(Color(1.0, 0.82, 0.45), 0.3)
	for i in SHRED_PELLETS:
		var dir := _spread_dir(base, SHRED_SPREAD_DEG)
		var to := from + dir * SHRED_RANGE
		var hit := _ray(from, to)
		var at := to
		var victim: Node3D = null
		if not hit.is_empty():
			at = hit.get("position", to)
			victim = _victim_of(hit.get("collider"))
		var col := Color(1.0, 0.82, 0.45)
		_beam(from, at, 0.012, col, 0.09, 2.0)
		if victim != null and not _is_dead(victim):
			_damage(victim, SHRED_DAMAGE, at)
			total += SHRED_DAMAGE
	Vfx.flash_light(_fx_root, from, Color(1.0, 0.82, 0.45), 4.0, 0.22, 10.0)
	if total > 0.0:
		Vfx.burst(_fx_root, _aim_point(target), Color(1.0, 0.82, 0.45), 16, 1.0,
			9.0, 0.35, -4.0)
	Vfx.shake(0.4, 0.2)


## 凯伊：轨道炮。先蓄力 0.28 s（聚能球 + 收束环 + 淡紫瞄准线），再打一条三层光柱。
## 用户 2026-11-14：「加队友特效，特别是凯伊」—— 她这条是队里唯一的「重炮」，
## 做成有蓄力、有电弧、有全屏微闪才配得上。
func _skill_rail(from: Vector3, target: Node3D) -> void:
	var aim := _aim_point(target)
	var col := Color(0.72, 0.4, 1.0)
	var orb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	orb.mesh = sm
	var mat := _glow_mat(col)
	orb.material_override = mat
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx_root.add_child(orb)
	orb.top_level = true
	orb.global_position = from
	orb.scale = Vector3.ONE * 0.2
	var tw := orb.create_tween()
	tw.set_parallel(true)
	tw.tween_property(orb, "scale", Vector3.ONE * 1.7, RAIL_CHARGE) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(mat, "emission_energy_multiplier", 7.0, RAIL_CHARGE)
	tw.chain().tween_callback(func() -> void:
		if is_instance_valid(orb):
			orb.queue_free()
		_rail_fire(from, aim))
	# 蓄力期的瞄准线（打出去之前先让玩家看见她要打哪）
	var dir := (aim - from).normalized()
	_beam(from, aim + dir * 12.0, 0.012, Color(0.7, 0.5, 1.0, 0.55), RAIL_CHARGE, 1.2)
	Vfx.ring(_fx_root, from, Color(0.72, 0.4, 1.0, 0.9), 1.2, RAIL_CHARGE, false)
	Vfx.flash_light(_fx_root, from, col, 3.0, RAIL_CHARGE, 8.0)


## 轨道炮本体：三层光柱 + 沿束电弧 + 枪口冲击环 + 终点爆点 + 全屏微紫闪
func _rail_fire(from: Vector3, aim: Vector3) -> void:
	if _fx_root == null or not is_instance_valid(_fx_root):
		return
	var dir := (aim - from).normalized()
	var end := from + dir * RAIL_RANGE
	# 光束先撞墙就截断在墙面上
	var wh := _ray(from, end)
	if not wh.is_empty() and _victim_of(wh.get("collider")) == null:
		end = wh.get("position", end)
	var victims: Array[Node3D] = []
	for t in _targets:
		if not is_instance_valid(t) or _is_dead(t):
			continue
		var p := _aim_point(t)
		if _point_seg_dist(p, from, end) > RAIL_WIDTH + 0.8:
			continue
		var hit := _ray(from, p)
		if hit.is_empty() or not _is_same_target(hit.get("collider"), t):
			continue
		victims.append(t)
	var col := Color(0.72, 0.4, 1.0)
	for t in victims:
		_damage(t, RAIL_DAMAGE, _aim_point(t))
	# 外辉 → 主束 → 白芯
	_beam(from, end, 0.42, Color(0.5, 0.18, 1.0, 0.5), 0.5, 2.2)
	_beam(from, end, 0.15, col, 0.38, 4.4)
	_beam(from, end, 0.045, Color(1.0, 0.95, 1.0), 0.22, 7.0)
	# 沿光束随机几簇小电弧
	for i in 7:
		var t := randf_range(0.08, 0.96)
		var p := from.lerp(end, t)
		var j := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
		if j.length() < 0.01:
			j = Vector3.UP
		j = j.normalized() * randf_range(0.7, 1.8)
		_beam(p, p + j, 0.028, Color(0.85, 0.7, 1.0), 0.14, 4.0)
	# 枪口 / 终点
	Vfx.ring(_fx_root, from, Color(0.72, 0.4, 1.0, 0.95), 3.0, 0.32, false)
	Vfx.burst(_fx_root, from, col, 20, 1.2, 12.0, 0.4, -3.0)
	Vfx.flash_light(_fx_root, from, col, 8.0, 0.35, 24.0)
	var hit_at: Vector3 = aim if victims.is_empty() else _aim_point(victims[0])
	Vfx.burst(_fx_root, hit_at, col, 34, 1.6, 16.0, 0.55, -4.0)
	Vfx.ring(_fx_root, hit_at, Color(0.8, 0.6, 1.0, 0.9), 7.0, 0.4, false)
	Vfx.flash_light(_fx_root, hit_at, col, 10.0, 0.35, 30.0)
	Vfx.flash(Color(0.72, 0.5, 1.0), 0.12, 0.25)
	Vfx.shake(0.7, 0.32)


func _spread_dir(base: Vector3, deg: float) -> Vector3:
	var right := base.cross(Vector3.UP)
	if right.length() < 0.01:
		right = Vector3.RIGHT
	right = right.normalized()
	var yaw := deg_to_rad(randf_range(-deg, deg))
	var pitch := deg_to_rad(randf_range(-deg, deg) * 0.55)
	return base.rotated(Vector3.UP, yaw).rotated(right, pitch).normalized()


## 点到线段的距离
func _point_seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.0001:
		return p.distance_to(a)
	var k := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * k)


## 射线打到的碰撞体属于哪个可打目标（Boss 的子碰撞体要往上找一层）
func _victim_of(collider: Variant) -> Node3D:
	if not (collider is Node):
		return null
	var n := collider as Node
	for t in _targets:
		if t == n or t == n.get_parent():
			return t
	return null


func _damage(t: Node3D, amount: float, at: Vector3) -> void:
	if t.has_method("take_damage"):
		t.take_damage(amount, at, (muzzle_position() - at).normalized())


## 一条瞬间出现、0.08 s 淡出的枪线（为什么不用飞行光弹见文件头）
func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	_beam(from, to, tracer_width, tracer_color, 0.08, 1.8)


## 一根加色发光的「枪线 / 光束」。技能和普通射击共用（宽度 / 颜色 / 停留时间可调）。
func _beam(from: Vector3, to: Vector3, width: float, col: Color, life: float,
		energy := 1.8) -> void:
	var total := from.distance_to(to)
	if total < 0.05 or _fx_root == null:
		return
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, width, 1.0)
	mi.mesh = box
	var mat := _glow_mat(col)
	mat.emission_energy_multiplier = energy
	mi.material_override = mat
	_fx_root.add_child(mi)
	mi.top_level = true

	# 局部 +Z 对到射线方向，于是 scale.z 就是枪线长度（盒子 z 边长定义为 1.0）
	var dir := (to - from).normalized()
	var ref := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(dir)
	if x.length() < 0.001:
		x = Vector3.RIGHT
	x = x.normalized()
	var y := dir.cross(x).normalized()
	mi.basis = Basis(x, y, dir)
	mi.scale = Vector3(1.0, 1.0, total)
	mi.global_position = from + dir * (total * 0.5)

	var tw := mi.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, life)
	tw.tween_callback(mi.queue_free)


## 加色发光的无光照材质（枪线 / 榴弹都用它）
func _glow_mat(col: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 1.8
	return mat


## 一张朝向相机的加色光斑（枪口焰 / 命中火花共用）。
## 用四边形 + 软点贴图而不是 GPUParticles3D：连射时每秒要出十几个，
## 建粒子系统太贵，一个 quad + 0.1 s 缩放淡出就够显眼。
func _glow_quad(pos: Vector3, col: Color, size: float, life: float, grow := 1.9) -> void:
	if _fx_root == null or not is_instance_valid(_fx_root):
		return
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	mi.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = Vfx.soft_dot()
	mat.albedo_color = col
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx_root.add_child(mi)
	mi.top_level = true
	mi.global_position = pos
	mi.scale = Vector3.ONE * maxf(size, 0.02)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size * grow, life)
	tw.tween_property(mat, "albedo_color:a", 0.0, life)
	tw.chain().tween_callback(mi.queue_free)


func _muzzle_flash(col: Color, size: float) -> void:
	_glow_quad(muzzle_position(), col, size, 0.07)


func _impact_spark(at: Vector3, col: Color, size: float) -> void:
	_glow_quad(at, col, size, 0.1, 2.2)


## 榴弹拖尾：一小束留在身后的加色软点（`local_coords = false` → 点停在原地）
func _attach_trail(host: Node3D, col: Color) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 14
	p.lifetime = 0.3
	p.local_coords = false
	p.emitting = true
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.05
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.5
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.09
	pm.scale_max = 0.2
	pm.color = col
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 0.9))
	ramp.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	pm.color_ramp = gt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = Vfx.soft_dot()
	quad.material = mat
	p.draw_pass_1 = quad
	host.add_child(p)
	return p


## 开过几枪 —— 自检用
func shot_count() -> int:
	return _shots


## 放过几次技能 —— 自检用
func skill_count() -> int:
	return _skills_cast


func last_skill() -> String:
	return _last_skill


## 自检用：无视冷却 / 距离 / 朝向，直接朝目标放一次技能。
## 返回技能名（放不出来时返回空串）。
func debug_force_skill(target: Node3D = null) -> String:
	if _companion == null or skill == Skill.NONE:
		return ""
	_ensure_fx_root()
	var t := target
	if t == null or not is_instance_valid(t):
		t = _pick_skill_target(_skill_range())
	if t == null:
		return ""
	_cast_skill(t)
	_skill_t = skill_interval
	return skill_name()


# --- 设置（Esc 菜单 / scripts/game_settings.gd）---

## 这把枪到底开不开火：`enabled`（场景与自检用的开关）**且**设置页没关掉。
## ⚠️ 两个来源分开存是故意的：自检会把 `enabled = false` 来测「停火」，
##    那条路径不该被设置页的状态影响，反过来也一样。
func _is_active() -> bool:
	return enabled and _settings_enabled


func _apply_settings() -> void:
	_settings_enabled = bool(GameSettings.value("companion_fire"))


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == "companion_fire":
		_apply_settings()
