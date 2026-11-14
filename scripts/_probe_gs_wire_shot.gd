extends SceneTree
## 出图验收：把「分块 GDGS 碰撞」的三角面半透明绿色叠在真泼溅上，直接看对不对齐。
## 2.6M 三角太多，按 stride 抽样到 ~15 万三角。
##
##   _tools/run_shot.sh res://scripts/_probe_gs_wire_shot.gd
## 产物：_arisu_captures/_gs_wire_1..4.png

const OUT_DIR := "C:/Users/WY157/Desktop/GODOT/_arisu_captures"
const MAX_TRIS := 150000


func _initialize() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	await process_frame
	await process_frame

	var campus := level.get_node_or_null("Campus")
	if campus == null:
		print("[gswire] 没有 Campus")
		quit(1)
		return
	campus.set("start_delay", 0.0)
	campus.set("low_priority", false)
	campus.set("unload_outside_room", false)
	var player := level.get_node_or_null("Player") as Node3D
	if player != null:
		player.global_position = Vector3(-120, 2.0, -200)
	campus.call("force_start")
	var t0 := Time.get_ticks_msec()
	while not bool(campus.call("is_ready")) and Time.get_ticks_msec() - t0 < 240000:
		await process_frame
	print("[gswire] 校园就绪 %d ms" % (Time.get_ticks_msec() - t0))

	var col := level.get_node_or_null("CampusCollision")
	if col == null:
		print("[gswire] 没有 CampusCollision")
		quit(1)
		return
	# 先数总三角，定抽样步长
	var shapes: Array[CollisionShape3D] = []
	var stack: Array[Node] = [col]
	var tris_total := 0
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CollisionShape3D and (n as CollisionShape3D).shape is ConcavePolygonShape3D:
			var cs := n as CollisionShape3D
			shapes.append(cs)
			tris_total += (cs.shape as ConcavePolygonShape3D).get_faces().size() / 3
		for ch in n.get_children():
			stack.append(ch)
	var stride := maxi(1, int(ceil(float(tris_total) / float(MAX_TRIS))))
	var verts := PackedVector3Array()
	for cs in shapes:
		var faces: PackedVector3Array = (cs.shape as ConcavePolygonShape3D).get_faces()
		var xf := cs.global_transform
		var t := 0
		while t + 2 < faces.size():
			if (t / 3) % stride == 0:
				verts.append(xf * faces[t])
				verts.append(xf * faces[t + 1])
				verts.append(xf * faces[t + 2])
			t += 3
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.0, 1.0, 0.2, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_fog = true
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	level.add_child(mi)
	print("[gswire] 碰撞体 %d 块 / %d 三角，抽样 1/%d → 显示 %d 三角" % [
		shapes.size(), tris_total, stride, verts.size() / 3])

	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.05
	cam.far = 2000.0
	level.add_child(cam)
	cam.current = true

	var shots := [
		["_gs_wire_1", Vector3(-120, 3.0, -160), Vector3(-120, 1.0, -260)],
		["_gs_wire_2", Vector3(0, 3.0, -120), Vector3(0, 1.0, -260)],
		["_gs_wire_3", Vector3(-40, 14.0, -260), Vector3(0, 2.0, -380)],
		["_gs_wire_4", Vector3(60, 40.0, -120), Vector3(-40, 2.0, -360)],
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
		print("[gswire] %s err=%d" % [p, err])
	quit(0)