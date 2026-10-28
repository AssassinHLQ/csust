extends SceneTree
## Compute 后端在 3× 校园下的实测：帧率、显存、俯视/地面画面、转视角稳定性。
##   _tools/run_shot.sh res://scripts/_probe_campus_compute.gd -- --no-capture
## 出图：_campus_compute_{overview,ground,rot0..3}.png

func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(name)
	root.get_texture().get_image().save_png(out)
	print("[compute] 截图 %s" % out)


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	var campus := level.get_node("Campus")
	campus.call("force_start")
	var t0 := Time.get_ticks_msec()
	while not bool(campus.call("is_ready")) and Time.get_ticks_msec() - t0 < 180000:
		await process_frame
	if not bool(campus.call("is_ready")):
		print("[compute] 校园没加载完")
		quit(1)
		return
	var player := level.get_node("Player") as CharacterBody3D
	player.global_position = Vector3(0.0, 0.3, -150.0)
	for _i in 10:
		await physics_frame
	for c in level.find_children("*", "CanvasLayer", true, false):
		var cl := c as CanvasLayer
		if cl != null:
			cl.visible = false
	var cam := Camera3D.new()
	cam.fov = 70.0
	level.add_child(cam)
	cam.current = true

	# 俯瞰
	cam.global_position = Vector3(120.0, 190.0, 30.0)
	cam.look_at(Vector3(0.0, 0.0, -260.0))
	await _shot("_campus_compute_overview.png")

	# 地面平视
	cam.global_position = Vector3(0.0, 1.7, -150.0)
	cam.look_at(Vector3(0.0, 1.7, -260.0))
	cam.fov = 72.0
	for _i in 3:
		await process_frame
	print("[compute] 显存 %.0f MB / 静态内存 %.0f MB" % [
		float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0,
		float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0])
	var f0 := Time.get_ticks_msec()
	for _i in 30:
		await process_frame
	var dt := (Time.get_ticks_msec() - f0) / 1000.0
	print("[compute] 地面平视 30 帧 %.2f s → %.1f fps" % [dt, 30.0 / dt])
	await _shot("_campus_compute_ground.png")

	# 小角度转视角：每 3° 一帧，看有没有整块跳
	cam.global_position = Vector3(0.0, 1.7, -150.0)
	var base := Vector3(0.0, 1.7, -260.0)
	for i in 4:
		var ang := deg_to_rad(3.0 * i)
		var target := Vector3(base.x + sin(ang) * 110.0, 1.7,
			base.z + cos(ang) * 110.0)
		cam.look_at(target)
		await _shot("_campus_compute_rot%d.png" % i)
	quit(0)
