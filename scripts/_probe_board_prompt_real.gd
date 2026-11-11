extends SceneTree
## 探针：「跑道口火箭脚下不出『按 F 上箭』提示」—— 到**真场景**里复现。
##
## 为什么不能只靠 `_verify_run_memory`：那条自检把玩家**直接 set 到**火箭旁边，
## 然后手动 `pk.set("_player", player)`，再等 6 个 process_frame —— 它验的是
## 「提示逻辑本身对不对」，**不是**「真游戏里玩家走过去会不会挂上」。
## 用户 2026-11-11 报的就是后者不行，所以这里走真 `game.tscn`。
##
## 查这三件事：
##   ① 跑道口那枚火箭到底 **visible** 没有（`_home_rocket_revealed` 是否被置位）
##   ② 人站到火箭脚下 3 m 处，`parkour._update_board_prompt()` 有没有把 owner 挂上
##   ③ 挂上了的话，HUD 那个 `Futures/Prompt` Label 的 `text` / `modulate.a` 是什么

const OFFWIN := preload("res://scripts/offscreen_window.gd")

var _game: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("========== 跑道口上箭提示探针 ==========")
	# 真场景要开窗口才能建渲染资源？不需要 —— headless 一样能跑逻辑，
	# 但 `game.tscn` 里有泼溅/后处理会 warn，用 --splat=off 关掉。
	_game = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(_game)
	for _i in 60:
		await physics_frame

	var pk := _game.get_node_or_null("Parkour")
	if pk == null:
		print("!! 场景里没有 Parkour")
		quit(1)
		return

	var player := get_first_node_in_group("player") as Node3D
	if player == null:
		print("!! 没有 player")
		quit(1)
		return

	print("\n── ① 状态 ──")
	print("  RunMemory.parkour_done() = %s" % str(bool(pk.get("_home_rocket_revealed"))))
	if pk.has_method("_home_spot"):
		var home: Vector3 = pk.call("_home_spot")
		print("  _home_spot() = %s" % str(home.snappedf(0.01)))
		var fin := pk.get("_finish_rocket") as Node3D
		print("  _finish_rocket = %s" % ("null" if fin == null else str(fin.global_position.snappedf(0.01))))
		if fin != null:
			print("  visible = %s / is_visible_in_tree = %s" % [
				str(fin.visible), str(fin.is_visible_in_tree())])

		# ── ② 把人放到火箭脚边 ──
		print("\n── ② 人去火箭脚下 3 m ──")
		player.global_position = home + Vector3(3.0, 1.2, 0.0)
		# 等几帧让物理落地、`_update_board_prompt()` 跑起来
		for _i in 30:
			await physics_frame
		print("  玩家 = %s（离停机位 %.2f m）" % [
			str(player.global_position.snappedf(0.01)),
			player.global_position.distance_to(home)])
		print("  parkour._board_prompting = %s" % str(pk.get("_board_prompting")))
		print("  parkour._riding         = %s" % str(pk.get("_riding")))

		# ── ③ HUD 上的字 ──
		var fut := get_first_node_in_group("futures")
		print("\n── ③ HUD 提示 ──")
		if fut == null:
			print("  !! 场上没有 futures 组")
		else:
			print("  prompt_owner() = %s" % str(fut.call("prompt_owner")))
			var lab := fut.get_node_or_null("FuturesHUD/Prompt") as Label
			if lab == null:
				print("  !! 没有 FuturesHUD/Prompt 这个 Label")
			else:
				print("  Prompt.text = 「%s」  modulate.a = %.2f  visible = %s" % [
					lab.text, lab.modulate.a, str(lab.is_visible_in_tree())])

	# ── ④ 谁在抢 owner ──
	print("\n── ④ 附近的拾取物 ──")
	for g in ["ryzen9950x3d", "rtx5090"]:
		var best := INF
		var best_n: Node3D = null
		for c in get_nodes_in_group(g):
			var n := c as Node3D
			if n == null:
				continue
			var d := player.global_position.distance_to(n.global_position)
			if d < best:
				best = d
				best_n = n
		if best_n == null:
			print("  %s：一颗都没有" % g)
		else:
			print("  %s：最近 %.2f m（%s）" % [g, best, str(best_n.global_position.snappedf(0.1))])

	_game.queue_free()
	await process_frame
	quit(0)
