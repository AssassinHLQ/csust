extends SceneTree
## 测：collider-forge 烘出来的 63 万面凹面碰撞，跟原来的 25 块盒比怎么样。
##   _tools/run_shot.sh res://scripts/_probe_campus_collider_mesh.gd -- --no-capture
## 出图：_campus_mesh_overlay.png / _campus_mesh_clay.png
##
## 做法：把场景里的 CampusCollision（25 盒）停掉，运行时挂上
## scenes/campus_collision_mesh.scn，然后打射线 + 让角色往墙里走。

func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(name)
	root.get_texture().get_image().save_png(out)
	print("[mesh] 截图 %s" % out)


func _disable_boxes(n: Node) -> void:
	for c in n.get_children():
		if c is StaticBody3D:
			(c as StaticBody3D).collision_layer = 0
			(c as StaticBody3D).collision_mask = 0
		_disable_boxes(c)


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> String:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = false
	var h := space.intersect_ray(q)
	if h.is_empty():
		return "无"
	var p := h.get("position") as Vector3
	var c := h.get("collider") as Node
	return "%s @ (%.1f, %.1f, %.1f)" % [c.name if c else "?", p.x, p.y, p.z]


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	var campus := level.get_node("Campus")
	campus.call("force_start")
	var t0 := Time.get_ticks_msec()
	while not bool(campus.call("is_ready")) and Time.get_ticks_msec() - t0 < 180000:
		await process_frame
	if not bool(campus.call("is_ready")):
		print("[mesh] 校园没加载完")
		quit(1)
		return
	var player := level.get_node("Player") as CharacterBody3D
	player.global_position = Vector3(0.0, 0.3, -120.0)
	for _i in 20:
		await physics_frame

	var boxes := level.get_node_or_null("CampusCollision")
	if boxes != null:
		_disable_boxes(boxes)
		print("[mesh] 已停掉 25 块盒碰撞")

	var t1 := Time.get_ticks_msec()
	var packed := load("res://scenes/campus_collision_mesh.scn") as PackedScene
	var mesh_body := packed.instantiate()
	var t_load := Time.get_ticks_msec() - t1
	t1 = Time.get_ticks_msec()
	level.add_child(mesh_body)
	await physics_frame
	var t_inst := Time.get_ticks_msec() - t1
	var cs := mesh_body.get_node("Collision") as CollisionShape3D
	var tris := 0
	if cs != null and cs.shape is ConcavePolygonShape3D:
		tris = (cs.shape as ConcavePolygonShape3D).get_faces().size() / 3
	print("[mesh] 加载 %d ms / 挂进树 %d ms，三角 %d" % [t_load, t_inst, tris])

	var space: PhysicsDirectSpaceState3D = level.get_world_3d().direct_space_state
	for i in 12:
		await physics_frame
	print("[mesh] 射线（从上往下 120 → −10）：")
	for p in [Vector3(72.3, 0, -385.6), Vector3(0, 0, -300.0), Vector3(0, 0, -200.0),
			Vector3(-200, 0, -400.0), Vector3(120, 0, -250.0)]:
		print("  (%6.1f, %6.1f) → %s" % [p.x, p.z,
			_ray(space, Vector3(p.x, 120, p.z), Vector3(p.x, -10, p.z))])

	# 让角色朝北（−Z）往建筑里走 2 秒，看会不会被挡住
	player.global_position = Vector3(72.3, 0.3, -370.0)
	player.set("_yaw", 0.0)
	for _i in 20:
		await physics_frame
	var before := player.global_position
	Input.action_press("move_forward")
	for _i in 120:
		await physics_frame
	Input.action_release("move_forward")
	var after := player.global_position
	print("[mesh] 走向建筑：%s → %s（z 变化 %.2f）"
		% [str(before.snappedf(0.1)), str(after.snappedf(0.1)), after.z - before.z])

	# 出图 1：半透明红覆盖，看碰撞面跟泼溅对不对齐
	var glb := "C:/Users/WY157/Desktop/GODOT/_arisu_captures/campus_collider_forge.glb"
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_file(glb, st)
	var vis: Node3D = null
	if err == OK:
		vis = doc.generate_scene(st)
		level.add_child(vis)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1.0, 0.15, 0.1, 0.28)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.no_depth_test = false
		for c in vis.find_children("*", "MeshInstance3D", true, false):
			(c as MeshInstance3D).material_override = mat
			(c as MeshInstance3D).cast_shadow = 0
	for c in level.find_children("*", "CanvasLayer", true, false):
		var cl := c as CanvasLayer
		if cl != null:
			cl.visible = false
	var cam := Camera3D.new()
	cam.fov = 68.0
	level.add_child(cam)
	cam.current = true
	cam.global_position = Vector3(120.0, 190.0, 30.0)
	cam.look_at(Vector3(0.0, 0.0, -260.0))
	await _shot("_campus_mesh_overlay.png")
	if vis != null:
		vis.visible = false
	cam.global_position = Vector3(72.3, 12.0, -350.0)
	cam.look_at(Vector3(72.3, 12.0, -420.0))
	cam.fov = 70.0
	await _shot("_campus_mesh_street.png")
	quit(0)
