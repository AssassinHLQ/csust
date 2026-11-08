extends SceneTree
## 量画室609 的真实高度范围（屋顶在哪、地板在哪），给「屋顶上不加载」定上限。
##
##   godot --path . --script res://scripts/_probe_room_height.gd

const SCENE := "res://scenes/game.tscn"


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _run() -> void:
	var packed := load(SCENE) as PackedScene
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame

	var col: Node = scene.get_node_or_null("Room609/RoomCollision")
	print("[h] ── 每个碰撞盒的世界 y 范围 ──")
	var wall_lo := INF
	var wall_hi := -INF
	var all_lo := INF
	var all_hi := -INF
	for c in col.get_children():
		var cs := c as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		var s: Vector3 = (cs.shape as BoxShape3D).size
		var b: AABB = cs.global_transform * AABB(-s * 0.5, s)
		var is_wall := s.y > 2.0
		print("[h]   %-12s y %.2f ~ %.2f（高 %.2f）%s" % [
			cs.name, b.position.y, b.position.y + b.size.y, s.y,
			"← 墙" if is_wall else ""])
		all_lo = min(all_lo, b.position.y)
		all_hi = max(all_hi, b.position.y + b.size.y)
		if is_wall:
			wall_lo = min(wall_lo, b.position.y)
			wall_hi = max(wall_hi, b.position.y + b.size.y)

	print("[h] 墙的 y 范围：%.2f ~ %.2f" % [wall_lo, wall_hi])
	print("[h] 所有盒 y 范围：%.2f ~ %.2f" % [all_lo, all_hi])

	# 屋顶板（扁、贴墙顶）
	print("[h] ── 屋顶 / 顶板候选（扁盒且 y 在墙顶附近）──")
	for c in col.get_children():
		var cs := c as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		var s: Vector3 = (cs.shape as BoxShape3D).size
		var b: AABB = cs.global_transform * AABB(-s * 0.5, s)
		if s.y > 2.0:
			continue
		var top := b.position.y + b.size.y
		if absf(top - wall_hi) < 1.0:
			print("[h]   %-12s y %.2f ~ %.2f（厚 %.2f）面积 %.0f m²" % [
				cs.name, b.position.y, top, s.y, s.x * s.z])

	# 代理网格的顶板（游戏里真正能看到的那块）
	var proxy: Node3D = scene.get_node_or_null("RoomProxy") as Node3D
	if proxy != null:
		print("[h] ── RoomProxy 子节点 y 范围 ──")
		for c in proxy.get_children():
			var mi := c as MeshInstance3D
			if mi == null:
				continue
			var bb := mi.get_aabb()
			var w := mi.global_transform * bb
			print("[h]   %-16s y %.2f ~ %.2f" % [
				mi.name, w.position.y, w.position.y + w.size.y])

	print("[h] 玩家出生点 y = %.2f" % (
		(scene.get_node_or_null("Player") as Node3D).global_position.y if scene.get_node_or_null("Player") else NAN))
	print("[h] 完成")
	quit(0)
