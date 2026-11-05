extends SceneTree
## 侧视 / 正视出图：确认模型是不是「多层建筑」、Y 方向到底怎么分布。
##
## 为什么要看侧面：俯视图只能看出「占多大平面」，看不出「有没有楼层」。
## 电竞酒店那个模型总包围盒 78 × 41 × 77 m，其中 **Y 有 41 米**——
## 但渲染图里椅子和床都在同一平面，所以那 41 米里八成有别的东西（高柜/装饰/多层）。
##
## 用法：
##   _tools/run_shot.sh res://scripts/_probe_sideview.gd -- --model=res://models/xxx.glb

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var model := ""
	var tag := "side"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--model="):
			model = a.substr(8)
		elif a.begins_with("--tag="):
			tag = a.substr(6)

	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(1400, 900)
	await process_frame

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.97, 0.97, 0.98)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.5
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -35, 0)
	sun.light_energy = 1.5
	root.add_child(sun)

	var inst: Node = (load(model) as PackedScene).instantiate()
	root.add_child(inst)
	await process_frame

	var box := _aabb(inst)
	var c := box.get_center()
	# 正视：从 +Z 方向看（能看出楼层/高度分布）
	var span := maxf(box.size.x, box.size.y) * 1.15
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(span, 1.0)
	root.add_child(cam)
	cam.global_position = c + Vector3(0.0, 0.0, maxf(box.size.z * 2.0, span))
	cam.look_at(c, Vector3.UP)
	cam.near = 0.05
	cam.far = maxf(box.size.length() * 12.0, 200.0)
	cam.current = true
	print("[side] 包围盒 %s，正交高 %.1f m" % [str(box.size.snappedf(0.1)), cam.size])
	await process_frame
	for i in 30:
		await RenderingServer.frame_post_draw

	var dir := ProjectSettings.globalize_path("res://").path_join("_log")
	DirAccess.make_dir_recursive_absolute(dir)
	root.get_texture().get_image().save_png(dir.path_join("sideview_%s.png" % tag))
	print("[side] 输出 %s" % dir.path_join("sideview_%s.png" % tag))
	quit(0)


func _aabb(node: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in _meshes(node):
		if mi.mesh == null:
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	_walk(node, out)
	return out


func _walk(node: Node, out: Array[MeshInstance3D]) -> void:
	var mi := node as MeshInstance3D
	if mi != null:
		out.append(mi)
	for c in node.get_children():
		_walk(c, out)
