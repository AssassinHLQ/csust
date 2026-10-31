extends SceneTree
## 拍新加的楼：一张纯几何（关 GGS），一张玩家视角（开 GGS）。
##   _tools/run_shot.sh res://scripts/_probe_campus_buildings_shot.gd

const OUT_DIR := "C:/Users/WY157/Desktop/GODOT/_arisu_captures"

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	await process_frame
	await process_frame
	var player := level.get_node_or_null("Player") as Node3D
	if player != null:
		player.global_position = Vector3(0, 0.05, -120)
	var ggs := level.get_node_or_null("CampusGGS")
	var t0 := Time.get_ticks_msec()
	while ggs != null and Time.get_ticks_msec() - t0 < 120000:
		var r = ggs.get("rasterizer")
		if r != null and r.is_loaded:
			break
		await process_frame
	print("[bldgshot] 加载完成 %d ms" % (Time.get_ticks_msec() - t0))

	var target := Vector3(-2, 0, -116)
	print("[bldgshot] 取景楼 %s" % str(target))

	# ① 纯几何：GGS 只认玩家相机，别的机位会被全屏 quad 盖掉，先关掉
	if ggs != null:
		ggs.set_process(false)
		var q = ggs.get("quad")
		if q != null:
			q.visible = false
	var cam := Camera3D.new()
	cam.fov = 65.0
	cam.near = 0.05
	cam.far = 2000.0
	level.add_child(cam)
	cam.current = true
	cam.global_position = target + Vector3(0, 20, 56)
	cam.look_at(target + Vector3(0, 5, 0), Vector3.UP)
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	print("[bldgshot] %s err=%d" % ["_bldg_geo", img.save_png("%s/_bldg_geo.png" % OUT_DIR)])

	# ② 玩家视角（开 GGS，带泼溅）
	if player != null and ggs != null:
		ggs.set_process(true)
		player.set("_yaw", 0.0)
		player.global_position = target + Vector3(0, 0.05, 30)
		var pc = player.get_node_or_null("CameraRig/SpringArm3D/Camera3D")
		if pc is Camera3D:
			(pc as Camera3D).current = true
		for i in 20:
			await process_frame
		await RenderingServer.frame_post_draw
		var img2 := root.get_texture().get_image()
		print("[bldgshot] %s err=%d" % ["_bldg_play", img2.save_png("%s/_bldg_play.png" % OUT_DIR)])
	quit(0)
