extends Boss
## 召唤物：**会飞的**飞猪优香。
##
## 用户 2026-11-13：「还要加召唤类技能，召唤 3 飞猪优香，这次真的是飞的，
## 而且飞猪优香也有更多技能了」。
##
## 和场景里站桩那只 `pig_boss.gd` 的区别：
##   · 那只贴地、只会原地预警圈拍人；这只是**真飞**——悬停、绕圈、俯冲；
##   · 自带 3 个技能：俯冲撞击 / 三连飞弹 / 俯冲轰炸；
##   · 血少（900）、有寿命（45 s），到期自己化掉，不会一直堆在场上。
##
## 三个坑：
## ① 它是 `Boss` 的子类，`Boss._ready()` 会 `add_to_group("bosses")` —— 这没问题：
##    第二关的"三只霸王龙"是在关卡 `_ready` 时数的，召唤物是后来才生成的，
##    不会被算进去；HUD 血条也是 `bind_bosses([终局 BOSS])` 显式绑的。
## ② 召唤物挂在 **ArenaLock**（BOSS 的父节点）下，不是 BOSS 的子节点 ——
##    BOSS 每帧转身，挂它下面就跟着绕圈（上次幻影就栽在这儿）。
## ③ 飞行是直接改 `global_position` 的，不靠物理；碰撞盒跟着走就行。

const HOVER_RADIUS := 17.0
const HOVER_ALT := 9.0
const FLY_SPEED := 10.0
const LIFE := 45.0
const ATTACK_INTERVAL := 3.6
const ATTACK_START := 1.6
const TURN_SPEED := 220.0

## 俯冲撞击
const DIVE_RADIUS := 5.0
const DIVE_WARN := 0.9
const DIVE_SPEED := 34.0
const DIVE_DAMAGE := 18.0

## 三连飞弹
const VOLLEY_COUNT := 3
const VOLLEY_DAMAGE := 8.0
const VOLLEY_SPEED := 24.0

## 俯冲轰炸
const BOMB_COUNT := 2
const BOMB_RADIUS := 4.0
const BOMB_DAMAGE := 16.0
const BOMB_FALL := 0.55

var _target: Node3D
var _life_t := LIFE
var _attack_t := ATTACK_START
var _skill_i := 0
var _bob_t := 0.0
var _orbit := 0.0
var _busy := false
var _ground_y := 0.0
var _orbs: Array[Dictionary] = []
var _marks: Array[Node3D] = []
var _hits := {"dive": 0, "volley": 0, "bomb": 0}
var _casts := {"dive": 0, "volley": 0, "bomb": 0}
var _dying := false


func _init() -> void:
	display_name = "飞猪优香"
	model_path = "res://models/boss_pig/猪猪优香.fbx"
	# 和场景里那只同一套贴图
	texture_map = {
		"Yuuka_Original_Halo_0Mat": "res://models/boss_pig/tex/pig_halo.png",
		"材质": "res://models/boss_pig/tex/pig_untitled1.png",
		"材质.001": "res://models/boss_pig/tex/pig_nose.png",
		"材质.002": "res://models/boss_pig/tex/pig_tail.png",
	}
	collision_factors = Vector3(0.85, 0.8, 0.75)
	height = 3.4
	max_health = 900.0
	respawn_on_death = false
	drop_yuan = 0
	drop_to_bank = false
	collision_mode = Boss.CollisionMode.BOX_PARTS
	boot_distance = 0.0
	boot_max_wait = 0.0
	flash_color = Color(1.0, 0.55, 0.55)
	# 封锁区是红色末日光，原色贴图会被压得很黑 —— 提亮一档，并加一层紫色自发光，
	# 一眼能看出"这是恐怖优香召唤出来的东西"
	tint = Color(1.15, 1.05, 1.2)


func _ready() -> void:
	super._ready()
	_boot()
	_ground_y = global_position.y
	_target = get_tree().get_first_node_in_group("player") as Node3D
	_orbit = randf() * TAU
	for m in _materials:
		if m == null:
			continue
		m.emission_enabled = true
		m.emission = Color(0.65, 0.10, 0.45)
		m.emission_energy_multiplier = 0.35
	print("[飞猪] 出场：%s，血量 %.0f" % [str(global_position.snappedf(0.1)), max_health])


## 召唤者可以塞一个玩家目标进来（比每次 group 查快，也避免场上多玩家时搞错）
func setup(who: Node3D) -> void:
	if who != null and is_instance_valid(who):
		_target = who
	# ⚠️ `_ready` 是 add_child 那一刻跑的，那时坐标还是 (0,0,0)，
	#    所以"地面高度"要等召唤者摆好位置之后再量一次。
	_ground_y = _ground_below()


func _find_target() -> Node3D:
	if _target != null and is_instance_valid(_target):
		return _target
	_target = get_tree().get_first_node_in_group("player") as Node3D
	return _target


# ────────────────────────── 飞行 ──────────────────────────

func _physics_process(delta: float) -> void:
	# ⚠️ Boss 的骨骼碰撞盒要靠它同步
	super._physics_process(delta)
	if _dead or _dying:
		return
	_life_t -= delta
	if _life_t <= 0.0:
		expire()
		return
	_fly(delta)
	_tick_orbs(delta)
	_attack_t -= delta
	if _attack_t <= 0.0 and not _busy:
		_attack_t = ATTACK_INTERVAL
		_attack()


## 悬停：绕着玩家转圈 + 上下浮动；俯冲/投弹时由那些函数临时接管位置
func _fly(delta: float) -> void:
	if _busy:
		return
	var p := _find_target()
	_bob_t += delta
	_orbit += delta * 0.55
	var anchor := p.global_position if p != null else global_position
	var want := anchor + Vector3(cos(_orbit), 0.0, sin(_orbit)) * HOVER_RADIUS
	want.y = anchor.y + HOVER_ALT + sin(_bob_t * 2.2) * 0.9
	want.y = maxf(want.y, _ground_y + 4.5)
	global_position = global_position.move_toward(want, FLY_SPEED * delta)
	if p != null:
		var d := p.global_position - global_position
		if Vector2(d.x, d.z).length() > 0.5:
			var want_yaw := atan2(d.x, d.z)
			rotation.y = rotate_toward(rotation.y, want_yaw,
				deg_to_rad(TURN_SPEED) * delta)


# ────────────────────────── 三个技能 ──────────────────────────

func _attack() -> void:
	var p := _find_target()
	if p == null:
		return
	_busy = true
	var kind := String(["dive", "volley", "bomb"][_skill_i % 3])
	_skill_i += 1
	_casts[kind] = int(_casts.get(kind, 0)) + 1
	print("[飞猪] 出招：%s" % kind)
	match kind:
		"dive":
			await _do_dive(p)
		"volley":
			await _do_volley(p)
		_:
			await _do_bomb(p)
	_busy = false


## 俯冲撞击：圈亮 0.9 s → 整只扎过去 → 爆一圈
func _do_dive(p: Node3D) -> void:
	var center := p.global_position
	var disc := _make_disc(center, DIVE_RADIUS, Color(1.0, 0.35, 0.85, 0.45))
	Sfx.play("fire_beam", -10.0)
	var tw := create_tween()
	tw.tween_property(disc, "scale", Vector3(DIVE_RADIUS, 1.0, DIVE_RADIUS), DIVE_WARN) \
		.from(Vector3(DIVE_RADIUS * 0.3, 1.0, DIVE_RADIUS * 0.3))
	await tw.finished
	if _dead or not is_instance_valid(self):
		if is_instance_valid(disc):
			disc.queue_free()
		return
	var to := center + Vector3.UP * 1.6
	var dur := maxf(global_position.distance_to(to) / DIVE_SPEED, 0.08)
	var tw2 := create_tween()
	tw2.tween_property(self, "global_position", to, dur) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await tw2.finished
	_hit(center, DIVE_RADIUS, DIVE_DAMAGE, "dive")
	_blast(center, Color(1.0, 0.3, 0.8, 0.9))
	Sfx.play("ui_close", -6.0)
	_flash_mark(disc, 1.3, 0.25)
	await get_tree().create_timer(0.45).timeout


## 三连飞弹：朝玩家当前位置各甩一发（带一点散布）
func _do_volley(p: Node3D) -> void:
	Sfx.play("fire", -12.0)
	var aim := p.global_position + Vector3.UP * 0.9
	for i in VOLLEY_COUNT:
		if _dead or not is_instance_valid(self):
			return
		var side := Vector3(randf_range(-1.0, 1.0), randf_range(-0.4, 0.6),
			randf_range(-1.0, 1.0)) * 1.2
		_spawn_orb(aim + side)
		await get_tree().create_timer(0.14).timeout
	await get_tree().create_timer(0.2).timeout


## 俯冲轰炸：飞到玩家头顶，扔两颗炸弹
func _do_bomb(p: Node3D) -> void:
	var above := p.global_position + Vector3.UP * 13.0
	var dur := maxf(global_position.distance_to(above) / (FLY_SPEED * 1.6), 0.25)
	var tw := create_tween()
	tw.tween_property(self, "global_position", above, dur) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	if _dead or not is_instance_valid(self):
		return
	for i in BOMB_COUNT:
		if _dead or not is_instance_valid(self):
			return
		var off := Vector3(randf_range(-4.0, 4.0), 0.0, randf_range(-4.0, 4.0))
		_drop_bomb(p.global_position + off)
		await get_tree().create_timer(0.18).timeout
	await get_tree().create_timer(BOMB_FALL + 0.4).timeout


# ────────────────────────── 弹 / 圈 ──────────────────────────

func _spawn_orb(target: Vector3) -> void:
	var orb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.9
	sm.height = 1.8
	sm.radial_segments = 12
	sm.rings = 6
	orb.mesh = sm
	orb.material_override = _additive(Color(1.0, 0.55, 0.9, 0.95))
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(orb)
	orb.global_position = global_position + Vector3.UP * height * 0.4
	var dir := target - orb.global_position
	dir = dir.normalized() if dir.length_squared() > 0.01 else Vector3.FORWARD
	_orbs.append({"node": orb, "dir": dir, "t": 0.0})


func _tick_orbs(delta: float) -> void:
	if _orbs.is_empty():
		return
	var p := _find_target()
	var keep: Array[Dictionary] = []
	for o in _orbs:
		var node: MeshInstance3D = o["node"]
		if node == null or not is_instance_valid(node):
			continue
		var t := float(o["t"]) + delta
		if t > 4.0:
			node.queue_free()
			continue
		var prev := node.global_position
		var next := prev + (o["dir"] as Vector3) * VOLLEY_SPEED * delta
		node.global_position = next
		if p != null and p.has_method("take_damage"):
			var chest := p.global_position + Vector3.UP * 0.9
			var closest := Geometry3D.get_closest_point_to_segment(chest, prev, next)
			if closest.distance_to(chest) <= 1.6:
				_hits["volley"] = int(_hits.get("volley", 0)) + 1
				p.call("take_damage", VOLLEY_DAMAGE, closest, 4.0)
				node.queue_free()
				continue
		o["t"] = t
		keep.append(o)
	_orbs = keep


func _drop_bomb(at: Vector3) -> void:
	var disc := _make_disc(at, BOMB_RADIUS, Color(1.0, 0.30, 0.75, 0.42))
	var rock := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.4
	sm.height = 2.8
	sm.radial_segments = 10
	sm.rings = 6
	rock.mesh = sm
	rock.material_override = _additive(Color(1.0, 0.45, 0.85, 0.9))
	rock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rock)
	rock.global_position = at + Vector3.UP * 16.0
	var tw := create_tween()
	tw.tween_property(rock, "global_position", at + Vector3.UP * 1.0, BOMB_FALL) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	if is_instance_valid(rock):
		rock.queue_free()
	if _dead or not is_instance_valid(self):
		if is_instance_valid(disc):
			disc.queue_free()
		return
	_hit(at, BOMB_RADIUS, BOMB_DAMAGE, "bomb")
	_blast(at, Color(1.0, 0.35, 0.8, 0.85))
	_flash_mark(disc, 1.3, 0.25)


func _make_disc(center: Vector3, radius: float, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(2.0, 2.0)
	mi.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/telegraph_disc.gdshader")
	mat.set_shader_parameter("color", col)
	mat.set_shader_parameter("alpha", 0.26)
	mat.set_shader_parameter("pulse", 0.0)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3(radius, 1.0, radius)
	add_child(mi)
	mi.global_position = Vector3(center.x, center.y + 0.06, center.z)
	_marks.append(mi)
	return mi


func _flash_mark(mark: Node3D, grow: float, time: float) -> void:
	_marks.erase(mark)
	if not is_instance_valid(mark):
		return
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mark, "scale", mark.scale * grow, time)
	var sh := (mark as MeshInstance3D).material_override as ShaderMaterial
	if sh != null:
		tw.tween_method(func(v: float) -> void:
			if is_instance_valid(sh):
				sh.set_shader_parameter("alpha", v), 0.6, 0.0, time)
	tw.chain().tween_callback(mark.queue_free)


func _additive(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = col
	return m


func _blast(at: Vector3, col: Color) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.0
	tm.rings = 48
	tm.ring_segments = 4
	ring.mesh = tm
	var mat := _additive(col)
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.global_position = at + Vector3.UP * 0.8
	ring.scale = Vector3(1.2, 2.0, 1.2)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(5.0, 2.0, 5.0), 0.35)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.45)
	tw.chain().tween_callback(ring.queue_free)


## 球判定：半径内就吃
func _hit(center: Vector3, radius: float, dmg: float, kind: String) -> void:
	var p := _find_target()
	if p == null or not p.has_method("take_damage"):
		return
	var chest := p.global_position + Vector3.UP * 0.9
	var d := chest.distance_to(center)
	if d <= radius:
		_hits[kind] = int(_hits.get(kind, 0)) + 1
		p.call("take_damage", dmg, center, 6.0)
		print("[飞猪] %s 命中（%.1f m）" % [kind, d])


# ────────────────────────── 收场 ──────────────────────────

## 寿命到了：淡出并消失（不结算掉落）
func expire() -> void:
	if _dying or _dead:
		return
	_dying = true
	_disable_collisions()
	var tw := create_tween()
	tw.set_parallel(true)
	if model != null:
		tw.tween_property(model, "scale", model.scale * 0.1, 0.45)
	tw.tween_property(self, "global_position",
		global_position + Vector3.UP * 6.0, 0.45)
	tw.chain().tween_callback(queue_free)
	print("[飞猪] 到时间退场")


func _die(by_damage: float) -> void:
	if _dead:
		return
	super._die(by_damage)
	_dying = true
	# 从空中掉下来 + 淡出
	var ground := _ground_below()
	var tw := create_tween()
	tw.tween_property(self, "global_position",
		Vector3(global_position.x, ground + 0.5, global_position.z), 0.7) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_interval(1.0)
	tw.tween_callback(queue_free)
	print("[飞猪] 被打下来")


func _disable_collisions() -> void:
	for c in _collisions:
		if is_instance_valid(c):
			c.set_deferred("disabled", true)


func _ground_below() -> float:
	var space := get_world_3d().direct_space_state
	if space == null:
		return _ground_y
	var q := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 40.0, global_position + Vector3.DOWN * 60.0)
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return _ground_y
	return (hit["position"] as Vector3).y


## 探针 / 召唤者用
func status() -> Dictionary:
	return {
		"health": health,
		"dead": _dead,
		"altitude": global_position.y - _ground_y,
		"hits": _hits.duplicate(),
		"casts": _casts.duplicate(),
		"life": _life_t,
	}


func total_hits() -> int:
	var n := 0
	for k in _hits.keys():
		n += int(_hits[k])
	return n
