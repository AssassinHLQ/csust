extends SceneTree
## 在部室最差机位（东侧看回来）逐个子节点隐藏，看「2.1M 图元」到底是谁画的。
##   _tools/run_shot.sh res://scripts/_probe_room_bisect.gd -- --splat=off --story=off


const POS := Vector3(58.0, 1.6, 0.0)
const LOOK := Vector3(52.0, 1.2, 0.0)


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _read(tag: String) -> void:
	await _wait(8)
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var prims := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	print("[bisect] %-24s draws=%4d prims=%7d" % [tag, draws, prims])


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(150)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var cam := Camera3D.new()
	cam.far = 400.0
	cam.near = 0.05
	cam.fov = 70.0
	root.add_child(cam)
	cam.current = true
	cam.global_position = POS
	cam.look_at(LOOK, Vector3.UP)

	await _read("all_on")
	var names: Array[String] = []
	for c in game.get_children():
		if c is Node3D:
			names.append(c.name)
	print("[bisect] 顶层 3D 子节点 %d 个：%s" % [names.size(), ", ".join(names)])

	var rows: Array = []
	for c in game.get_children():
		var n3 := c as Node3D
		if n3 == null or not n3.visible:
			continue
		n3.visible = false
		await _wait(4)
		var prims := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		n3.visible = true
		rows.append({"name": String(n3.name), "prims": prims, "draws": draws})

	rows.sort_custom(func(x, y): return int(x["prims"]) < int(y["prims"]))
	for r in rows:
		print("[bisect] 隐藏 %-20s → prims=%7d draws=%4d" % [r["name"], int(r["prims"]), int(r["draws"])])
	quit(0)