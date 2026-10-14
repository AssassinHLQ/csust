extends SceneTree
## 把霸王龙优香修成能用的形态并渲图：
##   1. 只留顶点最多的那个网格（Tyrannosaurus4LOW*，其余是 LOD 拷贝）
##   2. 去掉蒙皮（原 FBX 网格 980× / 骨架 1× 不一致，蒙皮后整体塌成一点）
##   3. 查到 6 m 高、脚底落在 y=0
##   4. 打印材质/贴图绑定情况
##
## 用法（要真渲染）：godot --path <工程> --script res://scripts/_probe_boss_fix.gd

const SCENE := "res://models/boss/优香霸王龙.fbx"
const TARGET_HEIGHT := 6.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1000, 660)
	var scene: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	# ---- 1. 选主网格，其余全隐藏 ----
	var meshes := _all(scene, "MeshInstance3D")
	var main_mesh: MeshInstance3D = null
	var best := -1
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var n := _vert_count(mi)
		if n > best:
			best = n
			main_mesh = mi
	print("================ 选主网格 ================")
	for m in meshes:
		var mi := m as MeshInstance3D
		var keep := mi == main_mesh
		print("  %-24s 顶点 %7d  %s" % [
			mi.name, _vert_count(mi), "← 保留" if keep else "隐藏"])
		if not keep:
			mi.visible = false
		else:
			mi.skin = null   # 2. 去蒙皮
	await process_frame

	print("\n================ 材质与贴图 ================")
	var am := main_mesh.mesh as ArrayMesh
	for s in am.get_surface_count():
		var mat := am.surface_get_material(s)
		if mat == null:
			print("  surface %d: 材质为空" % s)
			continue
		var albedo := ""
		var acol := Color.WHITE
		if mat is StandardMaterial3D:
			var sm := mat as StandardMaterial3D
			acol = sm.albedo_color
			if sm.albedo_texture:
				albedo = sm.albedo_texture.resource_path
			print("  surface %d: %s  albedo=%s  贴图=%s  shading=%d" % [
				s, mat.get_class(), str(acol), albedo if albedo != "" else "（无）", sm.shading_mode])
		elif mat is BaseMaterial3D:
			print("  surface %d: %s (BaseMaterial3D)" % [s, mat.get_class()])
		else:
			print("  surface %d: %s" % [s, mat.get_class()])

	# ---- 3. 归一化 ----
	var box := _world_box(main_mesh)
	print("\n================ 归一化 ================")
	print("  原始世界包围盒 size = %s" % str(box.size.snappedf(0.1)))
	var s := TARGET_HEIGHT / maxf(box.size.y, 0.0001)
	scene.scale = Vector3(s, s, s)
	await process_frame
	box = _world_box(main_mesh)
	scene.position = Vector3(-box.get_center().x, -(box.position.y), -box.get_center().z)
	await process_frame
	box = _world_box(main_mesh)
	print("  scale = %.6f → 包围盒 size = %s" % [s, str(box.size.snappedf(0.01))])
	print("  脚底 y = %.3f  顶端 y = %.3f" % [box.position.y, box.position.y + box.size.y])
	print("  （Arisu 高约 1.7 m，靶子 2 m —— 6 m 的霸王龙约 3.5 个 Arisu）")

	# ---- 4. 环境 + 渲图 ----
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.20, 0.22, 0.27)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.7)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -128, 0)
	sun.light_energy = 0.9
	root.add_child(sun)

	# 地面方块，方便看脚底与尺度
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
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
	var views := {
		"30_iso": Vector3(1.0, 0.35, 1.0),
		"31_side": Vector3(1.0, 0.12, 0.0),
		"32_front": Vector3(0.0, 0.20, 1.0),
	}
	for key in views:
		var dir: Vector3 = (views[key] as Vector3).normalized()
		cam.global_position = Vector3(0, TARGET_HEIGHT * 0.5, 0) + dir * (TARGET_HEIGHT * 1.7)
		cam.look_at(Vector3(0, TARGET_HEIGHT * 0.45, 0), Vector3.UP)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join("%s.png" % key))
		print("  [img] %s" % out.path_join("%s.png" % key))

	print("[boss] 输出目录：%s" % out)
	quit(0)


func _vert_count(mi: MeshInstance3D) -> int:
	if mi.mesh == null or not (mi.mesh is ArrayMesh):
		return 0
	var am := mi.mesh as ArrayMesh
	var n := 0
	for s in am.get_surface_count():
		var arr := am.surface_get_arrays(s)
		if arr.size() > Mesh.ARRAY_VERTEX and arr[Mesh.ARRAY_VERTEX] != null:
			n += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return n


func _world_box(mi: MeshInstance3D) -> AABB:
	if mi.mesh == null or not (mi.mesh is ArrayMesh):
		return AABB()
	var am := mi.mesh as ArrayMesh
	var box := AABB()
	var first := true
	for s in am.get_surface_count():
		var arr := am.surface_get_arrays(s)
		if arr.size() <= Mesh.ARRAY_VERTEX or arr[Mesh.ARRAY_VERTEX] == null:
			continue
		var verts := arr[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var step := maxi(1, verts.size() / 4000)
		var i := 0
		while i < verts.size():
			var w: Vector3 = mi.global_transform * verts[i]
			if first:
				box = AABB(w, Vector3.ZERO)
				first = false
			else:
				box = box.expand(w)
			i += step
	return box


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
