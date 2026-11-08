extends SceneTree
## 验收「跨出门框就释放泼溅显存 / 进门再开」。
##
##   _tools/run_shot.sh res://scripts/_probe_room_unload.gd
##
## 做法：真场景 + 真玩家，把玩家瞬移到几个位置，各停若干帧，
## 看 `Room609.splat_node` 在不在、VRAM 多少。
##
## 位置（实测画室609 墙框 x −5.85~4.86 / z −6.78~13.86）：
##   A 房间中央 (0, 0, 6)      → 应该**有**泼溅
##   B 门里侧   (0, 0, -6.0)   → 应该**有**泼溅（还在框内）
##   C 门框线上 (0, 0, -6.9)   → 应该**开始释放**（框外）
##   D 门外走廊 (0, 0, -9.0)   → 应该**已释放**
##   E 走回房里 (0, 0, 6)      → 应该**重新加载**回来

const SCENE := "res://scenes/game.tscn"
const STILL := 30


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	var t := create_timer(300.0, true)
	t.timeout.connect(func():
		print("[unload] !! 看门狗超时")
		quit(1))
	_run.call_deferred()


func _vram() -> float:
	var d := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)
	return float(d) / 1048576.0


func _run() -> void:
	var packed := load(SCENE) as PackedScene
	if packed == null:
		print("[unload] !! 载入失败")
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	var room: Node = scene.get_node_or_null("Room609")
	if room == null:
		print("[unload] !! 无 Room609")
		quit(1)
		return
	print("[unload] 设置 splat_unload_outside = %s" % str(GameSettings.value("splat_unload_outside")))
	print("[unload] 节点 unload_outside_room = %s" % str(room.get("unload_outside_room")))

	var p := get_first_node_in_group("player") as Node3D
	if p == null:
		p = scene.get_node_or_null("Player") as Node3D
	if p == null:
		print("[unload] !! 无玩家")
		quit(1)
		return

	# 等第一次加载完成
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 180000:
		await process_frame
		if room.get("splat_node") != null:
			break
	print("[unload] 房间范围 _room_xz = %s" % str(room.get("_room_xz")))
	print("[unload] 首次就绪 %.1f s｜泼溅=%s｜VRAM %.1f MiB" % [
		(Time.get_ticks_msec() - t0) / 1000.0,
		str(room.get("splat_node") != null), _vram()])

	# 把玩家物理停下来，免得瞬移后被墙推回去
	if p is CharacterBody3D:
		(p as CharacterBody3D).velocity = Vector3.ZERO

	await _at(p, room, "A 房间中央", Vector3(0, 0.2, 6), true)
	await _at(p, room, "B 门里侧  ", Vector3(0, 0.2, -6.0), true)
	await _at(p, room, "C 门框线上", Vector3(0, 0.2, -6.9), false)
	await _at(p, room, "D 门外走廊", Vector3(0, 0.2, -9.0), false)
	await _at(p, room, "E 走回房里", Vector3(0, 0.2, 6), true)

	print("[unload] 完成")
	quit(0)


func _at(p: Node3D, room: Node, tag: String, pos: Vector3, want_splat: bool) -> void:
	p.global_position = pos
	if p is CharacterBody3D:
		(p as CharacterBody3D).velocity = Vector3.ZERO
	# 等到「泼溅状态」符合预期，最多 8 秒（重载 2.3 s + 余量）
	var t0 := Time.get_ticks_msec()
	var got := false
	while Time.get_ticks_msec() - t0 < 8000:
		await process_frame
		var has := room.get("splat_node") != null
		if has == want_splat:
			got = true
			# 多等几帧确认稳定（防抖是 2 帧）
			for i in 10:
				await process_frame
			break
	var has_final := room.get("splat_node") != null
	var elapsed := (Time.get_ticks_msec() - t0) / 1000.0
	print("[unload] %s @ z=%.1f → 泼溅 %s（期望 %s）%s｜%.1f s｜VRAM %.1f MiB" % [
		tag, pos.z,
		"有" if has_final else "无", "有" if want_splat else "无",
		"" if has_final == want_splat else "  ❌",
		elapsed, _vram()])
