extends SceneTree
## 探针：小空（`小空1donzuo.blend` → Blender 导出 GLB）长什么样、多大、朝哪边、有没有动画。
##
## 用户 2026-10-21：「小空模型找到了，不是 glb，胜似 glb」——
## 原文件是 `.blend`（BA 那套 338 骨 + cs_* 控制块的 rig），用 Blender 5.0 无头导成 GLB。
## 这个探针只做一件事：把它摆在一块地上、四个方向各拍一张，量尺寸、数骨头、列贴图。
##
## 用法：godot --path <工程> --script res://scripts/_probe_sora.gd
## 输出：`_arisu_captures/_sora/` 下 4 张

const MODEL := "res://models/npc/sora/sora.glb"
const OUT := "_sora"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1200, 1000)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.14, 0.16, 0.2)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	sun.light_energy = 1.3
	root.add_child(sun)

	var ground := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(20, 1, 20)
	ground.mesh = bm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.30, 0.32, 0.36)
	gm.roughness = 0.95
	ground.material_override = gm
	ground.position = Vector3(0, -0.5, 0)
	root.add_child(ground)

	var ps := load(MODEL) as PackedScene
	if ps == null:
		print("!! 加载不了 %s" % MODEL)
		quit(1)
		return
	var model := ps.instantiate() as Node3D
	root.add_child(model)
	for _i in 20:
		await process_frame

	var aabb := _world_aabb(model)
	print("── 小空 ──")
	print("  AABB  lo=%s  hi=%s" % [aabb.position.snappedf(0.01), aabb.end.snappedf(0.01)])
	print("  尺寸  %.3f × %.3f × %.3f m" % [aabb.size.x, aabb.size.y, aabb.size.z])
	print("  网格  %d 个，顶点 %d" % [_all(model, "MeshInstance3D").size(), _verts(model)])
	for sk in _all(model, "Skeleton3D"):
		var s := sk as Skeleton3D
		print("  骨架「%s」%d 骨" % [s.name, s.get_bone_count()])
	var aps := _all(model, "AnimationPlayer")
	print("  动画：%s" % ("无" if aps.is_empty() else
		", ".join(aps.map(func(a): return "%s(%d 条)" % [a.name, a.get_animation_list().size()]))))
	var tex_seen := {}
	for mi in _all(model, "MeshInstance3D"):
		var am := (mi as MeshInstance3D).mesh as ArrayMesh
		if am == null:
			continue
		for i in am.get_surface_count():
			var mat := am.surface_get_material(i)
			if mat is StandardMaterial3D:
				var sm := mat as StandardMaterial3D
				var key := "%s → %s" % [sm.resource_name,
					sm.albedo_texture.resource_path.get_file() if sm.albedo_texture else "无贴图"]
				tex_seen[key] = true
	for k in tex_seen.keys():
		print("  材质 %s" % k)

	# 把她摆到原点，四个方向各拍一张
	model.position = Vector3.ZERO
	var out_dir := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.02
	cam.far = 200.0
	root.add_child(cam)
	cam.make_current()
	var c := aabb.get_center()
	var d := maxf(aabb.size.y * 1.35, aabb.size.length() * 0.7)
	var shots := [
		["front_posz.png", Vector3(0, aabb.size.y * 0.55, d)],
		["back_negz.png", Vector3(0, aabb.size.y * 0.55, -d)],
		["left_negx.png", Vector3(-d, aabb.size.y * 0.55, 0.01)],
		["right_posx.png", Vector3(d, aabb.size.y * 0.55, 0.01)],
	]
	for s in shots:
		cam.global_position = s[1]
		cam.look_at(Vector3(0, aabb.size.y * 0.5, 0), Vector3.UP)
		await _shot(out_dir.path_join(s[0]))
	print("\n出图：%s" % out_dir)
	quit(0)


func _shot(path: String) -> void:
	var before := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	while Engine.get_frames_drawn() == before and Time.get_ticks_msec() - t0 < 2000:
		await process_frame
	for _i in 6:
		await process_frame
	root.get_texture().get_image().save_png(path)
	print("[shot] %s" % path.get_file())


func _all(node: Node, cls: String) -> Array:
	var out: Array = []
	if node == null:
		return out
	if node.is_class(cls):
		out.append(node)
	for c in node.get_children():
		out.append_array(_all(c, cls))
	return out


func _verts(node: Node) -> int:
	var n := 0
	for mi in _all(node, "MeshInstance3D"):
		var am := (mi as MeshInstance3D).mesh as ArrayMesh
		if am != null:
			for i in am.get_surface_count():
				n += am.surface_get_array_len(i)
	return n


func _world_aabb(node: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in _all(node, "MeshInstance3D"):
		var g := mi as MeshInstance3D
		if not g.visible:
			continue
		var b := g.global_transform * g.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out
