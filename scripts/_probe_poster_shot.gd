extends SceneTree
## 电竞房海报诊断 + 出图。
##   _tools/run_shot.sh res://scripts/_probe_poster_shot.gd
##
## 一次跑出两张对照图：
##   _log/poster_as_is.png    保持场景原样
##   _log/poster_nudged.png   把海报沿法线往前挪 6 mm
##
## 用来判定「海报看不见」到底是遮挡、朝向，还是贴图没上。

const SCENE := "res://scenes/esports_room.tscn"
const OUT_A := "res://_log/poster_as_is.png"
const OUT_B := "res://_log/poster_nudged.png"

const POSTER_Z := -4.77


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var shot_a := await _shoot(0.0)
	var shot_b := await _shoot(0.006)
	print("[postershot] as_is   -> %s" % shot_a)
	print("[postershot] nudged  -> %s" % shot_b)
	quit(0)


func _shoot(nudge: float) -> String:
	# 每个机位重建一份场景，避免上一次的改动污染对照
	var room := (load(SCENE) as PackedScene).instantiate()
	root.add_child(room)

	var poster := room.get_node_or_null("PosterRoom") as MeshInstance3D
	var frame := room.get_node_or_null("PosterRoomFrame") as MeshInstance3D
	if poster == null:
		push_error("[postershot] 找不到 PosterRoom")
		return "<none>"

	var pz := poster.position.z
	var fz := frame.position.z if frame != null else 0.0
	print("[postershot] PosterRoom.z = %.4f   Frame.z = %.4f   框厚 0.03 → 框前面 = %.4f"
		% [pz, fz, fz + 0.015])

	poster.position.z = POSTER_Z + nudge

	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.5
	sun.rotation_degrees = Vector3(-35.0, 25.0, 0.0)
	root.add_child(sun)

	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.05, 0.07)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.5, 0.55)
	e.ambient_light_energy = 1.0
	we.environment = e
	root.add_child(we)

	var cam := Camera3D.new()
	cam.position = Vector3(POSTER_Z - 999.0, 0, 0)  # 先占位，下面再算
	cam.position = Vector3(1.8, 1.82, POSTER_Z + 1.6)
	cam.fov = 45.0
	root.add_child(cam)
	cam.look_at(Vector3(1.8, 1.82, POSTER_Z), Vector3.UP)
	cam.current = true

	for _i in 25:
		await process_frame
	await RenderingServer.frame_post_draw

	var img := root.get_texture().get_image()
	var path := OUT_B if nudge > 0.0 else OUT_A
	var abs_path := ProjectSettings.globalize_path(path)
	var err := img.save_png(abs_path)
	print("[postershot] 保存 %s err=%d" % [path, err])

	var mat := poster.material_override as StandardMaterial3D
	var tex := "<null>" if (mat == null or mat.albedo_texture == null) else mat.albedo_texture.resource_path
	print("[postershot] 贴图 = %s" % tex)

	# 清场，避免下一张图叠在这张上
	root.remove_child(room)
	root.remove_child(sun)
	root.remove_child(we)
	root.remove_child(cam)
	room.free()
	sun.free()
	we.free()
	cam.free()
	return path
