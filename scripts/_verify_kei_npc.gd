extends SceneTree
## headless 验第二场景里的凯伊：**不开窗口**。
##
##   _tools/run_probe.sh res://scripts/_verify_kei_npc.gd
##
## 查五件事：
##   1. 场景能起来、凯伊节点在、模型建出来了；
##   2. 她是**站桩**的（`is_standby()`），落地了（`is_on_floor()`），
##      没被墙挤走（位置和场景里写的差得不多）；
##   3. 第二场景里有 `DialogueBox`（原来没有，是给凯伊加的）；
##   4. 搭话能开起来（`DialogueBox.is_active()`）；
##   5. **付款回调真能扣钱 + 解锁载具形态**（这是核心，必须验）。
##
## ⚠️ 会写 `user://mech.cfg`：跑完把原来的状态放回去，别把用户的进度冲掉。

const Level := preload("res://scripts/next_level.gd")
const BankCard := preload("res://scripts/bank_card.gd")
const MechState := preload("res://scripts/mech_state.gd")

## 场景里写的位置（`scenes/next_level.tscn` 的 Kei 节点）
const EXPECT := Vector3(1.2, 0.35, 5.2)


func _initialize() -> void:
	# ⚠️ 看门狗：探针里任何一步报错都会让 `_run()` 中断、`quit()` 走不到，
	#    上一次就是这么**挂了 10 分钟**。这里兜一个上限，到点无论无何都退出。
	_watchdog()
	_run.call_deferred()


func _watchdog() -> void:
	var t := create_timer(90.0, true)
	t.timeout.connect(func():
		print("[kei] !! 看门狗超时（90 s）—— 探针中途出错了，强制退出")
		quit(1))


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame


func _run() -> void:
	var was_unlocked := MechState.carrier_unlocked()
	var was_balance := BankCard.balance()
	var fails := 0

	root.size = Vector2i(1280, 720)
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	# 同伴的模型是错峰延迟建的（`BOOT_FIRST_DELAY + slot * BOOT_STEP_DELAY`）
	await _wait(180)

	# ── 1. 节点与模型 ──
	var kei := level.get_node_or_null("Kei")
	if kei == null:
		print("[kei] !! 场景里没有 Kei 节点")
		quit(1)
		return
	var model = kei.get("model")
	var anim = kei.get("anim")
	print("[kei] 节点在｜模型=%s｜AnimDriver=%s｜动作=%s" % [
		"有" if model != null else "**没有**",
		"有" if anim != null else "**没有**",
		("-" if anim == null else str(anim.get("idle_anim")))])
	if model == null:
		fails += 1

	# ── 2. 站桩 + 落地 + 没被挤走 ──
	var standby := bool(kei.call("is_standby"))
	var body := kei as CharacterBody3D
	var on_floor := body != null and body.is_on_floor()
	var pos: Vector3 = (kei as Node3D).global_position
	var drift := Vector2(pos.x - EXPECT.x, pos.z - EXPECT.z).length()
	print("[kei] 站桩=%s｜落地=%s｜位置=(%.2f, %.2f, %.2f)｜水平偏移 %.2f m｜y=%.2f（地板约 0.00）" % [
		str(standby), str(on_floor), pos.x, pos.y, pos.z, drift, pos.y])
	if not standby:
		print("[kei] !! 她没在站桩状态，会跟着玩家跑")
		fails += 1
	if not on_floor:
		print("[kei] !! 她没落地（会在半空停住）")
		fails += 1
	if drift > 0.6:
		print("[kei] !! 水平被挤走 %.2f m —— 站位可能卡在墙/家具里" % drift)
		fails += 1

	# ── 3. 对话框 ──
	var d := level.get_node_or_null("DialogueBox") as DialogueBox
	print("[kei] DialogueBox=%s" % ("在" if d != null else "**没有**"))
	if d == null:
		print("[kei] !! 没有对话框，按 F 不会说话")
		fails += 1

	# ── 4. 搭话能开 ──
	if d != null:
		kei.call("_talk", d)
		await _wait(3)
		var active := d.is_active()
		print("[kei] 搭话：is_active=%s｜步骤数=%d" % [str(active), d.step_count()])
		if not active:
			print("[kei] !! 对话没起来")
			fails += 1
		d.finish()
		await _wait(3)

	# ── 5. 付款回调：扣钱 + 解锁 ──
	var price := MechState.CARRIER_PRICE
	MechState.set_carrier_for_test(false)
	BankCard.set_balance(price + 12345)
	var before := BankCard.balance()
	kei.call("_on_dialogue_custom", "mech_pay", {"amount": price, "label": "自检"})
	await _wait(2)
	var after := BankCard.balance()
	var unlocked := MechState.carrier_unlocked()
	print("[kei] 付款回调：卡 %s → %s（差 %s，应为 %s）｜解锁=%s" % [
		BankCard.format_yuan(before), BankCard.format_yuan(after),
		BankCard.format_yuan(before - after), BankCard.format_yuan(price), str(unlocked)])
	if before - after != price:
		print("[kei] !! 扣款金额不对")
		fails += 1
	if not unlocked:
		print("[kei] !! 没有解锁载具形态")
		fails += 1

	# ── 钱不够时不该扣成负数 ──
	MechState.set_carrier_for_test(false)
	BankCard.set_balance(1000)
	kei.call("_on_dialogue_custom", "mech_pay", {"amount": price, "label": "自检-钱不够"})
	await _wait(2)
	var poor := BankCard.balance()
	var poor_unlocked := MechState.carrier_unlocked()
	print("[kei] 钱不够：卡 %s（应还是 1000）｜解锁=%s（应为 false）" % [
		BankCard.format_yuan(poor), str(poor_unlocked)])
	if poor != 1000 or poor_unlocked:
		print("[kei] !! 钱不够却扣款/解锁了")
		fails += 1

	# ── 6. 载具形态（按 G 变形）：解锁前不该能变，解锁后要能建出来 ──
	var player := level.get_node_or_null("Player")
	var cf := player.get_node_or_null("Arisu/CarrierForm") if player != null else null
	if cf == null:
		print("[kei] !! 玩家身上没有 CarrierForm 节点")
		fails += 1
	else:
		MechState.set_carrier_for_test(false)
		var blocked := bool(cf.call("set_form", true))
		MechState.set_carrier_for_test(true)
		var turned_on := bool(cf.call("set_form", true))
		await _wait(3)
		var model_node := player.get_node_or_null("Arisu/Model") as Node3D
		var carrier_node := cf.get_node_or_null("Arisu_Battle_Carrier") as Node3D
		if carrier_node == null:
			# 实例名可能被 Godot 改了，按类型再找一次
			for c in cf.get_children():
				if c is Node3D and c.name.begins_with("Arisu_Battle_Carrier"):
					carrier_node = c
		var ap_names: Array = []
		for c in cf.find_children("*", "AnimationPlayer", true, false):
			ap_names = (c as AnimationPlayer).get_animation_list()
			break
		print("[kei] 载具：未解锁时能变=%s（应为 false）｜解锁后能变=%s｜本体隐藏=%s｜载具节点=%s｜动作=%s" % [
			str(blocked), str(turned_on),
			str(model_node != null and not model_node.visible),
			"有" if carrier_node != null else "**没有**", str(ap_names)])
		if blocked:
			print("[kei] !! 没解锁却能变形")
			fails += 1
		if not turned_on or carrier_node == null:
			print("[kei] !! 解锁后变形失败（载具没建出来）")
			fails += 1
		if not ap_names.has("Idle") or not ap_names.has("Walk"):
			print("[kei] !! 载具模型缺 Idle/Walk 动作")
			fails += 1
		var back := not bool(cf.call("set_form", false))
		print("[kei] 变回本体：%s" % ("可以" if back else "**失败**"))
		if not back:
			fails += 1

	# ── 收尾：把用户原来的进度还回去 ──
	if was_unlocked:
		MechState.unlock_carrier()
	else:
		MechState.reset()
	BankCard.set_balance(was_balance)
	print("[kei] 已还原：解锁=%s｜卡 %s" % [
		str(MechState.carrier_unlocked()), BankCard.format_yuan(BankCard.balance())])
	print("[kei] %s" % ("全部通过" if fails == 0 else "**%d 项不合格**" % fails))
	quit(0 if fails == 0 else 1)
