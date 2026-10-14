extends SceneTree
## 终版验证：保留蒙皮，按【骨架】的世界尺度取景。
##
## 之前的误判：网格绑定空间里的顶点跨度是 8732，但蒙皮后模型实际是骨架尺度（约 44），
## 本喵按 8732 取景 → 模型看起来像"一个像素点"。
##
## 用法（要真渲染）：godot --path <工程> --script res://scripts/_probe_boss_skin2.gd

const SCENE := "res://models/boss/优香霸王龙.fbx"
const TXT := "res://models/boss/tex/body_basecolor.png"
const TARGET_HEIGHT := 6.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1000, 660)
	var scene: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	var skel := (_all(scene, "Skeleton3D")[0]) as Skeleton3D
	var sscale := skel.global_transform.basis.get_scale().x

	# 隐藏小挂件（它们各自的缩放与身体差 1~2 个数量级，会变成怪东西）
	var hidden := 0
	for m in _all(scene, "MeshInstance3D"):
		var mi := m as MeshInstance3D
		if not mi.name.begins_with("Tyrannosaurus"):
			mi.visible = false
			hidden += 1
	print("隐藏挂件 %d 个，保留 4 个身体部件" % hidden)

	# 绑贴图到共享材质（4 个部件用同一份材质）
	var tex: Texture2D = load(TXT)
	var bound := 0
	for m in _all(scene, "MeshInstance3D"):
		var mi := m as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			continue
		var am := mi.mesh as ArrayMesh
		for s in am.get_surface_count():
			var mat := am.surface_get_material(s)
			if mat is StandardMaterial3D and (mat as StandardMaterial3D).albedo_texture == null:
				(mat as StandardMaterial3D).albedo_texture = tex
				(mat as StandardMaterial3D).albedo_color = Color.WHITE
				bound += 1
	print("绑贴图表面数 = %d（加载 %s）" % [bound, "成功" if tex else "失败"])

	# ---- 按骨架算世界包围盒 ----
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for i in skel.get_bone_count():
		var p: Vector3 = skel.global_transform * skel.get_bone_global_pose(i).origin
		lo = lo.min(p)
		hi = hi.max(p)
	print("骨架世界包围盒 size = %s   骨骼 global scale = %.2f" % [
		str((hi - lo).snappedf(0.01)), sscale])
	var bone_span := (hi - lo)
	print("  → 蒙皮后的模型大致就是这个尺度（不是网格绑定空间的 8732）")

	var sc := TARGET_HEIGHT / maxf(bone_span.y, 0.0001)
	print("  归一化到 %.1f m：scale = %.4f" % [TARGET_HEIGHT, sc])
	scene.scale = Vector3(sc, sc, sc)
	await process_frame
	# 重新算缩放后的脚底
	lo = Vector3(INF, INF, INF)
	hi = Vector3(-INF, -INF, -INF)
	for i in skel.get_bone_count():
		var p2: Vector3 = skel.global_transform * skel.get_bone_global_pose(i).origin
		lo = lo.min(p2)
		hi = hi.max(p2)
	var center := (lo + hi) * 0.5
	scene.position = Vector3(-center.x, -lo.y, -center.z)
	await process_frame
	print("  缩放后骨架包围盒 size = %s  脚底 y = %.3f" % [
		str((hi - lo).snappedf(0.01)), lo.y - (lo.y - lo.y)])

	# 环境
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.20, 0.22, 0.27)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.66, 0.78)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -128, 0)
	sun.light_energy = 1.0
	root.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.30, 0.32, 0.36)
	floor_mi.material_override = fm
	root.add_child(floor_mi)

	var cam := Camera3D.new()
	cam.fov = 45.0
	cam.near = 0.05
	cam.far = 500.0
	root.add_child(cam)
	cam.make_current()

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_boss")
	DirAccess.make_dir_recursive_absolute(out)
	# 取景距离按「最长边」算（霸王龙又长又扁，按高度取景会糊一脸）
	var span_after := (hi - lo)
	var reach := maxf(maxf(span_after.x, span_after.y), span_after.z)
	print("  取景：最长边 %.2f m → 相机距离 %.2f m" % [reach, reach * 1.15])
	var views := {
		"50_iso": Vector3(1.0, 0.30, 1.0),
		"51_side": Vector3(1.0, 0.10, 0.0),
		"52_front": Vector3(0.0, 0.18, 1.0),
	}
	for key in views:
		var dir: Vector3 = (views[key] as Vector3).normalized()
		cam.global_position = Vector3(0, TARGET_HEIGHT * 0.42, 0) + dir * (reach * 1.15)
		cam.look_at(Vector3(0, TARGET_HEIGHT * 0.38, 0), Vector3.UP)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		img.save_png(out.path_join("%s.png" % key))
		print("  [img] %s  非背景占比 %.4f" % [out.path_join("%s.png" % key), _fg(img)])

	quit(0)


func _fg(img: Image) -> float:
	var bg := img.get_pixel(2, 2)
	var hit := 0
	var n := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c := img.get_pixel(x, y)
			n += 1
			if absf(c.r - bg.r) + absf(c.g - bg.g) + absf(c.b - bg.b) > 0.04:
				hit += 1
	return 0.0 if n == 0 else float(hit) / float(n)


func _all(node: Node, cls: String) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n == null:
			continue
		if n.is_class(cls):
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out
