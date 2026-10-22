extends SceneTree
## 只读探针：渲染距离对**实际渲染开销**的影响（draw call / 图元 / 帧时间）。
##   godot --path . --script res://scripts/_probe_rd_perf.gd -- --splat=off
##
## 必须是**带窗口**的运行（headless 用的是哑渲染器，这几个 monitor 全是 0）。

func _initialize() -> void:
	_run.call_deferred()


func _sample(n: int) -> Dictionary:
	var calls := 0.0
	var prims := 0.0
	var proc := 0.0
	for _i in n:
		await process_frame
		calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		proc += Performance.get_monitor(Performance.TIME_PROCESS)
	return {"calls": calls / n, "prims": prims / n, "proc": proc / n * 1000.0}


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 60:
		await process_frame
	paused = false
	var dlg := game.get_node_or_null("DialogueBox") as CanvasLayer
	if dlg != null:
		dlg.visible = false
		if dlg.has_method("skip_all"):
			dlg.call("skip_all")

	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.05
	root.add_child(cam)
	cam.make_current()
	cam.global_position = Vector3(-8.0, 3.2, 9.0)
	cam.look_at(Vector3(-620.0, 14.0, -24.0), Vector3.UP)

	var rd_node := game.get_node_or_null("RenderDistance") as RenderDistance
	var old := float(GameSettings.value("render_distance"))
	print("[rd-perf] 机位 (-8, 3.2, 9) 朝 -X；每档采样 40 帧")
	for rd in [1000, 300, 100]:
		GameSettings.set_value("render_distance", float(rd))
		cam.far = float(rd)
		for _i in 10:
			await process_frame
		var s: Dictionary = await _sample(40)
		var st: Dictionary = rd_node.stats if rd_node != null else {}
		print("[rd-perf] %4d m   draw call %6.0f  图元 %8.0f  脚本 %5.2f ms  可见网格 %d/%d"
			% [rd, s["calls"], s["prims"], s["proc"],
				int(st.get("visible_meshes", 0)), int(st.get("meshes", 0))])
	GameSettings.set_value("render_distance", old)
	print("[rd-perf] 恢复原值 %.0f m" % old)
	quit(0)
