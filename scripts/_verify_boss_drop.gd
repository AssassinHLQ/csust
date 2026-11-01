extends SceneTree
## 验：飞猪 drop_yuan=10000、普通 Boss 默认 0；结算文案带 RAM/5090 拆分。
const BankCard := preload("res://scripts/bank_card.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var pig = load("res://scripts/pig_boss.gd").new()
	print("[drop] 飞猪 drop_yuan = %d（期望 10000）" % int(pig.get("drop_yuan")))
	pig.free()
	var trex = load("res://scripts/trex_yuuka_boss.gd").new()
	print("[drop] 霸王龙 drop_yuan = %d（期望 0，那 20 万由跑酷发）" % int(trex.get("drop_yuan")))
	trex.free()

	# 结算文案
	var fut = load("res://scripts/parkour_futures.gd").new()
	fut.set("margin", 0.0)
	fut.set("assets_yuan", 239996)
	fut.set("ram_count", 12)
	fut.set("gpu_count", 4)
	BankCard.set_balance(0)
	var msg: String = fut.call("settle_all")
	print("[drop] " + msg)
	print("[drop] 银行卡 = %s（期望 ¥24.0 万左右）" % BankCard.format_yuan(BankCard.balance()))
	fut.free()
	BankCard.set_balance(0)
	quit(0)
