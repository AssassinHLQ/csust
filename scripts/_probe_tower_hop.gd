extends SceneTree
## 诊断：螺旋塔的「站定短跳」为什么没有横向位移（跳起来、竖直够、横向≈0）。
##
## 复现自检里红的那一跳（`W1→W2`，站号 28 → 29）：把玩家摆在 W1 台面正中、朝向 W2 中心，
## 按真实时序走一遍（**等落地 → 按跳 → 按住 W + Shift**），逐帧打印这几样：
##   velocity(xz) / is_on_floor / _yaw / rig.rotation.y / rig.global_basis.z
##   / Input.get_vector(...) / 位置
## 一眼就能分清是「输入没进去」还是「朝向没生效」。
##
## 用法：godot --path <工程> --script res://scripts/_probe_tower_hop.gd -- --splat=off

var _p: Player
var _pk: Parkour


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 12:
		await process_frame
	_p = game.get_node_or_null("Player") as Player
	_pk = game.get_node_or_null("Parkour") as Parkour
	if _p == null or _pk == null:
		print("!! 缺 Player / Parkour")
		quit(1)
		return
	# ⚠️ 本喵原先在这里加了三样，最小探针证明「什么都不设」时跳是好的：
	#   `_pk.enabled = false` / `_p.set_process_input(false)` / 鼠标模式改 VISIBLE。
	#   现在**全都不设**，只保留「瞬移到 W1 台面」这一个动作，用来定位到底是哪一样在捣鬼。
	# _pk.enabled = false
	# _p.set_process_input(false)

	# 站号：段 4 从 28 开始 ⇒ 28=W1、29=W2（拿名字核对一遍）
	print("[probe] 28 = %s   29 = %s" % [_pk.label_at(28), _pk.label_at(29)])
	var a := _pk.box_at(28)
	var b := _pk.box_at(29)
	print("[probe] W1 台面 %.2f %s    W2 台面 %.2f %s"
		% [_pk.top_at(28), str(_pk.respawn_point(28).snappedf(0.01)),
			_pk.top_at(29), str(_pk.respawn_point(29).snappedf(0.01))])
	var center := b.position + b.size * 0.5
	var start := _pk.respawn_point(28)

	_release()
	_p.global_position = start
	_p.velocity = Vector3.ZERO
	_aim(Vector2(center.x - start.x, center.z - start.z).normalized())
	await _wait(3)

	# 等真落地
	var tw := Time.get_ticks_msec()
	while not _p.is_on_floor() and Time.get_ticks_msec() - tw < 500:
		await process_frame
	print("[probe] 落地了 = %s（y = %.2f）" % [_p.is_on_floor(), _p.global_position.y])

	# 打印第 0 帧（按跳前）
	_dump(0, "按跳前")
	# ⚠️ 试三种按法，看哪一种能让 `player.gd` 真的跳（`velocity.y` 应该变 +7.1）：
	#    A 按两帧空闲帧再松（自检现在用的）
	#    B 按一下、等**物理帧**
	#    C 按一下、物理帧里再确认
	for tag in ["A 两空闲帧", "B 等物理帧", "C 物理帧两次"]:
		Input.action_press("jump")
		if tag == "A 两空闲帧":
			await process_frame
			await process_frame
		elif tag == "B 等物理帧":
			await physics_frame
		else:
			await physics_frame
			await physics_frame
		print("  [jump] %-12s velocity.y = %+.2f  floor = %s  y = %.2f"
			% [tag, _p.velocity.y, _p.is_on_floor(), _p.global_position.y])
		Input.action_release("jump")
		await _wait(3)
		await _wait(3)
	# D ⚠️ 本喵怀疑的真凶：`jump` 是**单帧脉冲**，而这具身体落在小台上时会
	#   **穿透弹跳**（`is_on_floor()` 逐帧 true/false 交替）—— 脉冲正好落在 false 那帧就没了。
	#   所以：**在物理帧里按**（`physics_frame` 信号在节点 `_physics_process` 之前发），
	#   并且按之前**连续两帧确认踩在地上**。
	var y_before := _p.global_position.y
	var ok_d := false
	for attempt in 12:
		var n_ok := 0
		while n_ok < 2:
			await physics_frame
			n_ok = (n_ok + 1) if _p.is_on_floor() else 0
		Input.action_press("jump")
		await physics_frame
		if _p.velocity.y > 1.0:
			ok_d = true
			print("  [jump] D 物理帧里按：第 %d 次成功 velocity.y = %+.2f（y %.2f → %.2f）"
				% [attempt + 1, _p.velocity.y, y_before, _p.global_position.y])
			break
		Input.action_release("jump")
	Input.action_release("jump")
	print("  [jump] D 结果 = %s（velocity.y = %+.2f）" % [ok_d, _p.velocity.y])
	# E ⚠️ **合成输入事件**：真实按键走的是「事件缓冲 → 物理步前 `flush_buffered_events`」，
	#   帧计数器对的正是**下一个物理帧**；而 `Input.action_press` 是直接改状态，
	#   计数器停在上一个物理帧 ⇒ `player.gd` 在 `_physics_process` 里问
	#   `is_action_just_pressed` 永远看不到它。`_verify_spawnview` 驱动鼠标用的就是这条路。
	var ev := InputEventAction.new()
	ev.action = "jump"
	ev.pressed = true
	Input.parse_input_event(ev)
	await physics_frame
	await physics_frame
	print("  [jump] E 合成事件：velocity.y = %+.2f  floor = %s  y = %.2f"
		% [_p.velocity.y, _p.is_on_floor(), _p.global_position.y])
	ev = InputEventAction.new()
	ev.action = "jump"
	ev.pressed = false
	Input.parse_input_event(ev)
	await _wait(4)
	Input.action_press("move_forward")
	Input.action_press("sprint")

	var t0 := Time.get_ticks_msec()
	var n := 0
	while Time.get_ticks_msec() - t0 < 700:
		await process_frame
		n += 1
		# 复刻自检里的每帧转向
		var ps := _p.global_position
		var vs := Vector2(center.x - ps.x, center.z - ps.z)
		if vs.length() > 0.05:
			_aim(vs.normalized())
		_dump(n, "")
	_release()
	print("[probe] 结束位置 %s（W2 台面 %.2f）"
		% [str(_p.global_position.snappedf(0.01)), _pk.top_at(29)])
	quit(0)


func _dump(n: int, tag: String) -> void:
	var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var rig := _p.get_node_or_null("CameraRig") as Node3D
	var rb := rig.global_basis.z if rig != null else Vector3.ZERO
	print("  %02d %-6s v=(%+.2f,%+.2f) y=%+.2f floor=%s yaw=%+.1f rigY=%+.1f rigZ=(%+.2f,%+.2f) in=(%+.1f,%+.1f) W=%s"
		% [n, tag, _p.velocity.x, _p.velocity.z, _p.global_position.y, _p.is_on_floor(),
			rad_to_deg(_p._yaw), rad_to_deg(rig.rotation.y) if rig != null else 0.0,
			rb.x, rb.z, iv.x, iv.y, Input.is_action_pressed("move_forward")])


func _aim(dir: Vector2) -> void:
	_p._yaw = atan2(-dir.x, -dir.y)
	_p._facing_yaw = _p._yaw + PI
	_p.model_root.rotation.y = _p._facing_yaw


func _release() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "sprint", "crouch", "jump"]:
		Input.action_release(a)


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
