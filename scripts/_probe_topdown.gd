extends SceneTree
## 俯视预览：把一个模型按包围盒自动摆好，从正上方拍一张正交图。
##
## 为什么用正交俯视：**和缩放无关**。3ds Max 导出的模型常常差 100/1000 倍
## （厘米/毫米被当成米），先看清「布局是几个房间」再定缩放，比瞎猜强。
##
## 用法：
##   _tools/run_shot.sh res://scripts/_probe_topdown.gd -- --model=res://models/xxx.glb --tag=before
## 输出：<工程>/_log/topdown_<tag>.png

func _initialize() -> void:
	# 不抢用户前台（AGENTS.md 硬要求，2026-11-09）：取消最大化 + 禁止聚焦 + 挪出屏幕
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _run() -> void:
	var model := ""
	var tag := "shot"
	var scale := 1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--model="):
			model = a.substr(8)
		elif a.begins_with("--tag="):
			tag = a.substr(6)
		elif a.begins_with("--scale="):
			scale = float(a.substr(8))

	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(1400, 1000)
	await process_frame

	# 白色环境 + 天上一个灯，保证看得清
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.96, 0.96, 0.97)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.4
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-70, -30, 0)
	sun.light_energy = 1.6
	root.add_child(sun)

	if not ResourceLoader.exists(model):
		print("[top] 载入不了 %s" % model)
		quit(1)
		return
	var inst: Node = (load(model) as PackedScene).instantiate()
	inst.scale = Vector3.ONE * scale
	root.add_child(inst)
	await process_frame

	var box := _aabb(inst)
	var meshes := _meshes(inst)
	print("[top] 网格数 %d，包围盒 %s 中心 %s" % [
		meshes.size(), str(box.size.snappedf(0.01)), str(box.get_center().snappedf(0.01))])
	# 诊断：有几个网格是 visible 的、有几个真的挂在树里
	var vis := 0
	for m in meshes:
		if m.is_visible_in_tree():
			vis += 1
	print("[top] 可见网格 %d / %d" % [vis, meshes.size()])

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	# 正交窗口按「最大水平跨度」+ 10% 余量；俯视时看 X/Z
	var span := maxf(box.size.x, box.size.z) * 1.1
	cam.size = maxf(span, 1.0)
	var c := box.get_center()
	# ⚠️ 相机要**稍微偏一点**再 look_at：正上方 + look_at 在某些情况下
	#    会得到退化的基（up 与朝向平行），画面整个空掉。
	cam.global_position = c + Vector3(0.0, maxf(box.size.y * 3.0, span), span * 0.02)
	root.add_child(cam)
	cam.look_at(c, Vector3.FORWARD)
	cam.near = 0.05
	cam.far = maxf(box.size.length() * 12.0, 200.0)
	cam.current = true
	print("[top] 相机 pos %s  size %.1f  far %.0f" % [
		str(cam.global_position.snappedf(0.1)), cam.size, cam.far])
	await process_frame
	for i in 30:
		await RenderingServer.frame_post_draw

	var img := root.get_texture().get_image()
	var dir := ProjectSettings.globalize_path("res://").path_join("_log")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("topdown_%s.png" % tag)
	img.save_png(path)
	# 顺手报「非背景像素占多少」，空白图能一眼看出来
	var non_bg := 0
	var data := img.get_data()
	for i in range(0, data.size(), 4 * 97):   # 抽样，别扫全图
		var r := data[i]
		var g := data[i + 1]
		var b := data[i + 2]
		if absi(r - 245) > 12 or absi(g - 245) > 12 or absi(b - 247) > 12:
			non_bg += 1
	print("[top] 输出 %s（非背景采样点 %d，为 0 就是空图）" % [path, non_bg])
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
