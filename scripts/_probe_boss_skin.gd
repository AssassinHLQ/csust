extends SceneTree
## 对照实验：这个 FBX 的「网格 980× / 骨架 1×」不一致，蒙皮后模型会塌成一点。
## 试三种修法，各渲一张 + 统计非背景像素占比，看哪种能正常出图。
##
##   A 原样（skinned）
##   B 去掉 skin（当刚性网格用）—— 反正没有动画，丢掉蒙皮没有任何损失
##   C 保留 skin，但把 Skeleton3D 的缩放补偿回来（网格比骨架大 224 倍时 ×224）
##
## 用法（要真渲染）：godot --path <工程> --script res://scripts/_probe_boss_skin.gd

const SCENE := "res://models/boss/优香霸王龙.fbx"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(900, 700)
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_boss")
	DirAccess.make_dir_recursive_absolute(out)

	_build_env()
	var cam := Camera3D.new()
	cam.fov = 45.0
	cam.near = 0.01
	cam.far = 200000.0
	root.add_child(cam)
	cam.make_current()

	# ---- 基准：用刚性顶点量出的世界包围盒（上一轮探针的结果）----
	var rigid := await _measure("A_原样(skinned)", func(_s: Node) -> void: pass, 1.0, true)
	await _shot(cam, out.path_join("20_A_skinned.png"), rigid)
	await _free_current()

	await _measure("B_去蒙皮(刚性)", func(s: Node) -> void:
		for m in _all(s, "MeshInstance3D"):
			(m as MeshInstance3D).skin = null
	, 1.0, false)
	var rigid_b := await _rigid_box()
	await _shot(cam, out.path_join("21_B_rigid.png"), rigid_b)
	await _free_current()

	# C：保留 skin，把骨架补偿到网格尺度
	var ratio := await _skin_ratio()
	print("  网格/骨架 尺度比 = %.2f" % ratio)
	await _measure("C_补偿骨架", func(s: Node) -> void:
		var skel := _all(s, "Skeleton3D")[0] as Skeleton3D
		skel.scale = skel.scale * ratio
	, 1.0, false)
	var rigid_c := await _rigid_box()
	await _shot(cam, out.path_join("22_C_compensated.png"), rigid_c)
	await _free_current()

	print("[boss] 输出目录：%s" % out)
	quit(0)


var _current: Node = null


func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.18, 0.22)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.92, 1.0)
	env.ambient_light_energy = 1.1
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -125, 0)
	sun.light_energy = 1.2
	root.add_child(sun)


func _measure(label: String, tweak: Callable, _unused: float, report: bool) -> AABB:
	_current = (load(SCENE) as PackedScene).instantiate()
	root.add_child(_current)
	await process_frame
	await process_frame
	tweak.call(_current)
	await process_frame
	await process_frame
	var box := _rigid_box_sync()
	if report:
		print("=== %s ===" % label)
		print("  刚性顶点世界包围盒 size = %s" % str(box.size.snappedf(0.1)))
		var skel := _all(_current, "Skeleton3D")[0] as Skeleton3D
		print("  Skeleton3D global scale = %.2f   骨骼数 = %d" % [
			skel.global_transform.basis.get_scale().x, skel.get_bone_count()])
	return box


func _free_current() -> void:
	if _current:
		_current.free()
		_current = null
	await process_frame


func _rigid_box() -> AABB:
	await process_frame
	return _rigid_box_sync()


func _rigid_box_sync() -> AABB:
	var total := AABB()
	var first := true
	for m in _all(_current, "MeshInstance3D"):
		var mi := m as MeshInstance3D
		if mi.mesh == null or not (mi.mesh is ArrayMesh):
			continue
		var am := mi.mesh as ArrayMesh
		for s in am.get_surface_count():
			var arr := am.surface_get_arrays(s)
			if arr.size() <= Mesh.ARRAY_VERTEX or arr[Mesh.ARRAY_VERTEX] == null:
				continue
			var verts := arr[Mesh.ARRAY_VERTEX] as PackedVector3Array
			var step := maxi(1, verts.size() / 2000)
			var i := 0
			while i < verts.size():
				var w: Vector3 = mi.global_transform * verts[i]
				if first:
					total = AABB(w, Vector3.ZERO)
					first = false
				else:
					total = total.expand(w)
				i += step
	return total


## 网格尺度 / 骨架尺度 之比（用「网格顶点跨度」比「骨骼跨度」估）
func _skin_ratio() -> float:
	var skel := _all(_current, "Skeleton3D")[0] as Skeleton3D
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for i in skel.get_bone_count():
		var p := skel.get_bone_global_pose(i).origin
		lo = lo.min(p)
		hi = hi.max(p)
	var bone_span := (hi - lo).length()
	var mesh_span := _rigid_box_sync().size.length()
	if bone_span < 1e-6:
		return 1.0
	return mesh_span / bone_span


func _shot(cam: Camera3D, path: String, box: AABB) -> void:
	var center := box.get_center()
	var radius := maxf(box.size.length() * 0.5, 0.001)
	cam.global_position = center + Vector3(1.0, 0.45, 1.0).normalized() * radius * 1.6
	cam.look_at(center, Vector3.UP)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(path)
	print("  [img] %s   非背景像素占比 %.4f   框半径 %.0f" % [
		path.get_file(), _fg_ratio(img), radius])


func _fg_ratio(img: Image) -> float:
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
		if n.is_class(cls):
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out
