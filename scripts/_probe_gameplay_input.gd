extends SceneTree
## 探针：把 scenes/game.tscn 当主场景真跑起来，回答「为什么进去动不了」。
##
## ⚠️ 故意**不加 `--splat=off`**：加了的话 `splat_scene.gd::_disable_placed_collision()`
##    会把房间里手摆的碰撞全关掉，测出来的是「一间没有墙的房间」，撞墙卡住这种情况
##    根本测不到。
##
## ⚠️ 位移必须同时报**帧率**和**物理帧数**，否则分不清两种完全不同的病因：
##      ① 物理时间被稀释 —— 渲染帧太慢，Godot 每帧最多跑 max_physics_steps_per_frame
##         步物理，于是「1 秒内只推进了几步」，玩家看着就像不动
##      ② 被碰撞卡住 —— 物理帧数正常，但位移很小
##    本喵就靠这个量出了「全屏 2560×1440 把 1.9 m/s 打成 0.17 m/s」。
##
## 用法：
##   godot --path . --script res://scripts/_probe_gameplay_input.gd

const GAME := "res://scenes/game.tscn"
const MEASURE_SEC := 1.5

var _player: Node3D = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ps: PackedScene = load(GAME)
	root.add_child(ps.instantiate())
	await _frames(10)

	_player = root.get_node_or_null("Game/Player")
	if _player == null:
		push_error("[gp] 没有 Player")
		quit(1)
		return
	var room: Node3D = root.get_node_or_null("Game/Room609")
	var menu: Node = root.get_node_or_null("Game/SettingsMenu")

	var t0 := Time.get_ticks_msec()
	while room != null and not bool(room.call("is_ready")) and Time.get_ticks_msec() - t0 < 40000:
		await _frames(6)
	print("[gp] 泼溅就绪 = %s（等了 %d ms）" % [
		str(room.call("is_ready")) if room != null else "无 Room609", Time.get_ticks_msec() - t0])

	print("[gp] ── 开局状态 ──")
	print("[gp]   Input.mouse_mode = %d（2 = CAPTURED，0 = VISIBLE）" % Input.mouse_mode)
	print("[gp]   paused = %s    Esc 菜单 is_open = %s    window_is_focused = %s" % [
		str(paused), str(menu.get("is_open")) if menu != null else "无菜单",
		str(DisplayServer.window_is_focused())])
	print("[gp]   玩家位置 = %s" % str(_player.global_position.snappedf(0.01)))
	print("[gp]   视口尺寸 = %s（root.size）" % str(root.size))
	print("[gp]   max_physics_steps_per_frame = %d" % Engine.max_physics_steps_per_frame)
	print("[gp]   RoomCollision collision_layer = %d（0 = 被跳过加载关掉了）" % (
		(root.get_node("Game/Room609/RoomCollision") as CollisionObject3D).collision_layer
		if room != null and room.get_node_or_null("RoomCollision") != null else -1))

	# 出生点胶囊压到什么
	var probe := CapsuleShape3D.new()
	probe.radius = 0.3
	probe.height = 1.7
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = probe
	q.transform = Transform3D(Basis.IDENTITY, _player.global_position + Vector3.UP * 0.85)
	q.collision_mask = 0xFFFFFFFF
	var hits := _player.get_world_3d().direct_space_state.intersect_shape(q, 16)
	var names: Array[String] = []
	for h in hits:
		names.append(String((h["collider"] as Node).name))
	print("[gp]   出生点胶囊压到的碰撞体 %d 个：%s" % [hits.size(), str(names)])

	# ── 当前（全屏 2560×1440）下量一次 ──
	print("[gp] ── 按 W %.1f 秒 @ 当前视口（%s）──" % [MEASURE_SEC, str(root.size)])
	var a := await _measure_move(MEASURE_SEC)
	_report(a)

	# ── 把视口缩回设计分辨率，再量一次 ──
	# 这就是全屏真正的代价：`canvas_items` 拉伸模式下 3D 视口 = 窗口尺寸，
	# 所以全屏 2560×1440 就是把 3D 渲染面积翻了 2.6 倍。
	root.size = Vector2i(1600, 900)
	await _frames(20)
	print("[gp] ── 按 W %.1f 秒 @ 视口缩到 1600×900（=%s）──" % [MEASURE_SEC, str(root.size)])
	var b := await _measure_move(MEASURE_SEC)
	_report(b)

	print("[gp] ── 真键盘事件（Input.parse_input_event，物理键 W）──")
	var down := InputEventKey.new()
	down.physical_keycode = KEY_W
	down.keycode = KEY_W
	down.pressed = true
	Input.parse_input_event(down)
	await _frames(3)
	print("[gp]   is_action_pressed(\"move_forward\") = %s（true 说明键位映射没问题）" % str(
		Input.is_action_pressed("move_forward")))
	var pos0 := _player.global_position
	var t3 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t3 < 1000:
		await process_frame
	var up := InputEventKey.new()
	up.physical_keycode = KEY_W
	up.keycode = KEY_W
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(3)
	print("[gp]   真键盘事件位移 %.3f m" % _player.global_position.distance_to(pos0))

	quit(0)


## 按住 W 一段时间，同时统计渲染帧 / 物理帧 / 位移。
func _measure_move(sec: float) -> Dictionary:
	var f0 := Engine.get_frames_drawn()
	var p0 := Engine.get_physics_frames()
	var pos0 := _player.global_position
	Input.action_press("move_forward")
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < int(sec * 1000.0):
		await process_frame
	Input.action_release("move_forward")
	await _frames(2)
	var moved := _player.global_position.distance_to(pos0)
	return {
		"fps": float(Engine.get_frames_drawn() - f0) / sec,
		"phys": float(Engine.get_physics_frames() - p0) / sec,
		"moved": moved,
		"mps": moved / sec,
	}


func _report(m: Dictionary) -> void:
	# 60 Hz 物理下，1 秒该有 60 个物理帧；明显少于它 = 物理时间被稀释（渲染太慢）
	var phys := float(m["phys"])
	var verdict := "✅ 正常"
	if m["mps"] < 0.5:
		verdict = "⚠️ 几乎不动"
	elif m["mps"] < 1.5:
		verdict = "⚠️ 明显偏慢（走路应 2.0 m/s）"
	if phys < 45.0:
		verdict += "；物理帧只有 %.0f/秒 ⇒ **物理时间被稀释**（渲染跟不上）" % phys
	print("[gp]   渲染 %.1f fps ｜ 物理 %.1f 帧/秒 ｜ 位移 %.3f m（%.2f m/s）  %s" % [
		float(m["fps"]), phys, float(m["moved"]), float(m["mps"]), verdict])


func _frames(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
