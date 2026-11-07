extends SceneTree
## 贴脸补光 FaceFill 到底吃不吃帧：同一机位交替 开/关，两轮抵消漂移。
##   _tools/run_shot.sh res://scripts/_probe_facefill.gd -- --splat=off --story=off


const ROOM := "GameDevRoom"
const WARM := 20
const SAMPLE := 40


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var hit := _find_mesh(c)
		if hit != null:
			return hit
	return null


func _measure(tag: String) -> float:
	await _wait(WARM)
	var t0 := Time.get_ticks_usec()
	for _i in SAMPLE:
		await process_frame
	var fps := float(SAMPLE) / maxf(float(Time.get_ticks_usec() - t0) / 1000000.0, 0.0001)
	print("[fill] %-10s fps=%6.1f draws=%4d prims=%7d" % [tag, fps,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))])
	return fps


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(180)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var player := game.get_node_or_null("Player") as Node3D
	var fill := game.get_node_or_null("Player/FaceFill") as OmniLight3D
	var room := game.get_node_or_null(ROOM) as Node3D
	var mi := _find_mesh(room) if room != null else null
	if player == null or fill == null or mi == null:
		print("[fill] 缺 Player / FaceFill / 部室网格")
		quit(1)
		return
	print("[fill] FaceFill: energy=%.2f range=%.2f shadow=%s specular=%.2f" % [
		fill.light_energy, fill.omni_range, str(fill.shadow_enabled), fill.light_specular])

	var a := mi.get_aabb()
	var xf := mi.global_transform
	var centre := xf * Vector3(a.get_center().x, 1.2, a.get_center().z)

	# 玩家站到那一角，相机贴墙 —— 就是墙上出现光斑的那个机位
	player.global_position = xf * Vector3(a.end.x - 0.9, 0.1, a.end.z - 0.9)
	player.set("velocity", Vector3.ZERO)
	await _wait(60)
	var cam := Camera3D.new()
	cam.far = 400.0
	cam.near = 0.05
	cam.fov = 70.0
	root.add_child(cam)
	cam.current = true
	cam.global_position = xf * Vector3(a.end.x - 0.9, 1.6, a.end.z - 0.9)
	cam.look_at(centre, Vector3.UP)

	var on_sum := 0.0
	var off_sum := 0.0
	for r in 2:
		fill.visible = true
		on_sum += await _measure("r%d 开" % r)
		fill.visible = false
		off_sum += await _measure("r%d 关" % r)
	fill.visible = true
	print("[fill] 平均：开 %.1f fps / 关 %.1f fps" % [on_sum * 0.5, off_sum * 0.5])
	quit(0)