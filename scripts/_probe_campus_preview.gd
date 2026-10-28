extends SceneTree
## 验证编辑器预览：位置/范围要和泼溅内容盒对得上，并且能出图。
##   _tools/run_shot.sh res://scripts/_probe_campus_preview.gd -- --no-capture

func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(name)
	root.get_texture().get_image().save_png(out)
	print("[preview] 截图 %s" % out)


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	var campus := level.get_node("Campus")
	campus.call("force_start")
	var t0 := Time.get_ticks_msec()
	while not bool(campus.call("is_ready")) and Time.get_ticks_msec() - t0 < 180000:
		await process_frame
	var preview := level.get_node("Campus/CampusPreview") as Node3D
	var mi := preview.get_node("Points") as MeshInstance3D
	print("[preview] 运行时 visible=%s（应 false）" % str(preview.visible))
	preview.visible = true
	var paabb: AABB = mi.global_transform * mi.get_aabb()
	var caabb: AABB = campus.call("content_world_aabb")
	print("[preview] 预览世界盒 pos %s size %s" % [
		str(paabb.position.snappedf(0.1)), str(paabb.size.snappedf(0.1))])
	print("[preview] 泼溅内容盒 pos %s size %s" % [
		str(caabb.position.snappedf(0.1)), str(caabb.size.snappedf(0.1))])
	print("[preview] 盒中心差 %s" % str((paabb.get_center() - caabb.get_center()).snappedf(0.1)))

	# 藏掉真正的泼溅，只看点云预览
	var splat := campus.get("splat_node") as Node3D
	if splat != null:
		splat.visible = false
	for c in level.find_children("*", "CanvasLayer", true, false):
		var cl := c as CanvasLayer
		if cl != null:
			cl.visible = false
	var cam := Camera3D.new()
	cam.fov = 66.0
	level.add_child(cam)
	cam.current = true
	cam.global_position = Vector3(120.0, 190.0, 30.0)
	cam.look_at(Vector3(0.0, 0.0, -260.0))
	await _shot("_campus_preview_above.png")
	cam.global_position = Vector3(10.0, 18.0, -90.0)
	cam.look_at(Vector3(0.0, 6.0, -220.0))
	cam.fov = 72.0
	await _shot("_campus_preview_bridge.png")
	quit(0)
