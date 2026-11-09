extends SceneTree
## 人眼高度的室内出图：判断**减面之后贴脸看还成不成**。
##
## 为什么必须拍这个：远景/俯视图里减面看不出问题（那些三角本来就被像素压扁了），
## 真正会露馅的是**玩家站进去、离物件 1~2 米**的时候 —— 边缘会出锯齿、
## 弧面会变多边形、贴图会拉伸。这才是「能不能用」的判据。
##
## 用法：
##   _tools/run_shot.sh res://scripts/_probe_interior.gd -- \
##       --model=res://models/xxx.glb --tag=a --at=0.5,1.6,0.3 --look=0.5,1.4,0.0
##   （`--at` / `--look` 是**包围盒归一化坐标** 0~1，不是米 —— 换模型不用改参数）
##
## 不给 `--at` 就自动在包围盒里挑几个位置，朝中心看。

var _abs_at := Vector3(-1, -1, -1)
var _abs_look := Vector3(-1, -1, -1)


func _initialize() -> void:
	# 不抢用户前台（AGENTS.md 硬要求，2026-11-09）：取消最大化 + 禁止聚焦 + 挪出屏幕
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _run() -> void:
	var model := ""
	var tag := "in"
	var at := Vector3(-1, -1, -1)
	var look := Vector3(-1, -1, -1)
	var fov := 68.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--model="):
			model = a.substr(8)
		elif a.begins_with("--tag="):
			tag = a.substr(6)
		elif a.begins_with("--at="):
			at = _vec(a.substr(5))
		elif a.begins_with("--look="):
			look = _vec(a.substr(7))
		elif a.begins_with("--fov="):
			fov = float(a.substr(6))
		elif a.begins_with("--abs-at="):
			_abs_at = _vec(a.substr(9))
		elif a.begins_with("--abs-look="):
			_abs_look = _vec(a.substr(11))

	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(1600, 900)
	await process_frame

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.10, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.88, 0.95)
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	we.environment = env
	root.add_child(we)

	# 几盏灯，模拟室内照明（不然室内一片黑看不出细节）
	for spec in [[-30.0, -40.0, 2.6], [20.0, -150.0, 2.2], [140.0, 30.0, 1.8]]:
		var d := DirectionalLight3D.new()
		d.rotation_degrees = Vector3(spec[1], spec[0], 0)
		d.light_energy = spec[2]
		d.shadow_enabled = true
		root.add_child(d)

	var inst: Node = (load(model) as PackedScene).instantiate()
	root.add_child(inst)
	await process_frame

	var box := _aabb(inst)
	var c := box.get_center()
	var s := box.size
	print("[in] 包围盒 %s 中心 %s" % [str(s.snappedf(0.1)), str(c.snappedf(0.1))])

	var cam := Camera3D.new()
	cam.fov = fov
	cam.near = 0.05
	cam.far = s.length() * 4.0
	root.add_child(cam)
	cam.current = true

	# 归一化坐标 → 世界坐标
	var p_at := Vector3(
		box.position.x + s.x * at.x,
		box.position.y + s.y * at.y,
		box.position.z + s.z * at.z) if at.x >= 0.0 else Vector3.ZERO
	var p_look := Vector3(
		box.position.x + s.x * look.x,
		box.position.y + s.y * look.y,
		box.position.z + s.z * look.z) if look.x >= 0.0 else Vector3.ZERO

	if _abs_at.x >= 0.0:
		p_at = _abs_at
		p_look = _abs_look if _abs_look.x >= 0.0 else c
	elif at.x < 0.0:
		# 没给位置：站在包围盒中心偏一侧，高度取「人眼」（模型底 + 1.6 m）
		p_at = Vector3(c.x - s.x * 0.22, box.position.y + 1.6, c.z - s.z * 0.22)
		p_look = Vector3(c.x, box.position.y + 1.4, c.z)

	cam.global_position = p_at
	if p_look.distance_to(p_at) > 0.01:
		cam.look_at(p_look, Vector3.UP)
	print("[in] 相机 %s → 看 %s" % [str(p_at.snappedf(0.1)), str(p_look.snappedf(0.1))])

	await process_frame
	for i in 40:
		await RenderingServer.frame_post_draw
	var dir := ProjectSettings.globalize_path("res://").path_join("_log")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("interior_%s.png" % tag)
	root.get_texture().get_image().save_png(path)
	print("[in] 输出 %s" % path)
	quit(0)


func _vec(s: String) -> Vector3:
	var p := s.split(",")
	if p.size() != 3:
		return Vector3(-1, -1, -1)
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


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
