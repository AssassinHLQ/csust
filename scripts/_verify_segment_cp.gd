extends SceneTree
## 验「每段一个存档点」：摔落后回本段起点，进度退到段首。
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var lvl := (load("res://scenes/parkour.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(lvl)
	var player := (load("res://scenes/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	root.add_child(player)
	for _i in 30:
		await process_frame
	lvl.set("enabled", false)
	lvl.set("_player", player)

	for st in [-1, 5, 7, 8, 9, 19, 20, 32, 40, 98]:
		lvl.set("checkpoint", st)
		var back: int = lvl.call("respawn_station")
		var seg: int = int(lvl.call("segment_of", back))
		print("[seg] checkpoint=%d → 复活站 %d（第 %d 段起点）" % [st, back, seg + 1])

	# 真摔一次：放到第 20 站，调 _rescue
	lvl.set("checkpoint", 20)
	var seg20 := int(lvl.call("segment_of", 20))
	player.global_position = lvl.call("respawn_point", 20)
	await process_frame
	lvl.call("_rescue")
	for _i in 5:
		await process_frame
	var want: Vector3 = lvl.call("respawn_point", int(lvl.call("segment_start", seg20)))
	print("[seg] 从第 21 站摔落 → 落点 %s，期望 %s，checkpoint=%d（期望 %d）" % [
		str(player.global_position.snappedf(0.1)), str(want.snappedf(0.1)),
		lvl.get("checkpoint"), int(lvl.call("segment_start", seg20))])
	quit(0)
