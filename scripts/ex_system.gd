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


func _muzzle_point() -> Vector3:
	if _weapon != null:
		var m := _weapon.get_node_or_null("Muzzle") as Node3D
		if m != null:
			return m.global_position
	if _player != null:
		return _player.global_position + Vector3.UP * 1.4
	return global_position


func _aim_dir() -> Vector3:
	if _player != null and _player.has_method("camera_forward"):
		var d: Vector3 = _player.call("camera_forward")
		if d.length_squared() > 0.001:
			return d.normalized()
	return -global_transform.basis.z


func _fire_laser_orb() -> void:
	var origin := _muzzle_point()
	var dir := _aim_dir()

	var holder := Node3D.new()
	holder.name = "LaserOrb"
	_fx_root.add_child(holder)
	holder.global_position = origin

	var layers := [
		{"r": 1.00, "c": Color(0.55, 0.90, 1.00, 0.85), "e": 6.0},
		{"r": 0.62, "c": Color(0.85, 0.97, 1.00, 0.95), "e": 9.0},
		{"r": 0.30, "c": Color(1.00, 1.00, 1.00, 1.00), "e": 14.0},
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
	light.light_color = Color(0.55, 0.85, 1.0)
	light.light_energy = 5.6
	light.omni_range = 6.0
	light.shadow_enabled = false
	holder.add_child(light)

	_orb_fly(holder, origin, dir)


func _orb_fly(holder: Node3D, origin: Vector3, dir: Vector3) -> void:
	var space := _fx_root.get_world_3d().direct_space_state
	var pos := origin
	var travelled := 0.0
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


func _orb_explode(holder: Node3D, at: Vector3) -> void:
	var hurt := 0
	for n in get_tree().get_nodes_in_group("bosses"):
		var b := n as Node3D
		if b != null and b.global_position.distance_to(at) <= ORB_AOE \
				and b.has_method("take_damage"):
			b.call("take_damage", ORB_DAMAGE, at, Vector3.UP)
			hurt += 1
	for n in get_tree().get_nodes_in_group("targets"):
		var t := n as Node3D
		if t != null and t.has_method("take_damage") \
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
	mat.albedo_color = Color(0.75, 0.94, 1.0, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.85, 1.0)
	mat.emission_energy_multiplier = 10.0
	burst.material_override = mat
	_fx_root.add_child(burst)
	burst.global_position = at
	burst.scale = Vector3.ONE * 0.2

	var tw := burst.create_tween()
	tw.set_parallel(true)
	tw.tween_property(burst, "scale", Vector3.ONE * ORB_AOE, 0.42) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.42)
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
	var space := _fx_root.get_world_3d().direct_space_state
	var t_end := Time.get_ticks_msec() + int(RAIL_DURATION * 1000.0)
	var next_tick := 0
	var tick_count := 0
	var total_hits := 0

	var beams: Array = []
	for f in froms.size():
		var holder := Node3D.new()
		holder.name = "RailBeam%d" % f
		_fx_root.add_child(holder)
		var layer_specs := [
			{"r": 1.8, "c": Color(0.28, 0.55, 1.00, 0.20), "e": 1.2},
			{"r": 1.0, "c": Color(0.50, 0.80, 1.00, 0.60), "e": 3.5},
			{"r": 0.42, "c": Color(0.90, 0.98, 1.00, 0.95), "e": 9.0},
		]
		var mats: Array = []
		for L in layer_specs:
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = RAIL_WIDTH * float(L["r"])
			cm.bottom_radius = RAIL_WIDTH * float(L["r"])
			cm.height = 1.0
			cm.radial_segments = 16
			cm.rings = 1
			mi.mesh = cm
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
			mats.append(mat)
		beams.append({"holder": holder, "mats": mats})

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
		var tw := holder.create_tween()
		tw.set_parallel(true)
		for m in mats:
			tw.tween_property(m, "albedo_color:a", 0.0, 0.18)
		tw.chain().tween_callback(holder.queue_free)

	print("[EX] 轨道炮结束：%d 跳 × %.0f = 最多 %.0f，命中 %d 次" % [
		tick_count, RAIL_TICK_DAMAGE, RAIL_TICK_DAMAGE * tick_count, total_hits])
