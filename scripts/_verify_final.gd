extends SceneTree
## 定稿自检：一条命令验完所有关键行为。
## 用法（必须真渲染，不要 --headless）：
##   godot --path <工程> --script res://scripts/_verify_final.gd

var _fail := 0
var _pass := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(20)

	var player: Player = game.get_node("Player")
	var weapon: Weapon = game.get_node("Player/Weapon")
	var driver: AnimDriver = game.get_node("Player/Arisu/Model/AnimDriver")
	var skel: Skeleton3D = game.get_node("Player/Arisu/Model/Aris_Original_Mesh/bone_root/Bip001/Skeleton3D")
	var thigh := skel.find_bone("Bip001 R Thigh")

	# ---- 1. 输入：视角 ----
	_section("1. 鼠标视角（_input 通道）")
	_ok(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED,
		"鼠标已捕获（mouse_mode=%d）" % Input.mouse_mode)
	var yaw0 := player.rig.rotation.y
	var pitch0 := player._pitch
	await _mouse_move(30, 8, 12)
	_ok(absf(player.rig.rotation.y - yaw0) > 0.05,
		"鼠标横移能转视角（yaw %.3f → %.3f）" % [yaw0, player.rig.rotation.y])
	_ok(absf(player._pitch - pitch0) > 0.01,
		"鼠标纵移能抬低头（pitch %.3f → %.3f）" % [pitch0, player._pitch])

	# ---- 2. 输入：左键开火 ----
	_section("2. 左键开火（_input + poll 兜底）")
	var ammo0 := weapon.current_ammo
	await _mouse_button(MOUSE_BUTTON_LEFT, true)
	await _wait(30)
	await _mouse_button(MOUSE_BUTTON_LEFT, false)
	_ok(weapon.current_ammo < ammo0,
		"左键能开火（弹药 %d → %d）" % [ammo0, weapon.current_ammo])

	# ---- 3. 四方向移动 ----
	_section("3. WASD 四方向（相对相机）")
	for c in [["move_forward", "前"], ["move_back", "后"], ["move_left", "左"], ["move_right", "右"]]:
		Input.action_press(c[0])
		var p0 := player.global_position
		await _wait(50)
		var p1 := player.global_position
		Input.action_release(c[0])
		var moved := (p1 - p0)
		moved.y = 0.0
		var cam_fwd := _flat(player.camera_forward()).normalized()
		var cam_right := _flat(player.cam.global_transform.basis.x).normalized()
		var m := moved.normalized()
		var ok := false
		match c[0]:
			"move_forward": ok = m.dot(cam_fwd) > 0.9
			"move_back": ok = m.dot(cam_fwd) < -0.9
			"move_left": ok = m.dot(cam_right) < -0.9
			"move_right": ok = m.dot(cam_right) > 0.9
		_ok(ok, "%s：位移 %s（前向点积 %+.2f，右向点积 %+.2f）" % [
			c[1], str(moved.snappedf(0.01)), m.dot(cam_fwd), m.dot(cam_right)])
		await _wait(20)

	# ---- 4. 朝向：按 W 时脸应朝向移动方向 ----
	_section("4. 角色朝向（按 W 应面朝移动方向、背对相机）")
	# 两条判据一起看：
	#   a) 可控量：model_root.rotation.y 应等于 atan2(vel.x, vel.z)
	#      （四方位渲图已证明 rotation.y 与真实脸朝向一致，见 README §1.4）
	#   b) 眼睛骨量：有几十度固有偏差，只做定性核对（脸大致朝移动方向、背对相机）
	Input.action_press("move_forward")
	await _wait(80)
	var face := _face_dir(skel)
	var vel := _flat(player.velocity).normalized()
	var ang := rad_to_deg(face.angle_to(vel))
	var want_rot := atan2(vel.x, vel.z)
	var rot_err := rad_to_deg(absf(angle_difference(want_rot, player.model_root.rotation.y)))
	_ok(rot_err < 10.0, "model_root.rotation.y 与移动方向差 %.1f 度（应 < 10）" % rot_err)
	_ok(ang < 30.0, "脸朝向 与 移动方向 夹角 %.1f 度（应 < 30）" % ang)
	var to_move := _flat(player.global_position - player.cam.global_position).normalized()
	_ok(face.dot(to_move) > 0.7,
		"按 W 时背对相机（脸与「相机→角色」同向，点积 %+.2f）" % face.dot(to_move))
	Input.action_release("move_forward")
	await _wait(30)

	# ---- 5. 动画真的在播（像素比对 + 旋转判据）----
	_section("5. 动画真的在播")
	Input.action_press("move_forward")
	await _wait(20)
	var prev: Image = null
	var max_diff := 0
	var rots := {}
	for i in 20:
		await _wait(3)
		await RenderingServer.frame_post_draw
		var img: Image = game.get_viewport().get_texture().get_image()
		if prev != null:
			max_diff = maxi(max_diff, _diff(prev, img))
		prev = img
		var q: Quaternion = skel.get_bone_pose_rotation(thigh)
		rots["%.4f,%.4f,%.4f,%.4f" % [q.x, q.y, q.z, q.w]] = true
	Input.action_release("move_forward")
	_ok(max_diff > 5, "走动时相邻帧像素有差异（最大 %d / 4000）" % max_diff)
	_ok(rots.size() > 5, "走动时骨骼旋转在变（%d 种 / 20 帧）" % rots.size())
	print("      当前动画 = %s   速度 %.2f m/s" % [
		driver.current_clip(), Vector2(player.velocity.x, player.velocity.z).length()])
	await _wait(40)

	# ---- 6. 命中判定 ----
	_section("6. 命中判定（准星压在靶子上要掉血）")
	player.global_position = Vector3(6, 0.05, -4)
	player._yaw = 0.0
	player._facing_yaw = player._yaw + PI
	player.rig.rotation.y = 0.0
	player.model_root.rotation.y = PI
	# Target1 的碰撞盒/网格在 game.tscn 被往上抬了 4.117 m（用户未提交的改动），
	# 且命中判定 2026-10-27 改成相机中心（准星）——按碰撞盒实际位置算俯仰，
	# 并把角色右移补上越肩相机的横向偏移（相机 x = 角色 x − 0.4）。
	var t1 := game.get_node("Target1") as Target
	var t1_box := t1.get_node("Collision") as Node3D
	for _i in 3:
		var cam_now := player.cam.global_position
		var to_target: Vector3 = t1_box.global_position - cam_now
		player.set("_pitch", atan2(to_target.y, Vector2(to_target.x, to_target.z).length()))
		await _wait(10)
	player.global_position.x += t1_box.global_position.x - player.cam.global_position.x
	await _wait(10)
	var target: Target = game.get_node("Target1")
	var hp0 := target.health
	weapon.current_ammo = weapon.magazine_size
	weapon.spread_hip = 0.0
	for i in 3:
		weapon._cooldown = 0.0
		weapon.shoot()
		await _wait(4)
	_ok(target.health < hp0, "靶子掉血（%.0f → %.0f，每发 %.0f）" % [hp0, target.health, weapon.damage])

	# ---- 7. 换弹 ----
	_section("7. 换弹")
	weapon.current_ammo = 3
	weapon.fire_interval = 0.075
	weapon.try_reload()
	_ok(weapon.is_reloading(), "进入换弹")
	print("      try_reload 后计时器 = %.3f   is_processing = %s" % [
		weapon._reload_timer, str(weapon.is_processing())])
	# 等换弹结束：按**真实时间**等，不按帧数。
	# 原来是「16 步 × 20 帧 = 320 帧」——换弹要 1.05 s，帧率一高（实测能到 2000 fps）
	# 320 帧只有 0.16 s，会在换弹没结束时就断言假红。
	var t_reload := Time.get_ticks_msec()
	var step := 0
	while Time.get_ticks_msec() - t_reload < 4000:
		await _wait(20)
		step += 1
		print("      +%3d 帧 / %.2f s  计时器 %.3f  还在换弹 %s  弹药 %d" % [
			step * 20, (Time.get_ticks_msec() - t_reload) / 1000.0,
			weapon._reload_timer, str(weapon.is_reloading()), weapon.current_ammo])
		if not weapon.is_reloading():
			break
	_ok(not weapon.is_reloading(), "换弹结束")
	_ok(weapon.current_ammo == weapon.magazine_size,
		"换弹后满弹（%d / %d）" % [weapon.current_ammo, weapon.magazine_size])

	print("\n================ 结果 ================")
	print("通过 %d 项，失败 %d 项" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _section(t: String) -> void:
	print("\n--- %s ---" % t)


func _ok(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  [PASS] ", label)
	else:
		_fail += 1
		print("  [FAIL] ", label)


func _mouse_move(dx: float, dy: float, times: int) -> void:
	for i in times:
		var ev := InputEventMouseMotion.new()
		ev.relative = Vector2(dx, dy)
		ev.screen_relative = Vector2(dx, dy)
		ev.position = Vector2(800, 450)
		Input.parse_input_event(ev)
		await process_frame


func _mouse_button(btn: int, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = btn
	ev.pressed = pressed
	ev.position = Vector2(800, 450)
	Input.parse_input_event(ev)
	await process_frame


func _diff(a: Image, b: Image) -> int:
	var count := 0
	for s in 4000:
		var x := (s * 37) % a.get_width()
		var y := (s * 61) % a.get_height()
		var pa := a.get_pixel(x, y)
		var pb := b.get_pixel(x, y)
		if absf(pa.r - pb.r) + absf(pa.g - pb.g) + absf(pa.b - pb.b) > 0.01:
			count += 1
	return count


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## 脸的世界朝向 = 眼睛中点 - 头骨位置（水平投影）
## 这是唯一可靠的判据；节点朝向 / shoulder×up 叉乘都算不出真正的脸方向。
func _face_dir(skel: Skeleton3D) -> Vector3:
	var head_i := skel.find_bone("Bip001 Head")
	var eye_l := skel.find_bone("Bip001 eye_L")
	var eye_r := skel.find_bone("Bip001 eye_R")
	if head_i < 0 or eye_l < 0 or eye_r < 0:
		return Vector3.FORWARD
	var xf := skel.global_transform
	var h: Vector3 = xf * skel.get_bone_global_pose(head_i).origin
	var e: Vector3 = xf * ((skel.get_bone_global_pose(eye_l).origin
		+ skel.get_bone_global_pose(eye_r).origin) * 0.5)
	var d := _flat(e - h)
	return d.normalized() if d.length() > 0.0001 else Vector3.FORWARD


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
