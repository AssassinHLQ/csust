extends SceneTree
## 查：相机臂长在"静止不动"时来回抖（用户 2026-11-10：「摄像头总是突然一前一后」）。
##
## 本探针让玩家**完全静止**，墙放在"擦边"距离上，逐帧记录 spring_length，
## 统计它在一段窗口里**反向次数**和**峰峰值**。正常的相机应该收敛成一条直线；
## 抖动会表现为零值附近的来回翻动。
##
##   godot --headless --script res://scripts/_probe_cam_jitter.gd -- --splat=off --story=off --no-capture

const OffWin := preload("res://scripts/offscreen_window.gd")
const GAME := "res://scenes/game.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


## 统计一段序列的反向次数（相邻差分符号翻转几次）和峰峰值。
func _analyze(tag: String, seq: Array[float]) -> int:
	if seq.size() < 3:
		print("[cj] %s：样本太少" % tag)
		return 0
	var lo := INF
	var hi := -INF
	for v in seq:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	var reversals := 0
	var prev_sign := 0
	for i in range(1, seq.size()):
		var d := seq[i] - seq[i - 1]
		if absf(d) < 0.002:      # 噪声门槛：小于 2 mm 不算一次真实移动
			continue
		var s := 1 if d > 0.0 else -1
		if prev_sign != 0 and s != prev_sign:
			reversals += 1
		prev_sign = s
	print("[cj] %s：区间 [%.2f, %.2f]  峰峰值 %.3f m  反向 %d 次"
		% [tag, lo, hi, hi - lo, reversals])
	return reversals


func _run() -> void:
	await OffWin.apply(self, Vector2i(640, 360))
	await _wait(2)
	get_root().get_tree().create_timer(30.0).timeout.connect(func() -> void:
		print("[cj] !! 超时强制退出")
		quit(2))
	var game: Node = load(GAME).instantiate()
	root.add_child(game)
	await _wait(60)

	var p := game.get_node_or_null("Player") as CharacterBody3D
	if p == null:
		print("[cj] !! 没找到 Player")
		quit(1)
		return
	var spring := p.get_node_or_null("CameraRig/SpringArm3D") as SpringArm3D
	if spring == null:
		print("[cj] !! 没找到 SpringArm3D")
		quit(1)
		return

	# 造一堵墙
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var wcs := CollisionShape3D.new()
	var wbox := BoxShape3D.new()
	wbox.size = Vector3(6.0, 3.0, 0.3)
	wcs.shape = wbox
	wall.add_child(wcs)
	game.add_child(wall)

	var fail := 0

	# ── ① 完全静止，墙在"几乎擦边"的距离 ──
	# ⚠️ 墙必须沿**相机真实所在的方向**摆：`SpringArm3D` 把子节点放在局部
	#    `(0,0,+spring_length)`，即世界方向 `basis.z`。
	#    曾经按 `-basis.z` 摆，结果射线和相机在相反两侧，测试"通过"得毫无意义。
	print("[cj] ---- ① 静止 + 墙擦边：臂长不该抖 ----")
	p.global_position = Vector3(0, 0.2, 0)
	p.set("_yaw", PI)
	await _wait(30)
	var arm_axis := spring.global_transform.basis.z.normalized()
	var arm_right := spring.global_transform.basis.x.normalized()
	# 沿臂长方向 4.2 m、横向偏 1.4 m —— 只有画面边缘的射线才扫得到
	wall.global_position = spring.global_position + arm_axis * 4.2 + arm_right * 1.4
	await _wait(60)                                  # 先让它收敛

	var seq: Array[float] = []
	for _i in 90:
		await physics_frame
		seq.append(spring.spring_length)
	var rev := _analyze("静止（墙擦边）", seq)
	if rev > 4:
		print("[cj]   [FAIL] 静止时还反向 %d 次 —— 这就是用户看到的「一前一后」" % rev)
		fail += 1
	else:
		print("[cj]   [PASS] 静止时基本稳定")

	# ── ② 墙一点点挪开：不该来回摆，但应该**单调跟着变** ──
	print("[cj] ---- ② 墙缓慢移动：臂长应该平滑跟随，不来回摆 ----")
	var d0 := spring.global_position.distance_to(wall.global_position)
	# [diag] 探测器方向 + 一发实际射线，看看到底探到哪里
	var dirs_now: Array = p.call("_camera_probe_dirs", arm_axis, 4.2)
	print("[cj]   [diag] axis=%s  探测器 %d 条：%s"
		% [str(arm_axis.snappedf(0.01)), dirs_now.size(),
		   str(dirs_now.slice(1).map(func(v: Vector3) -> String:
			return str(v.snappedf(0.01))))])
	var sp := p.get_world_3d().direct_space_state
	for d: Vector3 in dirs_now:
		var q := PhysicsRayQueryParameters3D.create(
				spring.global_position, spring.global_position + d * 5.0, 1, [p.get_rid()])
		var h := sp.intersect_ray(q)
		print("[cj]   [diag] dir %s → %s" % [str(d.snappedf(0.01)),
			"命中 " + str(h.get("position")) if not h.is_empty() else "空"])
	var seq2: Array[float] = []
	for i in 80:
		# 让墙沿臂长方向慢慢远去（每帧 6 cm，模拟玩家向前走脱离墙角）
		wall.global_position += arm_axis * 0.06
		await physics_frame
		seq2.append(spring.spring_length)
	var rev2 := _analyze("墙缓慢远离", seq2)
	var d1 := spring.global_position.distance_to(wall.global_position)
	print("[cj]   [diag] 墙距离：%.2f → %.2f（移了 %.2f m）" % [d0, d1, d1 - d0])
	if rev2 > 6:
		print("[cj]   [FAIL] 墙单调远离时臂长反向 %d 次 —— 阻尼拉锯" % rev2)
		fail += 1
	elif absf(seq2[seq2.size() - 1] - seq2[0]) < 0.05:
		print("[cj]   [FAIL] 墙移开了 %.2f m，臂长却完全没变（%.2f）—— 死区卡死或探测失效"
			% [d1 - d0, seq2[0]])
		fail += 1
	else:
		print("[cj]   [PASS] 跟随平滑且确实跟随（%.2f → %.2f）"
			% [seq2[0], seq2[seq2.size() - 1]])

	# ── ③ 空地上静置：臂长应该是常数 ──
	print("[cj] ---- ③ 原地空置（无墙）：臂长必须恒定 ----")
	wall.global_position = Vector3(0, -50.0, 0)
	await _wait(60)
	var seq3: Array[float] = []
	for _i in 60:
		await physics_frame
		seq3.append(spring.spring_length)
	var rev3 := _analyze("空地静置", seq3)
	if rev3 > 1:
		print("[cj]   [FAIL] 空地上都在抖 %d 次" % rev3)
		fail += 1
	else:
		print("[cj]   [PASS] 空地上稳定")

	print("[cj] ==== %s（%d 项失败）====" % ["全部通过" if fail == 0 else "有失败", fail])
	quit(0 if fail == 0 else 1)
