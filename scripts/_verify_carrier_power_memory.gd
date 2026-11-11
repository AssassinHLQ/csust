extends SceneTree
## 自检：机甲能量条**跨场景保留** + HUD 用 BA 皮肤（2026-11-11）。
##
## 用户两个问题：
##   ① 「为什么跨场景就清空了r的技能充能?」
##   ② 「还有这个hud没有ui加上,蔚蓝档案ui」→ 追加「不要自己建,用别人做好的蔚蓝档案ui」
##
## ① 的根因和 9950X3D 一样：`energy_bars` / `fly_distance_m` / `_bar_timers` 都是
##    `carrier_form.gd` 的**实例变量**，换场景（旧场景整棵释放）就没了。
##    现在存进 `RunMemory`（进程内 static，重开游戏才清空）。
##
## ② 的验收点：HUD 必须**挂着 UiSkin 做出来的 StyleBox**，而不是裸 Label。
##    判据：面板/数值片上有 `panel` 这个 stylebox 覆盖，且不是空的 StyleBoxEmpty。
##
## 用法：
##   bash _tools/run_probe.sh res://scripts/_verify_carrier_power_memory.gd -- --splat=off

const RunMemory := preload("res://scripts/run_memory.gd")
const GAME := "res://scenes/game.tscn"

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  %s" % what)
	else:
		_fail += 1
		print("  FAIL  %s" % what)


func _carrier_of(game: Node) -> Node:
	var player := game.get_node_or_null("Player")
	if player == null:
		return null
	return player.get_node_or_null("Arisu/CarrierForm")


func _run() -> void:
	print("========== 机甲能量条：跨场景 + BA 皮肤 ==========")
	RunMemory.wipe()
	_check(RunMemory.carrier_snapshot()["bars"] == 0, "wipe 之后记忆是空的")

	# ── ① 第一次进场景：攒能量，然后"换场景" ──
	print("\n── ① 攒能量 → 换场景回来还在不在 ──")
	var g1 := (load(GAME) as PackedScene).instantiate()
	root.add_child(g1)
	current_scene = g1
	for _i in 20:
		await process_frame
	var cf := _carrier_of(g1)
	_check(cf != null, "找得到 CarrierForm")
	if cf == null:
		quit(1)
		return

	# 造状态：不真飞（攒 3000 m 要飞很久，和本条无关），但**必须模拟"真实一帧"**——
	# `_save_power_memory()` 是在 `_update_power()` 末尾调的，而它只在机甲形态下跑。
	# 所以这里直接改值 + 手动调一次保存，等价于「飞完之后的那一帧」。
	cf.set("energy_bars", 3)
	cf.set("fly_distance_m", 120.0)
	cf.call("_save_power_memory")
	# 再走一遍**真实**的 R 键路径（它内部会自己存一次）
	var used := bool(cf.call("use_energy_bar"))
	_check(used, "按 R 成功启用一条（真实 API）")
	for _i in 3:
		await process_frame
	var snap1 := RunMemory.carrier_snapshot()
	print("  第一次：energy_bars=%s  fly=%.0f  生效中=%d  记忆=%s" % [
		str(cf.get("energy_bars")), float(cf.get("fly_distance_m")),
		(cf.get("_bar_timers") as Array).size(), str(snap1)])
	_check(int(snap1["bars"]) == 2, "记忆里是 2 条（3 条花掉 1 条）")
	_check(float(snap1["fly_m"]) > 100.0, "记忆里带着攒条进度 %.0f m" % float(snap1["fly_m"]))
	_check((snap1["timers"] as Array).size() == 1, "记忆里带着 1 条生效中的剩余秒数")

	# 换场景 = 旧场景整棵释放 + 新的一份
	g1.queue_free()
	for _i in 4:
		await process_frame
	var g2 := (load(GAME) as PackedScene).instantiate()
	root.add_child(g2)
	current_scene = g2
	for _i in 20:
		await process_frame
	var cf2 := _carrier_of(g2)
	_check(cf2 != null, "新场景里也有 CarrierForm")
	if cf2 != null:
		print("  换场景回来：energy_bars=%s  fly=%.0f  生效中=%d  攻速=%.1f" % [
			str(cf2.get("energy_bars")), float(cf2.get("fly_distance_m")),
			(cf2.get("_bar_timers") as Array).size(), float(cf2.get("rate_scale"))])
		_check(int(cf2.get("energy_bars")) == 2,
			"★ 换场景之后**存条还在**（2 条，实际 %s）" % str(cf2.get("energy_bars")))
		_check(float(cf2.get("fly_distance_m")) > 100.0,
			"★ 攒条进度也在（%.0f m）" % float(cf2.get("fly_distance_m")))
		_check((cf2.get("_bar_timers") as Array).size() == 1,
			"★ 生效中那一条也在（1 条）")
		_check(absf(float(cf2.get("rate_scale")) - 2.0) < 0.001,
			"★ 攻速按生效条数重算对了（×2.0）")

	# ── ② 重开游戏 = wipe → 清空 ──
	print("\n── ② 重开游戏（wipe）──")
	RunMemory.wipe()
	_check(int(RunMemory.carrier_snapshot()["bars"]) == 0, "wipe 之后存条归零")
	_check((RunMemory.carrier_snapshot()["timers"] as Array).is_empty(), "wipe 之后生效计时也清空")
	g2.queue_free()
	for _i in 4:
		await process_frame

	# ── ③ HUD 是不是真的用了 BA 皮肤 ──
	print("\n── ③ HUD 用 BA 皮肤（不是裸 Label）──")
	var g3 := (load(GAME) as PackedScene).instantiate()
	root.add_child(g3)
	current_scene = g3
	for _i in 20:
		await process_frame
	var cf3 := _carrier_of(g3)
	if cf3 == null:
		_check(false, "（新场景里没有 CarrierForm，没法验 HUD）")
	else:
		# ⚠️ 必须先解锁：`set_form(true)` 开头有 `if not MechState.carrier_unlocked():
		#    push_warning + return false`，不解锁直接调会被静默拒掉，
		#    HUD 当然不会出现（第一版就是这么假红的）。
		var MechStateScript := load("res://scripts/mech_state.gd") as GDScript
		MechStateScript.call("set_carrier_for_test", true)
		var ok := bool(cf3.call("set_form", true))
		_check(ok, "变形成功（机甲已解锁）")
		# 造点能量再变机甲，HUD 才会出现
		cf3.set("energy_bars", 4)
		for _i in 25:
			await process_frame
		var layer := cf3.get_node_or_null("CarrierPowerHUD") as CanvasLayer
		_check(layer != null, "能量条 HUD 出现了")
		if layer != null:
			_check(layer.visible, "HUD 可见")
			# 找带 `panel` stylebox 覆盖的 PanelContainer
			var styled := 0
			var empty := 0
			for n in layer.find_children("*", "PanelContainer", true, false):
				var pc := n as PanelContainer
				var sb := pc.get_theme_stylebox("panel")
				if sb == null:
					continue
				if sb is StyleBoxEmpty:
					empty += 1
				else:
					styled += 1
					print("  %-12s 面板样式 = %s" % [pc.name, sb.get_class()])
			print("  带样式的面板 %d 个，空样式 %d 个" % [styled, empty])
			_check(styled >= 2,
				"★ HUD 用了 **UiSkin 的面板**（白板 + 数值片，%d 个 ≥ 2）" % styled)
			_check(empty == 0, "没有空样式（%d 个）" % empty)
			# 字体也得是 CJK 界面字体，否则中文变方框
			var font_ok := 0
			for n in layer.find_children("*", "Label", true, false):
				var lab := n as Label
				if lab.get_theme_font("font") != null:
					font_ok += 1
			print("  用了显式字体的 Label %d 个" % font_ok)
			_check(font_ok >= 3, "三个标签都挂了 CJK 界面字体（%d 个）" % font_ok)

	print("\n========== 结果 ==========")
	print("  通过 %d，失败 %d" % [_pass, _fail])
	print("  %s" % ("★ 能量条跨场景保留 + HUD 走 BA 皮肤" if _fail == 0 else "✗ 有问题"))
	quit(0 if _fail == 0 else 1)
