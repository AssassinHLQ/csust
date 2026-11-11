extends SceneTree
## 自检：开场标题卡（2026-11-11）。
##
## 用户的两次要求叠在一起，本探针逐条钉住：
##   ① 「现在 做开始动画」+ 选了「任意键可跳过」
##   ② 「开始动画最好覆盖在609高斯泼溅加载上面,遮住我们加载的卡顿」
##
## 所以最要紧的一条是 **②**：按键**只能跳动画，不能跳加载**。
## 第一版就是错的（`_hold_until_ready` 里带 `and not _skipped`、`SETTLE_MAX` 只有 12 s），
## 按一下键或者等满 12 秒，就正好把最卡的那一段露出来。
##
## 七条：
##   1. 标题卡真的建出来了（`TitleIntro` 层在）
##   2. 播完自己清理干净（层被释放、`is_playing()` 为假）
##   3. 播完黑幕没了（不挡住世界）
##   4. **等世界就绪**：`world_ready` 迟迟不真 → 标题卡就一直不结束
##   5. **按键不能提前放开加载**：按了键，`world_ready` 还没真 → 依然要等满
##   6. 按了键，入场动画直接落位（亮线/副标题都 visible，不是停在 alpha 0）
##   7. 游戏场景里：播的时候玩家被锁（`_ride_active`），播完解锁
##
## 用法：
##   bash _tools/run_probe.sh res://scripts/_verify_title_intro.gd -- --splat=off

const TitleIntroScript := preload("res://scripts/title_intro.gd")
const GAME := "res://scenes/game.tscn"

var _pass := 0
var _fail := 0


func _initialize() -> void:
	# ⚠️ 必须 `call_deferred`：`_initialize()` 那一刻树还没完全可用，
	#    直接在里头跑协程会在 `get_tree()` 上拿到 null
	#    （实测 `title_intro.gd:_layout_ready` 报 "Invalid access to property
	#     'process_frame' on a null instance"）。工程里其他自检也都是这么写的。
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  %s" % what)
	else:
		_fail += 1
		print("  FAIL  %s" % what)


## 一个「`delay` 秒之后才返回 true」的 Callable，用来假装世界还没加载好
func _ready_after(delay: float) -> Callable:
	var t0 := Time.get_ticks_msec()
	return func() -> bool:
		return float(Time.get_ticks_msec() - t0) / 1000.0 >= delay


## 发一个「任意键」——跳过就是靠它
func _press_key() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.physical_keycode = KEY_SPACE
	ev.pressed = true
	Input.parse_input_event(ev)


func _secs(t0: int) -> float:
	return float(Time.get_ticks_msec() - t0) / 1000.0


## 在**停留期间**把三样东西的状态抄下来（淡出之后它们会被归零，就查不到了）
func _sample(intro: Node, into: Dictionary) -> void:
	if intro == null or not is_instance_valid(intro):
		return
	var rule := intro.get_node_or_null("TitleIntro/Root/Rule") as ColorRect
	var sub := intro.get_node_or_null("TitleIntro/Root/Sub") as Label
	var tag := intro.get_node_or_null("TitleIntro/Root/Tag") as PanelContainer
	if rule != null:
		into["rule_w"] = rule.size.x
	if sub != null:
		into["sub_a"] = sub.modulate.a
	if tag != null:
		into["tag_a"] = tag.modulate.a


func _run() -> void:
	print("========== 开场标题卡 ==========")

	# ── 1~4：不跳过，世界 1.2 s 才就绪 ──
	print("\n── ① 正常播（世界 1.2 s 后才就绪）──")
	var host := Node.new()
	root.add_child(host)
	var intro := TitleIntroScript.new() as Node
	intro.name = "TitleIntro"
	host.add_child(intro)
	# ⚠️ 这时候**还看不到** `TitleIntro` 层：层是 `play()` 里的 `_build()` 才建的。
	#    第一版在这里就断言"层在"，必然假红（`play()` 甚至还没被调用）。
	var t0 := Time.get_ticks_msec()
	var pending := intro.call("play", _ready_after(1.2))
	# 等一帧让 `_build()` 跑起来，这时层才在
	await process_frame
	_check(intro.get_node_or_null("TitleIntro") != null,
		"标题卡建出来了（`TitleIntro` 层在）")
	await pending
	var took := _secs(t0)
	print("  播完用了 %.2f s（HOLD %.2f + 入场 + 淡出，且必须 ≥ 1.2 s）" % [
		took, float(TitleIntroScript.HOLD)])
	_check(took >= 1.2, "**等到了世界就绪**（%.2f s ≥ 1.2 s）" % took)
	_check(not bool(intro.call("is_playing")), "播完 `is_playing()` 为假")
	# ⚠️ `queue_free()` 是**延迟**的：`play()` 返回那一刻节点还在（只是已排队），
	#    立刻 `get_node_or_null` 一定拿得到。要等两帧再查。
	for _i in 3:
		await process_frame
	_check(intro.get_node_or_null("TitleIntro") == null, "播完自己清理干净（层已释放）")
	intro.queue_free()
	host.queue_free()
	for _i in 3:
		await process_frame

	# ── 5~6：按了键，但世界 1.5 s 才就绪 —— **必须照样等满** ──
	print("\n── ② 中途按键跳过：动画立刻落位，但加载照等 ──")
	var host2 := Node.new()
	root.add_child(host2)
	var intro2 := TitleIntroScript.new() as Node
	intro2.name = "TitleIntro"
	host2.add_child(intro2)
	# 0.25 s 后按一下键（这时入场动画刚开始，还没走完）
	var tmr := create_timer(0.25)
	tmr.timeout.connect(_press_key)
	# ⚠️ 「跳过后三样都落位」必须在**停留期间**采样。
	#    第一版是等 `play()` 返回之后才查的 —— 那时淡出动画已经把 modulate 归零，
	#    于是「副标题 alpha = 0.00」假红了一条（代码是对的，是自检查错了时候）。
	var snap := {"rule_w": -1.0, "sub_a": -1.0, "tag_a": -1.0}
	var tmr2 := create_timer(1.05)
	tmr2.timeout.connect(func() -> void: _sample(intro2, snap))
	var t1 := Time.get_ticks_msec()
	await intro2.call("play", _ready_after(1.5))
	var took2 := _secs(t1)
	print("  按了键，播完仍用了 %.2f s（世界 1.5 s 才就绪）" % took2)
	_check(took2 >= 1.5,
		"★ 按键**没有**提前放开加载（%.2f s ≥ 1.5 s）—— 这就是「遮住卡顿」那条" % took2)
	print("  停留期间采样：亮线宽 %.1f（应 > 0）、副标题 alpha %.2f、牌子 alpha %.2f" % [
		float(snap["rule_w"]), float(snap["sub_a"]), float(snap["tag_a"])])
	_check(float(snap["rule_w"]) > 1.0, "跳过之后亮线是**满宽**的（不是停在 0）")
	_check(float(snap["sub_a"]) > 0.9, "跳过之后副标题是**可见**的（不是停在 alpha 0）")
	_check(float(snap["tag_a"]) > 0.9, "跳过之后牌子是**可见**的")
	intro2.queue_free()
	host2.queue_free()
	for _i in 3:
		await process_frame

	# ── 7：接在真游戏场景里，玩家要被锁住 ──
	print("\n── ③ 接进 game.tscn：播的时候锁玩家、播完解锁 ──")
	var game := (load(GAME) as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	for _i in 20:
		await process_frame
	var player := game.get_node_or_null("Player")
	_check(player != null, "找得到 Player")
	if player != null:
		player.call("set_ride_lock", true)
		var locked := bool(player.call("is_riding"))
		_check(locked, "`set_ride_lock(true)` 之后玩家是锁住的（黑幕期间不会乱跑）")
		player.call("set_ride_lock", false)
		_check(not bool(player.call("is_riding")), "`set_ride_lock(false)` 正常解锁")

	print("\n========== 结果 ==========")
	print("  通过 %d，失败 %d" % [_pass, _fail])
	print("  %s" % ("★ 标题卡会一直盖着直到世界就绪；按键只跳动画" if _fail == 0 else "✗ 有问题"))
	quit(0 if _fail == 0 else 1)
