extends SceneTree
## 量：长沙理工校园泼溅的世界 y 分布，找出「地面」那一层。
##   _tools/run_shot.sh res://scripts/_probe_campus_ground.gd -- --no-capture

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(640, 480)
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	var campus := level.get_node_or_null("Campus")
	if campus == null:
		print("[ground] 没有 Campus")
		quit(1)
		return
	var t0 := Time.get_ticks_msec()
	while not bool(campus.call("is_ready")) and Time.get_ticks_msec() - t0 < 240000:
		await process_frame
	if not bool(campus.call("is_ready")):
		print("[ground] 没加载完")
		quit(1)
		return
	var node := campus.get("splat_node") as Node3D
	var res = node.get("gaussian")
	var xyz: PackedVector3Array = res.get("xyz")
	var xf := node.global_transform
	var bin := 0.5
	var hist := {}
	var min_y := INF
	var max_y := -INF
	for i in xyz.size():
		var wy := (xf * xyz[i]).y
		var b := int(floor(wy / bin))
		hist[b] = int(hist.get(b, 0)) + 1
		min_y = minf(min_y, wy)
		max_y = maxf(max_y, wy)
	print("[ground] 世界 y %.2f .. %.2f，%d 点（每格 %.1f m）" % [min_y, max_y, xyz.size(), bin])
	var keys := hist.keys()
	keys.sort()
	var total := xyz.size()
	for k in keys:
		var count := int(hist[k])
		if count >= total / 400:
			print("  y %.1f ~ %.1f : %d（%.2f%%）"
				% [float(k) * bin, (float(k) + 1.0) * bin, count, 100.0 * count / total])
	var box: AABB = campus.call("content_world_aabb")
	print("[ground] 内容盒 pos %s size %s" % [
		str(box.position.snappedf(0.01)), str(box.size.snappedf(0.01))])
	quit(0)
