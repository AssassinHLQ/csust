extends SceneTree
## 显存账单：校园点云到底占多少？其余是谁？
##
## 用户 2026-11-11：任务管理器里「专用 GPU 内存 6.9/8.0 GB」，
## 问「这个 lod 有效果吗？怎么还是占用这么多」。
##
## 先说结论性的判据：`lod_threshold_px` 走的是 `Viewport.mesh_lod_threshold`，
## **只管普通网格**（glb）；`addons/gdgs` 里根本没有 LOD 实现，
## 所以这个开关对校园点云一点作用都没有。这里用实测把「谁吃了显存」量出来。
##
##   _tools/run_shot.sh res://scripts/_probe_vram.gd -- --no-capture

const OffWin := preload("res://scripts/offscreen_window.gd")


func _initialize() -> void:
	if not OS.get_cmdline_user_args().has("--no-capture"):
		push_error("[vram] 缺 --no-capture")
		quit(2)
		return
	_run.call_deferred()


func _mb() -> float:
	return float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0


func _txt_mb() -> float:
	return float(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)) / 1048576.0


func _buf_mb() -> float:
	return float(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)) / 1048576.0


func _line(tag: String) -> void:
	print("[vram] %-22s 总计 %7.1f MB ｜ 纹理 %7.1f ｜ 缓冲 %7.1f"
		% [tag, _mb(), _txt_mb(), _buf_mb()])


func _run() -> void:
	await OffWin.apply(self, Vector2i(1280, 720))
	var safe0: Array = OffWin.is_safe()
	if not bool(safe0[0]):
		push_error("[vram] 窗口没挪到屏幕外：%s" % str(safe0[1]))
		quit(2)
		return

	# 先让 Performance 采一帧
	for _i in 10:
		await process_frame
	_line("空场景")

	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	# 玩家塞进校园：否则泼溅会被 unload 逻辑放掉
	var player := level.get_node_or_null("Player") as Node3D
	player.global_position = Vector3(-20.0, 2.0, -210.0)

	var campus: Node3D = level.get_node_or_null("Campus")
	# ★ 先别让它自己开始，量「没有点云」时的基线
	campus.set("start_delay", 0.0)
	campus.set("auto_start", false)
	for _i in 120:
		await process_frame
	_line("关卡就绪（无点云）")
	var base := _mb()

	campus.call("force_start")
	var t0 := Time.get_ticks_msec()
	while not bool(campus.call("is_ready")) and Time.get_ticks_msec() - t0 < 240000:
		await process_frame
	# 再等几十帧让 GPU 上传落定
	for _i in 90:
		await process_frame
	_line("点云加载完")
	var after := _mb()

	var node: Node3D = campus.get("splat_node")
	var g = node.get("gaussian")
	var pts := int(g.get("point_count")) if g != null else 0
	print("[vram] 点数 = %d" % pts)
	print("[vram] ★ 点云净增显存 = %.1f MB（%.1f MB → %.1f MB）"
		% [after - base, base, after])
	if pts > 0:
		print("[vram] ★ 折合 %.1f B/点" % ((after - base) * 1048576.0 / float(pts)))

	print("[vram] lod_threshold_px = %.2f（这是 Viewport.mesh_lod_threshold，**只管网格**）"
		% root.mesh_lod_threshold)
	print("[vram] crop_enabled=%s crop_margin=%.2f crop_max_scale=%.2f"
		% [str(campus.get("crop_enabled")), float(campus.get("crop_margin")),
		float(campus.get("crop_max_scale"))])
	var stats: Dictionary = campus.get("crop_stats")
	if not stats.is_empty():
		print("[vram] 裁剪统计 kept=%s dropped=%s scale_dropped=%s"
			% [str(stats.get("kept")), str(stats.get("dropped")),
			str(stats.get("scale_dropped"))])

	# 拆一下场景里的大户
	print("[vram] ── 场景大户（纹理/网格顶点）──")
	var world := level
	var stack: Array = [world]
	var rows := []
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var mi := n as MeshInstance3D
		if mi != null and mi.mesh != null:
			var v := 0
			for si in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(si)
				if arr.size() > Mesh.ARRAY_VERTEX and arr[Mesh.ARRAY_VERTEX] != null:
					v += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			if v > 20000:
				rows.append([v, mi.get_path()])
		for c in n.get_children():
			stack.append(c)
	rows.sort_custom(func(a, b): return int(a[0]) > int(b[0]))
	for i in mini(rows.size(), 8):
		print("[vram]   %8d 顶点  %s" % [int(rows[i][0]), str(rows[i][1])])

	# ══════════════════════════════════════════════════════════════
	#  决定性实验：把「渲染距离」压到 5 m、把点云整个藏起来，
	#  显存会不会降？如果一点都不降，就证明「调近加载距离」对显存无效。
	# ══════════════════════════════════════════════════════════════
	print("[vram] ══ 决定性实验：看得见 / 看不见，显存有区别吗 ══")
	var cam := root.get_viewport().get_camera_3d()
	if cam != null:
		print("[vram] 相机 far = %.1f m" % cam.far)
		cam.far = 5.0
	for _i in 60:
		await process_frame
	print("[vram] ① 相机 far 压到 5 m     → %7.1f MB" % _mb())

	root.mesh_lod_threshold = 8.0
	for _i in 60:
		await process_frame
	print("[vram] ② LOD 阈值调到 8.0 px  → %7.1f MB" % _mb())

	node.visible = false
	for _i in 60:
		await process_frame
	print("[vram] ③ 点云节点 visible=false → %7.1f MB" % _mb())

	# ④ 真正把节点从注册表摘掉（= 卸载），才会真的还显存
	node.get_parent().remove_child(node)
	node.queue_free()
	for _i in 120:
		await process_frame
	print("[vram] ④ 把点云节点整个 free 掉 → %7.1f MB  ← 只有这一步才降" % _mb())

	print("[vram] 完")
	quit(0)
