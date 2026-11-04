extends SceneTree
## 粉熊平滑着色 前/后 对比：同一个机位、同一套灯，只换模型。
##   _tools/run_shot.sh res://scripts/_probe_bear_ab.gd -- --splat=off --story=off


const OLD := "res://models/gamedev_room/gamedev_room.glb"
const NEW := "res://models/_wip_room/gamedev_room_smooth.glb"
## 熊在模型局部坐标里的位置（见本喵的 GLB 分析）
const BEAR := Vector3(-2.51, 1.01, 5.22)


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _setup_env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.36, 0.40, 0.47)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.92, 0.92, 0.97)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 40, 0)
	sun.light_energy = 2.0
	root.add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = BEAR + Vector3(0, 0.6, -1.6)
	fill.light_energy = 1.2
	fill.omni_range = 6.0
	root.add_child(fill)


func _shoot(cam: Camera3D, path: String) -> void:
	await _wait(25)
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("[bear] → %s" % path)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	_setup_env()
	var cam := Camera3D.new()
	cam.far = 400.0
	cam.near = 0.02
	cam.fov = 55.0
	root.add_child(cam)
	cam.current = true
	# 正对熊：从房间中部往 +z 墙看
	cam.global_position = BEAR + Vector3(0.0, 0.25, -1.75)
	cam.look_at(BEAR + Vector3(0.0, 0.05, 0.0), Vector3.UP)

	for pair in [[OLD, "res://_log/bear_before.png"], [NEW, "res://_log/bear_after.png"]]:
		var ps := load(pair[0]) as PackedScene
		if ps == null:
			print("[bear] 载入失败 %s" % pair[0])
			continue
		var room := ps.instantiate()
		root.add_child(room)
		await _wait(10)
		await _shoot(cam, pair[1])
		room.queue_free()
		await _wait(5)
		if cam.get_viewport() != null:
			cam.current = true
	quit(0)