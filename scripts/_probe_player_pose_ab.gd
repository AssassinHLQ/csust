extends SceneTree
## 对比：同一个 player.tscn 在 game.tscn 与 next_level.tscn 里的姿态。
##   _tools/run_probe.sh res://scripts/_probe_player_pose_ab.gd -- --splat=off

func _initialize() -> void:
	_run.call_deferred()


func _dump(tag: String, player: Node3D) -> void:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var rows: Array[String] = []
	for mi in player.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var b: AABB = m.global_transform * m.get_aabb()
		lo = lo.min(b.position)
		hi = hi.max(b.position + b.size)
		rows.append("%s y %.2f~%.2f" % [m.name, b.position.y, b.position.y + b.size.y])
	print("[%s] 玩家 %s  on_floor=%s" % [tag, str(player.global_position), str((player as CharacterBody3D).is_on_floor())])
	print("[%s] 全部网格 y %.3f ~ %.3f" % [tag, lo.y, hi.y])
	print("[%s] 逐网格：%s" % [tag, " | ".join(rows)])
	var ap := player.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap != null:
		print("[%s] 动画 %s @ %.3f playing=%s" % [tag, ap.current_animation, ap.current_animation_position, str(ap.is_playing())])
	var sk := player.find_child("Skeleton3D", true, false) as Skeleton3D
	if sk != null:
		for bone in ["Bip001 Pelvis", "Bip001 Head"]:
			var idx := sk.find_bone(bone)
			if idx >= 0:
				var p := (sk.global_transform * sk.get_bone_global_pose(idx)).origin
				print("[%s] %s 世界位置 (%.3f, %.3f, %.3f)" % [tag, bone, p.x, p.y, p.z])


func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 90:
		await process_frame
	_dump("Game", game.get_node("Player") as Node3D)
	game.queue_free()
	for _i in 4:
		await process_frame

	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	for _i in 90:
		await process_frame
	_dump("NextLevel", level.get_node("Player") as Node3D)
	quit(0)
