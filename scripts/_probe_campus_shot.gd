extends SceneTree
## 慢探针：等长沙理工校园泼溅（615 万点）在场景里加载完，量它落在哪、出图。
##   _tools/run_shot.sh res://scripts/_probe_campus_shot.gd -- --no-capture
## ⚠️ 第一次跑没有缓存，解码约 50 s + GPU 上传，耐心等。

func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(name)
	root.get_texture().get_image().save_png(out)
	print("[截图] %s" % out)


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	for _i in 60:
		await process_frame

	var campus := level.get_node_or_null("Campus")
	if campus == null:
		print("[campus] 没有 Campus 节点")
		quit(1)
		return
	print("[campus] start_delay=%.1f  loading=%s" % [
		float(campus.get("start_delay")), str(campus.get("loading"))])

	var t0 := Time.get_ticks_msec()
	var next_log := 0.0
	while Time.get_ticks_msec() - t0 < 240000:
		await process_frame
		var t := float(Time.get_ticks_msec() - t0) / 1000.0
		if t >= next_log:
			print("[campus] t=%.0fs  loading=%s  ready=%s"
				% [t, str(campus.get("loading")), str(bool(campus.call("is_ready")))])
			next_log += 10.0
		if bool(campus.call("is_ready")):
			break
	if not bool(campus.call("is_ready")):
		print("[campus] 240 s 内没加载完")
		quit(1)
		return
	var box: AABB = campus.call("content_world_aabb")
	print("[campus] 世界包围盒 pos %s size %s  顶面 y=%.2f  点数 %d"
		% [str(box.position.snappedf(0.1)), str(box.size.snappedf(0.1)),
			box.position.y + box.size.y, int(campus.get("point_count"))])
	print("[campus] 用时 %.1f s（缓存 %s）" % [
		float(campus.get("elapsed_seconds")),
		str(campus.get("_result") != null and bool(campus.get("_result").get("from_cache", false)))])

	for c in level.find_children("*", "CanvasLayer", true, false):
		var cl := c as CanvasLayer
		if cl != null:
			cl.visible = false
	var cam := Camera3D.new()
	cam.fov = 72.0
	level.add_child(cam)
	cam.current = true
	# 站在广场东边缘外看：脚下是校园（低 12 m），远处是大厅
	cam.global_position = Vector3(72.0, 6.0, 12.0)
	cam.look_at(Vector3(30.0, -8.0, -4.0))
	await _shot("_campus_outside.png")
	# 高空俯瞰：大厅 + 广场 + 四周校园
	cam.global_position = Vector3(60.0, 55.0, 60.0)
	cam.look_at(Vector3(0.0, -6.0, 0.0))
	cam.fov = 66.0
	await _shot("_campus_overview.png")
	quit(0)
