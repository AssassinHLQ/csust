extends Boss
## 分身：优香-恐怖召出来的假身（用户 2026-11-13）。
##
## 用户原话：「还要有分身技能，分身 10 个围住主角团，但是十个只有本体会技能，其他都是普攻」。
##
## 所以这只分身**只会做一件事**：追到你身边、抬手打一下（普攻）。
## 它不放任何技能 —— 玩家靠"谁在放技能"就能认出本体。
##
## 表现上做成半透明红影（同一份 Yuuka.glb，改用不受光的半透明材质），
## 一眼能分出"这是假的"。

const SPEED := 5.5
const MELEE_RANGE := 3.4
const MELEE_DAMAGE := 6.0
const MELEE_CD := 2.0
const LIFE := 20.0
const STEP_MAX := 2.5

var _life_t := LIFE
var _melee_cd := 0.8
var _target: Node3D
var _ground_y := 0.0
var _dying := false
var _hits := 0
var _strikes := 0


func _init() -> void:
	display_name = "优香-恐怖 分身"
	model_path = "res://models/companions/Yuuka.glb"
	height = 10.0
	max_health = 220.0
	respawn_on_death = false
	drop_yuan = 0
	drop_to_bank = false
	# 分身不需要精细碰撞：一个盒子就够（10 只 × 24 个骨骼盒太重）
	collision_mode = Boss.CollisionMode.BOX
	collision_factors = Vector3(0.42, 0.92, 0.36)
	boot_distance = 0.0
	boot_max_wait = 0.0
	tint = Color(1.0, 0.55, 0.6)
	flash_color = Color(1.0, 0.75, 0.75)


func _ready() -> void:
	super._ready()
	_boot()
	_apply_ghost_skin()
	_ground_y = global_position.y
	if model != null:
		for n in model.find_children("*", "AnimationPlayer", true, false):
			var ap := n as AnimationPlayer
			var idle := ap.get_animation("Normal_Idle")
			if idle != null:
				idle.loop_mode = Animation.LOOP_LINEAR
			ap.play("Normal_Idle")
			break


func setup(who: Node3D) -> void:
	if who != null and is_instance_valid(who):
		_target = who
	_ground_y = _ground_below(global_position)


## 半透明红影：保留原贴图，但不吃光 + 30% 亮度的红色自发光
func _apply_ghost_skin() -> void:
	if model == null:
		return
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		if m.mesh == null or not (m.mesh is ArrayMesh):
			continue
		var am := m.mesh as ArrayMesh
		for s in am.get_surface_count():
			var src := am.surface_get_material(s) as StandardMaterial3D
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			if src != null and src.albedo_texture != null:
				mat.albedo_texture = src.albedo_texture
			mat.albedo_color = Color(1.0, 0.42, 0.46, 0.62)
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.10, 0.12)
			mat.emission_energy_multiplier = 0.45
			m.set_surface_override_material(s, mat)


# ────────────────────────── 行为：追 + 普攻 ──────────────────────────

func _physics_process(delta: float) -> void:
	# ⚠️ Boss 的骨骼 / 碰撞盒同步
	super._physics_process(delta)
	if _dead or _dying:
		return
	_life_t -= delta
	if _life_t <= 0.0:
		expire()
		return
	var p := _find_target()
	if p == null:
		return
	var d := p.global_position - global_position
	var flat := Vector2(d.x, d.z)
	_melee_cd = maxf(_melee_cd - delta, 0.0)
	if flat.length() > MELEE_RANGE:
		_walk(flat.normalized(), delta, p)
		return
	_face(d)
	if _melee_cd > 0.0:
		return
	_melee_cd = MELEE_CD
	if not p.has_method("take_damage"):
		return
	_strikes += 1
	_hits += 1
	p.call("take_damage", MELEE_DAMAGE, global_position, 4.0)
	_slash_fx(p.global_position + Vector3.UP * 1.2)


func _walk(dir: Vector2, delta: float, p: Node3D) -> void:
	var step := SPEED * delta
	var nx := global_position.x + dir.x * step
	var nz := global_position.z + dir.y * step
	var space := get_world_3d().direct_space_state
	if space != null:
		# 前方 2 m 有墙就停（探低处，别被树冠误判）
		var from := global_position + Vector3.UP * 1.5
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(dir.x, 0, dir.y) * 2.0)
		q.collision_mask = 1
		q.exclude = [get_rid()]
		if not space.intersect_ray(q).is_empty():
			return
	var gy := _ground_below(Vector3(nx, global_position.y, nz))
	if absf(gy - global_position.y) > STEP_MAX:
		# 量不准地面（校园网格有洞）→ 保持高度先摸过去
		global_position = Vector3(nx, global_position.y, nz)
	else:
		global_position = Vector3(nx, gy + 0.05, nz)
	_face(p.global_position - global_position)


func _face(d: Vector3) -> void:
	if Vector2(d.x, d.z).length() < 0.4:
		return
	rotation.y = atan2(d.x, d.z)


func _slash_fx(at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.82
	tm.outer_radius = 1.0
	tm.rings = 40
	tm.ring_segments = 4
	mi.mesh = tm
	mi.material_override = _additive(Color(1.0, 0.25, 0.30, 0.85))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at
	mi.scale = Vector3(0.6, 2.0, 0.6)
	var mat := mi.material_override as StandardMaterial3D
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(2.6, 2.0, 2.6), 0.25)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.3)
	tw.chain().tween_callback(mi.queue_free)


func _additive(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = col
	return m


# ────────────────────────── 收场 ──────────────────────────

func expire() -> void:
	if _dying or _dead:
		return
	_dying = true
	_disable_collisions()
	var tw := create_tween()
	tw.set_parallel(true)
	if model != null:
		tw.tween_property(model, "scale", model.scale * 0.05, 0.4)
	tw.chain().tween_callback(queue_free)


func _die(by_damage: float) -> void:
	if _dead:
		return
	super._die(by_damage)
	_dying = true
	var tw := create_tween()
	tw.tween_interval(0.6)
	tw.tween_callback(queue_free)


func _disable_collisions() -> void:
	for c in _collisions:
		if is_instance_valid(c):
			c.set_deferred("disabled", true)


func _find_target() -> Node3D:
	if _target != null and is_instance_valid(_target):
		return _target
	_target = get_tree().get_first_node_in_group("player") as Node3D
	return _target


func _ground_below(at: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	if space == null:
		return at.y - 2.0
	var q := PhysicsRayQueryParameters3D.create(
		at + Vector3.UP * 120.0, at + Vector3.DOWN * 120.0)
	q.collision_mask = 1
	q.exclude = _boss_rids()
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return at.y - 2.0
	var gy := (hit["position"] as Vector3).y
	if gy < -20.0 or gy > at.y + 80.0:
		return at.y - 2.0
	return gy


## 地面射线要排除自己**和同类**（10 个分身挤在一起，会量到同伴头顶）
func _boss_rids() -> Array[RID]:
	var out: Array[RID] = [get_rid()]
	for n in get_tree().get_nodes_in_group("bosses"):
		if n is CollisionObject3D and n != self:
			out.append((n as CollisionObject3D).get_rid())
	return out


func status() -> Dictionary:
	return {
		"health": health,
		"strikes": _strikes,
		"hits": _hits,
		"life": _life_t,
	}
