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
## 7 名同伴同时开火时，飞行光弹会把玩家自己的子弹淹掉，也分不清是谁打的。

signal fired(target: Node3D)

@export var enabled := true
## 两次射击的间隔（秒）
@export var attack_interval := 1.8
## 进场后隔多久开始射击（秒）
@export var attack_start_delay := 1.2
@export var attack_range := 24.0
@export var attack_damage := 12.0
## 目标必须在这个半角内才会开火（度），见文件头第 3 条
@export_range(1.0, 90.0, 1.0) var aim_half_angle_degrees := 25.0
## 枪口：同伴节点上方多高、正前方多远。
## 模型是运行时加载的、也没有枪口骨可用（和玩家不同），所以只能用固定偏移。
@export var muzzle_height := 1.15
@export var muzzle_forward := 0.35
@export var tracer_color := Color(0.55, 0.85, 1.0)
@export var tracer_width := 0.012

var _cooldown := 0.0
var _companion: Companion
var _targets: Array[Node3D] = []
var _targets_collected := false
var _fx_root: Node3D
var _shots := 0


func _ready() -> void:
	_companion = get_parent() as Companion
	if _companion == null:
		push_warning("[CompanionGun] 父节点不是 Companion，这把枪不会工作")
		return
	_cooldown = attack_start_delay


## 特效挂到**场景根**下（与同伴平级、自身没有变换）：
## 挂在同伴下面的话，光柱会跟着同伴的旋转/缩放一起变形。
##
## ⚠️ 特意**延迟到第一次开火时**才建：在 `_ready()` 里往父节点 `add_child()` 会撞上
##    「Parent node is busy setting up children」—— 那一刻父节点还在装自己的孩子
##    （7 名同伴一次性报 7 条 ERROR）。放到 `_process` 里建就没这个问题。
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
	if not enabled or _companion == null:
		return
	_ensure_fx_root()
	if not _targets_collected:
		_collect_targets()
		_targets_collected = true
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	var target := _pick_target()
	if target == null:
		return
	_fire(target)


## 目标 = 可击毁靶子（`targets` 组）+ 所有 Boss（`bosses` 组）。
## 只收一次：这些节点不会在运行中被重建 —— 「死亡」只是内部标记 + 重生，
## 节点本身一直在（见 `Target._die()` / `Boss._die()`），所以缓存是安全的。
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


## 瞄准点：目标中心稍抬高一点（靶子和 Boss 的碰撞盒中心大致在身高一半）
func _aim_point(t: Node3D) -> Vector3:
	return t.global_position + Vector3.UP * 0.6


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
	_shots += 1
	fired.emit(target)


## 一条瞬间出现、0.08 s 淡出的枪线（为什么不用飞行光弹见文件头）
func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var total := from.distance_to(to)
	if total < 0.05 or _fx_root == null:
		return
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(tracer_width, tracer_width, 1.0)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = tracer_color
	mat.emission_enabled = true
	mat.emission = tracer_color
	mat.emission_energy_multiplier = 1.8
	mi.material_override = mat
	_fx_root.add_child(mi)

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
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.08)
	tw.tween_callback(mi.queue_free)


## 开过几枪 —— 自检用
func shot_count() -> int:
	return _shots
