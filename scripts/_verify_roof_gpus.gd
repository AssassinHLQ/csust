extends SceneTree
## 验：屋顶四张 5090 都生成了、位置摆得开；倭瓜掉 20 万
const BankCard := preload("res://scripts/bank_card.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var lvl := (load("res://scenes/parkour.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(lvl)
	for _i in 30:
		await process_frame
	var shed := lvl.get_node_or_null("Island/Props/Shed")
	var gpus: Array = []
	if shed != null:
		for c in shed.get_children():
			if String(c.name).begins_with("RTX5090"):
				gpus.append(c)
	print("[roof] 屋顶 5090 数量 = %d（期望 4）" % gpus.size())
	for g in gpus:
		print("[roof]   %s @ %s" % [g.name, str((g as Node3D).position.snappedf(0.01))])
	var fut := lvl.get_node_or_null("Futures")
	if fut != null:
		fut.set("assets_yuan", 0)
		fut.set("margin", 0.0)
		fut.set("debt", 0)
	BankCard.set_balance(0)
	lvl.call("_on_avenger_died", 1.0)
	for _i in 5:
		await process_frame
	print("[roof] 倭瓜掉落 → 银行卡 %s（期望 ¥0）、资产 %s（期望 20.0 万）" % [
		BankCard.format_yuan(BankCard.balance()),
		BankCard.format_yuan(int(fut.get("assets_yuan"))) if fut != null else "-"])
	BankCard.set_balance(0)
	quit(0)
