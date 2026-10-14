extends SceneTree
## 验这轮两个需求（其实是同一个几何关系的两头）：
##   1. 初始视角 = 标准越肩视角：镜头在角色**背后**，画面正前方就是靶区（看得见靶子）
##   2. 开火前强制转身：转身目标是**准星方向**（背对镜头、朝前），不是转过来面对镜头
##
## 几何关系（实测，见 README §1.4）：
##   相机挂在 rig 的 +Z 侧、看向 -Z
##   → 相机视线 = -(sin(_yaw), cos(_yaw))
##   → 角色脸朝向 = (sin(_facing_yaw), cos(_facing_yaw))
##   → 「朝准星」= _facing_yaw = _yaw + PI
##
## 用真实鼠标事件驱动，覆盖「甩镜头 + 按住左键」这一刻的判定时序。
##
## 用法（要真渲染，不要 --headless）：
##   godot --path <工程> --script res://scripts/_verify_spawnview.gd

var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	await _wait(30)

	var player: Player = game.get_node("Player")
	var weapon: Weapon = game.get_node("Player/Weapon")
	var arena := Vector3(0.0, 0.0, -1.0)

	print("========== 1. 初始视角：镜头在角色背后、视线指向靶区 ==========")
	print("  _yaw = %.4f（应 0）   _facing_yaw = %.4f   model.rot.y = %.4f" % [
		player._yaw, player._facing_yaw, player.model_root.rotation.y])
	_check(absf(player._yaw) < 0.001, "出生 _yaw = 0（相机在角色背后那侧）")

	var cfwd := _flat(player.camera_forward()).normalized()
	print("  相机视线 = %s   与靶区方向(-Z)点积 %+.3f" % [
		str(cfwd.snappedf(0.01)), cfwd.dot(arena)])
	_check(cfwd.dot(arena) > 0.9, "相机视线指向靶区（一进场就看得见靶子）")

	var face := _model_face(player)
	var to_cam := _flat(player.cam.global_position - player.global_position).normalized()
	print("  脸 = %s   角色→相机 = %s   点积 %+.3f" % [
		str(face.snappedf(0.01)), str(to_cam.snappedf(0.01)), face.dot(to_cam)])
	_check(face.dot(to_cam) < -0.7, "角色背对镜头（看到的是后脑勺）")
	_check(face.dot(arena) > 0.9, "角色面朝靶区")

	# 靶子是否真在画面里：dot > 0 才算在相机前方。
	# ⚠️ 不能用 unproject_position 判断「在不在画面内」——
	#    相机背后的点也会返回一个坐标，看着像在画面里，其实在身后。
	var front_count := 0
	for t in game.get_children():
		if t is Target:
			var d := _flat(t.global_position - player.global_position).normalized()
			var front := d.dot(cfwd)
			var sp := player.cam.unproject_position(t.global_position + Vector3.UP * 0.3)
			print("    %-8s 视线点积 %+.2f   屏幕 %s" % [t.name, front, str(sp.snappedf(1.0))])
			if front > 0.5:
				front_count += 1
	print("  位于相机前方的靶子 = %d / 5" % front_count)
	_check(front_count >= 3, "至少 3 个靶子在镜头前方（旧视角是 0 个）")

	var vp := root.get_visible_rect().size
	var t3: Target = game.get_node("Target3")
	var sp3 := player.cam.unproject_position(t3.global_position + Vector3.UP * 0.3)
	print("  场地正中 Target3 屏幕坐标 %s（视口 %s）" % [str(sp3.snappedf(1.0)), str(vp)])
	_check(sp3.x > vp.x * 0.15 and sp3.x < vp.x * 0.85 and sp3.y > 0.0 and sp3.y < vp.y,
		"场地正中的靶子落在画面里、且靠中间")

	# 存一张出生画面，方便肉眼对照
	var out_dir := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_spawn")
	DirAccess.make_dir_recursive_absolute(out_dir)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/spawn_after_fix.png" % out_dir)
	print("  已存 %s/spawn_after_fix.png" % out_dir)

	print("\n========== 2. 甩镜头 + 按住左键：先转身、后开火 ==========")
	# 甩镜头：真实鼠标移动事件（20 次 × 48 px ≈ 2.1 rad ≈ 120°）
	for _i in 20:
		var ev := InputEventMouseMotion.new()
		ev.relative = Vector2(48, 0)
		ev.screen_relative = Vector2(48, 0)
		ev.position = Vector2(640, 360)
		Input.parse_input_event(ev)
		await process_frame
	await _wait(3)

	var want := wrapf(player._yaw + PI, -PI, PI)
	var cur := wrapf(player.model_root.rotation.y, -PI, PI)
	var err_before := rad_to_deg(absf(angle_difference(want, cur)))
	print("  甩镜头后 _yaw = %.3f rad（%.0f 度）" % [player._yaw, rad_to_deg(player._yaw)])
	print("  此刻「准星方向」= _yaw+PI = %.3f rad   角色朝向 = %.3f rad   差 %.1f 度" % [
		want, cur, err_before])
	_check(err_before > 45.0, "起手角色确实没对着准星（差 %.1f 度，场景有意义）" % err_before)

	# 记录「开火那一瞬间」的朝向误差（在 fired 信号里同步取样）
	var probe := {"err": -1.0, "face_dot_fwd": -1.0, "count": 0}
	weapon.fired.connect(func(_i: int) -> void:
		probe["count"] = int(probe["count"]) + 1
		if float(probe["err"]) < 0.0:
			probe["err"] = player.align_error_deg()
			probe["face_dot_fwd"] = _model_face(player).dot(_flat(player.camera_forward()).normalized()))

	await _mouse_button(MOUSE_BUTTON_LEFT, true)
	# headless 下合成鼠标事件不会更新 Input.is_mouse_button_pressed，
	# 角色的 poll 兜底会把 _fire_held 清掉。真实鼠标不存在这问题，
	# 所以这里手动续上，只为把「按住左键」这个状态维持住。
	var polled := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	print("  Input.is_mouse_button_pressed(左键) = %s" % str(polled))

	var shots0 := weapon._shot_index
	var first_frame := -1
	var saw_turning := false
	var guard := 0
	while guard < 1500:
		await process_frame
		guard += 1
		if not polled:
			player._fire_held = true
		if weapon.is_turning():
			saw_turning = true
		if weapon._shot_index > shots0:
			first_frame = guard
			break

	print("  点后第 %d 帧开出第一枪   曾出现「转向中」= %s   累计开火 %d 发" % [
		first_frame, str(saw_turning), int(probe["count"])])
	print("  ★ 开火瞬间：align_error = %.1f 度（容差 22）   脸·准星方向 = %+.3f" % [
		float(probe["err"]), float(probe["face_dot_fwd"])])
	_check(first_frame > 2, "不是点下去同帧就开枪（先转身）")
	_check(float(probe["err"]) >= 0.0 and float(probe["err"]) <= 22.0,
		"开火瞬间旋转误差在容差内（%.1f 度）" % float(probe["err"]))
	# cos(22°) = 0.927 —— 「朝向准星」最直接的判据
	_check(float(probe["face_dot_fwd"]) > 0.92,
		"开火瞬间角色朝着准星方向（脸·视线 = %+.3f，旧 bug 时是 -1）" % float(probe["face_dot_fwd"]))

	print("\n========== 3. 转身目标 = 准星方向（针对反过来的旧 bug）==========")
	var got := wrapf(player.aim_facing_yaw(), -PI, PI)
	print("  aim_facing_yaw() = %.4f   期望 _yaw + PI = %.4f" % [got, want])
	_check(absf(angle_difference(want, got)) < 0.001, "开火时 aim_facing_yaw() == _yaw + PI")
	var wf := Vector3(sin(got), 0.0, cos(got))
	var to_cam2 := _flat(player.cam.global_position - player.global_position).normalized()
	print("  目标朝向 = %s   角色→相机 = %s   点积 %+.3f" % [
		str(wf.snappedf(0.01)), str(to_cam2.snappedf(0.01)), wf.dot(to_cam2)])
	_check(wf.dot(to_cam2) < -0.7, "转身目标是背对镜头（旧 bug 时这里是 +1，就是「转过去面对镜头」）")

	await _mouse_button(MOUSE_BUTTON_LEFT, false)
	weapon.trigger_up()
	player._fire_held = false

	print("\n================ 结果 ================")
	print("失败 %d 项" % _fail)
	quit(1 if _fail > 0 else 0)


func _model_face(player: Player) -> Vector3:
	return Vector3(sin(player.model_root.rotation.y), 0.0, cos(player.model_root.rotation.y))


func _mouse_button(btn: int, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = btn
	ev.pressed = pressed
	ev.position = Vector2(640, 360)
	Input.parse_input_event(ev)
	await process_frame


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
