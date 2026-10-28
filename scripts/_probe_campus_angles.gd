extends SceneTree
## 对照：同一个相机位置，「往下看」和「平视」校园泼溅差多少。
##   _tools/run_shot.sh res://scripts/_probe_campus_angles.gd -- --no-capture
## 出图：
##   _campus_angle_down.png  / _campus_angle_level.png
## 同时量：平均高斯世界尺寸、点密度。

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
	var campus := level.get_node("Campus")
	campus.call("force_start")
	var t0 := Time.get_ticks_msec()
	while not bool(campus.call("is_ready")) and Time.get_ticks_msec() - t0 < 180000:
		await process_frame
	if not bool(campus.call("is_ready")):
		print("[angle] 加载失败")
		quit(1)
		return
	var player := level.get_node("Player") as CharacterBody3D
	player.global_position = Vector3(0.0, 0.3, -150.0)
	for _i in 30:
		await physics_frame

	# 量平均高斯尺寸（协方差对角线开方，源坐标 → 世界坐标）
	var node := campus.get("splat_node") as Node3D
	var res = node.get("gaussian")
	var bytes: PackedByteArray = res.get("point_data_byte")
	var n := int(res.get("point_count"))
	var scale := float(campus.get("world_scale"))
	var step := maxi(1, n / 20000)
	var acc := 0.0
	var cnt := 0
	var i := 0
	while i < n:
		var off := i * 240
		var sx := sqrt(maxf(bytes.decode_float(off + 4 * 4), 0.0))
		var sy := sqrt(maxf(bytes.decode_float(off + 7 * 4), 0.0))
		var sz := sqrt(maxf(bytes.decode_float(off + 9 * 4), 0.0))
		acc += (sx + sy + sz) / 3.0
		cnt += 1
		i += step
	var box: AABB = campus.call("content_world_aabb")
	var area := box.size.x * box.size.z
	print("[angle] 点数 %d，内容 %.0f×%.0f m，密度 %.1f 点/m²"
		% [n, box.size.x, box.size.z, float(n) / area])
	print("[angle] 平均高斯半径（1σ）源坐标 %.4f → 世界 %.2f m（world_scale %.0f）"
		% [acc / cnt, acc / cnt * scale, scale])
	print("[angle] 点间距约 %.2f m" % sqrt(area / float(n)))

	for c in level.find_children("*", "CanvasLayer", true, false):
		var cl := c as CanvasLayer
		if cl != null:
			cl.visible = false
	var cam := Camera3D.new()
	cam.fov = 70.0
	level.add_child(cam)
	cam.current = true
	# 同一个位置：先平视，再低头 55°
	cam.global_position = Vector3(0.0, 8.0, -150.0)
	cam.look_at(Vector3(0.0, 8.0, -260.0))
	await _shot("_campus_angle_level.png")
	cam.global_position = Vector3(0.0, 8.0, -150.0)
	cam.look_at(Vector3(0.0, -8.0, -160.0))
	await _shot("_campus_angle_down.png")
	# 第三人称地面（复现用户那张）
	cam.current = false
	for _i in 20:
		await process_frame
	var pcam := player.get("cam") as Camera3D
	if pcam != null:
		pcam.current = true
	await _shot("_campus_angle_player.png")
	quit(0)
