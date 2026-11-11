extends SceneTree
## 验证「校园泼溅已去掉」：默认情况下**两套渲染器都不在**，
## 但校园区的实体网格（地板 / 桥 / 平台 / 碰撞）必须还在。
##
## 用户 2026-11-11：「先去掉校园泼溅」。
##
##   & <godot> --headless --path . --script res://scripts/_verify_campus_off.gd
##   & <godot> --headless --path . --script res://scripts/_verify_campus_off.gd -- -- --campus-splat=on
##                                                                ↑ 验证「能开回来」

const LEVEL := "res://scenes/next_level.tscn"

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String, detail := "") -> void:
	if ok:
		_pass += 1
		print("  [PASS] %s%s" % [what, ("  " + detail) if detail != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s%s" % [what, ("  " + detail) if detail != "" else ""])


func _run() -> void:
	var want_on := OS.get_cmdline_user_args().has("--campus-splat=on")
	print("========== 校园泼溅开关（期望：%s）==========" % ("开" if want_on else "关"))
	var ps := load(LEVEL) as PackedScene
	if ps == null:
		push_error("[off] 加载不了关卡")
		quit(1)
		return
	var level := ps.instantiate()
	root.add_child(level)
	# 给 `_ready` 足够帧让装配跑完
	for _i in 30:
		await process_frame

	var ggs := level.get_node_or_null("CampusGGS")
	var campus := level.get_node_or_null("Campus")

	if want_on:
		_check(ggs != null, "开启时 CampusGGS 应存在", "实际 %s" % ("有" if ggs != null else "无"))
		_check(campus != null, "开启时 GDGS 的 Campus 应存在",
			"实际 %s" % ("有" if campus != null else "无"))
	else:
		_check(ggs == null, "关闭时**不应有** CampusGGS（GGS 光栅器）",
			"实际 %s" % ("有 ★" if ggs != null else "无 ✓"))
		_check(campus == null, "关闭时**不应有** Campus（GDGS 泼溅）",
			"实际 %s" % ("有 ★" if campus != null else "无 ✓"))
		# GGS 节点若因别的原因存在，至少要 `_gave_up`
		if ggs != null:
			_check(bool(ggs.get("_gave_up")), "若有节点，必须 _gave_up（不建光栅器）")

	# 实体网格必须留着 —— 去掉泼溅不等于把校园拆了
	print("[实体] 检查校园的实体部分还在")
	for n in ["CampusBridge", "CampusFloor", "CampusPlinth", "Plaza", "Hall"]:
		_check(level.get_node_or_null(n) != null, "实体节点仍在：%s" % n)

	# 碰撞也要在（否则人会掉下去）
	var floor_body := level.get_node_or_null("CampusFloor") as StaticBody3D
	if floor_body != null:
		var has_col := false
		for c in floor_body.get_children():
			if c is CollisionShape3D:
				has_col = true
		_check(has_col, "CampusFloor 仍有碰撞形状")

	print()
	print("========== 结果 ==========")
	print("  通过 %d，失败 %d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
