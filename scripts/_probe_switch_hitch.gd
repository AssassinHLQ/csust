extends SceneTree
## 换窗口卡顿拆解：把「第二场景跨格子」这条路上的每一步**单独计时**。
##
## 已知（MEMORY §15）：跨格时最坏一帧 322~1258 ms。可疑的有四步：
##   ① `_write_window()`：主线程把 9 个分块文件**同步**拷成 user://campus_window.bin
##   ② `_release_campus(true)`：放掉细层光栅器（含 GPU 资源回收）
##   ③ `_make_bundle()`：重建光栅器 —— 重新编译 6 个 shader + 建 pipeline
##   ④ `pump_load` / `_pump_bin`：每帧 64 MB 上传，每帧都超预算
##
## 用法（必须真窗口）：
##   _tools/run_shot.sh res://scripts/_probe_switch_hitch.gd
## 输出：stdout + <工程>/_log/switch_hitch.txt

const WATCHDOG_MS := 900000
const BIG_FRAME_MS := 50

var _lines: PackedStringArray = PackedStringArray()
var _deadline := 0


func _initialize() -> void:
	_deadline = Time.get_ticks_msec() + WATCHDOG_MS
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size = Vector2i(1600, 900)
	await process_frame
	await process_frame
	Engine.max_fps = 0
	root.scaling_3d_scale = 0.5

	var level: Node = (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame

	var ggs: Node = null
	for i in 600:
		ggs = level.get_node_or_null("CampusGGS")
		if ggs != null:
			break
		await process_frame
	if ggs == null:
		_log("没找到 CampusGGS")
		quit(1)
		return
	var player: Node3D = level.get_node_or_null("Player") as Node3D
	if player == null:
		_log("没找到 Player")
		quit(1)
		return

	_log("=== 换窗口卡顿拆解 ===")
	_log("CampusGGS：分块=%s  窗口=%d×%d  粗层=%s" % [
		str(ggs.get("_use_chunks")), int(ggs.get("window_side")), int(ggs.get("window_side")),
		"开" if ggs.get("coarse_rasterizer") != null else "关"])

	# 出厅（`_process` 里 z < -74 才画校园）
	player.global_position = Vector3(0.0, 1.0, -120.0)
	var w0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - w0 < 180000:
		if String(ggs.get("_center_name")) != "" and _fine_loaded(ggs):
			break
		await process_frame
	if not _fine_loaded(ggs):
		_log("细层一直没加载完，退出")
		quit(1)
		return
	_log("首个窗口就位：%d 块，细层 %d 点，粗层 %d 点" % [
		(ggs.get("_window_names") as PackedStringArray).size(),
		int(ggs.get("_total")), int(ggs.get("_coarse_total"))])
	_log("")

	# ── 阶段 A：真实跨格，看游戏里玩家会感受到的最坏帧 ──
	var chunks: Array = ggs.get("_chunk_list")
	var path := _pick_path(chunks, player.global_position)
	_log("阶段 A：沿 %d 个格子中心走一遍（真实换窗口路径）" % path.size())
	for target in path:
		player.global_position = Vector3(target.x, 1.0, target.z)
		var before := String(ggs.get("_center_name"))
		var dts := await _walk_until_switch(ggs, before)
		var worst := 0.0
		var big := 0
		var total := 0.0
		for d in dts:
			worst = maxf(worst, d)
			total += d
			if d >= BIG_FRAME_MS:
				big += 1
		_log("  中心 %-12s → %-12s  %3d 帧  最坏 %7.1f ms  ≥%dms 的帧 %d  平均 %5.2f ms" % [
			before, String(ggs.get("_center_name")), dts.size(), worst, BIG_FRAME_MS,
			big, total / maxf(float(dts.size()), 1.0)])
	_log("")

	# ── 阶段 B：逐步计时 ──
	_log("阶段 B：把每一步单独计时（直接调内部函数）")
	var far := _far_chunk(chunks, player.global_position)
	if not far.is_finite():
		_log("  分块清单是空的，跳过阶段 B")
		_write_out()
		quit(0)
		return
	if true:
		player.global_position = Vector3(far.x, 1.0, far.z)
		await process_frame
		var want: PackedStringArray = ggs.call("_pick_window")
		var t0 := Time.get_ticks_msec()
		var bytes: int = ggs.call("_write_window", want)
		var t1 := Time.get_ticks_msec()
		_log("  ① _write_window   %d 块 / %.0f MB …… %d ms" % [
			want.size(), float(bytes) / 1048576.0, t1 - t0])

		t0 = Time.get_ticks_msec()
		ggs.call("_release_campus", true)
		t1 = Time.get_ticks_msec()
		_log("  ② _release_campus(true) …… %d ms" % (t1 - t0))

		ggs.set("_bin_path", "user://campus_window_a.bin")
		ggs.set("_window_names", want)
		ggs.set("_released", false)
		t0 = Time.get_ticks_msec()
		var ok: bool = ggs.call("_make_bundle")
		t1 = Time.get_ticks_msec()
		_log("  ③ _make_bundle（重建光栅器 / 编译 shader）…… %d ms（ok=%s）" % [t1 - t0, str(ok)])

		var up := await _walk_until_fine(ggs)
		var uw := 0.0
		var ubig := 0
		for d in up:
			uw = maxf(uw, d)
			if d >= BIG_FRAME_MS:
				ubig += 1
		_log("  ④ 上传新窗口：%d 帧，最坏 %7.1f ms，≥%dms 的帧 %d" % [
			up.size(), uw, BIG_FRAME_MS, ubig])

	_write_out()
	quit(0)


func _fine_loaded(ggs: Node) -> bool:
	var r = ggs.get("rasterizer")
	return r != null and r.is_loaded == true


## 从当前格出发，沿 z 轴挑一串格子（每个至少隔一格），保证每次都要真换窗口。
func _pick_path(chunks: Array, from: Vector3) -> Array:
	var sorted := chunks.duplicate()
	sorted.sort_custom(func(a, b): return (a["center"] as Vector3).z < (b["center"] as Vector3).z)
	var out: Array = []
	var last_z := INF
	for c in sorted:
		var p: Vector3 = c["center"]
		if absf(p.x - from.x) > 25.0:
			continue
		if absf(p.z - last_z) < 45.0:
			continue
		last_z = p.z
		out.append(p)
		if out.size() >= 6:
			break
	return out


func _far_chunk(chunks: Array, from: Vector3) -> Vector3:
	if chunks.is_empty():
		return Vector3.INF
	var best := Vector3.ZERO
	var bd := -1.0
	for c in chunks:
		var p: Vector3 = c["center"]
		var d := from.distance_to(p)
		if d > bd:
			bd = d
			best = p
	return best


## 逐帧采样，直到 `_center_name` 变了 **而且** 新细层加载完。
func _walk_until_switch(ggs: Node, before: String) -> PackedFloat32Array:
	var dts := PackedFloat32Array()
	var prev := Time.get_ticks_usec()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		dts.append(float(now - prev) / 1000.0)
		prev = now
		var now_name := String(ggs.get("_center_name"))
		if now_name != before and _fine_loaded(ggs):
			# 再多采 10 帧，把收尾也包进来
			for i in 10:
				await RenderingServer.frame_post_draw
				var n2 := Time.get_ticks_usec()
				dts.append(float(n2 - prev) / 1000.0)
				prev = n2
			return dts
	return dts


func _walk_until_fine(ggs: Node) -> PackedFloat32Array:
	var dts := PackedFloat32Array()
	var prev := Time.get_ticks_usec()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 120000:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		dts.append(float(now - prev) / 1000.0)
		prev = now
		if _fine_loaded(ggs):
			for i in 5:
				await RenderingServer.frame_post_draw
				var n2 := Time.get_ticks_usec()
				dts.append(float(n2 - prev) / 1000.0)
				prev = n2
			return dts
	return dts


func _write_out() -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("_log")
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("switch_hitch.txt"), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))
		f.close()


func _log(s: String) -> void:
	print("[hitch] " + s)
	_lines.append(s)
