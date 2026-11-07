extends SceneTree
## 一次性探针：**机甲（载具）形态下开火**到底发生了什么。
##
## 跑法：
##   & <godot> --headless --path . --script res://scripts/_probe_carrier_fire.gd -- --no-capture
##
## 要回答的问题：
##   ① 载具形态下 `Weapon` 还能不能开火（命中判定走相机中心，理论上能）
##   ② `Muzzle` 标记会不会**卡在原点**（找不到 `bone_Railgun_Muzzle_0*` 时）
##   ③ `AnimDriver` 在载具形态下是不是被跳过了（本体的 AnimDriver 挂在
##      `Arisu/Model` 下，载具是另一个节点 —— 它不知道机甲在开火）
##   ④ 载具骨架里有哪些骨可以当「枪口」用

const PlayerScene := preload("res://scenes/player.tscn")
const MechState := preload("res://scripts/mech_state.gd")
const CarrierForm := preload("res://scripts/carrier_form.gd")

var _player: Player
var _cf: CarrierForm
var _wpn: Weapon
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
	_player = root_node as Player
	await process_frame
	await process_frame

	_wpn = _player.get_node_or_null("Weapon") as Weapon
	_cf = _player.get_node_or_null("Arisu/CarrierForm") as CarrierForm
	_ok(_wpn != null, "Weapon 节点在")
	_ok(_cf != null, "CarrierForm 节点在")
	if _wpn == null or _cf == null:
		_done()
		return

	print("\n===== 1. 本体形态：基线 =====")
	var muzzle_before := _wpn.muzzle.global_position
	print("       Muzzle 世界坐标（本体）：%s" % str(muzzle_before.snappedf(0.001)))
	_ok(_wpn.skeleton != null, "本体 Weapon 找得到骨架")
	print("       Weapon 骨架骨头数：%d" % (_wpn.skeleton.get_bone_count() if _wpn.skeleton else -1))

	print("\n===== 2. 变形成机甲 =====")
	_ok(_cf.set_form(true), "变形成功")
	await process_frame

	# 载具骨架（CarrierForm 内部私有，通过反射拿不到就自己找）
	var carrier_skel := _find_carrier_skeleton()
	_ok(carrier_skel != null, "找得到载具骨架")
	if carrier_skel != null:
		print("       载具骨架骨头数：%d" % carrier_skel.get_bone_count())
		for bn in ["Bip001_Weapon", "fire_01", "bone_buttstack",
				"bone_energypack_01", "bone_gear_cannon_L", "bone_gear_cannon_R"]:
			var bi := carrier_skel.find_bone(bn)
			print("         %-22s index=%d" % [bn, bi])

	print("\n===== 3. 机甲形态下 Muzzle 还重不重要 =====")
	await process_frame
	var muzzle_after := _wpn.muzzle.global_position
	print("       Muzzle 世界坐标（机甲）：%s" % str(muzzle_after.snappedf(0.001)))
	var drift := (muzzle_after - muzzle_before).length()
	print("       变形前后 Muzzle 位移：%.3f m" % drift)
	# ⚠️ 不再断言「Muzzle 必须在地面之上」：本体的轨道枪本来就挂在腰侧，
	#    `bone_Railgun_Muzzle_*` 的原点实测 y ≈ 0（`_probe_carrier_fire` 第一版
	#    量出 -0.008），所以「Muzzle 低」不是 bug、是那把枪的真实位置。
	#    真正该断言的是：**机甲形态下 `Weapon` 不再用这个标记**（改用两门肩炮）。
	#    见第 4 节 `muzzle_count() == 2` 与 `_follow_muzzle_bone()` 的提前返回。
	print("       （Muzzle 是否被使用，交给第 4 节的 muzzle_count 断言）")

	print("\n===== 4. 机甲形态能不能开火 =====")
	# 先把炮口推一遍（正常游戏里 `_tick_flight()` 每帧都会做这件事）
	_cf.call("_push_cannon_muzzles")
	var muzzles: Array = _wpn.get("_carrier_muzzles")
	print("       喂给 Weapon 的炮口数：%d" % muzzles.size())
	_ok(muzzles.size() == 2, "两门炮的枪口都喂进去了（实际 %d）" % muzzles.size())
	for i in muzzles.size():
		var mp: Vector3 = muzzles[i]
		print("         炮口 %d 世界坐标 %s" % [i, str(mp.snappedf(0.001))])
		_ok(mp.y > 0.05, "炮口 %d 在地面之上（y=%.3f）" % [i, mp.y])

	# Muzzle 标记现在应该被 `Weapon` 的机甲路径**跳过**（`_follow_muzzle_bone` 直接 return），
	# 所以不动它，只确认不会被用到地底下去。
	_ok(_wpn.muzzle_count() == 2, "Weapon.muzzle_count() = 2（双炮）")

	_wpn.current_ammo = _wpn.magazine_size
	_wpn.set("_cooldown", 0.0)
	var ammo_before := _wpn.current_ammo
	var ok1 := _wpn.shoot()
	print("       shoot() 返回 %s，弹药 %d → %d" % [str(ok1), ammo_before, _wpn.current_ammo])
	_ok(ok1, "机甲形态下 shoot() 成功")
	_ok(_wpn.current_ammo == ammo_before - 1, "弹药确实减了 1")

	# 连开 5 发，确认不会卡住
	var fired := 0
	for i in 5:
		_wpn.set("_cooldown", 0.0)
		if _wpn.shoot():
			fired += 1
	_ok(fired == 5, "连开 5 发都成功（实际 %d）" % fired)

	print("\n===== 5. 炮口焰 + 后坐 =====")
	print("       炮口焰节点数：%d" % _cf.cannon_fx_count)
	_ok(_cf.cannon_fx_count == 2, "两门炮都建了焰口（实际 %d）" % _cf.cannon_fx_count)
	# 开火后跑一帧，`_run_cannon_flash` 应该把焰口点亮
	_cf.call("_run_effects", 1.0 / 60.0)
	var fx: Array = _cf.get("_cannon_fx")
	var lit := 0
	for f in fx:
		if (f["holder"] as Node3D).visible:
			lit += 1
	print("       开火后亮着的焰口：%d / %d" % [lit, fx.size()])
	_ok(lit >= 2, "开火后两门炮的焰口都亮了（实际 %d）" % lit)
	var recoil: float = float(_cf.get("_cannon_recoil"))
	print("       后坐脉冲：%.2f" % recoil)
	_ok(recoil > 0.5, "开火触发了后坐脉冲（%.2f > 0.5）" % recoil)

	print("\n===== 6. 炮口跟随骨骼（不是静态坐标）=====")
	var before0: Vector3 = (_cf.get("_cannon_fx")[0]["holder"] as Node3D).global_position
	# 把玩家挪 1 m，炮口应该跟着动
	_player.global_position += Vector3(1.0, 0.5, 0.0)
	_cf.call("_push_cannon_muzzles")
	_cf.call("_run_effects", 1.0 / 60.0)
	var after0: Vector3 = (_cf.get("_cannon_fx")[0]["holder"] as Node3D).global_position
	var moved := (after0 - before0).length()
	print("       玩家移动 (1,0.5,0) 后炮口位移：%.3f m" % moved)
	_ok(moved > 0.8, "炮口跟着角色动（位移 %.3f m）" % moved)

	print("\n===== 7. AnimDriver 知不知道机甲在开火 =====")
	var driver := _player.get_node_or_null("Arisu/Model/AnimDriver")
	_ok(driver != null, "本体 AnimDriver 仍在")
	if driver != null:
		print("       AnimDriver.state = %s，当前 clip = %s" % [
			str(driver.get("state")), str(driver.call("current_clip"))])
	# 机甲形态下 `Arisu` 子节点整个隐藏、AnimDriver 驱动的本体骨架不在画面上，
	# 所以它演什么不影响观感 —— 但载具自己没有开火动画，这是已知缺口。
	print("       （已知缺口：载具 glb 只有 Idle/Walk，没开火动作）")

	print("\n===== 8. 变回本体要清掉炮口 =====")
	_cf.set_form(false)
	var muzzles_after: Array = _wpn.get("_carrier_muzzles")
	_ok(muzzles_after.is_empty(), "变回本体后炮口清空（实际 %d 个）" % muzzles_after.size())
	_ok(_wpn.muzzle_count() == 1, "muzzle_count() 退回 1（单枪口）")

	MechState.set_carrier_for_test(false)
	_done()


func _find_carrier_skeleton() -> Skeleton3D:
	# 载具实例挂在 `Arisu/CarrierForm` 下；找骨头最多的那具
	var best: Skeleton3D = null
	var stack: Array[Node] = [_cf]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Skeleton3D:
			var s := n as Skeleton3D
			if best == null or s.get_bone_count() > best.get_bone_count():
				best = s
		for c in n.get_children():
			stack.append(c)
	return best


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
