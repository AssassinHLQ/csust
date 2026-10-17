extends SceneTree
## 验证「重进游戏回初始位置」：
##   · 存档里 checkpoint=35（W8），加载后 `Parkour.checkpoint` 必须还是 −1；
##   · 玩家必须留在 game.tscn 的初始出生点，不能被传送；
##   · `resume_on_start` 默认 false。

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 20:
		await process_frame
	var p := game.get_node_or_null("Player") as Player
	var pk := game.get_node_or_null("Parkour") as Parkour
	if p == null or pk == null:
		print("!! 缺 Player / Parkour")
		quit(1)
		return
	var spawn := Vector3(0, 0.05, 6)
	var ok_ck := pk.checkpoint == -1
	var ok_pos := p.global_position.distance_to(spawn) < 0.5
	print("[start] resume_on_start=%s checkpoint=%d finished=%s timer=%s" % [
		str(pk.resume_on_start), pk.checkpoint, str(pk.finished), str(pk.timer_running)])
	print("[start] player=%s  spawn=%s  在初始点=%s  检查点清零=%s" % [
		str(p.global_position.snappedf(0.01)), str(spawn), str(ok_pos), str(ok_ck)])
	# 再等 1.5 s，确认没有任何「读档续跑」迟到传送
	var t0 := Time.get_ticks_msec()
	var moved := 0.0
	while Time.get_ticks_msec() - t0 < 1500:
		await process_frame
		moved = maxf(moved, p.global_position.distance_to(spawn))
	print("[start] 1.5 s 内离初始点最远 %.3f m  最终 %s  最终检查点 %d" % [
		moved, str(p.global_position.snappedf(0.01)), pk.checkpoint])
	print("[start] 结论：%s" % ("PASS" if ok_ck and ok_pos and moved < 1.0 else "FAIL"))
	quit(0 if ok_ck and ok_pos and moved < 1.0 else 1)
