extends SceneTree
## 自检：开场 PV + 载入进度 + 开始按钮（2026-11-12 改版）。
##
## 用户这一轮的要求：
##   ① 做 PV（蔚蓝档案做法：图片从左往右缓慢平移），替代原来的开始动画；
##   ② 在高斯泼溅没加载完之前用它盖住加载过程；
##   ③ 进度条显示加载进度，加载完下方出现「开始游戏」；
##   ④ **点了才开始**；有缓存加载很快时，进度条与按钮照样要走一遍；
##   ⑤ 因为有人会听歌，所以**不能**「任意键跳过」。
##
## 用法：
##   bash _tools/run_probe.sh res://scripts/_verify_title_intro.gd -- --splat=off

const TitleIntroScript := preload("res://scripts/title_intro.gd")
const GAME := "res://scenes/game.tscn"

var _pass := 0
var _fail := 0


func _initialize() -> void:
	# ⚠️ 必须 `call_deferred`：`_initialize()` 那一刻树还没完全可用，
	#    直接跑协程会在 `get_tree()` 上拿到 null（工程里其它自检都是这么写的）。
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  %s" % what)
	else:
		_fail += 1
		print("  FAIL  %s" % what)


## 等墙钟时间（headless 跑得飞快，不能数帧）
func _wait_sec(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < sec:
		await process_frame


func _wait_until(pred: Callable, timeout := 6.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < timeout:
		if bool(pred.call()):
			return true
		await process_frame
	return bool(pred.call())


func _run() -> void:
	print("========== 开场 PV ==========")

	# ── ① 素材 ────────────────────────────────────────────────────────
	print("\n── ① 素材：PV 图 / 音乐 ──")
	var probe := TitleIntroScript.new() as Node
	_check(String(probe.call("kind")) == "pv",
		"正片类型 = pv（实测 %s）" % String(probe.call("kind")))
	var slides: Array = probe.call("_pv_slides")
	print("  PV 目录里的图：%d 张" % slides.size())
	var expected: Array[String] = []
	for file in DirAccess.get_files_at("res://_arisu_captures/_shots"):
		if file.get_extension().to_lower() == "png":
			expected.append("res://_arisu_captures/_shots/" + file)
	expected.sort()
	_check(not slides.is_empty() and slides == expected,
		"播放列表与 _shots 实际 PNG 完全一致、按文件名排序（%d 张）" % slides.size())
	var loaded := 0
	for p in slides:
		if probe.call("_load_texture", p) != null:
			loaded += 1
	_check(loaded == slides.size() and loaded > 0,
		"每一张 PV 图都能载入（%d / %d）" % [loaded, slides.size()])
	var stream: AudioStream = probe.call("_load_music")
	_check(stream != null, "开场音乐能载入（%s）" % ("有" if stream != null else "没有"))
	if stream != null:
		var mp3 := stream as AudioStreamMP3
		_check(mp3 != null, "音乐是 MP3（实测 %s）" % stream.get_class())
		_check(mp3 != null and mp3.loop, "音乐已设循环播放（能在开始界面听完整首）")

	_check(int(probe.call("slide_count")) == expected.size(),
		"开场报告的图片数量与截图目录一致")
	var mat: ShaderMaterial = probe.call("_slide_material")
	_check(mat != null and mat.shader != null
		and mat.shader.code.contains("sharpen"),
		"滑动图挂了「锐化 + 颗粒 + 暗角」调色着色器")
	probe.free()

	# ── ② 完整流程：加载中 → 进度 → 就绪 → 点击 ──────────────────────
	print("\n── ② 完整流程 ──")
	var host := Node.new()
	root.add_child(host)
	var intro := TitleIntroScript.new() as Node
	intro.name = "TitleIntro"
	host.add_child(intro)

	var t0 := Time.get_ticks_msec()
	var state := {"ready": false}
	var poll := func() -> Dictionary:
		var el := float(Time.get_ticks_msec() - t0) / 1000.0
		var names: Array = [] if bool(state["ready"]) else ["画室609"]
		return {"ratio": clampf(el / 2.0, 0.0, 0.92),
			"ready": bool(state["ready"]), "names": names}
	var pending: Variant = intro.call("play", poll)
	await process_frame
	# play 会先异步预载纹理；等音乐启动才检查播放阶段的状态。
	_check(await _wait_until(func() -> bool:
		return bool(intro.call("has_music")), 10.0), "后台预载完成并开始播放")

	_check(intro.get_node_or_null("TitleIntro") != null, "开场层建出来了")
	var btn := intro.get_node_or_null("TitleIntro/Root/Ui/StartButton") as Button
	_check(btn != null, "「开始游戏」按钮节点存在")
	_check(btn != null and not btn.visible, "加载期间「开始游戏」藏着自己")
	_check(Music.is_held(), "加载期间房间 BGM 被压住（`Music.hold(true)`）")
	_check(bool(intro.call("has_music")), "PV 音乐播放器在场")
	# 压住期间 Music.play 不能真的出声（否则和 PV 音乐叠在一起）
	Music.play("room609")
	_check(not Music.is_playing(), "压住期间 `Music.play()` 不出声")
	_check(Music.current().is_empty(), "压住期间 `Music.current()` 为空")

	# 进度条动起来、文字带百分比
	var fill := intro.get_node_or_null("TitleIntro/Root/Ui/BarTrack/BarFill") as Panel
	var label := intro.get_node_or_null("TitleIntro/Root/Ui/ProgressLabel") as Label
	await _wait_sec(0.6)
	var fill_w := 0.0
	if fill != null:
		fill_w = fill.size.x
	print("  0.6 s 时：进度条填充 %.1f px，文字「%s」" % [fill_w, "" if label == null else label.text])
	_check(fill_w > 1.0, "进度条在涨（%.1f px > 1）" % fill_w)
	_check(label != null and label.text.contains("%"), "进度文字带百分比")
	_check(label != null and label.text.contains("画室609"),
		"进度文字带了场地名（「%s」）" % ("" if label == null else label.text))

	# 加载期间按键不能跳过（用户：「因为有人会听歌」）
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.pressed = true
	intro.call("_input", ev)
	await _wait_sec(0.15)
	_check(not bool(intro.call("is_start_ready")), "加载没完时按空格**不**放出开始按钮")
	_check(bool(intro.call("is_playing")), "加载没完时 PV 仍在播（没被跳过）")

	# 跑满 2 s 再宣布就绪（顺便让进度条走一段）
	await _wait_sec(1.4)
	state["ready"] = true
	var ok_ready := await _wait_until(func() -> bool:
		return bool(intro.call("is_start_ready")), 6.0)
	_check(ok_ready, "世界就绪后弹出开始按钮")
	_check(btn != null and btn.visible, "「开始游戏」按钮可见")
	_check(btn != null and btn.text == "开始游戏", "按钮文字 =「开始游戏」")
	_check(label != null and label.text == "载入完成", "进度文字 =「载入完成」")
	var full_w := 0.0
	if fill != null:
		full_w = fill.size.x
	_check(full_w >= 517.0, "进度条满格（%.1f px）" % full_w)
	# 「首次启动久一点」那行只该出现在慢加载时；就绪后必须收掉
	var hint := intro.get_node_or_null("TitleIntro/Root/Ui/LoadHint") as Label
	_check(hint != null and (not hint.visible or hint.modulate.a < 0.05),
		"就绪后「首次启动比较久」提示已收掉")

	# 就绪后**不点**就不许自己进游戏
	await _wait_sec(0.5)
	_check(bool(intro.call("is_playing")), "★ 就绪后不点按钮，PV **不会**自己结束")

	# 点按钮（直接发 `pressed` 信号，等于真点）
	btn.emit_signal("pressed")
	await pending
	var total := float(Time.get_ticks_msec() - t0) / 1000.0
	print("  从开场到进游戏用了 %.1f s（其中「等就绪」约 2.0 s）" % total)
	_check(total >= 2.0, "整段至少等到加载完（%.1f s ≥ 2.0 s）" % total)
	_check(not bool(intro.call("is_playing")), "点开始后 `is_playing()` 为假")
	_check(not Music.is_held(), "点开始后房间 BGM 解除压制（`Music.hold(false)`）")
	for _i in 4:
		await process_frame
	_check(intro.get_node_or_null("TitleIntro") == null, "开场层已经释放")
	intro.queue_free()
	host.queue_free()
	for _i in 2:
		await process_frame

	# ── ③ 泼溅进度折算 ──────────────────────────────────────────────
	print("\n── ③ 泼溅阶段 → 总进度 ──")
	var splat: Node = load("res://scripts/splat_scene.gd").new()
	var seq := [
		["textures", 0, 1], ["textures", 1, 1],
		["center", 50, 100], ["center", 100, 100],
		["decode", 0, 100], ["decode", 50, 100], ["decode", 100, 100],
		["pack", 0, 1], ["pack", 1, 1],
		["cache", 0, 1], ["cache", 1, 1],
	]
	var prev := -1.0
	var monotonic := true
	for step in seq:
		splat.call("_on_load_progress", step[0], step[1], step[2])
		var r := float(splat.get("load_ratio"))
		if r < prev:
			monotonic = false
		prev = r
	print("  最后总进度 = %.3f，阶段 =「%s」" % [
		float(splat.get("load_ratio")), String(splat.get("load_phase"))])
	_check(monotonic, "各阶段折算的总进度**单调不减**")
	_check(prev > 0.9 and prev < 1.0,
		"解码完成时总进度接近满格但**不提前到 1.0**（%.3f，残量留给建节点）" % prev)
	_check(String(splat.get("load_phase")) == "cache", "阶段名跟着更新")
	splat.free()

	# ── ④ 和 game.gd 的接口 ─────────────────────────────────────────
	print("\n── ④ game.gd：`_intro_state()` 与强制开跑 ──")
	var game := (load(GAME) as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	for _i in 20:
		await process_frame
	_check(game.has_method("_intro_state"), "game.gd 有 `_intro_state()`")
	if game.has_method("_intro_state"):
		var st: Dictionary = game.call("_intro_state")
		print("  `_intro_state()` = %s" % str(st))
		_check(bool(st.get("ready", false)), "`--splat=off` 下 `ready` 为真（不会把玩家卡在开场）")
		_check(is_equal_approx(float(st.get("ratio", 0.0)), 1.0),
			"`--splat=off` 下 ratio = 1.0")
	var room := game.get_node_or_null("Room609")
	_check(room != null, "场上找得到 Room609")
	if room != null:
		_check(bool(room.get("_cli_skipped")),
			"`--splat=off` 的节点被标记 `_cli_skipped`（force_start 不会硬拉起来）")
		room.call("force_start")
		await process_frame
		_check(not bool(room.get("loading")), "被命令行排除的节点 `force_start()` 无效")
	game.queue_free()
	for _i in 3:
		await process_frame

	print("\n========== 结果 ==========")
	print("  通过 %d，失败 %d" % [_pass, _fail])
	print("  %s" % ("★ PV 盖住加载、进度条、点击才开始——都按用户口径走" if _fail == 0
		else "✗ 有问题"))
	quit(0 if _fail == 0 else 1)
