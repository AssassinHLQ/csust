extends SceneTree
## 看一眼从大杂烩里抽出来的「782061」到底是什么：包围盒 + 四个机位截图。
##   _tools/run_shot.sh res://scripts/_probe_hotel_look.gd -- --splat=off --story=off


const GLB := "res://models/_wip_hotel/hotel_782061.glb"


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var ps := load(GLB) as PackedScene
	if ps == null:
		print("[look] 载入失败")
		quit(1)
		return
	var room := ps.instantiate() as Node3D
	root.add_child(room)
	await _wait(30)

	var mn := Vector3(1e9, 1e9, 1e9)
	var mx := Vector3(-1e9, -1e9, -1e9)
	var n := 0
	var tris := 0
	for mi in room.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var ab: AABB = m.global_transform * m.get_aabb()
		for i in 3:
			mn[i] = minf(mn[i], ab.position[i])
			mx[i] = maxf(mx[i], ab.position[i] + ab.size[i])
		n += 1
		for s in m.mesh.get_surface_count():
			var arr := m.mesh.surface_get_arrays(s)
			if arr[Mesh.ARRAY_INDEX] != null:
				tris += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	print("[look] 网格=%d 三角=%d" % [n, tris])
	print("[look] 世界包围盒 min=%s max=%s size=%s" % [
		str(mn.snappedf(0.01)), str(mx.snappedf(0.01)), str((mx - mn).snappedf(0.01))])
	print("[look] 子节点数=%d" % room.get_child_count())

	# 环境（不然全黑）
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.35, 0.40, 0.48)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.9, 0.95)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = false
	root.add_child(sun)

	var cam := Camera3D.new()
	cam.far = 4000.0
	cam.near = 0.05
	cam.fov = 70.0
	root.add_child(cam)
	cam.current = true

	var c := (mn + mx) * 0.5
	var s := mx - mn
	var d := maxf(maxf(s.x, s.y), s.z)
	var shots := [
		["iso", Vector3(1.0, 0.8, 1.0), 1.2],
		["top", Vector3(0.0, 1.6, 0.05), 1.1],
		["front", Vector3(0.0, 0.35, -1.0), 1.1],
		["side", Vector3(-1.0, 0.35, 0.0), 1.1],
	]
	for sh in shots:
		cam.global_position = c + (sh[1] as Vector3).normalized() * d * float(sh[2])
		cam.look_at(c, Vector3.UP)
		await _wait(15)
		root.get_texture().get_image().save_png(
			ProjectSettings.globalize_path("res://_log/hotel_%s.png" % sh[0]))
		print("[look] → res://_log/hotel_%s.png" % sh[0])
	quit(0)