extends SceneTree
## 出图：开一枪，把「准星点（绿）」和「实际落点（红）」各放一个球，看是否重合。
##   _tools/run_shot.sh res://scripts/_probe_aim_shot.gd -- --no-capture
## 输出：
##   _aim_after_full.png   全屏
##   _aim_after_zoom.png   以屏幕中心裁 400×300、2× 最近邻放大
##
## 必须真窗口 + **不能带 --splat=off**：后者会把 609 的碰撞关掉（见 splat_scene.gd），
## 子弹会一直飞到 300 m 外。

func _initialize() -> void:
	_run.call_deferred()


func _marker(parent: Node, pos: Vector3, col: Color, radius: float) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.no_depth_test = true
	mi.material_override = m
	parent.add_child(mi)
	mi.global_position = pos


func _shot(file_name: String, crop_center: bool) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if crop_center:
		var c := Vector2i(root.size) / 2
		img = img.get_region(Rect2i(c - Vector2i(200, 150), Vector2i(400, 300)))
		img.resize(800, 600, Image.INTERPOLATE_NEAREST)
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(file_name)
	img.save_png(out)
	print("[截图] %s" % out)


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 60:
		await process_frame
	paused = false

	var player := game.get_node_or_null("Player") as Node3D
	var weapon := game.get_node_or_null("Player/Weapon")
	var pillar := game.get_node_or_null("Pillar1") as Node3D
	weapon.set("spread_hip", 0.0)
	weapon.set("spread_aim", 0.0)
	player.global_position = Vector3(6.0, 0.05, -4.0)
	player.set("_yaw", 0.0)
	# 瞄准 Pillar1 正面中心（方柱 0.8 m 高，正面 z 比中心近 0.8 m）
	var aim_at: Vector3 = pillar.global_position + Vector3(0.0, 0.2, 0.8)
	for _i in 3:
		var cam_now := player.get("cam") as Camera3D
		var to_aim: Vector3 = aim_at - cam_now.global_position
		player.set("_pitch", atan2(to_aim.y, Vector2(to_aim.x, to_aim.z).length()))
		await physics_frame
		await physics_frame
	player.global_position.x += aim_at.x - (player.get("cam") as Camera3D).global_position.x
	for _i in 10:
		await physics_frame

	var cam := player.get("cam") as Camera3D
	var cam_dir: Vector3 = player.call("camera_forward")
	var space := player.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position + cam_dir * 100.0)
	q.collide_with_areas = false
	q.exclude = [player.get_rid()]
	var ideal := space.intersect_ray(q)

	weapon.call("shoot")
	# 弹丸飞到就进 `_in_flight`，到达后会被回收 —— 所以**当场**取终点
	var flight: Array = weapon.get("_in_flight")
	var impact: Vector3 = flight[flight.size() - 1][2] if not flight.is_empty() else Vector3.ZERO
	await create_timer(0.15, true).timeout
	if ideal.is_empty() or impact == Vector3.ZERO:
		print("[aim-shot] 没打到东西：ideal=%s impact=%s" % [str(ideal), str(impact)])
		quit(1)
		return

	var p_cross: Vector2 = cam.unproject_position(ideal.position)
	var p_impact: Vector2 = cam.unproject_position(impact)
	print("[aim-shot] 准星点 %s → 屏幕 %s" % [str(ideal.position.snappedf(0.01)), str(p_cross.snappedf(0.1))])
	print("[aim-shot] 实际落点 %s → 屏幕 %s" % [str(impact.snappedf(0.01)), str(p_impact.snappedf(0.1))])
	print("[aim-shot] 世界差 %.3f m ｜ 屏幕差 %.1f px ｜ 屏幕中心 %s"
		% [impact.distance_to(ideal.position), (p_impact - p_cross).length(),
			str(Vector2(root.size) / 2.0)])

	_marker(game, ideal.position, Color(0.1, 1.0, 0.3), 0.055)
	_marker(game, impact, Color(1.0, 0.15, 0.1), 0.035)
	await create_timer(0.1, true).timeout
	await _shot("_aim_after_full.png", false)
	await _shot("_aim_after_zoom.png", true)
	quit(0)
