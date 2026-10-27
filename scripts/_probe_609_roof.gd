extends SceneTree
## 验：609 的**黑色屋顶**是不是按墙的碰撞体算出来的（用户 2026-10-27）。
## 同时出一张屋外俯瞰图。
##   _tools/run_shot.sh res://scripts/_probe_609_roof.gd

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 60:
		await process_frame
	paused = false
	for c in game.find_children("*", "CanvasLayer", true, false):
		var cl: CanvasLayer = c as CanvasLayer
		if cl != null:
			cl.visible = false
	# 玩家挪到屋外 → 代码会把代理墙/屋顶显示出来
	var player := game.get_node_or_null("Player") as Node3D
	if player != null:
		player.global_position = Vector3(20.0, 0.2, 3.0)
	for _i in 20:
		await process_frame

	var body := game.get_node_or_null("Room609/RoomCollision")
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var slab_size := Vector3.ZERO
	var slab_pos := Vector3.ZERO
	if body != null:
		# 先认墙（高 > 2 m），再从「扁且贴墙顶」的盒子里找屋顶板
		var boxes: Array[AABB] = []
		var sizes: Array[Vector3] = []
		var xfs: Array[Transform3D] = []
		for c in body.get_children():
			var cs := c as CollisionShape3D
			if cs == null or not (cs.shape is BoxShape3D):
				continue
			var s: Vector3 = (cs.shape as BoxShape3D).size
			boxes.append(cs.global_transform * AABB(-s * 0.5, s))
			sizes.append(s)
			xfs.append(cs.global_transform)
		for i in boxes.size():
			if sizes[i].y > 2.0:
				lo = lo.min(boxes[i].position)
				hi = hi.max(boxes[i].position + boxes[i].size)
		for i in boxes.size():
			var b: AABB = boxes[i]
			if sizes[i].y <= 2.0 and (b.position.y + b.size.y) >= hi.y - 1.0:
				slab_size = sizes[i]
				slab_pos = xfs[i].origin
				break
	print("墙包围：x %.3f ~ %.3f   z %.3f ~ %.3f   顶面 y = %.3f"
		% [lo.x, hi.x, lo.z, hi.z, hi.y])
	print("屋顶板碰撞：%.3f × %.3f × %.3f @ (%.3f, %.3f, %.3f)"
		% [slab_size.x, slab_size.y, slab_size.z, slab_pos.x, slab_pos.y, slab_pos.z])

	var proxy := game.get_node_or_null("RoomProxy")
	var roof: MeshInstance3D = null
	if proxy != null:
		roof = proxy.get_node_or_null("Roof") as MeshInstance3D
	if roof != null:
		var rs: Vector3 = (roof.mesh as BoxMesh).size
		var rp := roof.global_position
		print("黑色屋顶网格：中心 %s  尺寸 (%.3f, %.3f, %.3f)"
			% [str(rp.snappedf(0.001)), rs.x, rs.y, rs.z])
		var match_slab := slab_size != Vector3.ZERO \
			and rs.distance_to(slab_size) < 0.002 and rp.distance_to(slab_pos) < 0.002
		var cover := (absf((rp.x - rs.x * 0.5) - lo.x) < 0.002
			and absf((rp.x + rs.x * 0.5) - hi.x) < 0.002
			and absf((rp.z - rs.z * 0.5) - lo.z) < 0.002
			and absf((rp.z + rs.z * 0.5) - hi.z) < 0.002
			and absf((rp.y - rs.y * 0.5) - hi.y) < 0.002)
		if slab_size != Vector3.ZERO:
			print("  [%s] 屋顶网格 = 屋顶板碰撞盒（位置 + 尺寸）" % ("PASS" if match_slab else "FAIL"))
		else:
			print("  [%s] 没有屋顶板，屋顶按墙包围盒自动生成" % ("PASS" if cover else "FAIL"))
	else:
		print("  [FAIL] 没找到 RoomProxy/Roof")

	var cam := Camera3D.new()
	game.add_child(cam)
	cam.global_position = Vector3(16.0, 12.0, 22.0)
	cam.look_at(Vector3(-0.5, 2.0, 3.5))
	cam.current = true
	for _i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_room609_roof.png")
	img.save_png(out)
	print("[截图] %s" % out)
	quit(0)
