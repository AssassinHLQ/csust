extends SceneTree
## 验「血量归零 → 像掉虚空一样回存档点」，不再原地复活。
##   godot --path . --headless --script res://scripts/_probe_death_respawn.gd

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(level)
	for _i in 40:
		await process_frame
	var player := level.get("_player") as CharacterBody3D
	var spawn: Vector3 = (level.get_node("SpawnPoint") as Node3D).global_position
	print("[death] 存档点=%s  玩家起点=%s" % [str(player.respawn_point().snappedf(0.01)),
		str(player.global_position.snappedf(0.01))])
	# 先走远一点，免得「原地满血」也能蒙混过关
	player.global_position = Vector3(2.0, 0.6, -3.0)
	for _i in 10:
		await process_frame
	var before := player.global_position
	player.take_damage(9999.0)
	print("[death] 扣血后 health=%.1f 位置=%s" % [player.health, str(before.snappedf(0.1))])
	for _i in 20:
		await process_frame
	print("[death] 0.33 s：位置=%s（还没传送）" % str(player.global_position.snappedf(0.1)))
	for _i in 60:
		await process_frame
	var after := player.global_position
	print("[death] 重生后 health=%.1f 位置=%s  与存档点差 %.2f m" % [
		player.health, str(after.snappedf(0.1)), after.distance_to(spawn)])
	print("[death] 判定：%s" % ("通过（回存档点且满血）" if after.distance_to(spawn) < 1.0
		and player.health >= player.max_health - 0.1 else "不通过"))
	quit(0)
