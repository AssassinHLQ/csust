extends SceneTree
## A/B：同一机位下，校园 world_scale 75 / 50 / 25 的清晰度差别。
##   _tools/run_shot.sh res://scripts/_probe_campus_scale_ab.gd -- --no-capture
## 出图：_campus_ab_<scale>_{level,down,player}.png
##
## 摆放公式（实测反推）：地面 y≈−0.02 时
##   node.y = 11.98 + 0.5044·S
##   近边固定在 z=−75 → node.z = −75 − 3.229·S

func _initialize() -> void:
	_run.call_deferred()


func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(name)
	root.get_texture().get_image().save_png(out)
	print("[ab] 截图 %s" % out)


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	var campus := level.get_node("Campus")
	campus.call("force_start")
	var t0 := Time.get_ticks_msec()
	while not bool(campus.call("is_ready")) and Time.get_ticks_msec() - t0 < 180000:
		await process_frame
	if not bool(campus.call("is_ready")):
		print("[ab] 加载失败")
		quit(1)
		return
	level.get_node("Player").global_position = Vector3(0.0, 0.3, -150.0)
	for _i in 20:
		await physics_frame
	for c in level.find_children("*", "CanvasLayer", true, false):
		var cl := c as CanvasLayer
		if cl != null:
			cl.visible = false
	var cam := Camera3D.new()
	cam.fov = 70.0
	level.add_child(cam)
	cam.current = true

	for s in [75.0, 50.0, 25.0]:
		campus.set("world_scale", s)
		campus.position = Vector3(0.0, 11.98 + 0.5044 * s, -75.0 - 3.229 * s)
		campus.call("apply_transform")
		var node := campus.get("splat_node") as Node3D
		var box: AABB = campus.call("content_world_aabb")
		print("[ab] S=%.0f  盒 %.0f×%.0f m  密度 %.1f 点/m²"
			% [s, box.size.x, box.size.z,
				float(campus.get("point_count")) / (box.size.x * box.size.z)])
		for _i in 15:
			await process_frame
		cam.global_position = Vector3(0.0, 8.0, -150.0)
		cam.look_at(Vector3(0.0, 8.0, -300.0))
		await _shot("_campus_ab_%d_level.png" % int(s))
		cam.global_position = Vector3(0.0, 8.0, -150.0)
		cam.look_at(Vector3(0.0, -8.0, -160.0))
		await _shot("_campus_ab_%d_down.png" % int(s))
	quit(0)
