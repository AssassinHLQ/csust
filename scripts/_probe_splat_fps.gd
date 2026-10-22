extends SceneTree
## 只读探针：浇溅开/关的帧率对比（给「3DGS 适不适合替代粒子特效」这个问题提供实测）。
##   godot --path . --script res://scripts/_probe_splat_fps.gd -- --splat=off   （关）
##   godot --path . --script res://scripts/_probe_splat_fps.gd                  （开）
## 站在画室609 里朝房间中心看，采样 3 秒。

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	# ⚠️ 必须解除帧率上限（设置里默认 60），否则两档都是 60 fps，量不出差别
	Engine.max_fps = 0
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 90:
		await process_frame
	paused = false
	Engine.max_fps = 0
	var dlg := game.get_node_or_null("DialogueBox") as CanvasLayer
	if dlg != null:
		dlg.visible = false
		if dlg.has_method("skip_all"):
			dlg.call("skip_all")
	for _i in 30:
		await process_frame

	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.05
	cam.far = 120.0
	root.add_child(cam)
	cam.make_current()
	# 画室内部：站在房间靠墙一侧朝另一头看，尽量让泼溅铺满画面
	cam.global_position = Vector3(-0.42, 1.79, 10.2)
	cam.look_at(Vector3(-0.42, 1.30, -6.0), Vector3.UP)

	# 数哪里来的点：SplatScene 有几个、多少点
	var pts := 0
	var ready_n := 0
	for c in game.get_children():
		if c is SplatScene:
			var s := c as SplatScene
			if s.is_ready():
				ready_n += 1
	print("[fps] 泼溅场景 %d 个（就绪 %d）" % [game.find_children("*", "", true, false).size(), ready_n])

	# 等两秒让画面稳定（着色器编译、纹理上传）
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2000:
		await process_frame

	var f0 := Engine.get_frames_drawn()
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 3000:
		await process_frame
	var dt := (Time.get_ticks_msec() - t1) / 1000.0
	var frames := Engine.get_frames_drawn() - f0
	print("[fps] 模式=%s  3 秒画了 %d 帧 → %.1f fps  图元 %.0f  draw call %.0f"
		% ["关泼溅" if "--splat=off" in OS.get_cmdline_user_args() else "开泼溅",
			frames, frames / dt,
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	quit(0)
