extends SceneTree
## 量第一场景（画室609 泼溅）的**显存与帧率代价**：离屏真窗口，不抢前台。
##
##   # 开泼溅（默认）
##   _tools/run_shot.sh res://scripts/_probe_vram_cost.gd
##   # 关泼溅（基线）—— 两次一减就是泼溅自己的代价
##   _tools/run_shot.sh res://scripts/_probe_vram_cost.gd -- --splat=off
##
## 为什么要开窗口：`Performance.RENDER_VIDEO_MEM_USED` 只在有渲染设备时才有值，
## headless 下恒为 0（MEMORY §3 记过这条）。
##
## 打印四段：
##   ① 场景刚起来、泼溅还没加载
##   ② 泼溅加载完
##   ③ 3D 缩放 0.5（用户平时用的档）
##   ④ 3D 缩放 1.0（会掉到个位数帧的那档）
## 每段都给：进程内显存、实测 fps（帧间隔均值 + p99）。

const SCENE := "res://scenes/game.tscn"
const SETTLE := 40          # 每段先跑几帧让渲染稳定
const MEASURE := 150        # 正式计量的帧数


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	# 看门狗：任何一步出错都别挂死（踩过一次 10 分钟）
	var t := create_timer(180.0, true)
	t.timeout.connect(func():
		print("[vram] !! 看门狗超时，强制退出")
		quit(1))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame


func _vram() -> float:
	return float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0


func _objects() -> int:
	return int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))


func _draws() -> int:
	return int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))


## 跑 MEASURE 帧，返回 {fps, p50, p99, vram, objects, draws}
func _measure() -> Dictionary:
	await _wait(SETTLE)
	var dts: Array[float] = []
	for _i in MEASURE:
		var t0 := Time.get_ticks_usec()
		await process_frame
		dts.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	dts.sort()
	var sum := 0.0
	for d in dts:
		sum += d
	var avg := sum / maxf(float(dts.size()), 1.0)
	return {
		"fps": 1000.0 / maxf(avg, 0.001),
		"p50": dts[dts.size() / 2],
		"p99": dts[mini(int(float(dts.size()) * 0.99), dts.size() - 1)],
		"vram": _vram(),
		"objects": _objects(),
		"draws": _draws(),
	}


func _line(tag: String, m: Dictionary) -> void:
	print("[vram] %-18s 显存 %7.0f MiB｜%6.1f fps（p50 %5.1f / p99 %5.1f ms）｜物体 %5d｜draw %5d" % [
		tag, float(m["vram"]), float(m["fps"]), float(m["p50"]), float(m["p99"]),
		int(m["objects"]), int(m["draws"])])


func _run() -> void:
	# ⚠️ 第一版忘了这两句：默认 `fps_limit = 60` 且开 vsync，四段全是 60.0 fps，
	#    等于没量到性能。
	GameSettings.set_value("vsync", false)
	GameSettings.set_value("fps_limit", 0.0)

	var ua := OS.get_cmdline_user_args()
	var which := "res://scenes/game.tscn"
	for a in ua:
		if not String(a).begins_with("--"):
			which = String(a)
	root.size = Vector2i(1920, 1080)

	var game: Node = null
	if which == "empty":
		# 引擎地板：一个空 Node3D + 相机，用来把「引擎+窗口」和「场景」分开
		var bare := Node3D.new()
		var cam := Camera3D.new()
		cam.position = Vector3(0, 1.6, 0)
		bare.add_child(cam)
		cam.current = true
		game = bare
		print("[vram] 空场景基线（只有相机）")
	else:
		game = (load(which) as PackedScene).instantiate()
		print("[vram] 场景 %s" % which)
	root.add_child(game)
	current_scene = game
	await _wait(60)

	_line("① 刚起来（无泼溅）", await _measure())

	# 等泼溅加载完（Room609.is_ready()）
	var room := game.get_node_or_null("Room609")
	if room == null:
		print("[vram] !! 没找到 Room609 节点")
	else:
		var waited := 0
		while waited < 900:
			await _wait(30)
			waited += 30
			if bool(room.call("is_ready")):
				break
		print("[vram] 泼溅就绪=%s（等了 %d 帧）" % [str(room.call("is_ready")), waited])
	_line("② 泼溅加载完", await _measure())

	# ③ 用户平时的档：3D 缩放 0.5
	GameSettings.set_value("resolution_scale", 0.5)
	await _wait(30)
	_line("③ 缩放 0.5", await _measure())

	# ④ 会掉帧的那档：1.0
	GameSettings.set_value("resolution_scale", 1.0)
	await _wait(30)
	_line("④ 缩放 1.0", await _measure())

	print("[vram] 内存（CPU）%.0f MiB｜静态 %.0f MiB" % [
		float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0,
		float(Performance.get_monitor(Performance.MEMORY_STATIC_MAX)) / 1048576.0])
	quit(0)
