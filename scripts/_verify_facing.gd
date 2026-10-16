extends SceneTree
## 专测「停止后保持朝向」。判据收紧到变量层，不做角度插值比较。
## 用法：godot --path <工程> --script res://scripts/_verify_facing.gd

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	await _wait(20)

	var player: Player = game.get_node("Player")
	var skel: Skeleton3D = game.get_node("Player/Arisu/Model/Aris_Original_Mesh/bone_root/Bip001/Skeleton3D")
	var fail := 0

	print("========== 1. 出生时镜头应在角色背后（看到后脑勺）==========")
	# 需求：一进场就是标准越肩视角 —— 相机在角色背后，角色面朝场地深处的靶区。
	# 判据：脸与「角色→相机」反向（点积 ≈ -1）。
	var to_cam := _flat(player.cam.global_position - player.global_position).normalized()
	var f0 := _face(skel)
	print("  脸 %s   角色→相机 %s   点积 %+.2f（-1 = 背对镜头）" % [
		str(f0.snappedf(0.01)), str(to_cam.snappedf(0.01)), f0.dot(to_cam)])
	if f0.dot(to_cam) < -0.7:
		print("  [PASS] 出生时镜头在角色背后，看不到正脸")
	else:
		print("  [FAIL] 出生时镜头还在角色前面"); fail += 1
	# 再确认脸真的朝着靶区（-Z），而不是朝着场地外围
	var arena := Vector3(0.0, 0.0, -1.0)
	print("  脸·(朝靶区 -Z) = %+.2f" % f0.dot(arena))
	if f0.dot(arena) > 0.7:
		print("  [PASS] 出生时角色面朝靶区（-Z）")
	else:
		print("  [FAIL] 出生时角色没朝靶区"); fail += 1
	# 相机视线也应该指向靶区
	var cfwd := _flat(player.camera_forward()).normalized()
	print("  相机视线 %s   与 -Z 点积 %+.2f" % [str(cfwd.snappedf(0.01)), cfwd.dot(arena)])
	if cfwd.dot(arena) > 0.9:
		print("  [PASS] 出生时相机视线指向靶区")
	else:
		print("  [FAIL] 出生时相机看向空场地（就是「一进去看不见靶子」的毛病）"); fail += 1

	print("\n========== 2. 向右跑，等转向收敛 ==========")
	Input.action_press("move_right")
	await _wait(180)
	var vel := _flat(player.velocity).normalized()
	# ⚠️ 判据用 **`model_root.rotation.y`**（代码真正控制的那个角），**不要用眼骨**：
	#    眼骨在头局部带横向偏移、头部动画又一直在摆，实测哪怕站得笔直，
	#    「眼睛中点 − 头骨」与真实朝向也恒定差约 46°（`player.gd` 顶部那段）。
	#    这里把它顺带打出来当参考：2026-10 把「走路」从 `Cafe_Walk` 换成 `Move_Ing`
	#    （§1.17）之后，奔跑循环的头部摆动比漫步大，**同一个采样点**从 ~9° 变成 ~15° ——
	#    朝向本身一点没变（rig 差 0.0°），变的只是**姿势**。旧写法只卡眼骨 10°，
	#    于是这条断言测的其实是「采样到循环的哪一帧」。
	var rig_err := rad_to_deg(absf(angle_difference(atan2(vel.x, vel.z),
		player.model_root.rotation.y)))
	var f_moving := _face(skel)
	var eye_err := rad_to_deg(f_moving.angle_to(vel))
	print("  移动 %s   朝向 rig %+.3f rad（差 %.1f 度）   眼-头方向 %s（差 %.1f 度，含动画摆动）"
		% [str(vel.snappedf(0.01)), player.model_root.rotation.y, rig_err,
			str(f_moving.snappedf(0.01)), eye_err])
	if rig_err < 5.0 and eye_err < 30.0:
		print("  [PASS] 跑动时脸朝移动方向")
	else:
		print("  [FAIL] 跑动时脸没朝移动方向"); fail += 1

	print("\n========== 3. 松开按键 → 朝向必须完全冻结 ==========")
	Input.action_release("move_right")
	# 只等 3 帧：此时 lerp 还没收敛，正好检验「目标角度有没有被改掉」
	await _wait(3)
	var facing_a := player._facing_yaw
	var rot_a := player.model_root.rotation.y
	var cam_yaw_a := player._yaw
	print("  松开后 3 帧:  facing_yaw=%.4f  model.rot.y=%.4f  相机_yaw=%.4f" % [
		facing_a, rot_a, cam_yaw_a])
	await _wait(180)
	var facing_b := player._facing_yaw
	var rot_b := player.model_root.rotation.y
	print("  再等 180 帧: facing_yaw=%.4f  model.rot.y=%.4f  相机_yaw=%.4f" % [
		facing_b, rot_b, player._yaw])
	if absf(facing_b - facing_a) < 0.0001:
		print("  [PASS] facing_yaw 停止后不变（角色没有转回去）")
	else:
		print("  [FAIL] facing_yaw 变了 %.4f → %.4f" % [facing_a, facing_b]); fail += 1
	if absf(rot_b - rot_a) < 0.0001:
		print("  [PASS] model.rotation.y 停止后不再变化（转向已收敛完成）")
	else:
		print("  [FAIL] model.rotation.y 还在动 %.4f → %.4f" % [rot_a, rot_b]); fail += 1

	print("\n========== 4. 站着大幅转视角，角色不该跟着转 ==========")
	var f_before := _face(skel)
	var rot_before := player.model_root.rotation.y
	for i in 45:
		var ev := InputEventMouseMotion.new()
		ev.relative = Vector2(28, 0)
		ev.screen_relative = Vector2(28, 0)
		Input.parse_input_event(ev)
		await process_frame
	await _wait(40)
	var f_after := _face(skel)
	print("  相机 _yaw 转了 %.1f 度" % rad_to_deg(player._yaw))
	print("  转前 脸 %s   转后 脸 %s   漂移 %.2f 度" % [
		str(f_before.snappedf(0.01)), str(f_after.snappedf(0.01)),
		rad_to_deg(f_before.angle_to(f_after))])
	if absf(player.model_root.rotation.y - rot_before) < 0.0001:
		print("  [PASS] 转视角时角色朝向不动")
	else:
		print("  [FAIL] 转视角把角色带转了"); fail += 1

	print("\n========== 5. 开镜时朝向应跟准星方向一致（背对相机）==========")
	player._set_aiming(true)
	# 转向是带阻尼的 lerp（TURN_SMOOTH=14），headless 帧率低，要给足时间收敛
	await _wait(1200)
	var f_aim := _face(skel)
	# ⚠️ 判据用「相机视线方向」，不要用 (sin(_yaw),cos(_yaw))：
	#    相机挂在 rig 的 +Z 侧、看向 -Z，所以视线 = -(sin(_yaw),cos(_yaw))，
	#    角色要背对镜头就是 _facing_yaw = _yaw + PI。
	var want := Vector3(sin(player._yaw + PI), 0.0, cos(player._yaw + PI))
	var d := rad_to_deg(f_aim.angle_to(want))
	print("  脸 %s   期望朝向(相机视线) %s   夹角 %.1f 度" % [
		str(f_aim.snappedf(0.01)), str(want.snappedf(0.01)), d])
	print("  facing_yaw=%.4f  model.rot.y=%.4f  camera_yaw=%.4f" % [
		player._facing_yaw, player.model_root.rotation.y, player._yaw])
	# 容差说明：眼睛骨判据在头部有动画偏转时会有几十度的固定偏差
	# （眼骨在头局部不是纯前方，而是带横向偏移）。所以这里只验证
	# 「朝向跟随相机、且背对镜头」，不用它做精确角度断言。
	if d < 75.0:
		print("  [PASS] 开镜时朝向跟随相机（朝准星）")
	else:
		print("  [FAIL] 开镜时朝向没跟上相机（差 %.1f 度）" % d); fail += 1
	# 更硬的一条：脸必须与「相机→角色」同向（背对镜头）
	var to_move := _flat(player.global_position - player.cam.global_position).normalized()
	if f_aim.dot(to_move) > 0.7:
		print("  [PASS] 开镜时背对镜头（点积 %+.2f）" % f_aim.dot(to_move))
	else:
		print("  [FAIL] 开镜时正对镜头（点积 %+.2f）" % f_aim.dot(to_move)); fail += 1
	player._set_aiming(false)

	print("\n========== 6. 滚轮拉近 / 拉远 ==========")
	# 这一条是补的：README §1.1 和 HUD 提示里一直写着「滚轮 拉近拉远」，
	# 但代码里**从来没实现过**（用户报「滚轮的摄像头远近没有生效」）。
	# 现在 player.gd 的 _input 处理滚轮，改的是 _zoom_distance（腰射距离），
	# 开镜时仍然走 aim_distance。
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if player.aiming:
		player._set_aiming(false)
	var base := player.spring.spring_length
	var wheel_down := InputEventMouseButton.new()
	wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_down.pressed = true
	player._input(wheel_down)
	await _wait(60)
	print("  下滚一格：_zoom_distance = %.2f  spring_length = %.2f（原 %.2f）" % [
		player._zoom_distance, player.spring.spring_length, base])
	if player._zoom_distance > player.hip_distance:
		print("  [PASS] 下滚把距离推远了（%.2f > 默认 %.2f）" % [player._zoom_distance, player.hip_distance])
	else:
		print("  [FAIL] 下滚没有改变距离（%.2f）" % player._zoom_distance); fail += 1
	if player.spring.spring_length > base + 0.1:
		print("  [PASS] 相机真的被推远了（%.2f → %.2f）" % [base, player.spring.spring_length])
	else:
		print("  [FAIL] 相机长度没变（%.2f → %.2f）" % [base, player.spring.spring_length]); fail += 1

	for _i in 60:
		player._input(wheel_down)
	await _wait(80)
	print("  连滚到底：_zoom_distance = %.2f（zoom_max = %.2f）" % [
		player._zoom_distance, player.zoom_max])
	if is_equal_approx(player._zoom_distance, player.zoom_max):
		print("  [PASS] 到底被 zoom_max 卡住")
	else:
		print("  [FAIL] 没被 zoom_max 卡住（%.2f）" % player._zoom_distance); fail += 1

	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	for _i in 120:
		player._input(wheel_up)
	await _wait(120)
	print("  连滚到顶：_zoom_distance = %.2f（zoom_min = %.2f）  spring_length = %.2f" % [
		player._zoom_distance, player.zoom_min, player.spring.spring_length])
	if is_equal_approx(player._zoom_distance, player.zoom_min):
		print("  [PASS] 到顶被 zoom_min 卡住")
	else:
		print("  [FAIL] 没被 zoom_min 卡住（%.2f）" % player._zoom_distance); fail += 1
	if player.spring.spring_length < base:
		print("  [PASS] 拉近后相机确实更近了（%.2f < %.2f）" % [player.spring.spring_length, base])
	else:
		print("  [FAIL] 拉近没生效（%.2f）" % player.spring.spring_length); fail += 1

	print("\n================ 结果 ================")
	print("失败 %d 项" % fail)
	quit(1 if fail > 0 else 0)


func _face(skel: Skeleton3D) -> Vector3:
	var xf := skel.global_transform
	var h: Vector3 = xf * skel.get_bone_global_pose(skel.find_bone("Bip001 Head")).origin
	var l: Vector3 = skel.get_bone_global_pose(skel.find_bone("Bip001 eye_L")).origin
	var r: Vector3 = skel.get_bone_global_pose(skel.find_bone("Bip001 eye_R")).origin
	var e: Vector3 = xf * ((l + r) * 0.5)
	return _flat(e - h).normalized()


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
