extends SceneTree
## 验「开火前强制转向，且转到朝前（背对镜头）才出子弹」。
##
## 几何前提（实测，勿凭感觉改）：
##   相机挂在 rig 的 +Z 侧、看向 -Z → 相机视线 = -(sin(_yaw), cos(_yaw))
##   角色脸朝向 = (sin(_facing_yaw), cos(_facing_yaw))
##   「朝准星」= _facing_yaw = _yaw + PI
## 本测设在 _yaw = 0 → 准星指向 -Z，玩家 (6,-4) 正前方就是 Target1 (6,-10)。
##
## 判据用 model_root.rotation.y 的角度差（FIRE_ALIGN_TOLERANCE=0.38 rad≈22°）；
##   眼睛骨方向带横向偏移，**不能**当精确判据，只做定性核对。
##
## 用法：godot --path <工程> --script res://scripts/_verify_turnfire.gd

var _fail := 0
var _skel: Skeleton3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	await _wait(20)

	var player: Player = game.get_node("Player")
	var weapon: Weapon = game.get_node("Player/Weapon")
	var target: Target = game.get_node("Target1")
	_skel = game.get_node("Player/Arisu/Model/Aris_Original_Mesh/bone_root/Bip001/Skeleton3D")

	# 相机绕角 0 → 视线 -Z，正对 Target1；把模型强行转到 0（脸朝 +Z）→
	# 与准星方向正好差 180°，制造「背对准星」。
	player.global_position = Vector3(6, 0.05, -4)
	player._yaw = 0.0
	player._facing_yaw = player._yaw + PI
	player.rig.rotation.y = 0.0
	player.model_root.rotation.y = 0.0
	player._pitch = -0.02
	await _wait(2)
	player.model_root.rotation.y = 0.0

	print("========== 0. 制造朝向差 ==========")
	print("  相机视线 = %s" % str(player.camera_forward().snappedf(0.01)))
	print("  目标朝向 _facing_yaw = _yaw + PI = %.3f rad" % (player._yaw + PI))
	print("  当前 model_root.rotation.y  = %.3f rad" % player.model_root.rotation.y)
	print("  差值 = %.1f 度   is_aim_aligned = %s   align_error = %.1f 度" % [
		rad_to_deg(absf(wrapf(player._yaw + PI - player.model_root.rotation.y, -PI, PI))),
		str(player.is_aim_aligned()), player.align_error_deg()])
	_check(not player.is_aim_aligned(), "起手确实是「背对准星」")

	print("\n========== 1. 背对准星时扣扳机：不许出子弹 ==========")
	weapon.fire_interval = 0.05
	weapon._cooldown = 0.0
	weapon.spread_hip = 0.0
	weapon.spread_aim = 0.0
	var shots0 := weapon._shot_index
	var hp0 := target.health
	# 关掉玩家自己的**输入**处理：真实鼠标的「松开」事件会经 _input() / _poll_mouse_buttons()
	# 调 weapon.trigger_up()，把这条「按住不放」的测试链打断（mag 那套就是这么假红 6 条的）。
	# ⚠️ 只关输入，**不能**关 _physics_process —— 转身逻辑就跑在里面。
	player.set_process_input(false)
	weapon.trigger_down()
	# ⚠️ 这里必须等**物理帧**，不能等渲染帧：转身逻辑在 `_physics_process` 里，
	#    而 headless 的渲染帧可能慢到 6 fps —— 一帧渲染里能塞 10 个物理步，
	#    「2 帧」就够她转完 180°，断言必然假红（本轮实测：渲染帧 ×2 ⇒ 5°，
	#    物理帧 ×2 ⇒ 82°，判定才稳定）。
	await physics_frame
	await physics_frame
	var early := weapon._shot_index - shots0
	print("  扣扳机后 2 帧射出 %d 发（应 0）" % early)
	print("  此刻 align_error = %.1f 度   is_turning = %s   model.rot.y = %.3f" % [
		player.align_error_deg(), str(weapon.is_turning()), player.model_root.rotation.y])
	_check(early == 0, "没转到位前不出子弹")
	_check(target.health >= hp0, "没转到位前靶子不掉血")

	print("\n========== 2. 转向完成后自动开火 ==========")
	var guard := 0
	var first_at := -1
	var err_at_first := -1.0
	while guard < 3000:
		await physics_frame
		guard += 1
		if weapon._shot_index > shots0:
			first_at = guard
			err_at_first = player.align_error_deg()
			break
	print("  第 %d 帧开出第一枪   那一刻 align_error = %.1f 度（容差 22 度）" % [
		first_at, err_at_first])
	_check(first_at > 1, "是「先转身、后开火」而不是同帧开火")
	_check(err_at_first >= 0.0 and err_at_first <= 22.0,
		"开火时旋转误差在容差内（%.1f 度）" % err_at_first)

	print("\n========== 3. 对准之后连发正常，且子弹真的打在正前方的靶子上 ==========")
	var a := weapon._shot_index
	guard = 0
	# 按真实时间等（3 发 × fire_interval 0.05 s = 0.15 s；原来只给 300 帧，
	# 高帧率下 300 帧可能连 0.05 s 都不到）
	var t3 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t3 < 2000:
		await process_frame
		guard += 1
		if weapon._shot_index >= a + 3:
			break
	print("  又打了 %d 发   Target1 血量 %.0f → %.0f" % [
		weapon._shot_index - a, hp0, target.health])
	_check(weapon._shot_index >= a + 3, "对准后连发正常")
	_check(target.health < hp0, "子弹朝着准星飞（靶子掉血）")
	weapon.trigger_up()

	print("\n========== 4. 眼睛骨定性核对（不参与判定）==========")
	await _wait(120)
	# ⚠️ 先让角色**真的转到准星方向**再量。
	#    原来少了这一步，量到的是上一节开火结束时**残留的姿态** —— 判据于是依赖
	#    「模型刚好停在哪」，而不是「模型能不能对准」。7 名同伴加上枪之后帧率一变，
	#    残留姿态从「恰好同侧」变成「停在 -X」，这条就稳定红了（实测 84.5°，
	#    脸 (-1,0,-0.1) vs 准星 (0,0,-1)）—— 那是**断言的漏洞**，不是朝向坏了。
	#    这里直接按 `aim_dir` 的同一个 yaw 摆正，剩下的夹角就只剩眼骨固有偏差。
	player.model_root.rotation.y = player._yaw + PI
	await _wait(2)
	var aim_dir := _flat(Vector3(sin(player._yaw + PI), 0.0, cos(player._yaw + PI))).normalized()
	var bf := _face()
	print("  对准后：脸(眼骨量) %s   准星方向 %s   夹角 %.1f 度" % [
		str(bf.snappedf(0.01)), str(aim_dir.snappedf(0.01)),
		rad_to_deg(bf.angle_to(aim_dir))])
	print("  （眼骨量有几十度固有偏差，只说明「大致朝同一侧」）")
	_check(rad_to_deg(bf.angle_to(aim_dir)) < 75.0, "眼睛骨方向与准星同侧（定性）")

	print("\n========== 5. 转身耗时 ==========")
	player.model_root.rotation.y = 0.0
	await _wait(6)
	var frames := 0
	weapon._cooldown = 0.0
	weapon.trigger_down()
	while frames < 3000 and not player.is_aim_aligned():
		await process_frame
		frames += 1
	print("  从背对转到进入容差用了 %d 帧（headless ~6fps）" % frames)
	print("  真机 60fps、TURN_SMOOTH_FIRE=26 时，180° 约 0.15~0.2 秒")
	weapon.trigger_up()

	print("\n================ 结果 ================")
	print("失败 %d 项" % _fail)
	quit(1 if _fail > 0 else 0)


func _face() -> Vector3:
	var xf := _skel.global_transform
	var h: Vector3 = xf * _skel.get_bone_global_pose(_skel.find_bone("Bip001 Head")).origin
	var l: Vector3 = _skel.get_bone_global_pose(_skel.find_bone("Bip001 eye_L")).origin
	var r: Vector3 = _skel.get_bone_global_pose(_skel.find_bone("Bip001 eye_R")).origin
	var e: Vector3 = xf * ((l + r) * 0.5)
	return _flat(e - h).normalized()


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  [PASS] ", label)
	else:
		print("  [FAIL] ", label)
		_fail += 1


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
