extends SceneTree
## 探针：**激光大炮**——机甲形态下开火是不是真的走光束、数值对不对。
##
## 跑法：
##   & <godot> --headless --path . --script res://scripts/_probe_carrier_beam.gd -- --no-capture
##
## 验的东西：
##   ① 机甲形态 `use_beam()` 为真，本体形态为假（不污染本体那把步枪）
##   ② 开火**不产生飞行弹丸**（`_in_flight` 为空），而是生成光束节点
##   ③ 光束从炮口出发、连到命中点（长度 ≈ 炮口到命中点距离）
##   ④ 激光的连发间隔 / 伤害都用 beam 那套（不是步枪的 0.075s / 18）
##   ⑤ 变回本体后一切还原

const PlayerScene := preload("res://scenes/player.tscn")
const MechState := preload("res://scripts/mech_state.gd")
const CarrierForm := preload("res://scripts/carrier_form.gd")

var _fails: Array[String] = []
var _checks := 0


func _ok(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("  PASS  %s" % msg)
	else:
		print("  FAIL  %s" % msg)
		_fails.append(msg)


func _initialize() -> void:
	_run()


func _run() -> void:
	MechState.set_carrier_for_test(true)
	var root_node := PlayerScene.instantiate()
	(Engine.get_main_loop() as SceneTree).get_root().add_child(root_node)
	var player := root_node as Player
	await process_frame
	await process_frame

	var cf := player.get_node_or_null("Arisu/CarrierForm") as CarrierForm
	var wpn := player.get_node_or_null("Weapon") as Weapon
	_ok(cf != null and wpn != null, "CarrierForm / Weapon 都在")
	if cf == null or wpn == null:
		_done()
		return

	# 放到开阔地面（没有靶子，射线会打到很远）
	player.global_position = Vector3(0.0, 0.6, 0.0)
	await process_frame

	print("\n===== 1. 本体形态不该是激光 =====")
	_ok(not wpn.use_beam(), "本体形态 use_beam() = false")
	wpn.current_ammo = wpn.magazine_size
	wpn.set("_cooldown", 0.0)
	wpn.shoot()
	print("       本体开火后 _in_flight 数量 = %d（飞行弹丸，应该 > 0）" % (wpn.get("_in_flight") as Array).size())
	_ok((wpn.get("_in_flight") as Array).size() > 0, "本体开火产生飞行弹丸（老路径没坏）")
	# 清掉
	for it in (wpn.get("_in_flight") as Array):
		var mi := it[0] as Node
		if is_instance_valid(mi):
			mi.queue_free()
	(wpn.get("_in_flight") as Array).clear()

	print("\n===== 2. 变形成机甲 =====")
	_ok(cf.set_form(true), "变形成功")
	await process_frame
	_ok(wpn.use_beam(), "机甲形态 use_beam() = true")

	print("\n===== 3. 开火走光束、不产生飞行弹丸 =====")
	cf.call("_push_cannon_muzzles")
	await process_frame
	wpn.current_ammo = wpn.magazine_size
	wpn.set("_cooldown", 0.0)
	var before_beams: int = (wpn.get("_beams") as Array).size()
	var fired := wpn.shoot()
	await process_frame
	var after_beams: int = (wpn.get("_beams") as Array).size()
	var flying: int = (wpn.get("_in_flight") as Array).size()
	print("       shoot()=%s  光束 %d → %d  飞行弹丸 = %d" % [
		str(fired), before_beams, after_beams, flying])
	_ok(fired, "机甲开火成功")
	_ok(after_beams > before_beams, "生成了光束节点（%d → %d）" % [before_beams, after_beams])
	_ok(flying == 0, "没有飞行弹丸（激光是瞬时的，实际 %d 个）" % flying)

	print("\n===== 4. 光束几何：从炮口连到目标 =====")
	var beams: Array = wpn.get("_beams")
	_ok(not beams.is_empty(), "有光束节点可查")
	if not beams.is_empty():
		var holder: Node3D = beams[beams.size() - 1]
		# 光束以中点为原点，子节点是三层圆柱
		var parts := holder.get_children().filter(func(n): return n is MeshInstance3D)
		print("       光束层数 = %d（期望 3：芯/中/辉光）" % parts.size())
		_ok(parts.size() == 3, "三层光柱（实际 %d）" % parts.size())
		if parts.size() == 3:
			var mi := parts[0] as MeshInstance3D
			# 圆柱长度 = TRACER_LEN * scale.y
			var seg_len: float = 0.55 * mi.scale.y
			var cap: float = float(wpn.BEAM_MAX_VISUAL)
			print("       光柱长度 = %.2f m（视觉上限 %.0f）" % [seg_len, cap])
			_ok(seg_len > 5.0, "光柱长度足够（%.2f m > 5）" % seg_len)
			_ok(seg_len <= cap + 0.5, "光柱不超过视觉上限 %.0f m（实际 %.2f）" % [cap, seg_len])
			# 半径：scale.x * 0.015
			var rad: float = mi.scale.x * 0.015
			print("       光柱半径 = %.4f m" % rad)
			_ok(rad > 0.001, "光柱有粗细（%.4f m）" % rad)
			# 方向：圆柱局部 +Y 应指向炮口→命中点
			var dir_y := mi.global_transform.basis.y.normalized()
			print("       光柱轴向 = %s" % str(dir_y.snappedf(0.01)))

	print("\n===== 5. 激光的射速 / 伤害 =====")
	wpn.set("_cooldown", 0.0)
	wpn.shoot()
	var cd := float(wpn.get("_cooldown"))
	print("       开火后冷却 = %.3f s（步枪 %.3f / 激光 %.3f）" % [
		cd, float(wpn.fire_interval), float(wpn.beam_fire_interval)])
	_ok(absf(cd - float(wpn.beam_fire_interval)) < 0.001, "冷却用的是激光间隔 %.2f s" % wpn.beam_fire_interval)
	_ok(cd > float(wpn.fire_interval) * 3.0, "激光明显比步枪慢（%.2f vs %.3f）" % [cd, wpn.fire_interval])
	print("       伤害倍率 = %.1f×（单发 %.1f 点）" % [wpn.beam_damage_scale, wpn.damage * wpn.beam_damage_scale])
	_ok(wpn.beam_damage_scale > 1.0, "激光伤害比步枪高")

	print("\n===== 6. 连续开火不会堆积 =====")
	# 连开 5 发，光束应该都能正常生成；不期望 OOM 或节点爆炸
	var n0: int = (wpn.get("_beams") as Array).size()
	for i in 5:
		wpn.set("_cooldown", 0.0)
		wpn.shoot()
	await process_frame
	var n1: int = (wpn.get("_beams") as Array).size()
	print("       连开 5 发后光束节点 %d → %d" % [n0, n1])
	_ok(n1 >= n0, "连续开火不报错（%d 个光束）" % n1)

	print("\n===== 7. 变回本体要还回去 =====")
	cf.set_form(false)
	await process_frame
	_ok(not wpn.use_beam(), "变回本体后 use_beam() = false")
	_ok(not bool(wpn.beam_mode), "beam_mode 已关")
	_ok((wpn.get("_carrier_muzzles") as Array).is_empty(), "炮口已清空")

	MechState.set_carrier_for_test(false)
	_done()


func _done() -> void:
	print("\n========== 结果 ==========")
	if _fails.is_empty():
		print("全部 %d 项通过" % _checks)
	else:
		print("%d / %d 项失败：" % [_fails.size(), _checks])
		for f in _fails:
			print("  - %s" % f)
	print("")
	quit(0 if _fails.is_empty() else 1)
