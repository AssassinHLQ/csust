extends SceneTree

const SceneFlow := preload("res://scripts/scene_flow.gd")
## 量「真正切到第二关」这条路的卡顿：黑屏预载是否把 5 s 的大帧藏住了。
##   _tools/run_shot.sh res://scripts/_probe_switch_perf.gd

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var dummy := Node3D.new()
	dummy.name = "Dummy"
	root.add_child(dummy)
	current_scene = dummy
	await process_frame

	var t0 := Time.get_ticks_msec()
	var last := t0
	var max_during := 0
	var max_during_frame := -1
	var frames_during := 0
	SceneFlow.switch_scene("res://scenes/next_level.tscn", "", "probe", true)
	while SceneFlow.switching and Time.get_ticks_msec() - t0 < 40000:
		await process_frame
		var now := Time.get_ticks_msec()
		var dt := now - last
		last = now
		frames_during += 1
		if dt > max_during:
			max_during = dt
			max_during_frame = frames_during
	var t_switch := Time.get_ticks_msec() - t0

	# 淡入之后（玩家真正能看见画面）的 3 秒里有没有大卡顿
	last = Time.get_ticks_msec()
	var max_after := 0
	for i in 180:
		await process_frame
		var now := Time.get_ticks_msec()
		max_after = maxi(max_after, now - last)
		last = now

	print("[switch] 切场景全程 %.2f s" % (t_switch / 1000.0))
	print("[switch] 黑屏期间最长一帧 %d ms（第 %d 帧）" % [max_during, max_during_frame])
	print("[switch] 淡入后 3 s 内最长一帧 %d ms" % max_after)
	var ggs := current_scene.get_node_or_null("CampusGGS") if current_scene != null else null
	if ggs != null:
		print("[switch] GGS is_ready=%s" % str(ggs.call("is_ready")))
	quit(0)
