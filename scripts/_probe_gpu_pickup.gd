extends SceneTree
## 复现「捡起 5090 游戏崩了」（用户 2026-11-10 报）。
##
## 只走真实代码路径：拿到房顶那张 `Rtx5090`，直接调它的 `_take()` ——
## 也就是玩家连按两次 F 之后走的那一支，之后的陷阱 / 牢笼 / 倭瓜优香登场
## 全由 `parkour.gd::trap_sequence()` → `_spawn_avenger()` 负责。
##
##   godot --path <工程> --script res://scripts/_probe_gpu_pickup.gd \
##         -- --no-capture
##
## ⚠️ 走的是**真实按键路径**：先 `Futures.ask_prompt()` 把 owner 设成这张卡，
##    再合成两次 `KEY_F` 按下去打 `Rtx5090._input()` —— 崩溃若来自
##    「在自己 `_input()` 里 `queue_free()` 自己」，只有这条路径能复现。
## 窗口模式必须 `OffWin.apply()` 挪到屏幕外（工作区硬要求，不许抢前台）。
##
## 只要进程在两次 F 之后还能打印「还活着」，就说明这条链没有硬崩；
## 硬崩（段错误）会表现为输出突然截断 + 退出码非 0。

const OffWin := preload("res://scripts/offscreen_window.gd")

func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	if DisplayServer.get_name() != "headless":
		await OffWin.apply(self, Vector2i(960, 540))
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(60)

	var p := game.get_node_or_null("Player") as Player
	var pk := game.get_node_or_null("Parkour") as Parkour
	print("[pick] Player=%s  Parkour=%s  渲染=%s" % [
		str(p != null), str(pk != null), DisplayServer.get_name()])
	if p == null or pk == null:
		quit(1)
		return

	# 2026-11 起房顶是**四张**（`RTX5090_1` … `RTX5090_4`），不是单张 `RTX5090`
	var shed := pk.get_node_or_null("Island/Props/Shed") as Node3D
	if shed == null:
		print("[pick] 找不到 Island/Props/Shed")
		quit(1)
		return
	var gpus: Array[Node] = []
	for c in shed.get_children():
		if String(c.name).begins_with("RTX5090"):
			gpus.append(c)
	print("[pick] 房顶 5090 = %d 张：%s" % [gpus.size(), str(gpus.map(func(n): return n.name))])
	if gpus.is_empty():
		print("[pick] 没有 5090 可捡")
		quit(1)
		return

	var gpu := gpus[0]
	# 让这张卡成为 Futures 当前提示的 owner，否则 `_input()` 第一行就 return
	var fut := get_first_node_in_group("futures")
	if fut == null:
		print("[pick] 场上没有 Futures")
		quit(1)
		return
	fut.call("ask_prompt", gpu, "按 F 拾取 RTX 5090（¥59,999）")
	gpu.set("_prompting", true)

	var ev := InputEventKey.new()
	ev.keycode = KEY_F
	ev.pressed = true
	print("[pick] → 第一次 F（应该弹「真的要拾取吗？」）")
	gpu.call("_input", ev)
	print("[pick] 确认状态 = %s，Futures 正文 = 「%s」" % [
		str(gpu.get("_confirming")), str(fut.get("current_text") if fut.has_method("current_text") else "?")])

	print("[pick] → 第二次 F（真正收走：陷阱 + 倭瓜优香）")
	gpu.call("_input", ev)
	print("[pick] 两次 F 之后还活着，等 60 帧看倭瓜优香")
	await _wait(60)

	var av: Variant = pk.get("_avenger")
	print("[pick] _avenger = %s" % str(av))
	if av is Node3D:
		print("[pick] 倭瓜优香位置 %s  血量 %.0f" % [
			str((av as Node3D).global_position.snappedf(0.01)), float((av as Node).get("health"))])
	print("[pick] 还活着 ✓")
	quit(0)

