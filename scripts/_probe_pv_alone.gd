extends SceneTree
## **只加载开场 PV**（不带 game.tscn），量第一张图出现时的帧时间。
##
##   bash _tools/run_shot.sh res://scripts/_probe_pv_alone.gd
##   bash _tools/run_shot.sh res://scripts/_probe_pv_alone.gd -- --pv-warmup=off
##
## ── 为什么必须隔离 ──
## 用 `_probe_intro_hitch3.gd`（带整个 game.tscn）量的时候，帧时间被背景世界
## 的同伴骨骼动画 / LOD 后台载入搅得很花（22~25 fps、整段随机 200 ms 尖峰），
## 分不清哪一下是 PV 自己的。`_verify_title_intro.gd` 的做法是**只 new 一个
## TitleIntro**（不走 game.gd），本探针照抄那个思路，但开真窗口量帧时间。
##
## 输出：第一张 Slide 前后的卡顿对比 —— 这才是用户「加载第一张图片卡几下」的原貌。

const OffWin := preload("res://scripts/offscreen_window.gd")
const TitleIntroScript := preload("res://scripts/title_intro.gd")

const SPIKE_MS := 60.0
const WATCH_SEC := 14.0

var _intro: Node
var _mon: Node


func _initialize() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	var wd := create_timer(120.0, true)
	wd.timeout.connect(func() -> void:
		print("[pv] !! 看门狗超时")
		quit(2))
	_run.call_deferred()


func _run() -> void:
	await OffWin.apply(self, Vector2i(1600, 900))

	_mon = Monitor.new()
	_mon.name = "PvMonitor"
	_mon.set_process(false)
	root.add_child(_mon)

	# 只挂开场，不挂游戏场景
	_intro = TitleIntroScript.new() as Node
	_intro.name = "TitleIntro"
	root.add_child(_intro)

	var warm := true
	for a in OS.get_cmdline_user_args():
		if a == "--pv-warmup=off":
			warm = false
	print("[pv] 预热 = %s   类型=%s   图 %d 张" % [
		"开" if warm else "关", str(_intro.call("kind")),
		int(_intro.call("slide_count"))])

	_mon.begin()
	# 进度假装已经满了，让它马上走到「等点击」，画面只剩 PV
	_intro.call("play", func() -> Dictionary:
		return {"ratio": 1.0, "ready": true, "names": ["画室609"]})
	await _mon.finished
	_mon.report()
	quit(0)


class Monitor:
	extends Node

	signal finished

	var _t0 := 0
	var _last := 0
	var _frames := 0
	var _spikes: Array = []
	var _events: Array = []
	var _max_ms := 0.0
	var _sum_ms := 0.0
	var _first_slide_ms := -1.0
	var _started := false

	func begin() -> void:
		_t0 = Time.get_ticks_usec()
		_last = _t0
		_started = true
		set_process(true)
		get_tree().node_added.connect(_on_node_added)
		_watch()

	func _watch() -> void:
		var t0 := Time.get_ticks_msec()
		while float(Time.get_ticks_msec() - t0) / 1000.0 < WATCH_SEC:
			await get_tree().process_frame
		set_process(false)
		finished.emit()

	func _on_node_added(n: Node) -> void:
		if not _started:
			return
		var nm := String(n.name)
		if nm == "Slide":
			if _first_slide_ms < 0.0:
				_first_slide_ms = _elapsed()
				_ev("★ 第一张 Slide 加入")
			else:
				_ev("Slide 加入（换图）")
		elif nm == "WarmUp":
			_ev("WarmUp 加入（黑屏预热）")

	func _elapsed() -> float:
		return (Time.get_ticks_usec() - _t0) / 1000.0

	func _ev(text: String) -> void:
		_events.append([_elapsed(), text])

	func _process(_d: float) -> void:
		var now := Time.get_ticks_usec()
		var ms := (now - _last) / 1000.0
		_last = now
		_frames += 1
		_sum_ms += ms
		_max_ms = maxf(_max_ms, ms)
		if ms >= SPIKE_MS:
			_spikes.append([_elapsed(), ms, _frames])

	func report() -> void:
		print("\n========== 只测开场 PV：卡顿 ==========")
		print("观察 %.0f s，%d 帧，平均 %.1f ms（≈%.0f fps），最慢 %.1f ms" % [
			WATCH_SEC, _frames, _sum_ms / maxf(float(_frames), 1.0),
			1000.0 / maxf(_sum_ms / maxf(float(_frames), 1.0), 0.001), _max_ms])
		print("≥%.0f ms 的卡顿帧：%d 个" % [SPIKE_MS, _spikes.size()])
		if not _events.is_empty():
			for e in _events:
				print("  %8.1f ms  %s" % [e[0], e[1]])
		if not _spikes.is_empty():
			print("\n-- 卡顿帧 --")
			for s in _spikes:
				var near := "（黑屏期，用户看不见）" if s[0] < _first_slide_ms \
					else "（★ 图已经可见）"
				print("  帧 %4d  %8.1f ms  卡 %6.1f ms  %s" % [s[2], s[0], s[1], near])
		print("\n-- 结论 --")
		if _first_slide_ms < 0.0:
			print("  ✗ 没有 Slide，测量无效")
			return
		var before := 0
		var after := 0
		var worst_after := 0.0
		for s in _spikes:
			if s[0] < _first_slide_ms:
				before += 1
			else:
				after += 1
				worst_after = maxf(worst_after, s[1])
		print("  第一张 Slide 出现在 %.0f ms" % _first_slide_ms)
		print("  它之前（黑屏期）卡顿 %d 次 —— 用户看不见" % before)
		print("  它之后（图可见）卡顿 %d 次，最慢 %.0f ms" % [after, worst_after])
		if after == 0:
			print("  ★ 通过：第一张图出现后一帧都没卡")
		else:
			print("  ✗ 图出现之后还卡了 %d 次" % after)
