extends SceneTree
## 诊断：飞猪优香打完到底走哪条掉落路径？
##
## 用户 2026-11-09：「为什么飞猪优香打完不掉钱了，要银行卡的 1w」
##
## 疑点：`pig_boss.gd::_init()` 里写了 `drop_to_bank = true`，但 `_init()` 在
## **场景属性应用之前**跑。场景 `game.tscn` 的 BossPig 节点没写 `drop_to_bank`，
## 所以理论上不该被覆盖 —— 但 `@export` 字段在实例化时会用「默认值」重新赋值一次，
## 有可能把 `_init()` 里改的值冲掉。这条探针直接读运行时值来判定。
##
## 用法：
##   & <godot> --headless --path . --script res://scripts/_verify_pig_drop_bank.gd -- --no-capture

const GAME := "res://scenes/game.tscn"
const BankCard := preload("res://scripts/bank_card.gd")

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
	print("========== 飞猪优香掉落路径诊断 ==========")
	var ps := load(GAME) as PackedScene
	if ps == null:
		push_error("[diag] 加载不了 %s" % GAME)
		quit(1)
		return
	var level := ps.instantiate()
	root.add_child(level)
	for _i in 10:
		await process_frame

	var pig := level.get_node_or_null("BossPig")
	if pig == null:
		push_error("[diag] 找不到 BossPig")
		quit(1)
		return

	# ① 运行时字段值（这是最关键的：_init 里设的 true 还在不在）
	var drop_yuan := int(pig.get("drop_yuan"))
	var drop_to_bank := bool(pig.get("drop_to_bank"))
	print("\n── 运行时字段 ──")
	print("  drop_yuan    = %d" % drop_yuan)
	print("  drop_to_bank = %s" % str(drop_to_bank))
	print("  max_health   = %.0f（场景覆盖了 1800，对比 _init 的默认值）" % float(pig.get("max_health")))
	_check(drop_yuan == 10000, "drop_yuan = 10000（实际 %d）" % drop_yuan)
	_check(drop_to_bank, "drop_to_bank = true（实际 %s）—— true 才会进银行卡" % str(drop_to_bank))

	# ② 造两个假的「本轮资产」和银行卡，杀一次看钱去哪
	var fut := get_first_node_in_group("futures")
	if fut == null:
		print("\n  ⚠️ 场上没有 futures 节点 —— 若 drop_to_bank 万一为 false，钱会直接丢失")
	else:
		print("\n── futures 节点存在：%s ──" % fut.get_path())

	var bank_before := BankCard.balance()
	print("  银行卡余额（击杀前）= %d" % bank_before)

	# ③ 直接打死
	pig.call("take_damage", 999999.0)
	await process_frame
	await process_frame

	var bank_after := BankCard.balance()
	var gained := bank_after - bank_before
	print("\n── 击杀后 ──")
	print("  银行卡余额 = %d（增加 %d）" % [bank_after, gained])
	_check(gained == 10000, "银行卡 +10000（实际 +%d）" % gained)

	print("\n========== 结果 ==========")
	print("  通过 %d，失败 %d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
