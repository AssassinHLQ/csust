extends SceneTree
## 看段表与前两段的站点，判断「第 1 段终点」该不该算存档。
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var lvl := (load("res://scenes/parkour.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(lvl)
	for _i in 10:
		await process_frame
	var segs: Array = lvl.get("segments")
	print("[seg] segments（%d 段）：%s" % [segs.size(), str(segs)])
	print("[seg] 站数 %d" % int(lvl.call("node_count")))
	for i in range(0, 14):
		var b: AABB = lvl.call("box_at", i)
		print("[seg] 站 %2d  %-12s  %s" % [i, str(lvl.call("label_at", i)),
			str((b.position + b.size * 0.5).snappedf(0.1))])
	var beacon := lvl.get_node_or_null("Route/Beacon_C1") as Node3D
	if beacon != null:
		print("[seg] Beacon_C1（第 1 段·终点 牌子）在 %s" % str(beacon.global_position.snappedf(0.1)))
		var best := -1
		var bestd := 1e9
		for i in range(0, 20):
			var b2: AABB = lvl.call("box_at", i)
			var d := (b2.get_center() - beacon.global_position).length()
			if d < bestd:
				bestd = d
				best = i
		print("[seg] 离牌子最近的站：%d（%s），距离 %.1f m" % [best, str(lvl.call("label_at", best)), bestd])
	quit(0)
