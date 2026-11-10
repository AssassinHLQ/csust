extends SceneTree
## 自检：EX 必杀 = **连按 E → X**，消耗 6 COST，满功率直接发射。
##
## 用户 2026-11-10 原话（更正上一版）：
##   「我是说连续按键盘 E X 触发,消耗 6 cost,不需要充能条和蓄力时间,
##     就是按完 E X 键盘就是最大功率发射」
##
## 验证清单：
##   ① ExSystem 挂在 Player 上，且**没有**充能/蓄力那套接口了
##   ② COST 不足 6 时：按 E 不进入序列、按 X 也放不出来
##   ③ COST 够时：按 E → stage 1；再按 X → **立刻发射**并扣掉 6
##   ④ 顺序反了（先 X 后 E）不触发
##   ⑤ 超时作废（E 之后等太久，X 无效，要重新按 E）
##   ⑥ 只按 E 不按 X → 不发射、不扣钱
##   ⑦ 普通状态出 LaserOrb；机甲分支出 RailBeam*
##
## 用法：
##   & <godot> --headless --path . --script res://scripts/_verify_ex.gd

const GAME := "res://scenes/game.tscn"
const CostGauge := preload("res://scripts/cost_gauge.gd")

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


func _has_child(fx: Node, prefix: String) -> bool:
	if fx == null:
		return false
	for c in fx.get_children():
		if String(c.name).begins_with(prefix):
			return true
	return false


func _run() -> void:
	print("========== EX 必杀自检（E→X 连按，6 COST，满功率）==========")
	var ps := load(GAME) as PackedScene
	var level := ps.instantiate()
	root.add_child(level)
	current_scene = level
	for _i in 12:
		await process_frame

	var player := level.get_node_or_null("Player")
	if player == null:
		push_error("[verify] 没有 Player")
		quit(1)
		return
	var ex := player.get_node_or_null("ExSystem")
	_check(ex != null, "Player 下有 ExSystem")
	if ex == null:
		_finish()
		return
	var fx := ex.get_node_or_null("ExFx")
	_check(fx != null, "ExFx 容器存在")

	# ① 不该再有充能/蓄力接口
	_check(not ex.has_method("press_ex"), "已移除 press_ex()（不再长按蓄力）")
	_check(not ex.has_method("release_ex"), "已移除 release_ex()")
	var has_ratio := false
	for p in ex.get_property_list():
		if String(p.get("name", "")) == "ex_ratio":
			has_ratio = true
	_check(not has_ratio, "已移除 ex_ratio（不再有充能条）")

	# ② COST 不足
	CostGauge.reset(0.0)
	var ate_e := bool(ex.call("feed_key", KEY_E))
	_check(not ate_e, "COST 不足时按 E 不进入序列（返回 false）")
	var fired := bool(ex.call("feed_key", KEY_X))
	_check(not fired, "COST 不足时按 X 不触发")
	_check(CostGauge.display() == 0, "COST 没被扣（还是 %d）" % CostGauge.display())

	# ③ COST 够 → E → X
	CostGauge.reset(6.0)
	print("  COST 设为 6")
	var e_ok := bool(ex.call("feed_key", KEY_E))
	_check(e_ok, "按 E 进入序列（返回 true）")
	_check(int(ex.call("seq_stage")) == 1, "序列 stage = 1（实际 %d）" % int(ex.call("seq_stage")))

	var x_ok := bool(ex.call("feed_key", KEY_X))
	_check(x_ok, "按 X 触发成功")
	_check(int(ex.call("seq_stage")) == 0, "触发后序列复位到 0")
	print("  COST 扣完剩 %d" % CostGauge.display())
	_check(CostGauge.display() == 0, "扣掉 6（6 → %d）" % CostGauge.display())

	for _i in 3:
		await process_frame
	_check(_has_child(fx, "LaserOrb"), "普通状态放出激光球（LaserOrb）")

	# ④ 顺序反了不触发
	CostGauge.reset(10.0)
	var x_first := bool(ex.call("feed_key", KEY_X))
	_check(not x_first, "先按 X（没先按 E）不触发")
	_check(CostGauge.display() == 10, "COST 没被扣（%d）" % CostGauge.display())

	# ⑤ 只按 E 不按 X
	ex.call("feed_key", KEY_E)
	await process_frame
	_check(CostGauge.display() == 10, "只按 E 不扣钱（%d）" % CostGauge.display())
	_check(int(ex.call("seq_stage")) == 1, "此时在等 X（stage 1）")

	# ⑥ 超时作废
	print("  等 0.9 s 让 E 序列超时…")
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 900:
		await process_frame
	var late_x := bool(ex.call("feed_key", KEY_X))
	_check(not late_x, "超时后按 X 无效（要重新按 E）")
	_check(CostGauge.display() == 10, "超时也没扣钱（%d）" % CostGauge.display())

	# ⑦ 机甲分支（直接调内部函数验证分流）
	await process_frame
	ex.call("_fire_railgun")
	for _i in 3:
		await process_frame
	_check(_has_child(fx, "RailBeam"), "机甲分支射出轨道炮（RailBeam*）")

	_finish()


func _finish() -> void:
	print("\n========== 结果 ==========")
	print("  通过 %d，失败 %d" % [_pass, _fail])
	print("  %s" % ("★ EX 连按 E→X 正常" if _fail == 0 else "✗ 有问题"))
	quit(0 if _fail == 0 else 1)
