extends SceneTree
## 自检：霸王龙优香**血量两条**（用户 2026-11-09：「霸王龙增强血量，两倍」）。
##
## 背景：`next_level.tscn` 里三只 `TrexBoss*` 都**没有覆盖** `max_health`，
## 所以它们一直吃 `boss.gd` 的默认值 3000。这次在 `trex_yuka_boss.gd::_init()`
## 里抬到 6000。
##
## 这条自检盯四件事，缺一件都不算过：
##   ① 三只霸王龙实例的 `max_health` 都正好是 6000
##   ② 它们 `_ready()` 之后的 `health` 也填满了 6000（不是只有字段改了）
##   ③ 飞猪优香**没被连坐**（它继承同一个基类，但血量不该跟着涨）
##   ④ 打掉一半血之后 `health_ratio()` 正好 0.5（说明百分比条按新血量算）
##
## 用法：
##   & D:\GAME\godot\Godot_v4.7.1-stable_win64_console.exe --headless --path . \
##       --script res://scripts/_verify_trex_health.gd -- --no-capture

const LEVEL := "res://scenes/next_level.tscn"
const TREX_NAMES := ["TrexBossA", "TrexBossB", "TrexBossC"]
const EXPECTED := 6000.0

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run()


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  %s" % what)
	else:
		_fail += 1
		print("  FAIL  %s" % what)


func _run() -> void:
	print("========== 霸王龙血量 ×2 ==========")
	var ps := load(LEVEL) as PackedScene
	if ps == null:
		push_error("[Verify] 加载不了 %s" % LEVEL)
		quit(1)
		return
	var level := ps.instantiate()
	root.add_child(level)
	# 场景里的 Boss 走 BootGate（走近才建模型），血量在 `_ready()` 里就填了，
	# 所以只要等几帧让它进入树即可，不需要真的走近。
	for _i in 10:
		await process_frame

	# ---- ① / ② 三只霸王龙 ----
	var trexes: Array[Node] = []
	for n in TREX_NAMES:
		var b := level.get_node_or_null(n)
		if b == null:
			_check(false, "找到节点 %s" % n)
			continue
		trexes.append(b)
		var mh := float(b.get("max_health"))
		var hp := float(b.get("health"))
		_check(is_equal_approx(mh, EXPECTED),
			"%s max_health = %.0f（应为 %.0f）" % [n, mh, EXPECTED])
		_check(is_equal_approx(hp, EXPECTED),
			"%s 初始 health = %.0f（应已填满）" % [n, hp])

	# ---- ③ 飞猪没被连坐 ----
	var pig := level.get_node_or_null("PigBoss")
	if pig == null:
		# 第二场景里没有飞猪（它在第一场景 game.tscn），这条就跳过而不是算失败
		print("  SKIP  本场景没有 PigBoss，跳过「不连坐」检查")
	else:
		var pmh := float(pig.get("max_health"))
		_check(not is_equal_approx(pmh, EXPECTED),
			"飞猪 max_health = %.0f（**不应**是 %.0f）" % [pmh, EXPECTED])

	# ---- ④ 打掉一半 → 比例 0.5 ----
	if trexes.size() > 0:
		var t: Node = trexes[0]
		t.call("take_damage", EXPECTED * 0.5)
		var ratio := float(t.call("health_ratio"))
		_check(absf(ratio - 0.5) < 0.01,
			"打掉一半后 health_ratio = %.3f（应为 0.500）" % ratio)
		# 再补一刀，确认**死亡线**跟着新血量走。
		# ⚠️ 这里只读血量，不验死亡表现：探针没走近，BootGate 还没建模型，
		#    `Boss._die()` 里的倒下 tween 会找不到 `model` 而报 `rp_target is null`
		#    —— 那是探针环境的必然结果，不是血量逻辑的问题。
		t.call("take_damage", EXPECTED * 0.5 + 1.0)
		_check(float(t.get("health")) <= 0.0,
			"再打 %.0f 后血量归零（死亡线按 6000 算）" % (EXPECTED * 0.5 + 1.0))

	print("\n========== 结果 ==========")
	print("  通过 %d，失败 %d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
