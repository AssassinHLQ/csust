extends SceneTree
## 泼溅成本**分段**探针：改变渲染分辨率，看泼溅那 8 ms 里哪一部分跟像素走。
##
## 原理：同一档配置下
##   · **投影 + 排序** 的开销和屏幕像素数**无关**（点数固定）
##   · **raster** 的开销和像素数**成正比**（每个 tile 每个像素都要循环）
## 所以扫 0.25 / 0.5 / 1.0 三个缩放，就能把「固定成本」和「像素成本」分开。
##
## 三个对照（各自一个进程，见 `_tools/_run_splat_split.sh`）：
##   ① 正常              → 整帧
##   ② `--gdgs-skip-sort` → 摘掉排序那 4 遍（⚠️ 画面是错的，只看时间）
##   ③ `--splat=off`      → 摘掉整个泼溅
##
## 三者相减就得到：排序 / 投影+raster / 非泼溅底子。
##
## ⚠️ 必须带 `--gdgs-idle-skip=off`：否则相机静止时泼溅整条链被跳过，量出来全是 0。
##
## 用法：
##   _tools/run_shot.sh res://scripts/_probe_splat_scaling.gd -- --gdgs-idle-skip=off

const WARMUP := 20
const MEASURE := 90
const WATCHDOG_MS := 600000

var _scales: Array[float] = [0.25, 0.5, 1.0]
var _lines: PackedStringArray = PackedStringArray()
var _deadline := 0


func _initialize() -> void:
	_deadline = Time.get_ticks_msec() + WATCHDOG_MS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scales="):
			_scales.clear()
			for s in a.substr(9).split(","):
				_scales.append(float(s))
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(1600, 900)
	await process_frame
	await process_frame
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	await process_frame

	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)

	var w0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - w0 < 120000:
		var room: Node = game.get_node_or_null("Room609")
		if room != null and room.get("splat_node") != null:
			break
		await process_frame

	for c in game.get_children():
		var n := String(c.name)
		if n.begins_with("Companion") or n.begins_with("Target") or n.begins_with("Boss"):
			(c as Node).process_mode = Node.PROCESS_MODE_DISABLED
	var hud := game.get_node_or_null("HUD")
	if hud != null:
		(hud as CanvasLayer).visible = false

	var tag := "正常"
	if _has_arg("--gdgs-skip-sort"):
		tag = "跳过排序（只看时间）"
	if _has_arg("--splat=off") or _has_arg("--no-splat"):
		tag = "关泼溅"
	_log("配置：%s   视口 %s" % [tag, str(root.size)])
	_log("缩放    渲染像素      p50      p99      fps     显存 MiB   draw")
	_log("")

	for s in _scales:
		Engine.max_fps = 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		root.scaling_3d_scale = s
		for i in WARMUP:
			await process_frame
		var r := await _measure()
		_log("%.2f    %5d×%-5d  %6.2f   %6.2f   %6.1f   %7.0f   %5d" % [
			s, int(root.size.x * s), int(root.size.y * s),
			r["p50"], r["p99"], r["fps"], r["vram"], r["draw"]])

	_write_out()
	quit(0)


func _has_arg(want: String) -> bool:
	for a in OS.get_cmdline_user_args():
		if a == want:
			return true
	return false


func _measure() -> Dictionary:
	var dts := PackedFloat32Array()
	var prev := Time.get_ticks_usec()
	for i in MEASURE:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		dts.append(float(now - prev) / 1000.0)
		prev = now
	var sorted := PackedFloat32Array(dts)
	sorted.sort()
	var n := sorted.size()
	var sum := 0.0
	for v in sorted:
		sum += v
	return {
		"p50": sorted[int(n * 0.50)],
		"p99": sorted[mini(int(n * 0.99), n - 1)],
		"fps": 1000.0 / maxf(sum / float(n), 1e-6),
		"draw": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"vram": float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0,
	}


func _write_out() -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("_log")
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("splat_split.txt"), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))
		f.close()


func _log(s: String) -> void:
	print("[split] " + s)
	_lines.append(s)
