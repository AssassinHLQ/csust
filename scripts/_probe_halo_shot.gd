extends SceneTree
## 探针：柚子的**光环**近距特写 —— 修前 / 修后各三个角度，并打印材质参数。
##
## 用户 2026-10-22：「柚子的光环好像渲染出问题了」。
## `_probe_halo_shot.gd` 第一版量到的事实：
##     网格 `Yuzu_Original_Halo2` 0.274 × 0.202 × 0.170 m
##     材质 albedo 纯白、不透明、双面、**受光**、**不发光**、贴图 32×32 **无 alpha**
## 于是它就是一个「被灯照着的低模塑料圈」：每个面片亮度不同（近看一格一格），
## 不发光（开了辉光也不亮），还投阴影。
##
## 用法：godot --path <工程> --script res://scripts/_probe_halo_shot.gd -- --splat=off
## 输出：_arisu_captures/_halo/{before,after}_{top,side,back}.png

const MODEL := "res://models/companions/Yuzu.glb"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(640, 640)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.42, 0.5, 0.66)   # 偏暗的底色，自发光才看得出来
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.9, 1.0)
	env.ambient_light_energy = 1.8
	env.glow_enabled = true
	env.glow_intensity = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_energy = 1.2
	root.add_child(sun)

	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.near = 0.02
	root.add_child(cam)
	cam.make_current()

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_halo")
	DirAccess.make_dir_recursive_absolute(out)

	for mode in ["before", "after", "lit"]:
		var scene := (load(MODEL) as PackedScene).instantiate() as Node3D
		root.add_child(scene)
		await process_frame
		await process_frame
		var ap := _find(scene, "AnimationPlayer") as AnimationPlayer
		if ap != null and ap.has_animation("Normal_Idle"):
			ap.play("Normal_Idle")
			ap.seek(0.0, true)
			await process_frame
		var halos := _halo_meshes(scene)
		if halos.is_empty():
			print("!! 没找到光环网格")
			scene.queue_free()
			continue
		var mi := halos[0]
		if mode != "before":
			var rep := HaloFix.polish(scene)
			print("[%s] 光环抛光：%d 网格 / %d 材质  %s" % [mode,
				int(rep["meshes"]), int(rep["applied"]), str(rep["names"])])
		if mode == "lit":
			# 变体 C：保留受光（有体积感）+ 自发光；看看是不是比纯 unshaded 好看
			for h in halos:
				var m := h.get_active_material(0) as StandardMaterial3D
				if m != null:
					m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
					m.emission_energy_multiplier = 0.8
		_dump(mi, mode)

		# 机位：以光环自身包围盒的中心为圆心，距离按它的尺寸给（不再瞎猜头顶高度）
		var box := AABB(mi.global_position, Vector3.ZERO)
		for i in halos.size():
			var b: AABB = halos[i].global_transform * halos[i].get_aabb()
			box = b if i == 0 else box.merge(b)
		var centre := box.get_center()
		var span := maxf(maxf(box.size.x, box.size.y), box.size.z)
		var dist := span * 2.6
		print("  光环包围盒 %s 中心 %s 跨度 %.3f m" % [str(box.size.snappedf(0.001)),
			str(centre.snappedf(0.001)), span])
		var views := {
			"top": Vector3(0.0, dist, 0.001),
			"side": Vector3(dist * 0.72, dist * 0.45, dist * 0.5),
			"back": Vector3(0.0, dist * 0.28, -dist),
		}
		for view in views:
			cam.global_position = centre + (views[view] as Vector3)
			cam.look_at(centre, Vector3.UP if view != "top" else Vector3.FORWARD)
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var file := "%s/%s_%s.png" % [out, mode, view]
			root.get_texture().get_image().save_png(file)
			print("  [img] %s" % file)
		scene.queue_free()
		await process_frame
	quit(0)


func _dump(mi: MeshInstance3D, mode: String) -> void:
	var mat := mi.get_active_material(0) as StandardMaterial3D
	if mat == null:
		print("[%s] 材质不是 StandardMaterial3D" % mode)
		return
	print("[%s] %s：unshaded=%s  emission=%s %s  cast_shadow=%d  transparency=%d" % [
		mode, String(mi.name), str(mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED),
		str(mat.emission_enabled), str(mat.emission), int(mi.cast_shadow),
		int(mat.transparency)])


func _halo_meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D and String(n.name).to_lower().contains("halo"):
			out.append(n as MeshInstance3D)
	return out


func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r != null:
			return r
	return null
