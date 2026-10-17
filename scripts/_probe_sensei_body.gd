extends SceneTree
## 探针：确认老师身上真的挂了一个**胶囊碰撞体**，并打半径/总高/位置。
## 不渲图（`_probe_sensei_shot.gd` 那种要等 `frame_post_draw`，headless 下会永远等下去）。
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_sensei_body.gd


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 30:
		await process_frame
	var sensei := game.get_node_or_null("Sensei")
	if sensei == null:
		print("!! 场景里没有 Sensei")
		quit(1)
		return
	var body := sensei.get_node_or_null("Body") as StaticBody3D
	if body == null:
		print("!! 老师身上没有 Body（碰撞没建出来）")
		quit(1)
		return
	print("[body] StaticBody3D layer=%d mask=%d" % [body.collision_layer, body.collision_mask])
	for c in body.get_children():
		if c is CollisionShape3D:
			var cs := c as CollisionShape3D
			if cs.shape is CapsuleShape3D:
				var cap := cs.shape as CapsuleShape3D
				print("[body] 胶囊：半径 %.3f m  总高 %.3f m  位置 y=%.2f  世界位置 %s" % [
					cap.radius, cap.height, cs.position.y,
					str((cs.global_position).snappedf(0.01))])
			else:
				print("[body] 形状类型 %s" % cs.shape.get_class())
	var player := game.get_node_or_null("Player") as Node3D
	var sp: Vector3 = sensei.global_position
	print("[body] 老师 %s  玩家 %s  水平距离 %.2f m" % [
		str(sp.snappedf(0.01)),
		str(player.global_position.snappedf(0.01)) if player else "?",
		Vector2(sp.x - player.global_position.x, sp.z - player.global_position.z).length()
		if player else -1.0])
	quit(0)
