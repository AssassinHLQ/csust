extends SceneTree
## 3/4 透视预览：把模型缩到合理尺寸、摆好相机、拍一张能看清的图。
##
## 和 `_probe_topdown.gd` 的分工：那个用正交俯视**和缩放无关**地看布局；
## 这个用透视**验证缩放后观感**（椅子像不像椅子、床是不是床）。
##
## 用法：
##   _tools/run_shot.sh res://scripts/_probe_model_preview.gd -- \
##       --model=res://models/xxx.glb --scale=0.01 --tag=hotel
##   … --yaw=35 --pitch=22 --zoom=0.9     手动调角度

func _initialize() -> void:
	# 不抢用户前台（AGENTS.md 硬要求，2026-11-09）：取消最大化 + 禁止聚焦 + 挪出屏幕
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _run() -> void:
	var model := ""
	var tag := "preview"
	var scale := 1.0
	var yaw := 35.0
	var pitch := 22.0
	var zoom := 1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--model="):
			model = a.substr(8)
		elif a.begins_with("--tag="):
			tag = a.substr(6)
		elif a.begins_with("--scale="):
			scale = float(a.substr(8))
		elif a.begins_with("--yaw="):
			yaw = float(a.substr(6))
		elif a.begins_with("--pitch="):
			pitch = float(a.substr(8))
		elif a.begins_with("--zoom="):
			zoom = float(a.substr(7))

	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(1600, 900)
	await process_frame

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.55, 0.66, 0.82)
	sky_mat.sky_horizon_color = Color(0.85, 0.87, 0.90)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.1
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	root.add_child(sun)

	if not ResourceLoader.exists(model):
		print("[prev] 载入不了 %s" % model)
		quit(1)
		return
	var inst: Node = (load(model) as PackedScene).instantiate()
	inst.scale = Vector3.ONE * scale
	root.add_child(inst)
	await process_frame

	var box := _aabb(inst)
	var c := box.get_center()
	print("[prev] 缩放 %.4f 后包围盒 %s（中心 %s）" % [
		scale, str(box.size.snappedf(0.01)), str(c.snappedf(0.01))])

	# 相机绕模型转：按包围盒半径 + FOV 算距离，再乘 zoom 微调
	var radius := box.size.length() * 0.5
	var fov := 55.0
	var dist := radius / tan(deg_to_rad(fov * 0.5)) * 1.9 * zoom
	var yd := deg_to_rad(yaw)
	var pd := deg_to_rad(pitch)
	var offset := Vector3(cos(pd) * sin(yd), sin(pd), cos(pd) * cos(yd)) * dist
	var cam := Camera3D.new()
	cam.fov = fov
	root.add_child(cam)
	cam.global_position = c + offset
	cam.look_at(c, Vector3.UP)
	cam.near = maxf(dist * 0.001, 0.05)
	cam.far = dist * 40.0
	cam.current = true
	print("[prev] 相机距中心 %.1f m，仰角 %.0f°" % [dist, pitch])
	await process_frame
	for i in 40:
		await RenderingServer.frame_post_draw

	var img := root.get_texture().get_image()
	var dir := ProjectSettings.globalize_path("res://").path_join("_log")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("preview_%s.png" % tag)
	img.save_png(path)
	print("[prev] 输出 %s" % path)
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
