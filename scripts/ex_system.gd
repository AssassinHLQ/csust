extends Node3D
## EX 必杀系统（2026-11-09）—— 充能 + 两套必杀。
##
## ── 用户原话 ──
## 「爱丽丝普通状态,攻击从机枪变成激光机枪」
## 「按 EX 连按释放必杀技能：普通状态是蓄力激光球，机甲状态是蓄力激光巨型连续轨道炮。
##   EX 充能是随着时间增加的」
##
## ── 设计 ──
## 这个脚本**只管三件事**：攒能量、接 EX 键、按形态分派到两个必杀实现。
##   ① 充能：`EX_PER_SEC` 每秒自动涨，满了就停（不溢出、不存多管）。
##   ② 触发：按住 EX 开始蓄力，**松手才放**（用户说的「蓄力」）。
##           蓄力时间决定威力：0.35 s 起，1.2 s 封顶（`CHARGE_FULL_SEC`）。
##   ③ 分派：`carrier.is_on()` → 轨道炮；否则 → 激光球。
##
## ── 为什么「连按」也能放 ──
## 用户说「连按释放」。如果严格要求长按，点一下就松的人永远放不出来。
## 所以：按键本身立刻开始蓄力，**最短只要求 0.18 s**（`CHARGE_MIN_SEC`），
## 点一下（约 0.1 s）也能放出去，只是威力低。连按两次 = 两次小必杀。
## 这样「连按」和「蓄力」两种手感都满足。
##
## ── 依赖 ──
## 需要兄弟节点 `Weapon`（取枪口）与 `Player`（取相机/朝向）。
## 都由 `player.gd` 在 `_ready()` 里按名字挂，不存在时不崩、只是不放技能。

## 充满一管 EX 要多久（秒）。对齐「攒满 = 一场架里能放 2~3 次」。
const EX_FILL_SEC := 22.0
## 蓄力：最短（点一下）/ 封顶
const CHARGE_MIN_SEC := 0.18
const CHARGE_FULL_SEC := 1.20

var ex_ratio := 0.0            ## 0..1，HUD 直接读
var charging := false
var _charge_t := 0.0
var _armed := false            ## 已经按过 EX、还没放出去

var _player: Node3D
var _weapon: Node
var _carrier: Node
var _fx_root: Node3D


func setup(player: Node3D, weapon: Node, carrier: Node) -> void:
	_player = player
	_weapon = weapon
	_carrier = carrier
	# 特效挂在一个独立的 Node3D 下（跟着玩家走），方便整组清理
	_fx_root = Node3D.new()
	_fx_root.name = "ExFx"
	add_child(_fx_root)


## 现在是不是机甲形态（决定放哪个必杀）
func is_mech() -> bool:
	return _carrier != null and _carrier.has_method("is_on") and bool(_carrier.call("is_on"))


## EX 是否可用（充满 + 没在蓄力）
func is_ready() -> bool:
	return ex_ratio >= 1.0 and not _armed


func _process(delta: float) -> void:
	# ① 充能：满了停住，不做溢出
	if ex_ratio < 1.0 and not _armed:
		ex_ratio = minf(ex_ratio + delta / EX_FILL_SEC, 1.0)

	# ② 蓄力推进
	if _armed:
		_charge_t += delta
		charging = true


## EX 键按下：开始蓄力（扣掉这一管能量，放不放得出来都算花掉）
func press_ex() -> bool:
	if _armed or ex_ratio < 1.0:
		return false
	_armed = true
	_charge_t = 0.0
	charging = true
	ex_ratio = 0.0           # 一按就清零：防止「蓄力中被打断」变成无限能量
	return true


## EX 键松开：把蓄力放出去
func release_ex() -> bool:
	if not _armed:
		return false
	var t := clampf(_charge_t, CHARGE_MIN_SEC, CHARGE_FULL_SEC)
	var charge := t / CHARGE_FULL_SEC     # 0..1 归一化威力
	_armed = false
	charging = false
	_charge_t = 0.0

	if is_mech():
		_fire_railgun(charge)
	else:
		_fire_laser_orb(charge)
	return true


## 蓄力进度（0..1），给特效/HUD 画蓄力圈用
func charge_ratio() -> float:
	if not _armed:
		return 0.0
	return clampf(_charge_t / CHARGE_FULL_SEC, 0.0, 1.0)


# ═══════════════════════════════════════════════════════════════════
#  必杀 ①：普通状态 —— 蓄力激光球
# ═══════════════════════════════════════════════════════════════════
##
## 观感：一个蓝白色能量球在枪口前凝聚（蓄力越久越大越亮），
## 松开后**向前飞**，飞行途中留下一串光晕，命中时炸开成一个球形冲击波。
##
## 伤害：基础 350，蓄满 ×2.2 = 770。范围 3.2 m（蓄满 4.5 m）。
## 为什么不做成「即时命中」：球体飞行是「能看见的必杀」，
## 玩家能感知到自己在放大招，这是普通攻击给不了的正反馈。

const ORB_BASE_DAMAGE := 350.0
const ORB_FULL_MULT := 2.2
const ORB_SPEED := 42.0
const ORB_LIFE := 3.0
const ORB_BASE_RADIUS := 0.16
const ORB_FULL_RADIUS := 0.34
const ORB_BASE_AOE := 3.2
const ORB_FULL_AOE := 4.5


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


func _fire_laser_orb(charge: float) -> void:
	var dmg := ORB_BASE_DAMAGE * lerpf(1.0, ORB_FULL_MULT, charge)
	var radius := lerpf(ORB_BASE_RADIUS, ORB_FULL_RADIUS, charge)
	var aoe := lerpf(ORB_BASE_AOE, ORB_FULL_AOE, charge)

	var origin := _muzzle_point()
	var dir := _aim_dir()

	# ── 球体本体：三层球，加色混合 ──
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
		sm.radius = radius * float(L["r"])
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

	# 跟着球走的一盏灯（照亮经过的地方）
	var light := OmniLight3D.new()
	light.light_color = Color(0.55, 0.85, 1.0)
	light.light_energy = 4.0 * lerpf(0.7, 1.4, charge)
	light.omni_range = 6.0
	light.shadow_enabled = false
	holder.add_child(light)

	_orb_fly(holder, origin, dir, dmg, aoe, charge)


## 球的飞行与命中（用 `_process` 逐帧推进，不靠物理体 —— 必杀要保证打得中）
func _orb_fly(holder: Node3D, origin: Vector3, dir: Vector3, dmg: float,
		aoe: float, charge: float) -> void:
	var space := _fx_root.get_world_3d().direct_space_state
	var pos := origin
	var travelled := 0.0
	var step_total := ORB_SPEED * ORB_LIFE
	while travelled < step_total and is_instance_valid(holder):
		await get_tree().process_frame
		if not is_instance_valid(holder):
			return
		var dt := get_process_delta_time()
		var step := ORB_SPEED * dt
		var next := pos + dir * step
		var q := PhysicsRayQueryParameters3D.create(pos, next)
		q.collide_with_areas = false
		q.collide_with_bodies = true
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			holder.global_position = hit["position"]
			_orb_explode(holder, hit["position"], dmg, aoe, charge)
			return
		pos = next
		travelled += step
		holder.global_position = pos
	holder.queue_free()


## 命中爆开：球形冲击波 + 范围伤害
func _orb_explode(holder: Node3D, at: Vector3, dmg: float, aoe: float, charge: float) -> void:
	# 范围伤害：找附近所有可伤害的节点
	var hurt := 0
	for n in get_tree().get_nodes_in_group("bosses"):
		var b := n as Node3D
		if b == null:
			continue
		if b.global_position.distance_to(at) <= aoe and b.has_method("take_damage"):
			b.call("take_damage", dmg, at, Vector3.UP)
			hurt += 1
	# 也打普通 targets 组的
	for n in get_tree().get_nodes_in_group("targets"):
		var t := n as Node3D
		if t == null or not t.has_method("take_damage"):
			continue
		if t.global_position.distance_to(at) <= aoe:
			t.call("take_damage", dmg, at, Vector3.UP)
			hurt += 1

	# 视觉：冲击波球快速膨胀淡出
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
	tw.tween_property(burst, "scale", Vector3.ONE * aoe, 0.42) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.42)
	tw.chain().tween_callback(burst.queue_free)

	# 爆点的灯
	var light := OmniLight3D.new()
	light.light_color = Color(0.6, 0.88, 1.0)
	light.light_energy = 8.0
	light.omni_range = aoe * 2.4
	light.shadow_enabled = false
	_fx_root.add_child(light)
	light.global_position = at
	var lt := light.create_tween()
	lt.tween_property(light, "light_energy", 0.0, 0.5)
	lt.tween_callback(light.queue_free)

	holder.queue_free()
	print("[EX] 激光球命中：伤害 %.0f、范围 %.1f m、命中 %d 个目标（蓄力 %.0f%%）" % [
		dmg, aoe, hurt, charge * 100.0])


# ═══════════════════════════════════════════════════════════════════
#  必杀 ②：机甲状态 —— 蓄力激光巨型连续轨道炮
# ═══════════════════════════════════════════════════════════════════
##
## 观感：两肩炮口先凝聚能量（蓄力越久越粗），松手后射出一条**持续 0.9 s 的巨型光柱**，
## 光柱存续期间**每 0.06 s 结算一次伤害**（这就是「连续轨道炮」）。
##
## 伤害：每跳 90，蓄满 ×2.0 = 180；0.9 s ÷ 0.06 = 15 跳
##      ⇒ 蓄满共约 **2700**（足够点名一只 6000 血的霸王龙到半血）。
## 为什么用「多跳」而不是一炮轰掉：连续射击的手感是机甲的核心卖点，
## 一击秒杀反而无聊。

const RAIL_TICK_DAMAGE := 90.0
const RAIL_FULL_MULT := 2.0
const RAIL_DURATION := 0.9
const RAIL_TICK_SEC := 0.06
const RAIL_RANGE := 220.0
const RAIL_BASE_WIDTH := 0.35
const RAIL_FULL_WIDTH := 0.95


func _fire_railgun(charge: float) -> void:
	var dmg := RAIL_TICK_DAMAGE * lerpf(1.0, RAIL_FULL_MULT, charge)
	var width := lerpf(RAIL_BASE_WIDTH, RAIL_FULL_WIDTH, charge)
	var dir := _aim_dir()
	var origin := _muzzle_point()

	# 炮口可能有多个（机甲双肩炮），没有就用枪口那一个
	var froms: Array[Vector3] = [origin]
	if _weapon != null and _weapon.has_method("muzzle_count"):
		if int(_weapon.call("muzzle_count")) > 0:
			var arr: Array = _weapon.get("_carrier_muzzles")
			if arr.size() > 0:
				froms.clear()
				for v in arr:
					froms.append(v)

	_rail_fire(froms, dir, dmg, width, charge)


func _rail_fire(froms: Array[Vector3], dir: Vector3, dmg: float,
		width: float, charge: float) -> void:
	var space := _fx_root.get_world_3d().direct_space_state
	var t_end := Time.get_ticks_msec() + int(RAIL_DURATION * 1000.0)
	var next_tick := 0
	var tick_count := 0
	var total_hits := 0

	# 光柱本体：一个长圆柱 + 外层辉光，每帧更新长度（跟随相机朝向）
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
			cm.top_radius = width * float(L["r"])
			cm.bottom_radius = width * float(L["r"])
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

	# 持续期间逐帧刷新：位置/朝向/长度 + 周期性结算伤害
	while Time.get_ticks_msec() < t_end and is_instance_valid(self):
		await get_tree().process_frame
		if not is_instance_valid(self):
			return
		dir = _aim_dir()
		var now := Time.get_ticks_msec()

		for fi in froms.size():
			var from: Vector3 = froms[fi]
			# 机甲在动，炮口位置每帧得重新取
			if _weapon != null and _weapon.has_method("muzzle_count") \
					and int(_weapon.call("muzzle_count")) > 0:
				var arr2: Array = _weapon.get("_carrier_muzzles")
				if fi < arr2.size():
					from = arr2[fi]
			var endp := from + dir * RAIL_RANGE
			var q := PhysicsRayQueryParameters3D.create(from, endp)
			q.collide_with_areas = false
			var hit := space.intersect_ray(q)
			var reach := RAIL_RANGE
			if not hit.is_empty():
				reach = from.distance_to(hit["position"])

			var b: Dictionary = beams[fi]
			var holder: Node3D = b["holder"]
			holder.global_position = from + dir * (reach * 0.5)
			# 圆柱默认沿 +Y，转到 dir
			var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
			var right := up.cross(dir).normalized()
			var realup := dir.cross(right).normalized()
			holder.global_basis = Basis(right, dir, realup)
			for mi in holder.get_children():
				if mi is MeshInstance3D:
					(mi as MeshInstance3D).scale = Vector3(1.0, reach, 1.0)

			# 伤害结算（按 RAIL_TICK_SEC 节流，不是每帧）
			if now >= next_tick and not hit.is_empty():
				var col = hit.get("collider")
				if col != null and col.has_method("take_damage"):
					col.call("take_damage", dmg, hit["position"], -dir)
					total_hits += 1
				elif col is Node and (col as Node).get_parent() != null \
						and (col as Node).get_parent().has_method("take_damage"):
					(col as Node).get_parent().call("take_damage", dmg, hit["position"], -dir)
					total_hits += 1
		if now >= next_tick:
			next_tick = now + int(RAIL_TICK_SEC * 1000.0)
			tick_count += 1

	# 收尾：光柱淡出
	for b in beams:
		var holder: Node3D = b["holder"]
		var mats: Array = b["mats"]
		var tw := holder.create_tween()
		tw.set_parallel(true)
		for m in mats:
			tw.tween_property(m, "albedo_color:a", 0.0, 0.18)
		tw.chain().tween_callback(holder.queue_free)

	print("[EX] 轨道炮结束：%d 跳 × 每跳 %.0f = 最多 %.0f，命中 %d 次（蓄力 %.0f%%）" % [
		tick_count, dmg, dmg * tick_count, total_hits, charge * 100.0])
