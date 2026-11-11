extends SceneTree
## 「切场景」和「离开学校区域」到底能不能还显存？逐条实测。
##
## 代码里的两条路：
##   ① 切场景  → `scene_flow.gd::_release_backend_gpu()`
##                → `gaussian_backend_selector.gd::release_gpu()`
##                注释写明：管理器挂在 `root` 下、跨场景常驻，不显式放就要等 GC。
##   ② 离开区域 → `splat_scene.gd::_unload_for_vram()`
##                只 `queue_free()` 泼溅节点，**没有**调 `release_gpu()`
##                ⇒ 怀疑：节点没了，缓冲还在。
##
## 本探针按真实顺序量：
##   V0 点云加载完
##   V1 把玩家挪回大厅（= 离开学校区域），等它真的卸载
##   V2 再走回校园（验证能重新加载）
##   V3 把整棵关卡 free 掉（= 切场景时旧树没了）
##   V4 再调 `release_gpu()`（= 切场景时那段专门的释放）
##
##   _tools/run_shot.sh res://scripts/_probe_vram_release.gd -- --no-capture

const OffWin := preload("res://scripts/offscreen_window.gd")
const Selector := preload("res://addons/gdgs/runtime/render/backend/gaussian_backend_selector.gd")


func _initialize() -> void:
	if not OS.get_cmdline_user_args().has("--no-capture"):
		push_error("[rel] 缺 --no-capture")
		quit(2)
		return
	_run.call_deferred()


func _mb() -> float:
	return float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0


func _line(tag: String) -> void:
	print("[rel] %-38s → %7.1f MB" % [tag, _mb()])


func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame


func _run() -> void:
	await OffWin.apply(self, Vector2i(1280, 720))
	var safe0: Array = OffWin.is_safe()
	if not bool(safe0[0]):
		push_error("[rel] 窗口没挪到屏幕外：%s" % str(safe0[1]))
		quit(2)
		return

	await _settle(10)
	_line("空场景")

	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	var player := level.get_node_or_null("Player") as Node3D
	var campus: Node3D = level.get_node_or_null("Campus")
	player.global_position = Vector3(-20.0, 0.5, -210.0)
	campus.set("start_delay", 0.0)
	campus.set("low_priority", false)
	campus.call("force_start")
	var t0 := Time.get_ticks_msec()
	while not bool(campus.call("is_ready")) and Time.get_ticks_msec() - t0 < 240000:
		await process_frame
	await _settle(90)
	_line("V0 点云加载完")
	var v0 := _mb()

	# ══ ② 离开学校区域 ══
	print("[rel] ── 把玩家挪回大厅（校园外），等 unload 逻辑生效 ──")
	player.global_position = Vector3(-2.0, 0.6, 5.0)
	var waited := 0
	while bool(campus.call("is_ready")) and waited < 600:
		await process_frame
		waited += 1
	print("[rel] 卸载触发用了 %d 帧；is_ready = %s" % [waited, str(campus.call("is_ready"))])
	await _settle(150)
	_line("V1 离开区域 + 节点已释放")
	var v1 := _mb()
	print("[rel] ★ 离开区域省下 %.1f MB（%.1f%%）" % [v0 - v1, 100.0 * (v0 - v1) / maxf(1.0, v0)])

	# ══ 走回校园：能不能重新加载 ══
	print("[rel] ── 走回校园，验证能重新解码 ──")
	player.global_position = Vector3(-20.0, 0.5, -210.0)
	var t1 := Time.get_ticks_msec()
	while not bool(campus.call("is_ready")) and Time.get_ticks_msec() - t1 < 240000:
		await process_frame
	await _settle(90)
	_line("V2 重新加载完")
	var v2 := _mb()
	print("[rel] 重新加载耗时 %d ms；回到 %.1f MB（和 V0 差 %.1f）"
		% [Time.get_ticks_msec() - t1, v2, v2 - v0])

	# ══ ① 切场景 ══
	print("[rel] ── 模拟切场景：free 整棵旧树（不动 root）──")
	level.queue_free()
	await _settle(200)
	_line("V3 旧场景已 free（还没调 release_gpu）")
	var v3 := _mb()

	Selector.release_gpu()
	print("[rel] 已调 gaussian_backend_selector.release_gpu()")
	await _settle(200)
	_line("V4 release_gpu() 之后")
	var v4 := _mb()
	print("[rel] ★ 切场景（free + release_gpu）共省下 %.1f MB" % (v2 - v4))
	print("[rel] ★ 其中：free 旧树省 %.1f MB，release_gpu 省 %.1f MB" % [v2 - v3, v3 - v4])

	print("[rel] 完")
	quit(0)
