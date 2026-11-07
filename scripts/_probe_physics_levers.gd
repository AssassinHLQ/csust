extends SceneTree
## 物理杠杆 A/B：① 每帧物理步上限；② 部室凹面 trimesh 换成盒地板。
##   _tools/run_shot.sh res://scripts/_probe_physics_levers.gd -- --splat=off --story=off


const SPOT := Vector3(54.87, 0.6, 3.38)
const WARM := 90
const SAMPLE := 40


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _measure(tag: String) -> void:
	await _wait(WARM)
	var phys := 0.0
	var t0 := Time.get_ticks_usec()
	for _i in SAMPLE:
		await process_frame
		phys += float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
	var fps := float(SAMPLE) / maxf(float(Time.get_ticks_usec() - t0) / 1000000.0, 0.0001)
	print("[lever] %-26s fps=%6.1f  物理=%6.2f ms" % [tag, fps, phys / float(SAMPLE)])


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(180)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var player := game.get_node_or_null("Player") as Node3D
	if player == null:
		print("[lever] 缺 Player")
		quit(1)
		return
	player.global_position = SPOT
	player.set("velocity", Vector3.ZERO)

	var steps0 := Engine.max_physics_steps_per_frame
	print("[lever] 默认每帧物理步上限 = %d" % steps0)

	# ① 步数上限
	for n in [steps0, 4, 2, 1]:
		Engine.max_physics_steps_per_frame = n
		await _measure("步上限=%d" % n)
	Engine.max_physics_steps_per_frame = steps0

	# ② trimesh → 盒地板（只当测成本，测完还原）
	var cs := game.get_node_or_null("GameDevRoom/Model/Collision/Mesh") as CollisionShape3D
	if cs == null:
		print("[lever] 找不到部室碰撞节点")
		quit(0)
		return
	var old_shape := cs.shape
	var box := BoxShape3D.new()
	box.size = Vector3(10.9, 0.3, 13.4)
	cs.shape = box
	await _measure("盒地板替 trimesh")
	cs.shape = old_shape
	await _measure("还原 trimesh")
	quit(0)