extends SceneTree
## 验跑酷：复活点只剩「本场景存档点」一个，不再跟着 checkpoint 走。
##   godot --path . --headless --script res://scripts/_probe_parkour_single_cp.gd

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var player := (load("res://scenes/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	root.add_child(player)
	var pk := (load("res://scenes/parkour.tscn") as PackedScene).instantiate()
	root.add_child(pk)
	for _i in 10:
		await process_frame
	pk.set("enabled", false)
	pk.set("_player", player)

	print("[cp] respawn_station() = %d（期望 0）" % pk.call("respawn_station"))
	pk.set("checkpoint", 42)
	print("[cp] checkpoint=42 时 respawn_station() = %d（期望仍是 0）"
		% pk.call("respawn_station"))

	var scene_cp := Vector3(-10.5, 0.05, 6.5)
	# 真实流程里这一步由 game.gd 做：进场景时把「本场景唯一的存档点」交给玩家
	player.set_respawn_point(scene_cp)
	var far := pk.call("respawn_point", 42) as Vector3
	player.global_position = far
	for _i in 5:
		await process_frame
	print("[cp] 先把人放到第 42 站 %s" % str(player.global_position.snappedf(0.1)))
	pk.call("_rescue")
	for _i in 5:
		await process_frame
	print("[cp] 摔落后位置=%s  checkpoint=%d  timer=%s" % [
		str(player.global_position.snappedf(0.1)), pk.get("checkpoint"),
		str(pk.get("timer_running"))])
	var d: float = player.global_position.distance_to(scene_cp)
	print("[cp] 判定：%s" % ("通过（回场景存档点、进度清零）" if d < 1.0
		and int(pk.get("checkpoint")) == -1 else "不通过"))
	quit(0)
