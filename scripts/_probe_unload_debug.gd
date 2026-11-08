extends SceneTree
## 诊断：玩家站在门外时，609 的「出房间释放」为什么没生效。
##
##   godot --path . --windowed --script res://scripts/_probe_unload_debug.gd
##
## 用户实测：站在 (5.74, 0.00, 1.81) —— 墙外框只到 x=4.86，这是**屋外**，
## 可是显存 2324 MiB，泼溅还在。说明 `_update_room_exit_unload()` 要么没跑、
## 要么判成屋里、要么被别的条件卡住。
##
## 逐步打印每个可能卡住的地方，不猜。

const SCENE := "res://scenes/game.tscn"


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	var t := create_timer(300.0, true)
	t.timeout.connect(func():
		print("[dbg] !! 看门狗超时")
		quit(1))
	_run.call_deferred()


func _vram() -> float:
	return float(RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)) / 1048576.0


func _run() -> void:
	var packed := load(SCENE) as PackedScene
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	var room: Node = scene.get_node_or_null("Room609")
	var p := scene.get_node_or_null("Player") as Node3D

	print("[dbg] ===== ① 开关状态 =====")
	print("[dbg]   GameSettings splat_unload_outside = %s" % str(GameSettings.value("splat_unload_outside")))
	print("[dbg]   room.unload_outside_room          = %s" % str(room.get("unload_outside_room")))
	print("[dbg]   room.process_mode                 = %s" % str(room.process_mode))
	print("[dbg]   room.is_processing()              = %s" % str(room.is_processing()))

	# 等点云加载
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 180000:
		await process_frame
		if room.get("splat_node") != null:
			break
	print("[dbg] ===== ② 加载完成 =====")
	print("[dbg]   splat_node = %s｜VRAM %.1f MiB" % [
		str(room.get("splat_node") != null), _vram()])
	var rect: Rect2 = room.get("_room_xz")
	print("[dbg]   _room_xz = x %.2f~%.2f  z %.2f~%.2f" % [
		rect.position.x, rect.position.x + rect.size.x,
		rect.position.y, rect.position.y + rect.size.y])
	print("[dbg]   _room_y_lo/_hi = %.2f / %.2f" % [
		float(room.get("_room_y_lo")), float(room.get("_room_y_hi"))])
	print("[dbg]   _room_xz_is_walls = %s" % str(room.get("_room_xz_is_walls")))

	# 停掉物理，把玩家放到用户报的位置
	if p is CharacterBody3D:
		(p as CharacterBody3D).set_physics_process(false)

	print("[dbg] ===== ③ 把玩家放到 (5.74, 0.00, 1.81) =====")
	p.global_position = Vector3(5.74, 0.00, 1.81)
	await process_frame
	await process_frame

	# 手动算 _is_inside_room
	var inside: bool = room.call("_is_inside_room", p.global_position)
	print("[dbg]   _is_inside_room(5.74, 0.00, 1.81) = %s  ← 期望 false" % str(inside))
	print("[dbg]   _player_node() = %s" % str(room.call("_player_node")))

	# 看几个内部状态
	print("[dbg]   loading = %s｜_thread = %s" % [
		str(room.get("loading")), str(room.get("_thread"))])
	print("[dbg]   _outside_clock = %.2f｜_outside_streak = %d" % [
		float(room.get("_outside_clock")), int(room.get("_outside_streak"))])
	print("[dbg]   _inside_clock = %.2f｜_inside_streak = %d" % [
		float(room.get("_inside_clock")), int(room.get("_inside_streak"))])

	# 等 3 秒看有没有释放
	print("[dbg] ===== ④ 原地等 3 秒，看会不会释放 =====")
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 3000:
		await process_frame
	print("[dbg]   splat_node = %s｜VRAM %.1f MiB" % [
		str(room.get("splat_node") != null), _vram()])
	print("[dbg]   _outside_clock = %.2f｜_outside_streak = %d" % [
		float(room.get("_outside_clock")), int(room.get("_outside_streak"))])

	print("[dbg] ===== ⑤ 再挪到真正的屋外 (0, 0, -9) 对照 =====")
	p.global_position = Vector3(0.0, 0.2, -9.0)
	var t2 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t2 < 5000:
		await process_frame
		if room.get("splat_node") == null:
			break
	print("[dbg]   splat_node = %s｜VRAM %.1f MiB｜耗时 %.1f s" % [
		str(room.get("splat_node") != null), _vram(),
		(Time.get_ticks_msec() - t2) / 1000.0])

	print("[dbg] 完成")
	quit(0)
