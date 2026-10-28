extends SceneTree
## 量/看：校园放大 3 倍 + 校平 + 多盒碰撞之后的样子。
##   _tools/run_shot.sh res://scripts/_probe_campus_scale.gd -- --no-capture
## 出图：
##   _campus_scale_bridge.png     桥头望向校园
##   _campus_scale_overview.png   高空俯瞰
##   _campus_scale_ground.png     站在校园地面上（第三人称，复现用户视角）
##   _hall_ambient.png            大厅内（检查环境光是不是黑的）

func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(name)
	root.get_texture().get_image().save_png(out)
	print("[截图] %s" % out)


func _down_y(space: PhysicsDirectSpaceState3D, x: float, z: float, from_y := 120.0) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, from_y, z), Vector3(x, -10.0, z))
	q.collide_with_areas = false
	var h := space.intersect_ray(q)
	return float(h.position.y) if not h.is_empty() else -999.0


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	var campus := level.get_node_or_null("Campus")
	if campus == null:
		print("[scale] 没有 Campus")
		quit(1)
		return
	campus.call("force_start")
	var t0 := Time.get_ticks_msec()
	while not bool(campus.call("is_ready")) and Time.get_ticks_msec() - t0 < 180000:
		await process_frame
	if not bool(campus.call("is_ready")):
		print("[scale] 校园没加载完")
		quit(1)
		return
	for _i in 10:
		await process_frame

	var box: AABB = campus.call("content_world_aabb")
	print("[scale] 内容盒 pos %s size %s" % [
		str(box.position.snappedf(0.1)), str(box.size.snappedf(0.1))])
	print("[scale] 世界尺寸应约 576 × 484 m（放大 3 倍）")
	var node := campus.get("splat_node") as Node3D
	var top_world: float = (node.global_transform * (campus.get("content_max") as Vector3)).y
	print("[scale] 内容顶面 y=%.2f" % top_world)

	var col := level.get_node_or_null("CampusCollisionMesh")
	if col == null:
		col = level.get_node_or_null("CampusCollision")
	var shapes := 0
	var tris := 0
	if col != null:
		for c in col.find_children("*", "CollisionShape3D", true, false):
			var cs := c as CollisionShape3D
			shapes += 1
			if cs.shape is ConcavePolygonShape3D:
				tris += (cs.shape as ConcavePolygonShape3D).get_faces().size() / 3
			elif cs.shape is BoxShape3D:
				tris += 12
	print("[scale] 校园碰撞：%d 形状 / %d 面" % [shapes, tris])

	var space: PhysicsDirectSpaceState3D = level.get_world_3d().direct_space_state
	for p in [Vector2(0, -120), Vector2(0, -200), Vector2(60, -300), Vector2(-200, -400)]:
		print("[scale] 地面射线 (%d, %d) → y=%.2f" % [int(p.x), int(p.y), _down_y(space, p.x, p.y)])
	# 找一块烘好的建筑，从上往下打，应该比地面高很多
	if col != null and col.get_child_count() > 2:
		var b := col.get_child(2) as Node3D
		var bp := b.global_position
		var q := PhysicsRayQueryParameters3D.create(
			Vector3(bp.x, 120.0, bp.z), Vector3(bp.x, -10.0, bp.z))
		q.collide_with_areas = false
		var h: Dictionary = space.intersect_ray(q)
		if h.is_empty():
			print("[scale] 建筑 %s 射线下没有碰撞" % b.name)
		else:
			var hit := h.get("position") as Vector3
			var collider := h.get("collider") as Node
			print("[scale] 建筑 %s 中心 %s → 命中 %s，顶面 y=%.2f"
				% [b.name, str(bp.snappedf(0.1)),
					collider.name if collider else "?", hit.y])

	# 先让玩家站到桥头 —— 可见性闸门是按玩家位置判的，人还在大厅里校园就是藏着的
	var player := level.get_node("Player") as CharacterBody3D
	player.global_position = Vector3(10.0, 0.3, -60.0)
	for _i in 20:
		await physics_frame
	for c in level.find_children("*", "CanvasLayer", true, false):
		var cl := c as CanvasLayer
		if cl != null:
			cl.visible = false
	var cam := Camera3D.new()
	cam.fov = 70.0
	level.add_child(cam)
	cam.current = true

	cam.global_position = Vector3(10.0, 9.0, -52.0)
	cam.look_at(Vector3(0.0, 8.0, -160.0))
	await _shot("_campus_scale_bridge.png")

	cam.global_position = Vector3(120.0, 190.0, 30.0)
	cam.look_at(Vector3(0.0, 0.0, -260.0))
	cam.fov = 66.0
	await _shot("_campus_scale_overview.png")

	# 第三人称：把玩家放到校园地面上，让相机自己跟上
	cam.current = false
	player.global_position = Vector3(0.0, 0.4, -150.0)
	for _i in 40:
		await physics_frame
	for _i in 10:
		await process_frame
	await _shot("_campus_scale_ground.png")
	print("[scale] 玩家落点 %s" % str(player.global_position.snappedf(0.1)))

	for c in level.find_children("*", "CanvasLayer", true, false):
		var cl := c as CanvasLayer
		if cl != null:
			cl.visible = true
	var pcam := player.get("cam") as Camera3D
	if pcam != null:
		pcam.current = true
	await _shot("_campus_scale_ground_hud.png")

	# 大厅内环境光检查
	player.global_position = Vector3(0.0, 0.3, 4.0)
	for _i in 40:
		await physics_frame
	for _i in 10:
		await process_frame
	await _shot("_hall_ambient_player.png")

	cam.current = true
	cam.global_position = Vector3(0.0, 2.3, 8.0)
	cam.look_at(Vector3(0.0, 4.6, -6.0))
	await _shot("_hall_ambient.png")
	quit(0)
