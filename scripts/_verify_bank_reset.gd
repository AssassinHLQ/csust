extends SceneTree
## 验：每次启动（新进程）银行卡从 0 开始；同一局里照常累计。
##   godot --path . --headless --script res://scripts/_verify_bank_reset.gd
const BankCard := preload("res://scripts/bank_card.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# 先在磁盘上伪造一张「上次玩剩下 100 万」的卡
	var cf := ConfigFile.new()
	cf.set_value("card", "yuan", 1000000)
	cf.set_value("card", "v", 2)
	cf.save(BankCard.PATH)

	print("[bank] 磁盘旧卡 = ¥1,000,000；本进程第一次读 = %s（期望 ¥0）" % [
		BankCard.format_yuan(BankCard.balance())])
	# 同一进程内：结算/扣款照常累计
	BankCard.add(670000)
	print("[bank] 本局赚 67 万 → %s（期望 ¥67.0 万，说明同局不清零）" % [
		BankCard.format_yuan(BankCard.balance())])
	BankCard.spend(670000)
	print("[bank] 买整机扣 67 万 → %s（期望 ¥0）" % BankCard.format_yuan(BankCard.balance()))
	quit(0)
