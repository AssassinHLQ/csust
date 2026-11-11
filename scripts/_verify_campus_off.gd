extends SceneTree
## 验证校园泼溅的**渲染路径选择**（2026-11-11 从 GGS 改回 GDGS 之后）。
##
## 用户点破的事：「校园改回 gdgs,raster 这么快,原来是把点全部砍掉了,也不要 lod 了」
##   ⇒ 当年那组 fps 不可比：Compute 3.2 fps 是**全量 615 万点**，
##     Raster 50 fps 是**只画 3×3 窗口 ~120 万点 + q4 粗层**。
##     现在默认走 GDGS 全量，不切窗口、不用粗层。
##
## 三种模式各验一遍：
##   默认                     → Campus（GDGS）在、CampusGGS 不在
##   -- --ggs-campus=on       → CampusGGS 在（GGS 分块窗口）
##   -- --campus-splat=off    → 两者都不在（只留实体网格）
##
##   & <godot> --headless --path . --script res://scripts/_verify_campus_off.gd

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


func _mode() -> String:
	var args := OS.get_cmdline_user_args()
	if args.has("--campus-splat=off") or args.has("--no-campus-splat"):
		return "off"
	if args.has("--ggs-campus=on"):
		return "ggs"
	return "gdgs"


func _run() -> void:
	var mode := _mode()
	print("========== 校园泼溅路径（模式 = %s）==========" % mode)
	var ps := load(LEVEL) as PackedScene
	if ps == null:
		push_error("[off] 加载不了关卡")
		quit(1)
		return
	var level := ps.instantiate()
	root.add_child(level)
	for _i in 30:
		await process_frame

	var ggs := level.get_node_or_null("CampusGGS")
	var campus := level.get_node_or_null("Campus")

	match mode:
		"off":
			_check(ggs == null, "不该有 CampusGGS", "实际 %s" % ("有 ★" if ggs != null else "无 ✓"))
			_check(campus == null, "不该有 Campus（GDGS）", "实际 %s" % ("有 ★" if campus != null else "无 ✓"))
		"ggs":
			_check(ggs != null, "该有 CampusGGS", "实际 %s" % ("有 ✓" if ggs != null else "无 ★"))
		_:
			# 默认 = GDGS 全量
			_check(ggs == null, "GDGS 模式**不该**挂 CampusGGS", "实际 %s" % ("有 ★" if ggs != null else "无 ✓"))
			_check(campus != null, "GDGS 模式**该有** Campus（全量泼溅）",
				"实际 %s" % ("有 ✓" if campus != null else "无 ★"))
			if campus != null:
				# 全量：不该有分块窗口 / 粗层那套概念
				_check(campus.get("sog_path") == "res://splatdata/school_playable.sogdata",
					"指向全量 SOG", str(campus.get("sog_path")))
				print("      splash_node = %s" % str(campus.get("splat_node") != null))

	# 实体网格永远要在
	print("[实体] 检查校园实体部分还在")
	var ok_all := true
	for n in ["CampusBridge", "CampusFloor", "CampusPlinth", "Plaza", "Hall"]:
		if level.get_node_or_null(n) == null:
			ok_all = false
			print("     缺 %s" % n)
	_check(ok_all, "实体节点全在（地板/桥/平台/大厅）")

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
