extends SceneTree
## 真跑开场 PV，量「第一张图出现」那几帧的帧时间，验证预载+预热是否真的消除了卡顿。
##
##   bash _tools/run_shot.sh res://scripts/_probe_intro_hitch3.gd -- --intro=on
##   bash _tools/run_shot.sh res://scripts/_probe_intro_hitch3.gd -- --intro=on --splat=off
##
## ── 前置条件 ──
## 开场 PV 平时在 `--script` 模式被 `game.gd::_play_title_intro()` 主动跳过，
## 所以必须带 `-- --intro=on`（2026-11-13 为此新增的强制开关）。
##
## ── 量什么 ──
## 从 `TitleIntro` 节点出现起记每帧 delta，并记下「Slide 加入」「预载完成」
## 「WarmUp 加入」这些事件时间点，最后对齐打印。预载+预热生效的话，
## 卡顿帧应该**全部挤在 `Slide` 之前**（那时候还是黑屏，用户看不见），
## `Slide` 之后应该一条 ≥60 ms 的都没有。

const OffWin := preload("res://scripts/offscreen_window.gd")

const SPIKE_MS := 60.0
const WATCH_SEC := 22.0
const WAIT_INTRO_SEC := 150.0

var _game: Node
var _mon: Node


func _initialize() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	var wd := create_timer(280.0, true)
	wd.timeout.connect(func() -> void:
		print("[hitch3] !! 看门狗超时")
		quit(2))
	_run.call_deferred()


func _run() -> void:
	await OffWin.apply(self, Vector2i(1600, 900))

	_mon = Monitor.new()
	_mon.name = "HitchMonitor3"
	_mon.set_process(false)
	root.add_child(_mon)

	_game = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(_game)
	current_scene = _game

	# ── 等 TitleIntro（带 --intro=on 时会出现）──
	var t0 := Time.get_ticks_msec()
	var intro: Node = null
	while float(Time.get_ticks_msec() - t0) / 1000.0 < WAIT_INTRO_SEC:
		intro = _game.get_node_or_null("TitleIntro")
		if intro != null:
			break
		await process_frame
	if intro == null:
		print("[hitch3] ✗ 没等到 TitleIntro（记得加 `-- --intro=on`）")
		quit(1)
		return
	print("[hitch3] TitleIntro 出现（等了 %.1f s），类型=%s，图 %d 张" % [
		float(Time.get_ticks_msec() - t0) / 1000.0,
		str(intro.call("kind")), int(intro.call("slide_count"))])

	_mon.begin(intro)
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
	var _intro: Node
	var _first_slide_ms := -1.0
	var _started := false

	func begin(intro: Node) -> void:
		_intro = intro
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
				_ev("★ 第一张 Slide 加入（此后用户能看见图）")
			else:
				_ev("Slide 加入（换图）")
		elif nm == "WarmUp":
			_ev("WarmUp 加入（黑屏期预热着色器）")

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
		print("\n========== 开场 PV 卡顿测量（--intro=on 强制播）==========")
		print("观察 %.0f s，%d 帧，平均 %.1f ms（≈%.0f fps），最慢 %.1f ms" % [
			WATCH_SEC, _frames, _sum_ms / maxf(float(_frames), 1.0),
			1000.0 / maxf(_sum_ms / maxf(float(_frames), 1.0), 0.001), _max_ms])
		print("≥%.0f ms 的卡顿帧：%d 个" % [SPIKE_MS, _spikes.size()])
		if not _events.is_empty():
			print("\n-- 事件 --")
			for e in _events:
				print("  %8.1f ms  %s" % [e[0], e[1]])
		if not _spikes.is_empty():
			print("\n-- 卡顿帧 --")
			for s in _spikes:
				var near := "（无）"
				var best := -1.0
				for e in _events:
					if e[0] <= s[0] and e[0] > best:
						best = e[0]
						near = "%s @%.1f ms" % [e[1], e[0]]
				print("  帧 %4d  %8.1f ms  卡 %6.1f ms  ← %s" % [s[2], s[0], s[1], near])

		# ── 结论 ──
		print("\n-- 结论 --")
		if _first_slide_ms < 0.0:
			print("  ✗ 整个窗口里没有 Slide 出现，测量无效")
			return
		var after := 0
		var worst_after := 0.0
		for s in _spikes:
			if s[0] >= _first_slide_ms:
				after += 1
				worst_after = maxf(worst_after, s[1])
		print("  第一张 Slide 出现在 %.1f ms，它**之后**的卡顿帧：%d 个（最慢 %.1f ms）" % [
			_first_slide_ms, after, worst_after])
		if after == 0:
			print("  ★ 通过：图出现之后一帧都没卡 —— 预载 + 预热生效")
		else:
			print("  ✗ 图出现之后还卡了 %d 次，预载/预热没吃干净（看上面的对齐表）" % after)
