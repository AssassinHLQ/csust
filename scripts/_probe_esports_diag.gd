extends SceneTree
## 查：给电竞房打上明显光照、深色背景，看清「模型到底空不空」。
## 逐个网格也能单独看：用 --only=<名字片段> 只保留匹配的网格。
##
## 出图：`_arisu_captures/_esports_diag/`

const SCENE := "res://scenes/esports_room.tscn"
const OUT := "res://_arisu_captures/_esports_diag"

var _only := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	await _wait(2)

	# 深色世界，方便看白墙
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.7)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	root.add_child(we)

	# 一盏从斜上方的方向光
	var sun := DirectionalLight3D.new()
	sun.light_energy = 2.2
	sun.rotation_degrees = Vector3(-42, -55, 0)
	root.add_child(sun)

	var room: Node3D = load(SCENE).instantiate()
	root.add_child(room)
	await _wait(6)

	# 过滤
	if _only != "":
		for mi in room.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if not m.name.contains(_only):
				m.visible = false
		print("[diag] only meshes containing: %s" % _only)

	var aabb := AABB()
	var first := true
	for mi in room.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.visible:
			continue
		var gw: AABB = m.global_transform * m.get_aabb()
		if first:
			aabb = gw
			first = false
		else:
			aabb = aabb.merge(gw)
	if first:
		print("[diag] nothing visible")
		quit(1)
		return

	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 500.0
	root.add_child(cam)
	var c := aabb.get_center()
	var r := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))

	var shots := {
		"a_front": c + Vector3(0, r * 0.30, r * 1.15),
		"b_side": c + Vector3(r * 1.15, r * 0.30, 0),
		"c_top": c + Vector3(0, r * 1.5, 0.01),
		"d_iso": c + Vector3(r * 0.80, r * 0.65, r * 0.80),
		"e_back": c + Vector3(0, r * 0.30, -r * 1.15),
		"f_inside": c,
	}
	for nm in shots.keys():
		cam.global_position = shots[nm]
		cam.look_at(c, Vector3.UP)
		await _wait(5)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
		var img: Image = root.get_texture().get_image()
		var tag: String = nm
		if _only != "":
			tag = nm + "_" + _only
		img.save_png("%s/%s.png" % [OUT, tag])
		print("[diag] shot %s" % tag)

	print("[diag] aabb=%s size=%s" % [str(aabb), str(aabb.size)])
	quit(0)
