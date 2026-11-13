extends SceneTree
## 验：期货 HUD 在**常态**（没在跑酷）下要显示**银行卡余额**。
##
## 用户 2026-11-13 截图问：「为什么常态不显示银行卡余额而显示这个（最近结算：—）」
##
## 病因：`_build_hud()` 里 `_update_hud_text()` 被放在「`_debt_label` 建好、
##       `_bank_label` 还没建」的位置，函数里 `if _bank_label != null` 直接跳过
##       ⇒ 银行卡那行 text 永远是空串，之后只有结算/捡钱/买卖才会再刷。
##       所以「啥也没干」的时候只剩一行填不上的「最近结算：—」。
##
##   godot --path . --script res://scripts/_verify_futures_hud.gd -- --no-capture

const OFF := preload("res://scripts/offscreen_window.gd")

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await OFF.apply(self, Vector2i(1280, 720))
	for _i in 3:
		await process_frame
	print("═══ 期货 HUD · 常态余额验收 ═══\n")

	var scene := (load("res://scenes/parkour.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for _i in 90:
		await process_frame

	var fut: Node = get_first_node_in_group("futures")
	_check(fut != null, "场景里有 `Futures` 总控")
	if fut == null:
		_summary()
		quit(1)
		return

	var bank: Label = fut.get("_bank_label")
	var result: Label = fut.get("_result_label")
	var debt: Label = fut.get("_debt_label")
	_check(bank != null, "建出了银行卡余额那行")
	_check(debt != null, "建出了保证金那行")
	_check(result != null, "建出了「最近结算」那行")
	if bank == null or result == null:
		_summary()
		quit(1)
		return

	# ① 常态：余额那行要有内容（这就是用户要的「一直显示银行卡余额」）
	var bt := bank.text.strip_edges()
	print("  [HUD] 银行卡行：`%s`" % bt)
	print("  [HUD] 最近结算行：`%s`" % result.text.strip_edges())
	_check(not bt.is_empty(), "常态下银行卡余额**有字**（不是空字符串）")
	_check(bt.begins_with("银行卡"), "余额那行写的是「银行卡 …」（实际 `%s`）" % bt)
	_check(bt.contains("¥"), "带上了 ¥ 金额（实际 `%s`）" % bt)

	# ② 常态：余额那行是**亮着**的（跑酷中/结束后都不该淡出）
	_check(bank.modulate.a >= 0.99,
		"余额那行不透明（alpha %.2f）" % bank.modulate.a)

	# ③ 常态：保证金那行淡出（别和余额抢位置）
	_check(debt.modulate.a <= 0.05,
		"保证金那行在常态是淡出的（alpha %.2f）" % debt.modulate.a)

	# ④ 没结算过时，「最近结算」那行不该用「—」占位
	_check(result.text.strip_edges().is_empty(),
		"还没结算过 → 最近结算那行留空（实际 `%s`）" % result.text.strip_edges())

	# ⑤ 结算之后它才出现（拿真接口改一下状态，别手改私有变量）
	fut.call("_update_hud_text")
	var bt2 := bank.text.strip_edges()
	_check(bt2 == bt, "再刷一次也不会变成空（`%s`）" % bt2)

	print("\n  [HUD] 余额行锚点 y=%.0f..%.0f，最近结算行 y=%.0f..%.0f"
		% [bank.offset_top, bank.offset_bottom, result.offset_top, result.offset_bottom])
	_check(result.offset_top >= bank.offset_bottom,
		"两行不重叠（余额 %.0f–%.0f / 结算 %.0f–%.0f）"
		% [bank.offset_top, bank.offset_bottom, result.offset_top, result.offset_bottom])

	_summary()
	quit(0 if _fail == 0 else 1)


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % what)
	else:
		_fail += 1
		print("  ✗ %s" % what)


func _summary() -> void:
	print("\n═══ 通过 %d / 失败 %d ═══" % [_pass, _fail])
