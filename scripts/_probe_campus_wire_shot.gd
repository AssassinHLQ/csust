extends SceneTree
## 在真泼溅上叠碰撞线框拍照，直接看碰撞和可见地面对不对得上。
##   _tools/run_shot.sh res://scripts/_probe_campus_wire_shot.gd -- --gdgs-backend=raster
## 产物：_arisu_captures/_wire_shot_1/2/3.png

const OUT_DIR := "C:/Users/WY157/Desktop/GODOT/_arisu_captures"

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	await process_frame
	await process_frame

	var campus := level.get_node_or_null("Campus")
	if campus == null:
		print("[wire] 没有 Campus")
		quit(1)
		return
	campus.set("start_delay", 0.0)
	campus.call("force_start")
	# 把玩家挪到校园里，否则可见性闸门会把泼溅藏起来（大厅里不渲染）
	var player := level.get_node_or_null("Player") as Node3D
	if player != null:
		player.global_position = Vector3(0, 1.0, -110)
	var t0 := Time.get_ticks_msec()
	while not bool(campus.call("is_ready")) and Time.get_ticks_msec() - t0 < 180000:
		await process_frame
	print("[wire] 校园就绪 %d ms" % (Time.get_ticks_msec() - t0))

	# 自己画碰撞网格（比 debug_collisions_hint 稳）：绿色半透明、不做深度测试
	var body := level.get_node_or_null("CampusCollisionMesh")
	var cs: CollisionShape3D = null
	if body != null:
		cs = body.get_node_or_null("Collision") as CollisionShape3D
	if cs != null and cs.shape is ConcavePolygonShape3D:
		var faces: PackedVector3Array = (cs.shape as ConcavePolygonShape3D).get_faces()
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = cs.global_transform * faces
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.0, 1.0, 0.2, 0.45)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.no_depth_test = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.disable_fog = true
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		level.add_child(mi)
		print("[wire] 碰撞网格面 %d" % (faces.size() / 3))

	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.05
	cam.far = 2000.0
	level.add_child(cam)
	cam.current = true

	var shots := [
		["_wire_shot_1", Vector3(0, 2.6, -110), Vector3(0, 2.2, -220)],
		["_wire_shot_2", Vector3(0, 2.6, -200), Vector3(0, 2.2, -320)],
		["_wire_shot_3", Vector3(-40, 12.0, -300), Vector3(0, 2.0, -380)],
	]
	for s in shots:
		cam.global_position = s[1]
		cam.look_at(s[2], Vector3.UP)
		for i in 5:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var p := "%s/%s.png" % [OUT_DIR, s[0]]
		var err := img.save_png(p)
		print("[wire] %s err=%d" % [p, err])
	quit(0)
