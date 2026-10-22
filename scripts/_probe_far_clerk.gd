extends SceneTree
## 探针：① 渲染距离 400 m、把人挪到 450 m 外，玩家模型还在不在
##       ② 芹香有没有碰撞（从正面打一条射线）
##   godot --path . --script res://scripts/_probe_far_clerk.gd -- --splat=off
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 60:
		await process_frame
	paused = false
	GameSettings.set_value("render_distance", 400.0)
	game.call("_apply_render")
	for _i in 10:
		await process_frame

	var rd: Node = game.get("_rd")
	var player := game.get("_player") as Node3D
	var model := player.get_node_or_null("Arisu/Model") as Node3D
	print("── ① 远处还看得见自己吗 ──")
	print("   出生点 %s  模型 visible=%s" % [str(player.global_position.snappedf(0.1)), str(model.visible)])
	# 挪到 450 m 外（内存条市场那一片）
	player.global_position = player.global_position + Vector3(-450.0, 0.0, 0.0)
	for _i in 12:
		await process_frame
	print("   挪到 %s 后：模型 visible=%s（应为 true）" % [
		str(player.global_position.snappedf(0.1)), str(model.visible)])
	var st: Dictionary = rd.get("stats")
	print("   距离统计：%s" % str(st))

	print("── ② 芹香碰撞 ──")
	var clerk := game.get_node_or_null("Shop/ClerkSerika") as Node3D
	if clerk != null:
		var body := clerk.get_node_or_null("ClerkBody") as StaticBody3D
		print("   ClerkBody 存在=%s 层=%d" % [str(body != null), body.collision_layer if body else -1])
		var space := (clerk as Node3D).get_world_3d().direct_space_state
		var from := clerk.global_position + Vector3(-1.2, 0.9, 0.0)
		var to := clerk.global_position + Vector3(1.2, 0.9, 0.0)
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collide_with_areas = false
		var hit := space.intersect_ray(q)
		print("   射线 %s → %s ：%s" % [str(from.snappedf(0.01)), str(to.snappedf(0.01)),
			"打中 " + str(hit.get("collider").name) if not hit.is_empty() else "什么也没打到"])
	quit(0)
