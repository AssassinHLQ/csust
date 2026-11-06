extends SceneTree
## 验：钱包从 0 开始 / 倭瓜掉 10 万 / 通关传送门能送到结算屋
##   godot --path . --headless --script res://scripts/_verify_economy.gd
const BankCard := preload("res://scripts/bank_card.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("[eco] 新存档默认余额 = %s（期望 ¥0）" % BankCard.format_yuan(BankCard.balance()))

	var lvl := (load("res://scenes/parkour.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(lvl)
	var player := (load("res://scenes/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	root.add_child(player)
	for _i in 30:
		await process_frame

	# ① 倭瓜掉落：先记本轮资产，**结算前不进银行卡**
	var fut := lvl.get_node_or_null("Futures")
	if fut != null:
		fut.set("assets_yuan", 0)
		fut.set("margin", 0.0)
		fut.set("debt", 0)
	BankCard.set_balance(0)
	lvl.call("_on_avenger_died", 1.0)
	for _i in 5:
		await process_frame
	print("[eco] 倭瓜倒下后 银行卡 = %s（期望 ¥0）、资产 = %s（期望 20.0 万）" % [
		BankCard.format_yuan(BankCard.balance()),
		BankCard.format_yuan(int(fut.get("assets_yuan"))) if fut != null else "-"])
	if fut != null:
		fut.call("settle_all")
		print("[eco] 结算后 银行卡 = %s（期望 20.0 万）" % BankCard.format_yuan(BankCard.balance()))

	# ② 通关 → 传送门
	var launch := lvl.get_node_or_null("Launch") as Node3D
	var shed := lvl.get_node_or_null("Island/Props/Shed") as Node3D
	lvl.call("_on_run_finished", 60.0, 55.0)
	for _i in 10:
		await process_frame
	var portal := lvl.get_node_or_null("FinishPortal") as Node3D
	print("[eco] 传送门=%s 位置=%s（跑道口 %s）" % [
		"有" if portal != null else "无",
		str(portal.global_position.snappedf(0.1)) if portal != null else "-",
		str(launch.global_position.snappedf(0.1)) if launch != null else "-"])

	# ③ 踩上去 → **坐火箭**送到结算屋
	#    2026-11-06 起传送不再是瞬移（见 `scripts/rocket_ride.gd`）：飞行全程约
	#    1.10 + 2.60 + 1.30 + 0.35 ≈ 5.35 s，所以不能像以前那样 20 帧就断言到站。
	#    这里改用 `physics_frame` 轮询 `_riding`（进程帧在 headless 下跑得飞快，
	#    按进程帧数等会等不到物理时间）。
	if portal != null:
		player.global_position = portal.global_position + Vector3(0.0, 1.0, 0.0)
		player.velocity = Vector3.ZERO
		var guard := 0
		# 先等它真的起飞（触发盒 → begin() 有 1~2 帧延迟）
		while not bool(lvl.get("_riding")) and guard < 60:
			guard += 1
			await physics_frame
		var rode := bool(lvl.get("_riding"))
		var ticks := 0
		while bool(lvl.get("_riding")) and ticks < 900:
			ticks += 1
			await physics_frame
		var d: float = player.global_position.distance_to(shed.global_position) if shed != null else -1.0
		print("[eco] 火箭起飞=%s，飞了 %d 物理帧（%.2f s）" % [
			str(rode), ticks, float(ticks) / 60.0])
		print("[eco] 踩门后玩家到结算屋距离 = %.2f m（期望 < 2）" % d)

	BankCard.set_balance(0)
	print("[eco] 余额已重置为 ¥0（正式开局状态）")
	quit(0)
