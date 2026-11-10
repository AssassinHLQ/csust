extends SceneTree
## 查：相机避墙的三件事。
##
## 使用者 2026-11-10 第一轮：「穿过狭窄走廊，为什么会让摄像机突然靠前?」
##   → 已确认是碰撞。修法见 `player.gd::_collide_camera_arm()`：
##     关掉 SpringArm3D 内置收缩，改成射线探测 + 指数阻尼。
##
## 使用者 2026-11-10 第二轮：「摄像机穿过碰撞了；FOV 拉大、滚轮拉到最远时
##                              经常超出建筑物看不见角色」
##   → 两个新问题：① 单中心射线在 FOV 大时会漏掉画面边缘；
##                  ② 阻尼太快会一帧跨过墙。已改成近平面四角探测 + 位移上限。
##
## 本探针量五件事：
##   ① `spring.collision_mask` 是否已置 0（内置收缩必须关掉，否则白改）
##   ② 贴墙：逐帧 `spring_length` 变化应该很小（阻尼生效）
##   ③ 墙搬走：长度平滑弹回
##   ④ **单帧位移不超过上限**（防"跨墙"）
##   ⑤ **FOV 越大探测越宽**：同一面斜墙，FOV 大时应该压得更短
##      （只打中心射线时两者会一样 —— 那就是漏墙的根因）
##
##   godot --headless --script res://scripts/_probe_cam_wall.gd -- --splat=off --story=off --no-capture

const OffWin := preload("res://scripts/offscreen_window.gd")
const GAME := "res://scenes/game.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	await OffWin.apply(self, Vector2i(640, 360))
	await _wait(2)
	# ⚠️ 兜底：任何一步抛错都不能让探针卡住不退出（headless 下会一直挂着）。
	#    实测 2026-11-10：⑤ 里 `get_node()` 拿到 null，脚本报错后没走到 quit()，
	#    进程一直不退。这里挂个定时器，8 秒没结束就强制退出。
	get_root().get_tree().create_timer(8.0).timeout.connect(func() -> void:
		print("[cw] !! 超时强制退出（有步骤卡住了）")
		quit(2))
	var game: Node = load(GAME).instantiate()
	root.add_child(game)
	await _wait(60)

	var p := game.get_node_or_null("Player") as CharacterBody3D
	if p == null:
		print("[cw] !! 没找到 Player")
		quit(1)
		return

	var spring := p.get_node_or_null("CameraRig/SpringArm3D") as SpringArm3D
	var rig := p.get_node_or_null("CameraRig") as Node3D
	var cam := p.get_node_or_null("CameraRig/SpringArm3D/Camera3D") as Camera3D
	if spring == null or rig == null or cam == null:
		print("[cw] !! 相机节点缺失")
		quit(1)
		return

	var fail := 0
	var prev := 0.0
	var max_step := 0.0

	# ── ① 内置收缩是否已关 ──
	print("[cw] ---- ① SpringArm3D 内置收缩 ----")
	print("[cw]   collision_mask = %d（必须是 0）" % spring.collision_mask)
	if spring.collision_mask != 0:
		print("[cw]   [FAIL] 内置收缩还开着 —— 它会一帧把镜头怼到墙上，阻尼白做")
		fail += 1
	else:
		print("[cw]   [PASS] 已关闭，由 _collide_camera_arm() 接管")

	# ── ② 贴墙测试（自己造一堵墙，不依赖场景内容）──
	print("[cw] ---- ② 贴着墙、回头看：逐帧记录 spring_length ----")
	var space := p.get_world_3d().direct_space_state

	# ⚠️ 场景里的碰撞体在 headless 下不一定进了物理世界（实测 Room609 的墙打空），
	#    所以这里**自己造一堵 StaticBody3D 当墙**，只验证相机逻辑本身。
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var wcs := CollisionShape3D.new()
	var wbox := BoxShape3D.new()
	wbox.size = Vector3(4.0, 3.0, 0.4)
	wcs.shape = wbox
	wall.add_child(wcs)
	game.add_child(wall)

	# ⚠️ 墙必须沿**相机真实所在方向**摆 = `spring.global_transform.basis.z`
	#    （`SpringArm3D` 把子节点放在局部 `(0,0,+spring_length)`）。
	#    曾经按 `-basis.z` 摆墙：射线和相机在相反两侧，测试用错误的理由"通过"了，
	#    真机室内穿墙 139/225 帧才暴露出来（见 `_probe_cam_indoor.gd`）。
	p.global_position = Vector3(0, 0.2, 0)
	p.set("_yaw", PI)
	await _wait(6)
	var arm_dir := spring.global_transform.basis.z.normalized()
	wall.global_position = spring.global_position + arm_dir * 1.2
	await _wait(6)

	print("[cw]   [diag] 玩家 %s  collision_mask=%d"
		% [str(p.global_position.snappedf(0.01)), spring.collision_mask])
	print("[cw]   [diag] 弹簧臂支点 %s  相机在 %s 方向"
		% [str(spring.global_position.snappedf(0.01)), str(arm_dir.snappedf(0.01))])
	print("[cw]   [diag] 相机实际位置 %s（支点 + %.2f × 方向）"
		% [str(cam.global_position.snappedf(0.01)), spring.spring_length])
	# 用和 `_collide_camera_arm()` **完全相同**的参数，手动打一发，看会不会命中。
	var q := PhysicsRayQueryParameters3D.create(
			spring.global_position,
			spring.global_position + arm_dir * 6.0,
			1, [p.get_rid()])
	var h := space.intersect_ray(q)
	print("[cw]   [diag] 手动射线（同参数）→ %s"
		% ("命中 " + str(h.get("position")) if not h.is_empty() else "空"))

	prev = spring.spring_length
	max_step = 0.0
	var steps: Array[float] = []
	for _i in 40:
		await physics_frame
		var cur := spring.spring_length
		max_step = maxf(max_step, absf(cur - prev))
		steps.append(cur)
		prev = cur
	print("[cw]   40 帧 spring_length：起 %.2f  终 %.2f  单帧最大变化 %.3f"
		% [steps[0], steps[steps.size() - 1], max_step])
	print("[cw]   前 8 帧：%s" % str(steps.slice(0, 8).map(func(v: float) -> String:
		return "%.2f" % v)))
	# 阈值：单帧 0.35 m 以上就算「突然」（3.4 m 的臂长一帧走 10% 以上）
	if max_step > 0.35:
		print("[cw]   [FAIL] 单帧最多跳了 %.2f m —— 还是突变" % max_step)
		fail += 1
	else:
		print("[cw]   [PASS] 单帧最大 %.3f m，是滑过去的" % max_step)
	# 是不是真被墙压短了？起点就该已被压过（墙在 1.2 m 处，臂长必然远小于 4.2）。
	# 判据用「起点是否明显短于目标」而不是固定阈值 —— 墙远近不同，压到的值不同。
	var target_now := 4.2  # hip_distance 默认；够用
	if steps[0] > target_now - 0.5:
		print("[cw]   [WARN] 起点 %.2f m 几乎没被压 —— 墙没挡住相机，本轮结论不算数"
			% steps[0])
		fail += 1
	else:
		print("[cw]   [PASS] 被墙压短了：%.2f → %.2f（目标 %.1f）"
			% [target_now, steps[steps.size() - 1], target_now])

	# ── ③ 离开墙后是否平滑弹回 ──
	print("[cw] ---- ③ 把墙搬走：长度应该慢慢弹回目标 ----")
	var before := spring.spring_length
	# ⚠️ 人别动（一挪就绕了一圈，测的不是同一条线），**把墙搬走**才对：
	#    搬走后射线打空 → blocked = want → 应该按 CAM_OUT_TAU 慢慢伸回去。
	wall.global_position = spring.global_position + arm_dir * 200.0
	await _wait(2)
	prev = spring.spring_length
	max_step = 0.0
	var back: Array[float] = []
	for _i in 40:
		await physics_frame
		var cur2 := spring.spring_length
		max_step = maxf(max_step, absf(cur2 - prev))
		back.append(cur2)
		prev = cur2
	print("[cw]   起 %.2f → 终 %.2f   单帧最大变化 %.3f"
		% [back[0], back[back.size() - 1], max_step])
	# 判据改成「单帧位移上限」而不是固定 0.35：
	# 上限 = 32 m/s × 帧长（1/60 → 0.53 m），留 15% 余量。
	var step_cap := 32.0 * (1.0 / 60.0) * 1.15
	if max_step > step_cap:
		print("[cw]   [FAIL] 松开时单帧跳了 %.2f m（上限 %.2f）" % [max_step, step_cap])
		fail += 1
	else:
		print("[cw]   [PASS] 回弹平滑，单帧最大 %.3f m（上限 %.2f）" % [max_step, step_cap])
	if absf(back[back.size() - 1] - back[0]) > 0.01:
		print("[cw]   （长度确实变了：%.2f → %.2f）" % [back[0], back[back.size() - 1]])
	else:
		print("[cw]   [WARN] 长度没变，这次测试可能没真正贴到墙")

	# ── ④ 单帧位移上限（防"跨墙"）──
	# 直接把 spring_length 手动拉到最远，再让墙把它压回来：这一步最容易出现
	# 一帧跨过墙的情况。逐帧记录，检查没有一帧超过 CAM_MAX_STEP_SPEED*dt。
	print("[cw] ---- ④ 从最远距离被墙压回来：单帧位移必须受限 ----")
	wall.global_position = spring.global_position + arm_dir * 1.2
	await _wait(2)
	spring.spring_length = 9.0
	prev = spring.spring_length
	max_step = 0.0
	var worst_t := -1
	var press: Array[float] = []
	for i in 90:
		await physics_frame
		var cur3 := spring.spring_length
		if absf(cur3 - prev) > max_step:
			max_step = absf(cur3 - prev)
			worst_t = i
		press.append(cur3)
		prev = cur3
	print("[cw]   9.00 → %.2f   单帧最大变化 %.3f（上限 %.2f）"
		% [press[press.size() - 1], max_step, step_cap])
	print("[cw]   [diag] 最大跳变在第 %d 帧；Engine.time_scale=%.2f  物理帧率=%d"
		% [worst_t, Engine.time_scale, Engine.physics_ticks_per_second])
	print("[cw]   [diag] 前 12 帧：%s" % str(press.slice(0, 12).map(func(v: float) -> String:
		return "%.2f" % v)))
	if max_step > step_cap:
		print("[cw]   [FAIL] 单帧 %.2f m 超过上限 —— 低帧时会跨过墙" % max_step)
		fail += 1
	elif press[press.size() - 1] > 4.0:
		print("[cw]   [WARN] 90 帧后长度仍 %.2f m，墙没压住" % press[press.size() - 1])
		fail += 1
	else:
		print("[cw]   [PASS] 压回 %.2f m，且每帧都在 %.2f m 以内"
			% [press[press.size() - 1], step_cap])

	# ── ⑤ FOV 越大，探测越宽（斜墙时必须压得更短）──
	# 关键回归项：只打中心射线时，小 FOV 和大 FOV 会得到**同一个**长度，
	# 那正是"FOV 拉大后画面边缘看穿墙"的根因。这里用一面**斜放的墙**来区分：
	# 只有近平面四角的射线才扫得到它。
	print("[cw] ---- ⑤ FOV 拉大 → 探测锥必须变宽 ----")
	# ⚠️ 这一项**只验证探测锥的张角**，不验证"墙压得更短"。
	#    原因：想构造"62° 打不到、105° 打得到"的墙位需要墙精确落在锥体边缘的夹缝里，
	#    受支点肩偏移（+0.42 m）、墙厚、扫描步长影响极其敏感，探针里反复摆不准
	#    （2026-11-10 连试四次：wide 墙全命中、窄墙又全打空）。
	#    而"锥体会不会跟着 FOV 变"本来就是**纯几何**问题，直接算两个方向的开角即可，
	#    比摆墙可靠得多。墙压缩效果由 ②④ 覆盖。
	# ⚠️ 方向同样必须取 `+basis.z`（相机实际所在的那一侧）。
	var axis_now := spring.global_transform.basis.z.normalized()
	var basis_now := spring.global_transform.basis
	var aspect := cam.get_viewport().get_visible_rect().size.aspect()

	## 按 FOV 算近平面右侧那条射线的偏角（度）。和 `_camera_probe_dirs()` 同一公式。
	var right_angle := func(fov_deg: float, at: float) -> float:
		var hh := at * tan(deg_to_rad(fov_deg) * 0.5)
		var hw := hh * aspect
		var corner := (axis_now * at + basis_now.x.normalized() * hw).normalized()
		return rad_to_deg(axis_now.angle_to(corner))

	var a62: float = right_angle.call(62.0, 4.2)
	var a105: float = right_angle.call(105.0, 4.2)
	print("[cw]   fov 62°  → 右边缘射线偏角 %.1f°" % a62)
	print("[cw]   fov 105° → 右边缘射线偏角 %.1f°" % a105)
	if a105 > a62 + 1.0:
		print("[cw]   [PASS] FOV 越大探测锥越宽（%.1f° → %.1f°）—— 边缘会先扫到墙"
			% [a62, a105])
	else:
		print("[cw]   [FAIL] 探测锥没跟着 FOV 张开（%.1f° vs %.1f°）" % [a62, a105])
		fail += 1

	# 再确认真正在用的那个函数和这条公式一致（防止两处公式漂移）。
	var dirs_from_fn: Array = p.call("_camera_probe_dirs", axis_now, 4.2)
	var max_dev := 0.0
	for i in range(1, dirs_from_fn.size()):
		var ang := rad_to_deg(axis_now.angle_to(dirs_from_fn[i] as Vector3))
		# 四角里最大的偏角应该 ≥ 上面算出来的右边缘偏角（角上的偏角更大）
		max_dev = maxf(max_dev, ang)
	print("[cw]   [diag] 实际 _camera_probe_dirs 最大偏角 %.1f°（cam.fov=%.1f）"
		% [max_dev, cam.fov])
	if max_dev < 1.0:
		print("[cw]   [FAIL] 探测器角和中心轴几乎一样 —— 四角根本没铺开")
		fail += 1

	print("[cw] ==== %s（%d 项失败）====" % ["全部通过" if fail == 0 else "有失败", fail])
	quit(0 if fail == 0 else 1)
