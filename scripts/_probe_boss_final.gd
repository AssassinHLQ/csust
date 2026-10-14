extends SceneTree
## 霸王龙优香「抢救」终版：
##   1. 留 4 个 Tyrannosaurus4LOW* 部件（它们不是 LOD，是身体各部分），隐藏小挂件
##   2. 去掉蒙皮（原 FBX 网格 980× / 骨架 1× 不一致，蒙皮后整体塌成一点）
##   3. 材质没有 albedo 贴图 → 手工绑 `图片/other_BaseColor.png`
##   4. 查到 6 m 高、脚底 y=0，渲三视图
##
## 用法（要真渲染）：godot --path <工程> --script res://scripts/_probe_boss_final.gd

const SCENE := "res://models/boss/优香霸王龙.fbx"
const TEX := "res://models/boss/tex/body_basecolor.png"
const TARGET_HEIGHT := 6.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1000, 660)
	var scene: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	print("================ 部件取舍 ================")
	var kept: Array[MeshInstance3D] = []
	for m in _all(scene, "MeshInstance3D"):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var is_body := mi.name.begins_with("Tyrannosaurus")
		print("  %-24s 顶点 %7d  材质 %-14s UV %s  %s" % [
			mi.name, _verts(mi), _mat_name(mi), str(_has_uv(mi)),
			"保留" if is_body else "隐藏（挂件）"])
		if is_body:
			mi.skin = null
			kept.append(mi)
		else:
			mi.visible = false
	await process_frame

	# 绑贴图
	var tex: Texture2D = load(TEX)
	print("\n================ 贴图 ================")
	print("  %s → %s" % [TEX.get_file(), "加载成功" if tex else "失败"])
	var bound := 0
	for mi in kept:
		var am := mi.mesh as ArrayMesh
		for s in am.get_surface_count():
			var mat := am.surface_get_material(s)
			if mat is StandardMaterial3D:
				var sm := mat as StandardMaterial3D
				if sm.albedo_texture == null:
					sm.albedo_texture = tex
					bound += 1
					if _has_uv(mi):
						sm.albedo_color = Color.WHITE
	print("  给 %d 个表面绑上了贴图" % bound)
	if not _has_uv(kept[0]):
		print("  ⚠️ 网格没有 UV 坐标，贴图不会有正确效果")

	# 归一化（用所有保留部件合并后的包围盒）
	var box := _box(kept)
	print("\n================ 归一化 ================")
	print("  原始世界包围盒 size = %s" % str(box.size.snappedf(0.1)))
	var sc := TARGET_HEIGHT / maxf(box.size.y, 0.0001)
	scene.scale = Vector3(sc, sc, sc)
	await process_frame
	box = _box(kept)
	scene.position = Vector3(-box.get_center().x, -box.position.y, -box.get_center().z)
	await process_frame
	box = _box(kept)
	print("  scale = %.6f → size = %s  脚底 y = %.3f" % [
		sc, str(box.size.snappedf(0.01)), box.position.y])

	# 环境
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.20, 0.22, 0.27)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.65, 0.78)
	env.ambient_light_energy = 0.5
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
	var views := {
		"40_iso": Vector3(1.0, 0.30, 1.0),
		"41_side": Vector3(1.0, 0.10, 0.0),
		"42_front": Vector3(0.0, 0.18, 1.0),
	}
	for key in views:
		var dir: Vector3 = (views[key] as Vector3).normalized()
		cam.global_position = Vector3(0, TARGET_HEIGHT * 0.5, 0) + dir * (TARGET_HEIGHT * 1.5)
		cam.look_at(Vector3(0, TARGET_HEIGHT * 0.45, 0), Vector3.UP)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join("%s.png" % key))
		print("  [img] %s" % out.path_join("%s.png" % key))

	quit(0)


func _verts(mi: MeshInstance3D) -> int:
	var am := mi.mesh as ArrayMesh
	var n := 0
	for s in am.get_surface_count():
		var a := am.surface_get_arrays(s)
		if a.size() > Mesh.ARRAY_VERTEX and a[Mesh.ARRAY_VERTEX] != null:
			n += (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return n


func _mat_name(mi: MeshInstance3D) -> String:
	var am := mi.mesh as ArrayMesh
	if am.get_surface_count() == 0:
		return "（无表面）"
	var m := am.surface_get_material(0)
	if m == null:
		return "（空）"
	return m.resource_name if m.resource_name != "" else m.get_class()


func _has_uv(mi: MeshInstance3D) -> bool:
	var am := mi.mesh as ArrayMesh
	for s in am.get_surface_count():
		var a := am.surface_get_arrays(s)
		if a.size() > Mesh.ARRAY_TEX_UV and a[Mesh.ARRAY_TEX_UV] != null:
			return true
	return false


func _box(list: Array[MeshInstance3D]) -> AABB:
	var out := AABB()
	var first := true
	for mi in list:
		var am := mi.mesh as ArrayMesh
		for s in am.get_surface_count():
			var a := am.surface_get_arrays(s)
			if a.size() <= Mesh.ARRAY_VERTEX or a[Mesh.ARRAY_VERTEX] == null:
				continue
			var verts := a[Mesh.ARRAY_VERTEX] as PackedVector3Array
			var step := maxi(1, verts.size() / 4000)
			var i := 0
			while i < verts.size():
				var w: Vector3 = mi.global_transform * verts[i]
				if first:
					out = AABB(w, Vector3.ZERO)
					first = false
				else:
					out = out.expand(w)
				i += step
	return out


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
