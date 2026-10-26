extends SceneTree
## 验数 + 判图：芹香**在店里实际站着**的高度 —— 头顶骨、脚骨、以及一张侧视全身。
##   godot --path . --script res://scripts/_probe_clerk_height.gd -- --splat=off
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(700, 900)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 130:
		await process_frame
	paused = false
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_clerkview")
	DirAccess.make_dir_recursive_absolute(out)
	for c in game.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
	var clerk := game.get_node_or_null("Shop/ClerkSerika") as Node3D
	var base := clerk.global_position
	var skel: Skeleton3D = clerk.find_children("*", "Skeleton3D", true, false)[0]
	print("骨骼 %d 根" % skel.get_bone_count())
	# 找头、脚、胯
	var pick := ["head", "hip", "pelvis", "foot", "toe"]
	for i in skel.get_bone_count():
		var n := skel.get_bone_name(i).to_lower()
		for k in pick:
			if n.contains(k):
				var w: Vector3 = skel.global_transform * skel.get_bone_global_pose(i).origin
				print("  %-28s 世界 y = %+.3f" % [skel.get_bone_name(i), w.y])
				break

	# 世界包围盒（绑定姿势，但足以判断「她的高度量级对不对」）
	var bb := AABB()
	var first := true
	for mi in clerk.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var a: AABB = m.global_transform * m.mesh.get_aabb()
		bb = a if first else bb.merge(a)
		first = false
	print("网格世界包围盒 y %.3f ~ %.3f（高 %.3f）" % [
		bb.position.y, bb.end.y, bb.end.y - bb.position.y])

	var cam := Camera3D.new()
	cam.fov = 34.0
	cam.near = 0.02
	cam.far = 400.0
	root.add_child(cam)
	# 南侧平视全身：她和柜台的关系一眼看清
	# ⚠️ 相机必须站在**店内**：她 z = -15.30，商店南墙内表面 z = -18.10，
	#    原来退到 base.z - 3.60 = -18.90 已经在墙外了（整屏一面墙色）。
	#    柜台占 z -17.10 ~ -13.30，所以从**北侧**（z = -13.0）往南看是唯一无遮挡的直线。
	cam.global_position = Vector3(base.x, 0.80, base.z + 2.30)
	cam.look_at(Vector3(base.x, 0.80, base.z), Vector3.UP)
	cam.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/elevation.png" % out)
	print("[截图] %s/elevation.png" % out)
	quit(0)
