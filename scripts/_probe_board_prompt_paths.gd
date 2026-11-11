extends SceneTree
## 探针（二）：**按最短通关路径**验证「跑道口火箭脚下会不会挂出『按 F 上箭』」。
##
## ── 为什么要重新写一条 ──
## `_probe_board_prompt_real` 直接把 `RunMemory.set_parkour_done(true)` 之前的现场
## 拿来用，量到的 `_home_rocket_revealed = false` 是**正常的**（这一局刚开，没通关）。
## 但它也没回答真正的问题：玩家**这一局通关回来之后**，站到火箭脚下还会不会有提示。
##
## ── 怎么走最短路径 ──
## `_on_run_finished()` 是 `run_finished` 的槽 —— 直接 `run_finished.emit()` 等价于
## 「计时器在最后一站停了表」，和真跑完全程比起来少掉的是「跑」的部分，不是状态机。
## 所以分三种情形各验一遍：
##   ① 本局通关（emit run_finished）
##   ② 换场景回来（RunMemory 记着 + 重新实例化 parkour.tscn）
##   ③ 两种情形下都把人放到**门前**（0 m，会被门吞掉）和**门侧**（3 m）各量一次
##
## 用法：
##   godot --headless --path . --script res://scripts/_probe_board_prompt_paths.gd -- --no-capture

var _fail := 0
var _pass := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, msg: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % msg)
	else:
		_fail += 1
		print("  ✗ %s" % msg)


func _new_parkour() -> Node3D:
	var pk := (load("res://scenes/parkour.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(pk)
	return pk


func _new_player() -> Node3D:
	var p := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Node3D
	p.add_to_group("player")
	root.add_child(p)
	return p


func _run() -> void:
	print("========== 上箭提示路径探针 ==========")
	var rm := load("res://scripts/run_memory.gd")
	rm.call("wipe")

	# ── ① 本局通关 ──
	print("\n──── ① 本局通关（emit run_finished）────")
	var pk := _new_parkour()
	var player := _new_player()
	for _i in 40:
		await physics_frame
	pk.set("_player", player)
	print("  通关前 _home_rocket_revealed = %s" % str(pk.get("_home_rocket_revealed")))
	# 走真实信号路径
	pk.emit_signal("run_finished", 60.0, 55.0)
	for _i in 10:
		await physics_frame
	_check(bool(pk.get("_home_rocket_revealed")), "通关后 _home_rocket_revealed = true")
	_check(bool(rm.call("parkour_done")), "RunMemory.parkour_done() = true（跨场景可记住）")
	var home: Vector3 = pk.call("_home_spot")
	var door := pk.get_node_or_null("FinishPortal") as Node3D
	_check(door != null, "传送门立起来了")
	if door != null:
		print("  门 = %s / 停机位 = %s（相距 %.2f m）" % [
			str(door.global_position.snappedf(0.01)),
			str(home.snappedf(0.01)),
			door.global_position.distance_to(home)])

	# ①-a 站门侧 3 m（玩家真实处境：回程落地后站在门旁边）
	player.global_position = home + Vector3(3.0, 1.2, 0.0)
	for _i in 20:
		await physics_frame
	var fut := get_first_node_in_group("futures")
	print("  站门侧：玩家 %s，_riding = %s，owner = %s" % [
		str(player.global_position.snappedf(0.01)),
		str(pk.get("_riding")),
		str(fut.call("prompt_owner") if fut != null else "无 futures")])
	_check(fut != null and fut.call("prompt_owner") == pk,
		"★ 门侧 3 m 会挂出「按 F 上箭」提示")
	if fut != null:
		var lab := fut.get_node_or_null("FuturesHUD/Prompt") as Label
		if lab != null:
			print("  HUD 文本 = 「%s」 alpha = %.2f" % [lab.text, lab.modulate.a])

	# ①-b 站门正中（会被门自动带走 —— 这是设计，不是 bug）
	if door != null:
		player.global_position = door.global_position + Vector3(0.0, 1.2, 0.0)
		for _i in 6:
			await physics_frame
		print("  站门正中：_riding = %s（门会自动拉走去坐火箭）" % str(pk.get("_riding")))
		_check(bool(pk.get("_riding")),
			"站门正中会被自动带走（`_riding` = true）—— 所以门里**不会**有 F 提示")
		# 等人落地
		var g := 0
		while bool(pk.get("_riding")) and g < 1200:
			g += 1
			await physics_frame
		print("  落地：玩家 %s" % str(player.global_position.snappedf(0.01)))

	pk.queue_free()
	player.queue_free()
	for _i in 6:
		await physics_frame

	# ── ② 换场景回来（RunMemory 记着）──
	print("\n──── ② 换场景回来（RunMemory 已记）」────")
	var pk2 := _new_parkour()
	var player2 := _new_player()
	for _i in 40:
		await physics_frame
	pk2.set("_player", player2)
	_check(bool(pk2.get("_home_rocket_revealed")), "新实例化的跑酷：火箭直接亮着")
	var door2 := pk2.get_node_or_null("FinishPortal") as Node3D
	_check(door2 != null, "传送门直接就在")
	var home2: Vector3 = pk2.call("_home_spot")
	player2.global_position = home2 + Vector3(3.0, 1.2, 0.0)
	for _i in 20:
		await physics_frame
	var fut2 := get_first_node_in_group("futures")
	print("  站门侧：owner = %s，_riding = %s" % [
		str(fut2.call("prompt_owner") if fut2 != null else "无"),
		str(pk2.get("_riding"))])
	_check(fut2 != null and fut2.call("prompt_owner") == pk2,
		"★ 换场景回来、门侧 3 m 仍然会挂出提示")

	print("\n========== 结果：通过 %d，失败 %d ==========" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
