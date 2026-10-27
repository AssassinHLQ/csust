extends SceneTree
## 量：画室609 泼溅从开始解码到就绪，主线程卡在哪几帧。
##   _tools/run_shot.sh res://scripts/_probe_splat_hitch.gd -- --no-capture
##
## 做法：把 start_delay 改成 3 s、start_distance 归零（不看距离），
## 逐帧记 `process_frame` 间隔；≥30 ms 的帧就是玩家能感觉到的卡顿。

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var ps := load("res://scenes/game.tscn") as PackedScene
	var game := ps.instantiate()
	var room := game.get_node_or_null("Room609")
	room.set("start_delay", 3.0)
	room.set("start_distance", 0.0)
	root.add_child(game)

	var t0 := Time.get_ticks_usec()
	var last := t0
	var spikes: Array[String] = []
	var ready_at := -1.0
	while true:
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := float(now - last) / 1000.0
		var t := float(now - t0) / 1000000.0
		last = now
		if dt >= 30.0:
			spikes.append("t=%.2fs  帧 %.0f ms" % [t, dt])
		if ready_at < 0.0 and bool(room.call("is_ready")):
			ready_at = t
		if ready_at > 0.0 and t > ready_at + 2.0:
			break
		if t > 45.0:
			break
	print("[hitch] 就绪 t=%.2fs（SplatScene elapsed %.2fs），≥30 ms 的帧 %d 个"
		% [ready_at, float(room.get("elapsed_seconds")), spikes.size()])
	for s in spikes:
		print("  %s" % s)
	quit(0)
