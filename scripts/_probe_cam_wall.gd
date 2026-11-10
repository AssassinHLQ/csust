extends SceneTree
## 查：相机撞墙时长度是「滑过去」还是「瞬移怼脸」。
##
## 使用者 2026-11-10：「穿过狭窄走廊，为什么会让摄像机突然靠前?」
## → 已确认是碰撞。修法见 `player.gd::_collide_camera_arm()`：
##   关掉 SpringArm3D 内置收缩，改成射线探测 + 指数阻尼。
##
## 本探针量三件事：
##   ① `spring.collision_mask` 是否已置 0（内置收缩必须关掉，否则白改）
##   ② 找一面墙，把玩家贴过去、反方向看，逐帧记录 `spring_length`
##      → 单帧最大变化量应该很小（阻尼生效），而不是 3.4 → 0.3 的一帧跳变
##   ③ 把玩家拉回空地，再看长度是否**平滑**回到目标值（不是「啪」弹回）
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

	# 玩家站 (0, 0.2, 0)，墙放在她 **+Z** 侧 1.2 m 处。
	# ⚠️ 实测（探针打的 diag）：`_yaw = PI` 时弹簧臂支点在 (0.42,1.62,0)、伸向 +Z。
	#    所以墙必须放在 +Z —— 放 -Z 的话射线打空，整轮结论都是假的。
	p.global_position = Vector3(0, 0.2, 0)
	wall.global_position = Vector3(0, 1.5, 1.2)
	p.set("_yaw", PI)
	await _wait(6)

	var best_dir := -Vector3.BACK  # 只是保留变量形状，后面不用
	print("[cw]   [diag] 玩家 %s  墙 %s  collision_mask=%d"
		% [str(p.global_position.snappedf(0.01)),
		   str(wall.global_position), spring.collision_mask])
	# 把弹簧臂的真实朝向和支点打出来 —— 方向搞反了整轮结论都是假的。
	var arm_dir := -spring.global_transform.basis.z.normalized()
	print("[cw]   [diag] 弹簧臂支点 %s  伸向 %s"
		% [str(spring.global_position.snappedf(0.01)), str(arm_dir.snappedf(0.01))])
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
	wall.global_position = Vector3(0, 1.5, 200.0)
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
	if max_step > 0.35:
		print("[cw]   [FAIL] 松开时也跳了 %.2f m" % max_step)
		fail += 1
	else:
		print("[cw]   [PASS] 回弹也是平滑的")
	if absf(back[back.size() - 1] - back[0]) > 0.01:
		print("[cw]   （长度确实变了：%.2f → %.2f）" % [back[0], back[back.size() - 1]])
	else:
		print("[cw]   [WARN] 长度没变，这次测试可能没真正贴到墙")

	print("[cw] ==== %s（%d 项失败）====" % ["全部通过" if fail == 0 else "有失败", fail])
	quit(0 if fail == 0 else 1)
