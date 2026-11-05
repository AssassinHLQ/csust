extends SceneTree
## 验「进过第二场景（校园）再回第一场景，显存有没有还回去」：离屏真窗口。
##
##   _tools/run_shot.sh res://scripts/_probe_vram_leak.gd
##
## 背景：用户 F3 实测 6918 MiB，而本喵单独量「第一场景 + 画室609」只有 3069 MiB。
## 怀疑是**跨场景没释放**（校园那边有两套光栅器 + 粗层 352 MB bin + 细层窗口）。
##
## 走法照游戏的真实路径：加载 game.tscn → 手工切到 next_level.tscn（等校园 GGS 就位）
## → 再切回 game.tscn，每一步都记显存。若第三步明显高于第一步，就是泄漏。

const S1 := "res://scenes/game.tscn"
const S2 := "res://scenes/next_level.tscn"


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	var t := create_timer(300.0, true)
	t.timeout.connect(func():
		print("[leak] !! 看门狗超时")
		quit(1))
	_run.call_deferred()


func _v() -> Array:
	return [
		float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0,
		float(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)) / 1048576.0,
		float(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)) / 1048576.0,
	]


func _line(tag: String, v: Array) -> void:
	print("[leak] %-26s 总 %7.0f｜纹理 %7.0f｜缓冲 %7.0f MiB" % [
		tag, float(v[0]), float(v[1]), float(v[2])])


func _swap(path: String) -> Node:
	if current_scene != null:
		current_scene.queue_free()
		await process_frame
		await process_frame
	var inst := (load(path) as PackedScene).instantiate()
	root.add_child(inst)
	current_scene = inst
	return inst


func _run() -> void:
	GameSettings.set_value("vsync", false)
	GameSettings.set_value("fps_limit", 0.0)
	root.size = Vector2i(1920, 1080)

	var a := await _swap(S1)
	for _i in 180:
		await process_frame
	_line("① 第一场景（画室609）", _v())

	var b := await _swap(S2)
	# 等校园 GGS 就位（它由 next_level.gd 运行时挂上去）
	var ggs: Node = null
	for _i in 600:
		await process_frame
		if ggs == null:
			ggs = b.get_node_or_null("CampusGGS")
		if ggs != null:
			var r = ggs.get("rasterizer")
			if r != null and bool(r.get("is_loaded")):
				break
	_line("② 第二场景（校园就位）", _v())
	print("[leak]   校园节点=%s｜粗层=%s" % [
		"有" if ggs != null else "没有",
		"-" if ggs == null else str(ggs.get("coarse_rasterizer") != null)])

	var c := await _swap(S1)
	for _i in 180:
		await process_frame
	_line("③ 回到第一场景", _v())

	print("[leak] 判据：③ 应该和 ① 差不多（差 < 300 MiB）。差得多就是跨场景没释放。")
	quit(0)
