extends SceneTree
## 验「反复换分块窗口会不会把显存越吃越多」：离屏真窗口。
##
##   _tools/run_shot.sh res://scripts/_probe_vram_switch.gd
##
## 背景：用户 F3 实测 6918 MiB，而本喵量「第一场景 + 画室609」只有 3069 MiB、
## 跨场景来回也不涨。那就剩一个嫌疑：**校园里每跨一格就重拼一次 bin（100~270 MB）**，
## 每次都新建 Texture2DRD / 缓冲，驱动不还的话显存就一路涨。
##
## 做法：把玩家沿 -Z 一格格挪过去，每跨一次记一次显存，看曲线是不是单调上升。

const S2 := "res://scenes/next_level.tscn"
## 沿校园纵深走（z 从 -150 走到 -450，每 45 m 跨一格）
const Z_FROM := -150.0
const Z_TO := -450.0
const STEPS := 9


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	var t := create_timer(420.0, true)
	t.timeout.connect(func():
		print("[sw] !! 看门狗超时")
		quit(1))
	_run.call_deferred()


func _v() -> float:
	return float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0


func _buf() -> float:
	return float(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)) / 1048576.0


func _run() -> void:
	GameSettings.set_value("vsync", false)
	GameSettings.set_value("fps_limit", 0.0)
	root.size = Vector2i(1280, 720)

	var level := (load(S2) as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	for _i in 180:
		await process_frame

	var ggs := level.get_node_or_null("CampusGGS")
	var p := level.get_node_or_null("Player") as Node3D
	if ggs == null or p == null:
		print("[sw] !! 缺 CampusGGS 或 Player")
		quit(1)
		return
	p.set_physics_process(false)

	print("[sw] 起点：(%.0f, %.0f)｜显存 %.0f MiB（缓冲 %.0f）" % [
		p.global_position.x, p.global_position.z, _v(), _buf()])
	var first := _v()
	var switches := 0
	for i in range(1, STEPS + 1):
		var t := float(i) / float(STEPS)
		var z: float = lerpf(Z_FROM, Z_TO, t)
		p.global_position = Vector3(60.0, 1.0, z)
		# 等窗口评估（WINDOW_POLL 0.5 s）+ 重拼 + 重传
		for _j in 200:
			await process_frame
			var r = ggs.get("rasterizer")
			if r != null and bool(r.get("is_loaded")):
				break
		switches += 1
		print("[sw] 第 %d 站 z=%.0f｜窗口 %d 块｜显存 %7.0f（%+7.0f vs 起点）｜缓冲 %7.0f" % [
			i, z, (ggs.get("_window_names") as PackedStringArray).size(),
			_v(), _v() - first, _buf()])

	print("[sw] 判据：显存应基本持平。若每跨一格就涨 100~300 MB，就是每次重拼都在漏。")
	quit(0)
