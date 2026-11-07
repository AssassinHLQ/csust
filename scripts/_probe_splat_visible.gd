extends SceneTree
## 决定性实验：泼溅在显存里常驻时，「节点可见 / 不可见」差多少帧。
##   _tools/run_shot.sh res://scripts/_probe_splat_visible.gd -- --story=off
##
## 用户现场：3D 缩放 0.50、特效全关、阴影低，却是 7 fps、帧 133 ms。
## 渲染侧已经没什么可省的，所以怀疑是泼溅合成器在跑。


const SPOT := Vector3(54.87, 0.6, 3.38)
const WARM := 120
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
	var t0 := Time.get_ticks_usec()
	for _i in SAMPLE:
		await process_frame
	var dt := float(Time.get_ticks_usec() - t0) / 1000000.0
	print("[splatv] %-20s fps=%6.1f 帧=%7.2fms draws=%4d prims=%8d" % [
		tag, float(SAMPLE) / maxf(dt, 0.0001), dt / float(SAMPLE) * 1000.0,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))])


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(200)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var player := game.get_node_or_null("Player") as Node3D
	if player == null:
		print("[splatv] 缺 Player")
		quit(1)
		return
	player.global_position = SPOT
	player.set("velocity", Vector3.ZERO)
	await _wait(240)

	var rs = game.get("_room_scene")
	if rs == null:
		print("[splatv] 泼溅没加载，测不了")
		quit(1)
		return
	var splat := rs.get("splat_node") as Node3D
	print("[splatv] 泼溅就绪，节点 visible=%s vram=%.0f MiB 玩家在部室" % [
		str(splat.visible),
		float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0])

	await _measure("节点隐藏(游戏现状)")
	splat.visible = true
	await _measure("强开泼溅节点")
	splat.visible = false
	await _measure("再藏回去")

	# 顺带：把整棵树上的泼溅节点都找出来，看有没有第二个
	var all := game.find_children("*", "Node3D", true, false)
	var cnt := 0
	for n in all:
		if n.get_script() != null and String(n.get_script().resource_path).ends_with("splat_scene.gd"):
			cnt += 1
	print("[splatv] 场景里 SplatScene 共 %d 个" % cnt)
	quit(0)