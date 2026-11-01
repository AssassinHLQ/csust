extends SceneTree
## 验：落到结束平台就记存档；摔了回岛上。倭瓜四技能、频率 1.8。
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var lvl := (load("res://scenes/parkour.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(lvl)
	var player := (load("res://scenes/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	root.add_child(player)
	for _i in 20:
		await process_frame

	player.global_position = Vector3(-590.95, 8.4, -9.5)
	for _i in 10:
		await process_frame
	var cp: Vector3 = lvl.get("_island_cp")
	print("[island] 落到岛上后存档点 = %s（期望不是 inf）" % str(cp.snappedf(0.1)))

	player.global_position = Vector3(-300, 0, 0)
	lvl.call("_rescue")
	for _i in 5:
		await process_frame
	print("[island] 摔落后位置 = %s（期望回岛上 %s）" % [
		str(player.global_position.snappedf(0.1)), str(cp.snappedf(0.1))])

	var sb = load("res://scripts/squash_boss.gd").new()
	var consts: Dictionary = sb.get_script().get_script_constant_map()
	print("[squash] 技能数 = %d（期望 4）  interval=%.2f  start_delay=%.2f  windup=%.2f" % [
		int(consts.get("SKILL_COUNT", -1)), float(sb.get("attack_interval")),
		float(sb.get("attack_start_delay")), float(sb.get("windup_time"))])
	for fn in ["_skill_slam", "_skill_dash", "_skill_quake"]:
		print("[squash] %s 存在 = %s" % [fn, str(sb.has_method(fn))])
	sb.free()
	quit(0)
