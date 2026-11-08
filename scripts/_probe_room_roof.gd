extends SceneTree
## 验收「站在屋顶上不许加载泼溅」。
##
##   godot --path . --windowed --script res://scripts/_probe_room_roof.gd
##
## 用户实测：站在屋顶 y=5.80、水平 (-1.30, 3.84)（在门框矩形内）时，
## 609 的泼溅被重新加载，显存涨回 2299 MiB、FPS 掉到 4.0。
## 根因是判据只判 XZ，屋顶正在房间正上方，分不出来。
##
## 用例（609 墙框 x −5.95~6.10 / z −6.93~14.02，墙 y −2.65~5.65，屋顶顶面 5.80）：
##   A 屋里地面 (0, 0, 6)          → 有
##   B 屋顶上   (-1.30, 5.80, 3.84) → **无**（用户报的那个位置）
##   C 墙外地面 (0, 0, -9)          → 无
##   D 走回屋里 (0, 0, 6)          → 有

const SCENE := "res://scenes/game.tscn"


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	var t := create_timer(300.0, true)
	t.timeout.connect(func():
		print("[roof] !! 看门狗超时")
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
	print("[roof] unload_outside_room = %s" % str(room.get("unload_outside_room")))

	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 180000:
		await process_frame
		if room.get("splat_node") != null:
			break
	var rect: Rect2 = room.get("_room_xz")
	var ylo: float = room.get("_room_y_lo")
	var yhi: float = room.get("_room_y_hi")
	print("[roof] 判据 x %.2f~%.2f  z %.2f~%.2f  y %.2f~%.2f" % [
		rect.position.x, rect.position.x + rect.size.x,
		rect.position.y, rect.position.y + rect.size.y, ylo, yhi])
	print("[roof] 首次就绪｜泼溅=%s｜VRAM %.1f MiB" % [
		str(room.get("splat_node") != null), _vram()])

	if p is CharacterBody3D:
		(p as CharacterBody3D).set_physics_process(false)

	await _at(p, room, "A 屋里地面", Vector3(0, 0.2, 6), true)
	await _at(p, room, "B 屋顶上  ", Vector3(-1.30, 5.80, 3.84), false)
	await _at(p, room, "C 墙外地面", Vector3(0, 0.2, -9), false)
	await _at(p, room, "D 走回屋里", Vector3(0, 0.2, 6), true)
	print("[roof] 完成")
	quit(0)


func _at(p: Node3D, room: Node, tag: String, pos: Vector3, want: bool) -> void:
	p.global_position = pos
	if p is CharacterBody3D:
		(p as CharacterBody3D).velocity = Vector3.ZERO
	var t0 := Time.get_ticks_msec()
	var ok := false
	while Time.get_ticks_msec() - t0 < 10000:
		await process_frame
		if (room.get("splat_node") != null) == want:
			ok = true
			for i in 10:
				await process_frame
			break
	var has := room.get("splat_node") != null
	print("[roof] %s @ (%.1f, %.2f, %.1f) → 泼溅 %s（期望 %s）%s｜%.1f s｜VRAM %.1f MiB" % [
		tag, pos.x, pos.y, pos.z, "有" if has else "无", "有" if want else "无",
		"" if ok else "  ❌", (Time.get_ticks_msec() - t0) / 1000.0, _vram()])
