extends SceneTree
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(640, 480)
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	for _i in 30:
		await process_frame
	var chunks := level.get_node("CampusChunks")
	var t0 := Time.get_ticks_msec()
	var list: Array[Node] = []
	for c in chunks.get_children():
		list.append(c)
	while true:
		var done := 0
		for c in list:
			if bool(c.call("is_ready")):
				done += 1
		if done == list.size() or Time.get_ticks_msec() - t0 > 300000:
			break
		await process_frame
	print("[dbg] 根 transform = %s" % str((chunks as Node3D).global_transform))
	for c in list:
		if not bool(c.call("is_ready")):
			continue
		var cn := c as Node3D
		var node := cn.get("splat_node") as Node3D
		var res = node.get("gaussian")
		print("[dbg] %s  node=%s  offset=%s  scale=%s" % [
			cn.name, str(node.transform), str(cn.get("offset")), str(cn.get("world_scale"))])
		print("        content_min=%s content_max=%s  aabb=%s" % [
			str(cn.get("content_min").snappedf(0.01)), str(cn.get("content_max").snappedf(0.01)),
			str((cn.call("content_world_aabb") as AABB).position.snappedf(0.1))])
	quit(0)
