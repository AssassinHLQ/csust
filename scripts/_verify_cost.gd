extends SceneTree
## 自检：COST（费用）系统 —— 攒 / 封顶 / 花 / HUD 接线。
##
## 规则由用户 2026-11-09 指定：**上限 10、开局 0、每秒固定回 1、只有爱丽丝花**。
##
##   _tools/run_probe.sh res://scripts/_verify_cost.gd
##
## 覆盖：
##   ① `cost_gauge.gd` 的三个常量就是用户说的那三个数
##   ② `tick()` 按 `PER_SECOND` 累加，且**封顶在上限**（不溢出）
##   ③ 小数不丢（条是连续涨的；只有显示才取整）
##   ④ `spend()`：不够不扣、够了才扣、扣完余下的小数留着
##   ⑤ HUD 真把那一行建出来了（`Cost` / `CostTrough` / `CostBar`），
##      且**排在最上面**（弹药在它下面）
##   ⑥ HUD 真的在喂时间（`has_ticked()`），而且 `_player` 为空时也喂
##      —— 这一条是这次最容易写错的地方（原来 `_process` 开头就 return 了）

const CostGauge := preload("res://scripts/cost_gauge.gd")
## BA 风格自绘条（三层斜切）。用它当类型标注，自检才能直接读那几个几何常量。
const CostBarView := preload("res://scripts/cost_bar.gd")
const HUD_SCENE := "res://scenes/hud.tscn"

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


func _run() -> void:
	print("========== 1. 常量就是用户说的那三个数 ==========")
	_check(CostGauge.MAX_COST == 10, "上限 = 10（实际 %d）" % CostGauge.MAX_COST)
	_check(is_equal_approx(CostGauge.START_COST, 0.0),
		"开局 = 0（实际 %.2f）" % CostGauge.START_COST)
	_check(is_equal_approx(CostGauge.PER_SECOND, 1.0),
		"每秒回复 = 1.0（实际 %.2f）" % CostGauge.PER_SECOND)
	# 爱丽丝 EX 的消耗 —— wiki 查证值（见 `cost_gauge.gd` 里那条注释的出处）
	_check(CostGauge.ARISU_EX_COST == 6,
		"爱丽丝 EX 消耗 = 6（wiki 查证值，实际 %d）" % CostGauge.ARISU_EX_COST)
	_check(CostGauge.ARISU_EX_COST <= CostGauge.MAX_COST,
		"EX 消耗不超过上限（%d ≤ %d）" % [CostGauge.ARISU_EX_COST, CostGauge.MAX_COST])

	print("")
	print("========== 2. 攒：按秒累加 + 封顶 ==========")
	CostGauge.reset()
	_check(is_equal_approx(CostGauge.cost, 0.0), "reset() 后回到 0")
	CostGauge.tick(1.0)
	print("       tick(1.0) → cost = %.4f，显示 %d" % [CostGauge.cost, CostGauge.display()])
	_check(is_equal_approx(CostGauge.cost, 1.0), "攒 1 秒 = 1 点")
	CostGauge.tick(0.5)
	print("       再 tick(0.5) → cost = %.4f，显示 %d" % [CostGauge.cost, CostGauge.display()])
	_check(is_equal_approx(CostGauge.cost, 1.5), "攒 1.5 秒 = 1.5 点（小数留着）")
	_check(CostGauge.display() == 1, "显示取整 = 1（向下取整）")
	CostGauge.tick(100.0)
	print("       再 tick(100) → cost = %.4f" % CostGauge.cost)
	_check(is_equal_approx(CostGauge.cost, 10.0), "封顶在 10，不会溢出")

	# 显示取整的边界
	CostGauge.set_cost_for_test(9.999)
	_check(CostGauge.display() == 9, "9.999 显示 9（不是 10 —— 没攒满就还没满）")
	CostGauge.set_cost_for_test(10.0)
	_check(CostGauge.display() == 10, "10.0 显示 10")

	print("")
	print("========== 3. 花：不够不扣、够了才扣 ==========")
	CostGauge.set_cost_for_test(3.0)
	_check(not CostGauge.can_afford(4), "3 点放不了 4 费技能")
	_check(not CostGauge.spend(4), "spend(4) 返回 false")
	_check(is_equal_approx(CostGauge.cost, 3.0), "失败的 spend **一点都没扣**（还是 3.0）")
	_check(CostGauge.can_afford(3), "3 点放得了 3 费技能")
	_check(CostGauge.spend(3), "spend(3) 返回 true")
	_check(is_equal_approx(CostGauge.cost, 0.0), "扣完正好 0")

	CostGauge.set_cost_for_test(2.7)
	_check(CostGauge.spend(2), "2.7 点放得了 2 费技能")
	print("       2.7 花掉 2 → cost = %.4f，显示 %d" % [CostGauge.cost, CostGauge.display()])
	_check(is_equal_approx(CostGauge.cost, 0.7), "**小数不丢**：剩下 0.7")
	_check(CostGauge.display() == 0, "剩下 0.7 显示 0")

	# 浮点容差：累加出来的 1.9999999 也该算「有 2 点」
	CostGauge.set_cost_for_test(1.99999)
	_check(CostGauge.can_afford(2), "1.99999 也算够 2 点（浮点容差）")
	_check(CostGauge.spend(0), "spend(0) 不做任何事、返回 true")

	print("")
	print("========== 4. HUD 把那一行建出来了 ==========")
	var hud := (load(HUD_SCENE) as PackedScene).instantiate() as CanvasLayer
	root.add_child(hud)
	for i in 4:
		await process_frame

	var vbox := hud.get_node_or_null("Panel/Margin/VBox") as VBoxContainer
	var label := hud.get_node_or_null("Panel/Margin/VBox/Cost") as Label
	var bar := hud.get_node_or_null("Panel/Margin/VBox/CostBar") as CostBarView
	_check(vbox != null, "拿到弹药面板的 VBox")
	_check(label != null, "COST 数字行 `Cost` 建出来了")
	_check(bar != null, "COST 条 `CostBar` 建出来了（`cost_bar.gd` 自绘条）")
	if bar != null:
		_check(is_equal_approx(bar.max_value, 10.0),
			"条的 max_value = 10（实际 %.1f）" % bar.max_value)
		_check(bar.has_method("set_cost"), "条有 `set_cost()`（喂值入口，内部会重画）")
		_check(bar.show_ticks, "条默认画 10 格刻度线")
		# 自绘条必须真的占到地方，否则 `_draw()` 第一行就 return 了、什么都不画
		_check(bar.size.x > 40.0 and bar.size.y >= 8.0,
			"条拿到了实际尺寸（%.0f×%.0f）" % [bar.size.x, bar.size.y])
		# 喂一个值 → 比例跟着走（证明 `set_cost` 真的写进去了）
		bar.set_cost(2.5)
		_check(is_equal_approx(bar.ratio(), 0.25), "喂 2.5 → 比例 0.25")
		bar.set_cost(50.0)
		_check(is_equal_approx(bar.ratio(), 1.0), "喂超上限 → 比例夹在 1.0")
	if label != null and vbox != null:
		_check(label.get_index() == 0, "COST 排在 VBox 第 0 位（最上面）")
		var ammo := hud.get_node_or_null("Panel/Margin/VBox/Ammo")
		if ammo != null:
			_check(label.get_index() < ammo.get_index(), "弹药在 COST 下面（挨着弹药那块）")
	if bar != null and vbox != null:
		_check(bar.get_index() == 1, "条紧跟数字行（第 1 位）")

	print("")
	print("========== 4b. 自绘条的三层几何 = 社区还原项目量到的官方值 ==========")
	# 出处：`ywhdzrb/BlueArchiveUI`（MIT）`src/ba_progress_bar.cpp` 按官方
	#      `Common_Bg_Raius5px` 量出的规格。这几个数**不是本喵调的**，改之前先去看那个文件。
	_check(is_equal_approx(CostBarView.BASE_H, 31.0), "官方基准高 31 px")
	_check(is_equal_approx(CostBarView.SLOPE, 0.42), "端部斜切量 = 层高 × 0.42")
	_check(is_equal_approx(CostBarView.CORNER, 0.18), "转角圆角 = 层高 × 0.18")
	_check(is_equal_approx(CostBarView.INSET_X, 4.5)
		and is_equal_approx(CostBarView.INSET_Y, 3.0), "外底→内槽：左右 4.5k / 上下 3.0k")
	_check(is_equal_approx(CostBarView.FORE_PAD, 3.5), "内槽→填充：再各内缩 3.5k")
	# 官方内槽色 (0.19, 0.27, 0.40)
	var tr: Color = CostBarView.C_TROUGH
	_check(absf(tr.r - 0.19) < 0.005 and absf(tr.g - 0.27) < 0.005
		and absf(tr.b - 0.40) < 0.005,
		"内槽深蓝 = (0.19, 0.27, 0.40)（实际 %.2f, %.2f, %.2f）" % [tr.r, tr.g, tr.b])
	# 自绘条**不许**引用任何贴图（官方《二创指引》禁止直接用游戏原始素材）
	var src := FileAccess.get_file_as_string("res://scripts/cost_bar.gd")
	_check(not src.contains("load(\"res://assets"),
		"自绘条不引用 `assets/` 下的贴图（不搬游戏原始素材）")

	print("")
	print("========== 5. HUD 真的在喂时间 ==========")
	# ⚠️ 这一段的关键：**此时 `hud._player` 是空的**。
	#    `_process` 原来第一行就是 `if _player == null: return`，
	#    所以「喂时间」那句必须放在它**前面**，否则玩家没绑上时费用永远不涨。
	CostGauge.reset()
	var before := CostGauge.cost
	for i in 30:
		await process_frame
	var after := CostGauge.cost
	print("       30 帧里：%.4f → %.4f（涨了 %.4f）" % [before, after, after - before])
	_check(CostGauge.has_ticked(), "HUD 调过 `tick()`（有人接线）")
	_check(after > before, "费用真的在涨（**且 `_player` 为空时也涨**）")
	if label != null:
		print("       数字行内容 = 「%s」" % label.text)
		_check(label.text.begins_with("COST "), "数字行文案是 `COST n / 10`")

	print("")
	print("========== 结果 ==========")
	if _fail == 0:
		print("全部 %d 项通过" % _pass)
	else:
		print("%d 项通过，%d 项失败" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
