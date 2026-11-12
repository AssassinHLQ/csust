extends Node3D
## EX 必杀系统（2026-11-09，2026-11-10 按用户更正重写）—— 连按 E→X 触发。
##
## ── 用户原话（2026-11-10，更正上一版）──
## 「我是说连续按键盘E X 触发,消耗6cost,不需要充能条和蓄力时间,
##   就是按完E X键盘就是最大功率发射」
##
## ── 所以这一版和上一版的区别（上一版做错的地方）──
##   上一版：Q 键长按蓄力、自己攒一个 22 s 的充能条、蓄力越久越强。
##   本版：**连按 E 再 X**（先 E 后 X，间隔 `SEQ_WINDOW` 内有效）→ 立刻**满功率**发射。
##         消耗走游戏里早就有的 `CostGauge`（消耗 6，上限 10，每秒 +1）。
##         **没有充能条**（COST 条 HUD 上本来就有，不在本类里另画）。
##         **没有蓄力时间**（按完就最大威力）。
##
## ── 为什么是「E 再 X」两个键 ──
## 单键容易误触（尤其 Q/R/T/F/G 全被占了）。两键连按是格斗游戏搓招的惯例，
## 手指有两个动作，不会在走位时随手按出来。
## 顺序固定「先 E 后 X」：反着按无效（`_seq_stage` 只认 0→1→触发）。
##
## ── 分派 ──
## `carrier.is_on()` → 巨型连续轨道炮；否则 → 激光球。两者都是**最大功率**。

## E 和 X 之间允许的最大间隔（秒）。超过就作废，要重新按 E。
const SEQ_WINDOW := 0.65
## 消耗多少 COST（`cost_gauge.gd::ARISU_EX_COST` 的镜像，权威值仍在那边）
const EX_COST := 6

var _player: Node3D
var _weapon: Node
var _carrier: Node
var _fx_root: Node3D

## 0 = 还没按 E；1 = 按过 E，正在等 X
var _seq_stage := 0
var _seq_deadline_ms := 0

const CostGauge := preload("res://scripts/cost_gauge.gd")


func setup(player: Node3D, weapon: Node, carrier: Node) -> void:
	_player = player
	_weapon = weapon
	_carrier = carrier
	_fx_root = Node3D.new()
	_fx_root.name = "ExFx"
	add_child(_fx_root)


func is_mech() -> bool:
	return _carrier != null and _carrier.has_method("is_on") and bool(_carrier.call("is_on"))


## 现在能不能放（COST 够不够）
func can_fire() -> bool:
	return CostGauge.can_afford(EX_COST)


## 喂一个键进来。返回 true = 这一个键被 EX 系统吃掉了（调用方不要再处理）。
##
## 用户要的是「连按键盘 E X」：
##   · 按 E：进入 stage 1，开始计时
##   · 按 X：stage 1 且没超时 → **立刻满功率发射**，扣 6 COST
##   · 按 X 时 stage 0（还没按 E）→ 什么都不做，也不吃这个键
##   · 超时后再按 X → 作废，要重新按 E
func feed_key(key: int) -> bool:
	var now := Time.get_ticks_msec()
	# 超时就把序列清掉
	if _seq_stage == 1 and now > _seq_deadline_ms:
		_seq_stage = 0

	if key == KEY_E:
		# 不够钱就不进入序列（免得玩家按完 E X 才发现放不出来）
		if not can_fire():
			_seq_stage = 0
			return false
		_seq_stage = 1
		_seq_deadline_ms = now + int(SEQ_WINDOW * 1000.0)
		return true

	if key == KEY_X:
		if _seq_stage != 1:
			return false
		_seq_stage = 0
		if not CostGauge.spend(EX_COST):
			return true     # 键吃掉但不放（理论上进不来，can_fire 在 E 那次已查过）
		_fire_max()
		return true

	return false


## 最大功率发射（按形态分流）。**没有蓄力，直接满威力。**
func _fire_max() -> void:
	# 声音：爱丽丝本人的 EX 技能原声（切掉前 2 s 蓄力，见 `sfx.gd` 的 `ex_fire` 那条）。
	# 放在分流**之前**：两种形态都是同一发 EX，音效不该跟着形态变。
	Sfx.play("ex_fire")
	if is_mech():
		print("[EX] 机甲 → 巨型轨道炮（满功率，COST -%d，剩 %d）" % [
			EX_COST, CostGauge.display()])
		_fire_railgun()
	else:
		print("[EX] 普通 → 激光球（满功率，COST -%d，剩 %d）" % [
			EX_COST, CostGauge.display()])
		_fire_laser_orb()


## 序列状态（自检用）
func seq_stage() -> int:
	return _seq_stage


# ═══════════════════════════════════════════════════════════════════
#  必杀 ①：普通状态 —— 激光球（满功率）
# ═══════════════════════════════════════════════════════════════════
##
## 观感：三层加色能量球从枪口射出，向前飞，命中炸开成球形冲击波。
##
## 伤害：**满功率固定值**（不再随蓄力变化，因为没有蓄力了）。
## 770 = 350 × 2.2，就是上一版「蓄满」的数值 —— 用户要的就是这个威力。

const ORB_DAMAGE := 770.0
const ORB_SPEED := 42.0
const ORB_LIFE := 3.0
const ORB_RADIUS := 0.34
const ORB_AOE := 4.5

## ── 普通爱丽丝 EX 的观感（用户 2026-11-11 二次给图：「这个是普通爱丽丝的 ex 技能,
##    3、4 这是蓄力,有点糊你凑合看」）──
##
## 参考图里这一发是**紫粉色能量爆 + 一圈圈蓝色电光**，不是本喵以前那颗青白色小球：
##   图 3/4（蓄力）：枪口一颗粉色光球，外面有蓝色电弧乱窜、越蓄越大；
##   图 1/2（发射）：主体是**紫红/品红**的爆团，外面包着**青色蓝**的弧形电光。
## 所以配色改成「粉紫核心 + 青蓝外壳」，并在球外面挂几根抖动旋转的蓝色电弧细杆。
const ORB_CHARGE_TIME := 0.42       # 蓄力时长（秒），期间不放球
const ORB_CORE := Color(1.00, 0.55, 0.92, 0.95)   # 粉紫核心
const ORB_MID := Color(0.72, 0.42, 1.00, 0.55)    # 紫
const ORB_SHELL := Color(0.35, 0.80, 1.00, 0.32)  # 青蓝外壳
const ORB_ARC := Color(0.55, 0.95, 1.00, 0.85)    # 蓝色电弧


## 蓄力：枪口一颗粉色光球由小涨大，外面几根蓝色电弧抖动旋转（图 3/4）。
## 结束后光球就地销毁，交给 `_fire_laser_orb()` 的飞行球接上。
func _orb_charge(origin: Vector3, dir: Vector3) -> void:
	var holder := Node3D.new()
	holder.name = "OrbCharge"
	_fx_root.add_child(holder)
	holder.global_position = origin

	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 20
	sm.rings = 12
	core.mesh = sm
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cmat := _add_mat(Color(ORB_CORE.r, ORB_CORE.g, ORB_CORE.b, 0.0), 9.0)
	core.material_override = cmat
	holder.add_child(core)

	# 蓄力光晕（图 3/4 那团糊开的光）
	var chalo := _halo(ORB_RADIUS * 9.0, Color(1.00, 0.70, 0.95, 0.0), 6.5)
	holder.add_child(chalo)

	# 蓝色电弧：几根细杆，每帧随机旋转、随机长度，做出「乱窜」的抖动感
	var arcs: Array = []
	for i in 5:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, 0.05, 1.0)
		mi.mesh = bm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = _add_mat(Color(ORB_ARC.r, ORB_ARC.g, ORB_ARC.b, 0.0), 8.0)
		holder.add_child(mi)
		arcs.append(mi)

	var t0 := Time.get_ticks_msec()
	var span := int(ORB_CHARGE_TIME * 1000.0)
	while is_instance_valid(self):
		var el := Time.get_ticks_msec() - t0
		if el >= span:
			break
		var t := float(el) / float(span)
		var cs := lerpf(0.18, 0.62, t)
		core.scale = Vector3(cs, cs, cs)
		cmat.albedo_color.a = 0.25 + 0.6 * t
		chalo.scale = Vector3.ONE * lerpf(0.25, 1.0, t)
		(chalo.material_override as StandardMaterial3D).albedo_color.a = 0.15 + 0.5 * t
		for a in arcs:
			var mi2 := a as MeshInstance3D
			var rr := randf() * TAU
			var tilt := randf_range(-1.1, 1.1)
			mi2.global_position = origin
			mi2.global_basis = Basis(dir, rr) * Basis(Vector3.RIGHT, tilt)
			var ln := randf_range(0.35, 0.85) * lerpf(0.6, 1.4, t)
			mi2.scale = Vector3(1.0, 1.0, ln)
			(mi2.material_override as StandardMaterial3D).albedo_color.a = \
				randf_range(0.35, 0.9) * (1.0 - t * 0.5)
		await get_tree().process_frame
	if is_instance_valid(holder):
		holder.queue_free()


func _muzzle_point() -> Vector3:
	if _weapon != null:
		var m := _weapon.get_node_or_null("Muzzle") as Node3D
		if m != null:
			return m.global_position
	if _player != null:
		return _player.global_position + Vector3.UP * 1.4
	return global_position


## 准星对准点：从**相机中心**打一条 300 m 射线，命中就以命中点为目标。
##
## 用户 2026-11-11：「也很难打中,总是打偏」。
## 根因：以前光球是从**炮口**沿 `camera_forward()` 方向射出 —— 炮口在角色身侧、
## 和准星不在同一条线上，于是几百米外就看出偏差（近距离看不出来）。
## 正确做法：先把准星指到的东西找到，再让「炮口 → 那个点」成方向。
func _crosshair_point() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3.ZERO
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * 300.0
	var space := _fx_root.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [_player]
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		return hit["position"]
	return to


## `dir` 用准星点算；准星点算不出来才退回相机朝向。
func _aim_dir_to_crosshair(from: Vector3) -> Vector3:
	var pt := _crosshair_point()
	if pt == Vector3.ZERO:
		return _aim_dir()
	var d := pt - from
	if d.length_squared() < 0.0001:
		return _aim_dir()
	return d.normalized()


func _aim_dir() -> Vector3:
	if _player != null and _player.has_method("camera_forward"):
		var d: Vector3 = _player.call("camera_forward")
		if d.length_squared() > 0.001:
			return d.normalized()
	return -global_transform.basis.z


func _fire_laser_orb() -> void:
	var origin := _muzzle_point()
	var dir := _aim_dir()

	# ① 先蓄力（参考图 3/4：枪口粉色光球 + 蓝色电弧乱窜），期间不放球
	await _orb_charge(origin, dir)
	if not is_instance_valid(self):
		return
	# 蓄力这 0.42 s 里枪口可能已经跟着走位挪了，重取一次
	origin = _muzzle_point()
	# ⚠️ 方向改成「炮口 → 准星点」，否则远距离必然打偏（用户：「总是打偏」）
	dir = _aim_dir_to_crosshair(origin)

	var holder := Node3D.new()
	holder.name = "LaserOrb"
	_fx_root.add_child(holder)
	holder.global_position = origin

	# ② 飞行球配色改成参考图 1/2 的「粉紫核心 + 青蓝外壳」
	var layers := [
		{"r": 1.00, "c": Color(ORB_SHELL.r, ORB_SHELL.g, ORB_SHELL.b, 0.42), "e": 5.0},
		{"r": 0.66, "c": Color(ORB_MID.r, ORB_MID.g, ORB_MID.b, 0.72), "e": 8.0},
		{"r": 0.34, "c": Color(ORB_CORE.r, ORB_CORE.g, ORB_CORE.b, 1.00), "e": 13.0},
	]
	for L in layers:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = ORB_RADIUS * float(L["r"])
		sm.height = sm.radius * 2.0
		sm.radial_segments = 20
		sm.rings = 12
		mi.mesh = sm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_color = L["c"]
		mat.emission_enabled = true
		mat.emission = Color((L["c"] as Color).r, (L["c"] as Color).g, (L["c"] as Color).b)
		mat.emission_energy_multiplier = float(L["e"])
		mi.material_override = mat
		holder.add_child(mi)

	var light := OmniLight3D.new()
	light.light_color = Color(0.85, 0.55, 1.0)
	light.light_energy = 5.6
	light.omni_range = 6.0
	light.shadow_enabled = false
	holder.add_child(light)

	# ③ 球外面挂几根抖动的蓝色电弧（参考图 1/2 那圈青色电光）
	var arc_meshes: Array = []
	for i in 6:
		var ami := MeshInstance3D.new()
		var abm := BoxMesh.new()
		abm.size = Vector3(0.045, 0.045, 1.0)
		ami.mesh = abm
		ami.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ami.material_override = _add_mat(ORB_ARC, 9.0)
		holder.add_child(ami)
		arc_meshes.append(ami)
	holder.set_meta("arcs", arc_meshes)
	# 光晕（假泛光）
	var orb_halo := _halo(ORB_RADIUS * 7.0, Color(0.95, 0.70, 1.00, 0.55), 7.0)
	holder.add_child(orb_halo)
	# 身后的速度条纹（用户手绘示意的那种长条）
	_attach_trail(holder, dir)

	_orb_fly(holder, origin, dir)


## 光球后面的**速度条纹**（用户 2026-11-12 画了示意图：一颗圆球 + 后面好几道长长的直线）。
##
## ⚠️ 本喵第一版做的是「每帧在身后留一片小光晕、0.22 s 淡出」——
##    那是**一串会消散的点**，不是条纹，实机几乎看不出来（用户：「你怎么只有圆球
##    没有后面的特效了?」）。正确做法是**细长的条**，而且必须挂在球上跟着走，
##    这样它才是一条笔直拖在后面的线，而不是散开的一团。
##
## 做法：挂一个 `OrbTrail` 子节点，把它的局部 **+Z 指向身后（−dir）**，
## 然后沿 +Z 摆若干根细长盒子（0.035 m 见方、长 2~7 m、横截面随机散开成一小簇）。
## 每帧轻微抖动长度与透明度 → 像高速掠过的光条，而不是死板的棍子。
func _attach_trail(holder: Node3D, dir: Vector3) -> void:
	var trail := Node3D.new()
	trail.name = "OrbTrail"
	holder.add_child(trail)
	var up0 := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var right0 := up0.cross(dir).normalized()
	var realup0 := dir.cross(right0).normalized()
	# 局部 +Z = −dir ⇒ 局部 z 为正就是把东西摆在球**后面**
	trail.global_basis = Basis(right0, realup0, -dir)
	var streaks: Array = []
	for i in 12:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.035, 0.035, 1.0)
		mi.mesh = bm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := _add_mat(Color(0.86, 0.72, 1.00, 0.5), 7.0)
		mi.material_override = mat
		trail.add_child(mi)
		var ang := randf() * TAU
		var rad := sqrt(randf()) * 0.55
		var ln := randf_range(2.0, 7.0)
		mi.position = Vector3(cos(ang) * rad, sin(ang) * rad, 0.35 + ln * 0.5)
		mi.scale = Vector3(1.0, 1.0, ln)
		streaks.append({"mi": mi, "mat": mat, "len": ln})
	holder.set_meta("streaks", streaks)


func _orb_fly(holder: Node3D, origin: Vector3, dir: Vector3) -> void:
	var space := _fx_root.get_world_3d().direct_space_state
	var pos := origin
	var travelled := 0.0
	var last_crescent := 0.0
	var step_total := ORB_SPEED * ORB_LIFE
	while travelled < step_total and is_instance_valid(holder):
		await get_tree().process_frame
		if not is_instance_valid(holder):
			return
		var step := ORB_SPEED * get_process_delta_time()
		var next := pos + dir * step
		var q := PhysicsRayQueryParameters3D.create(pos, next)
		q.collide_with_areas = false
		q.collide_with_bodies = true
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			holder.global_position = hit["position"]
			_orb_explode(holder, hit["position"])
			return
		pos = next
		travelled += step
		holder.global_position = pos
		# 速度条纹：每帧轻微抖动长度/透明度（条纹本身挂在球上，位置不用管）
		if holder.has_meta("streaks"):
			for s in (holder.get_meta("streaks") as Array):
				var mi3 := s["mi"] as MeshInstance3D
				var ln2: float = float(s["len"]) * randf_range(0.75, 1.25)
				mi3.scale = Vector3(1.0, 1.0, ln2)
				mi3.position.z = 0.35 + ln2 * 0.5
				(s["mat"] as StandardMaterial3D).albedo_color.a = randf_range(0.20, 0.58)
		# 弯月扫掠：每 3.8 m 在球的位置甩一片扩张的青色弧（参考图 1/2）
		if travelled - last_crescent >= 3.8:
			last_crescent = travelled
			_crescent(pos, dir, randf_range(2.2, 3.4), ORB_ARC)
		# 电弧每帧抖一下：绕球随机朝向 + 随机长度（参考图里那圈乱窜的青色电光）
		if holder.has_meta("arcs"):
			for a in (holder.get_meta("arcs") as Array):
				var ami := a as MeshInstance3D
				var rr := randf() * TAU
				var tt := randf_range(-1.2, 1.2)
				ami.global_position = pos
				ami.global_basis = Basis(Vector3.FORWARD, rr) * Basis(Vector3.RIGHT, tt)
				ami.scale = Vector3(1.0, 1.0, randf_range(0.30, 0.75))
				(ami.material_override as StandardMaterial3D).albedo_color.a = randf_range(0.45, 1.0)
	holder.queue_free()


## 这个节点能不能按「敌人」的签名挨 EX 的伤害？
##
## 为什么要判签名，而不是只判 `has_method("take_damage")`：
## **`Player` 也有 `take_damage`，但参数是 `(amount, hit_from, knockback)`** ——
## 第 3 个（从 0 数起是 index 2）是 `float`；而 Boss / 靶子是
## `(amount, hit_pos, hit_dir)`，第 3 个是 `Vector3`。EX 按后者传，
## 落到 Player 身上就变成「Cannot convert argument 4 from Vector3 to float」，
## GDScript 直接**硬崩**（用户 2026-11-10「机甲按 EX 就闪退」，调试器 79 条同类错误）。
##
## 判据用 `get_method_list()` 看 **index 2** 的参数类型（实测 4.7.1）：
##   boss.gd   → [amount:float, _hit_pos:Vector3, _hit_dir:Vector3]
##   player.gd → [amount:float, hit_from:Vector3, knockback:float]
## ⚠️ 别去判「参数个数 ≥ 4」—— 两边的 `args.size()` **都是 3**（本喵第一版判错了，
##    导致 Boss 也被判成「不能挨打」）。
func _can_hurt_take_damage(n: Object) -> bool:
	if n == null or not n.has_method("take_damage"):
		return false
	for m in n.get_method_list():
		if String(m.get("name", "")) != "take_damage":
			continue
		var args: Array = m.get("args", [])
		if args.size() < 3:
			return false
		# GDScript 的 args 是 [{"name":..., "type": TYPE_*, ...}, ...]
		var t2 := int((args[2] as Dictionary).get("type", TYPE_NIL))
		return t2 == TYPE_VECTOR3
	return false


## 这个节点能不能被 EX 的**光球**溅到（`_orb_explode` 走的是另一条路径）。
## 判据和前一个函数一样：只认「敌人签名」的 take_damage。
func _can_hurt_orb(n: Object) -> bool:
	return _can_hurt_take_damage(n)


## 这个节点是不是「不该挨自己 EX」的玩家？（光球路径也要挡）
func _is_player_node(n: Object) -> bool:
	return n != null and _player != null and n == _player


func _orb_explode(holder: Node3D, at: Vector3) -> void:
	var hurt := 0
	for n in get_tree().get_nodes_in_group("bosses"):
		var b := n as Node3D
		if b != null and b.global_position.distance_to(at) <= ORB_AOE \
				and _can_hurt_orb(b):
			b.call("take_damage", ORB_DAMAGE, at, Vector3.UP)
			hurt += 1
	for n in get_tree().get_nodes_in_group("targets"):
		var t := n as Node3D
		if t != null and _can_hurt_orb(t) \
				and t.global_position.distance_to(at) <= ORB_AOE:
			t.call("take_damage", ORB_DAMAGE, at, Vector3.UP)
			hurt += 1

	var burst := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 24
	sm.rings = 14
	burst.mesh = sm
	burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(ORB_MID.r, ORB_MID.g, ORB_MID.b, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(ORB_CORE.r, ORB_CORE.g, ORB_CORE.b)
	mat.emission_energy_multiplier = 11.0
	burst.material_override = mat
	_fx_root.add_child(burst)
	burst.global_position = at
	burst.scale = Vector3.ONE * 0.2

	var tw := burst.create_tween()
	tw.set_parallel(true)
	tw.tween_property(burst, "scale", Vector3.ONE * ORB_AOE, 0.42) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.42)

	# 爆炸光晕（假泛光）+ 两片弯月，让爆点不只是「一个球」
	var ex_halo := _halo(ORB_AOE * 3.2, Color(0.95, 0.72, 1.00, 0.65), 8.0)
	_fx_root.add_child(ex_halo)
	ex_halo.global_position = at
	ex_halo.scale = Vector3.ONE * 0.3
	var htw := ex_halo.create_tween()
	htw.set_parallel(true)
	htw.tween_property(ex_halo, "scale", Vector3.ONE, 0.5) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	htw.tween_property(ex_halo.material_override, "albedo_color:a", 0.0, 0.5)
	htw.chain().tween_callback(ex_halo.queue_free)
	_crescent(at, Vector3.UP, ORB_AOE * 1.5, ORB_ARC)
	_crescent(at, Vector3.RIGHT, ORB_AOE * 1.2, Color(1.0, 0.75, 1.0, 0.9))
	tw.chain().tween_callback(burst.queue_free)

	var light := OmniLight3D.new()
	light.light_color = Color(0.6, 0.88, 1.0)
	light.light_energy = 8.0
	light.omni_range = ORB_AOE * 2.4
	light.shadow_enabled = false
	_fx_root.add_child(light)
	light.global_position = at
	var lt := light.create_tween()
	lt.tween_property(light, "light_energy", 0.0, 0.5)
	lt.tween_callback(light.queue_free)

	holder.queue_free()
	print("[EX] 激光球命中：伤害 %.0f、范围 %.1f m、命中 %d 个目标" % [
		ORB_DAMAGE, ORB_AOE, hurt])


# ═══════════════════════════════════════════════════════════════════
#  必杀 ②：机甲状态 —— 巨型连续轨道炮（满功率）
# ═══════════════════════════════════════════════════════════════════
##
## 双肩炮各射一条三层层叠光柱，持续 `RAIL_DURATION`，每 `RAIL_TICK_SEC` 结算一跳。
## 每跳 **180**（上一版「蓄满」的值）× 15 跳 ≈ **2700**。

const RAIL_TICK_DAMAGE := 180.0
const RAIL_DURATION := 0.9
const RAIL_TICK_SEC := 0.06
const RAIL_RANGE := 220.0
const RAIL_WIDTH := 0.95

## ── 照碧蓝档案「临战」阿比·埃修改的观感（用户 2026-11-11 给了 8 张参考图）──
##
## 用户原话：「机甲爱丽丝普通攻击,图一图二,3 4,5 ex蓄力 678 ex技能,
##            是**一开始超大然后缩减**的,这才是真正的机甲爱丽丝」。
##
## 参考图里 EX 其实是两段：
##   ① **蓄力**（图 3/4/5）：一圈圈白色光环从枪口由小涨大、核心越来越亮；
##   ② **发射**（图 6/7/8）：枪口那一端是**巨大**的光团，沿射线方向**迅速收细**成一条线，
##      整体宽度还会随时间缩 —— 不是本喵以前那种「等半径圆管」。
##
## 所以这里两处改动：
##   · 光柱从圆柱改成**锥形**（`bottom_radius` 在枪口那端更大，`top_radius` 远端更小）；
##   · 发射瞬间再乘一个**收缩系数** `shrink`（1 → 0，0.45 s 内），
##     让「一开始超大」那一下真的存在，而不是整段都一样粗。
const RAIL_CHARGE_TIME := 0.55       # 蓄力时长（秒），期间不放伤害
const RAIL_SHRINK_SEC := 0.22        # 枪口宽度从「超大」收到正常所用的时间
const CHARGE_RING_MAX := 5.2         # 蓄力环涨到多大（米，半径）
const CHARGE_RINGS := 3              # 几圈（错开相位，像参考图那样一层层）


## ── 蓄力（图 3/4/5）──
##
## 在枪口前方竖着放几圈光环，半径由小涨大、透明度先亮后灭，中间一颗核心球越蓄越大。
## 环面与射线方向**垂直**（用和光柱同一套 basis，环的局部 Y 轴对到 `dir`）。
## 全部用加色透明材质 + 不投影，和光柱同一套观感；结束时统一淡出并释放。
func _rail_charge(from: Vector3, dir: Vector3) -> void:
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var right := up.cross(dir).normalized()
	var realup := dir.cross(right).normalized()
	var basis := Basis(right, dir, realup)

	var holder := Node3D.new()
	holder.name = "RailCharge"
	_fx_root.add_child(holder)
	holder.global_position = from

	# 光环
	var rings: Array = []
	for i in CHARGE_RINGS:
		var mi := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.86
		tm.outer_radius = 1.0
		tm.rings = 32
		tm.ring_segments = 6
		mi.mesh = tm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := _add_mat(Color(0.70, 0.92, 1.00, 0.0), 5.0)
		mi.material_override = mat
		holder.add_child(mi)
		# 进树之后才能写 global_*；环面与射线垂直（局部 Y 轴对到 dir）
		mi.global_position = from + dir * 0.55
		mi.global_basis = basis
		rings.append({"mi": mi, "mat": mat, "phase": float(i) / float(CHARGE_RINGS)})

	# 核心球（越蓄越亮）
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 20
	sm.rings = 10
	core.mesh = sm
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cmat := _add_mat(Color(0.85, 0.97, 1.00, 0.0), 8.0)
	core.material_override = cmat
	_fx_root.add_child(core)
	core.global_position = from + dir * 0.55

	var t0 := Time.get_ticks_msec()
	var span := int(RAIL_CHARGE_TIME * 1000.0)
	while is_instance_valid(self):
		var el := Time.get_ticks_msec() - t0
		if el >= span:
			break
		var t := float(el) / float(span)
		for r in rings:
			# 每圈错开相位循环吞吐：0→1 涨大，透明度先亮后灭
			var k := fposmod(t + float(r["phase"]), 1.0)
			var mi: MeshInstance3D = r["mi"]
			var s := lerpf(0.35, CHARGE_RING_MAX, k)
			mi.global_basis = basis.scaled(Vector3(s, s, s))
			(r["mat"] as StandardMaterial3D).albedo_color.a = 0.75 * (1.0 - k)
		var cs := lerpf(0.28, 1.25, t)
		core.global_basis = Basis.from_scale(Vector3(cs, cs, cs))
		cmat.albedo_color.a = 0.35 + 0.45 * t
		await get_tree().process_frame
	if not is_instance_valid(self):
		return
	# 收尾：干净地清掉（发射的光柱接上）
	for r in rings:
		(r["mi"] as Node3D).queue_free()
	core.queue_free()
	holder.queue_free()


## 加色透明材质（光柱/蓄力共用），集中一处省得每层重复五行
func _add_mat(c: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = c
	mat.emission_enabled = true
	mat.emission = Color(c.r, c.g, c.b)
	mat.emission_energy_multiplier = energy
	return mat


# ═══════════════════════════════════════════════════════════════════
#  「假泛光」：FX 自己带光晕，不去动场景的 glow
# ═══════════════════════════════════════════════════════════════════
##
## 用户 2026-11-11 要求照参考图补足（参考图里那圈糊开的白光）。
##
## ⚠️ **不能靠拉高 `glow_intensity`**：`game.tscn` 是 0.25、`next_level.tscn` 只有 0.12，
##    这是为了灯管和室内不过曝特意压下去的（见 `mondrian_house.gd` 里那段记录：
##    「配 glow_intensity = 0.25 会在天花板上糊成一大团白」）。全局拉高 → 天花板先炸。
##
## 所以改成 FX 自带：程序生成一张**径向渐变**贴图（白芯→透明边），
## 贴在加色混合的 billboard 方片上当光晕。亮度靠 emission，形状靠贴图，
## 完全不依赖后处理，也不受场景 glow 强弱影响。
static var _HALO_TEX: GradientTexture2D


func _halo_tex() -> GradientTexture2D:
	if _HALO_TEX != null:
		return _HALO_TEX
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	_HALO_TEX = t
	return t


## 一片光晕（billboard 方片 + 径向渐变 + 加色）。`size` 是边长（米）。
func _halo(size: float, c: Color, energy: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := _add_mat(c, energy)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = _halo_tex()
	mi.material_override = mat
	return mi


# ═══════════════════════════════════════════════════════════════════
#  流线条纹：把噪声沿轴向拉成「一道道光条」，再让 UV 滚动
# ═══════════════════════════════════════════════════════════════════
##
## 参考图里的光柱不是均匀的糖葫芦色块，而是**一条条平行流线**在流动。
##
## 做法：`NoiseTexture2D`（FastNoiseLite 无缝噪声）当 albedo_texture，
## 把 `uv1_scale` 的 **V 方向压到很小**（0.12）—— 圆柱的 V 就是沿轴方向，
## 于是噪声被拉成很长的条纹；再每帧推 `uv1_offset.y`，看起来就是能量在往炮口外流。
## ⚠️ 噪声是程序生成的，不占仓库、也不依赖任何贴图资源。
static var _STREAK_TEX: NoiseTexture2D


func _streak_tex() -> NoiseTexture2D:
	if _STREAK_TEX != null:
		return _STREAK_TEX
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = 0.055
	n.fractal_octaves = 4
	var t := NoiseTexture2D.new()
	t.noise = n
	t.seamless = true
	t.width = 256
	t.height = 256
	_STREAK_TEX = t
	return t


## 给材质套上流线条纹（只在需要的那层调）。
## `stretch` 越小条纹越长；`around` 越大横向条纹越密。
func _add_streaks(mat: StandardMaterial3D, around := 6.0, stretch := 0.12) -> void:
	mat.albedo_texture = _streak_tex()
	mat.uv1_scale = Vector3(around, stretch, 1.0)
	# 噪声图默认是灰度，用 albedo_color 乘上去就变成「光条 + 底色」的层次
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR


## 弯月扫掠（参考图 1/2 那几道青蓝弧光）：
## 在 `at` 处生成两片**倾斜的月牙**，向外扩、同时淡出，然后自删。
## 月牙是自定义 ArrayMesh（见 `_crescent_mesh`），不是环 —— 环是等宽的一圈，
## 月牙是**中间厚两端尖**的一段弧，才是参考图那个「扫过去」的形状。
func _crescent(at: Vector3, dir: Vector3, radius: float, col: Color) -> void:
	var holder := Node3D.new()
	holder.name = "Crescent"
	_fx_root.add_child(holder)
	holder.global_position = at
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var right := up.cross(dir).normalized()
	var realup := dir.cross(right).normalized()
	holder.global_basis = Basis(right, dir, realup)

	var mats: Array = []
	for i in 2:
		var mi := MeshInstance3D.new()
		mi.mesh = _crescent_mesh(1.0, 150.0, 0.22)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := _add_mat(col, 6.0)
		mi.material_override = mat
		holder.add_child(mi)
		# 两片各自绕 X 倾斜不同角度 → 看起来像斜着扫过去的两道
		mi.rotation = Vector3(deg_to_rad(58.0 if i == 0 else 72.0), 0.0, deg_to_rad(-18.0 + 36.0 * i))
		mats.append(mat)
	holder.scale = Vector3.ONE * 0.25 * radius

	var tw := holder.create_tween()
	tw.set_parallel(true)
	tw.tween_property(holder, "scale", Vector3.ONE * radius, 0.34) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for m in mats:
		tw.tween_property(m, "albedo_color:a", 0.0, 0.34)
	tw.chain().tween_callback(holder.queue_free)


## 月牙网格：一段圆弧，**中间厚两端尖**（外弧半径 = radius，内弧 = radius − 宽度）。
## 宽度按 `sin(π·t)` 变化 ⇒ 两端收到 0，中间最厚。
## 平面朝 +Z（调用方用 basis 让它朝向射线方向）。
func _crescent_mesh(radius: float, arc_deg: float, thick: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 28
	var arc := deg_to_rad(arc_deg)
	for i in seg:
		var t0 := float(i) / float(seg)
		var t1 := float(i + 1) / float(seg)
		var a0 := -arc * 0.5 + arc * t0
		var a1 := -arc * 0.5 + arc * t1
		var w0 := thick * sin(PI * t0)
		var w1 := thick * sin(PI * t1)
		var o0 := Vector3(cos(a0), sin(a0), 0.0) * radius
		var o1 := Vector3(cos(a1), sin(a1), 0.0) * radius
		var i0 := Vector3(cos(a0), sin(a0), 0.0) * maxf(radius - w0, 0.0)
		var i1 := Vector3(cos(a1), sin(a1), 0.0) * maxf(radius - w1, 0.0)
		# 两个三角（双面材质，所以不用管绕序）
		st.add_vertex(o0)
		st.add_vertex(i0)
		st.add_vertex(o1)
		st.add_vertex(o1)
		st.add_vertex(i0)
		st.add_vertex(i1)
	return st.commit()


func _fire_railgun() -> void:
	var dir := _aim_dir()
	var froms: Array[Vector3] = [_muzzle_point()]
	if _weapon != null and _weapon.has_method("muzzle_count"):
		if int(_weapon.call("muzzle_count")) > 0:
			var arr: Array = _weapon.get("_carrier_muzzles")
			if arr.size() > 0:
				froms.clear()
				for v in arr:
					froms.append(v)
	_rail_fire(froms, dir)


func _rail_fire(froms: Array[Vector3], dir: Vector3) -> void:
	# ① 先蓄力（图 3/4/5）：一圈圈光环涨大 + 核心变亮，期间不结算伤害
	await _rail_charge(froms[0], dir)
	if not is_instance_valid(self) or froms.is_empty():
		return

	var space := _fx_root.get_world_3d().direct_space_state
	var t_fire := Time.get_ticks_msec()
	var t_end := t_fire + int(RAIL_DURATION * 1000.0)
	var next_tick := 0
	var tick_count := 0
	var total_hits := 0

	var beams: Array = []
	for f in froms.size():
		var holder := Node3D.new()
		holder.name = "RailBeam%d" % f
		_fx_root.add_child(holder)
		# 每层的 `r` = 常态半径比；`m` = 发射瞬间枪口端额外放大倍数（图 6/7/8 那团大光）
		#
		# ⚠️ 透明度要**外层很淡、核心极亮**：加色混合会叠加，
		#    第一版中间层给了 0.60，三层叠起来就成一块实心三角、没有发光感。
		# ⚠️ 2026-11-11 用户实机反馈：「我这个视角只能够看见一坨光」——
		#    因为 `m` 给到 4.2 时枪口端半径 7.66 m，站在炮口后面那是**糊满屏幕的一团**。
		#    现在 `m` 全部压到 1.5~1.9，收缩时间也从 0.45 s 缩到 0.22 s：
		#    仍然「一开始粗一点」，但不再糊屏。
		# ⚠️ 配色改**紫**（用户：「原作开大因为是超载会有紫色特效」）。
		var layer_specs := [
			{"r": 2.6, "m": 1.9, "c": Color(0.30, 0.15, 0.75, 0.07), "e": 1.0},
			{"r": 1.5, "m": 1.8, "c": Color(0.45, 0.22, 0.95, 0.14), "e": 1.8},
			{"r": 0.95, "m": 1.5, "c": Color(0.62, 0.45, 1.00, 0.24), "e": 3.2},
			{"r": 0.42, "m": 1.3, "c": Color(0.92, 0.88, 1.00, 0.88), "e": 11.0},
		]
		var mats: Array = []
		var cones: Array = []
		for li in layer_specs.size():
			var L: Dictionary = layer_specs[li]
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			# 锥形：枪口端（bottom，因为 holder 放在中点、-Y 朝枪口）粗，远端（top）细
			cm.bottom_radius = RAIL_WIDTH * float(L["r"])
			cm.top_radius = RAIL_WIDTH * float(L["r"]) * 0.55
			cm.height = 1.0
			cm.radial_segments = 24
			cm.rings = 1
			mi.mesh = cm
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var lmat := _add_mat(L["c"], float(L["e"]))
			# 外层两层加流线条纹（核心那两层保持干净，否则整根柱子会糊）
			if li <= 1:
				_add_streaks(lmat, 9.0, 0.10)
			mi.material_override = lmat
			holder.add_child(mi)
			mats.append(lmat)
			cones.append({"cm": cm, "r": float(L["r"]), "m": float(L["m"])})
		beams.append({"holder": holder, "mats": mats, "cones": cones,
			"halo": _halo(RAIL_WIDTH * 7.0, Color(0.72, 0.45, 1.00, 0.45), 5.5), "from": froms[f]})
		_fx_root.add_child(beams[beams.size() - 1]["halo"])

	while Time.get_ticks_msec() < t_end and is_instance_valid(self):
		await get_tree().process_frame
		if not is_instance_valid(self):
			return
		dir = _aim_dir()
		var now := Time.get_ticks_msec()

		for fi in froms.size():
			var from: Vector3 = froms[fi]
			if _weapon != null and _weapon.has_method("muzzle_count") \
					and int(_weapon.call("muzzle_count")) > 0:
				var arr2: Array = _weapon.get("_carrier_muzzles")
				if fi < arr2.size():
					from = arr2[fi]
			var endp := from + dir * RAIL_RANGE
			var q := PhysicsRayQueryParameters3D.create(from, endp)
			q.collide_with_areas = false
			# ⚠️ **射线必须排除自己**（玩家 CharacterBody3D）。
			#
			#    用户 2026-11-10：「爱丽丝机甲按 EX 就闪退」，调试器里 79 条
			#    `Invalid type in function 'take_damage' (via call) in base
			#     'CharacterBody3D (Player)'. Cannot convert argument 4 from Vector3 to float.`
			#    根因：射线从**炮口**出发（`_carrier_muzzles`），而机甲的炮口贴着机体，
			#    射线一出发就撞到自己身上 ⇒ `hit.collider` 是 Player ⇒
			#    下面 `hit.collider.has_method("take_damage")` 为真（Player 也有
			#    `take_damage`）⇒ 按「敌人」的签名（amount, hit_pos, hit_dir）传了
			#    **4 个参数**，而 `player.gd` 的是 `(amount, hit_from, knockback)`——
			#    第 4 个是 float。GDScript 的 `call` 参数类型不匹配会**硬崩**，
			#    每 0.06 s 一跳 × 两条射线，于是一按 EX 就刷屏式崩溃。
			#
			#    用 `exclude` 而不是「撞到自己就跳过」：后者会让光柱在自机位置上
			#    被截断，视觉上短一截。
			q.exclude = [_player]
			var hit := space.intersect_ray(q)
			var reach := RAIL_RANGE
			if not hit.is_empty():
				reach = from.distance_to(hit["position"])

			var b: Dictionary = beams[fi]
			var holder: Node3D = b["holder"]
			holder.global_position = from + dir * (reach * 0.5)
			var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
			var right := up.cross(dir).normalized()
			var realup := dir.cross(right).normalized()
			holder.global_basis = Basis(right, dir, realup)
			for mi in holder.get_children():
				if mi is MeshInstance3D:
					(mi as MeshInstance3D).scale = Vector3(1.0, reach, 1.0)
			# 枪口那团「超大」随时间收细（图 6/7/8 的关键手感）：
			# shrink 从 1 掉到 0，每层枪口端半径 = 常态 × (1 + (m−1) × shrink)
			var shrink := 1.0 - clampf(
				float(now - t_fire) / (RAIL_SHRINK_SEC * 1000.0), 0.0, 1.0)
			for cd in b["cones"]:
				var cm2: CylinderMesh = cd["cm"]
				var mult := 1.0 + (float(cd["m"]) - 1.0) * shrink
				cm2.bottom_radius = RAIL_WIDTH * float(cd["r"]) * mult
			# 枪口光晕跟着一起收细（假泛光，不依赖场景 glow）
			var mh: MeshInstance3D = b.get("halo")
			if mh != null and is_instance_valid(mh):
				mh.global_position = from + dir * 0.5
				mh.scale = Vector3.ONE * (1.0 + 1.6 * shrink)
				(mh.material_override as StandardMaterial3D).albedo_color.a = \
					0.28 + 0.45 * shrink
			# 流线条纹滚动：UV 沿轴向推，看起来能量在往外流
			for m in b["mats"]:
				var mm := m as StandardMaterial3D
				if mm.albedo_texture != null:
					mm.uv1_offset.y -= get_process_delta_time() * 2.4

			if now >= next_tick and not hit.is_empty():
				var col = hit.get("collider")
				# ⚠️ 第三道保险：**不给自己发伤害**。
				#    前两道是 `q.exclude = [_player]`（射线不撞自己）和
				#    `_can_hurt_take_damage()`（签名对不上就不调，见下面那个函数）。
				#    这里再挡一次是因为 `exclude` 认的是**节点身份**，而换场景 / 自检里
				#    `_player` 有可能已经失效或换了个实例，那时排除不生效。
				if col != null and col == _player:
					col = null
				if col != null and _can_hurt_take_damage(col):
					col.call("take_damage", RAIL_TICK_DAMAGE, hit["position"], -dir)
					total_hits += 1
				elif col is Node and (col as Node).get_parent() != null \
						and _can_hurt_take_damage((col as Node).get_parent()):
					(col as Node).get_parent().call("take_damage",
						RAIL_TICK_DAMAGE, hit["position"], -dir)
					total_hits += 1

			# ⚠️ 这一段必须在 `for fi in froms.size():` **循环体内**（缩进 3 个 tab），
			#    不能提到循环外 —— `now` / `next_tick` 都是循环里算出来的。
			#    本喵第一次改就是把缩进弄出去了，报 "Identifier now not declared"。
			if now >= next_tick:
				next_tick = now + int(RAIL_TICK_SEC * 1000.0)
				tick_count += 1

	for b in beams:
		var holder: Node3D = b["holder"]
		var mats: Array = b["mats"]
		var halo: MeshInstance3D = b.get("halo")
		var tw := holder.create_tween()
		tw.set_parallel(true)
		for m in mats:
			tw.tween_property(m, "albedo_color:a", 0.0, 0.18)
		tw.chain().tween_callback(holder.queue_free)
		if halo != null and is_instance_valid(halo):
			var htw := halo.create_tween()
			htw.set_parallel(true)
			htw.tween_property(halo.material_override, "albedo_color:a", 0.0, 0.18)
			htw.chain().tween_callback(halo.queue_free)

	print("[EX] 轨道炮结束：%d 跳 × %.0f = 最多 %.0f，命中 %d 次" % [
		tick_count, RAIL_TICK_DAMAGE, RAIL_TICK_DAMAGE * tick_count, total_hits])
