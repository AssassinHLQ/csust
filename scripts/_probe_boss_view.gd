extends SceneTree
## 探针：看霸王龙优香本体 —— 逐网格 AABB（判断尺度基准）、骨骼分布、
## 并把它归一化到 6 m 高渲三个视角（确认贴图有没有绑上）。
##
## 用法（要真渲染）：godot --path <工程> --script res://scripts/_probe_boss_view.gd

const SCENE := "res://models/boss/优香霸王龙.fbx"
const TARGET_HEIGHT := 6.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1000, 750)
	if not ResourceLoader.exists(SCENE):
		push_error("找不到 %s" % SCENE)
		quit(1)
		return
	var scene: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.18, 0.22)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.92, 1.0)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -130, 0)
	sun.light_energy = 1.1
	root.add_child(sun)

	print("================ 1. 逐网格 AABB（原始单位）================")
	var body := AABB()
	var body_first := true
	for m in _all(scene, "MeshInstance3D"):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var box := mi.get_aabb()
		var wbox := mi.global_transform * box
		print("  %-24s mesh AABB size %s" % [mi.name, str(box.size.snappedf(0.1))])
		if mi.name.begins_with("Tyrannosaurus") or mi.name.contains("Tyranno"):
			body = wbox if body_first else body.merge(wbox)
			body_first = false
	if body_first:
		body = _visual_aabb(scene)
	print("  —— 身体（Tyrannosaurus* 合并）size = %s" % str(body.size.snappedf(0.1)))
	var scale := TARGET_HEIGHT / maxf(body.size.y, 0.0001)
	print("  归一化：height %.1f → %.1f m，scale = %.6f" % [body.size.y, TARGET_HEIGHT, scale])

	print("\n================ 2. 骨骼分布（缩放后，m）================")
	var skel := (_all(scene, "Skeleton3D")[0]) as Skeleton3D
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var lowest := ""
	var highest := ""
	var frontmost := ""
	var backmost := ""
	for i in skel.get_bone_count():
		var p: Vector3 = skel.get_bone_global_pose(i).origin * scale
		if p.y < lo.y:
			lowest = skel.get_bone_name(i)
		if p.y > hi.y:
			highest = skel.get_bone_name(i)
		if p.z > hi.z:
			frontmost = skel.get_bone_name(i)
		if p.z < lo.z:
			backmost = skel.get_bone_name(i)
		lo = lo.min(p)
		hi = hi.max(p)
	print("  骨骼包围盒 size = %s" % str((hi - lo).snappedf(0.01)))
	print("  最低骨 = %s   最高骨 = %s" % [lowest, highest])
	print("  +Z 最远骨 = %s   -Z 最远骨 = %s" % [frontmost, backmost])
	print("  （模型脸朝哪边要看渲图；Arisu 是 rotation.y=0 朝 +Z）")

	# 归一化并摆到原点
	scene.scale = Vector3(scale, scale, scale)
	scene.position = -body.get_center() * scale
	await process_frame

	var cam := Camera3D.new()
	cam.fov = 45.0
	cam.near = 0.05
	cam.far = 500.0
	root.add_child(cam)
	cam.make_current()

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_boss")
	DirAccess.make_dir_recursive_absolute(out)

	var views := {
		"10_iso": Vector3(1.0, 0.42, 1.0),
		"11_side": Vector3(1.0, 0.12, 0.0),
		"12_front": Vector3(0.0, 0.22, 1.0),
		"13_top": Vector3(0.02, 1.0, 0.02),
	}
	for key in views:
		var dir: Vector3 = (views[key] as Vector3).normalized()
		cam.global_position = dir * (TARGET_HEIGHT * 1.6) + Vector3(0, TARGET_HEIGHT * 0.45, 0)
		cam.look_at(Vector3(0, TARGET_HEIGHT * 0.42, 0), Vector3.UP)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join("%s.png" % key))
		print("  [img] %s" % out.path_join("%s.png" % key))

	print("[boss] 输出目录：%s" % out)
	quit(0)


func _all(node: Node, cls: String) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.is_class(cls):
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out


func _visual_aabb(node: Node) -> AABB:
	var out := AABB()
	var first := true
	for m in _all(node, "VisualInstance3D"):
		var vi := m as VisualInstance3D
		var box := vi.get_aabb()
		if box.size.length() <= 0.0001:
			continue
		var b := vi.global_transform * box
		out = b if first else out.merge(b)
		first = false
	return out
