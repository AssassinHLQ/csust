extends SceneTree
## 把爱丽丝放在校园路上，从侧后方拍她脚下，看看到底浮空还是陷进去。
##   _tools/run_shot.sh res://scripts/_probe_campus_stand_shot.gd -- --gdgs-backend=raster
## 产物：_arisu_captures/_stand_1.png / _stand_2.png

const OUT_DIR := "C:/Users/WY157/Desktop/GODOT/_arisu_captures"

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	await process_frame
	await process_frame
	var campus := level.get_node_or_null("Campus")
	campus.set("start_delay", 0.0)
	campus.call("force_start")
	var player := level.get_node_or_null("Player") as Node3D
	var spots := [Vector3(0, 0.05, -130), Vector3(0, 0.05, -300)]
	player.global_position = spots[0]
	var t0 := Time.get_ticks_msec()
	while not bool(campus.call("is_ready")) and Time.get_ticks_msec() - t0 < 180000:
		await process_frame
	print("[stand] 校园就绪 %d ms" % (Time.get_ticks_msec() - t0))

	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.near = 0.05
	level.add_child(cam)
	cam.current = true
	for i in 2:
		player.global_position = spots[i]
		player.velocity = Vector3.ZERO
		for f in 30:
			await physics_frame
		var p := player.global_position
		cam.global_position = p + Vector3(2.2, 1.1, 3.0)
		cam.look_at(p + Vector3(0, 0.6, 0), Vector3.UP)
		for f in 5:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var path := "%s/_stand_%d.png" % [OUT_DIR, i + 1]
		print("[stand] 玩家 y=%.2f  on_floor=%s → %s err=%d"
			% [p.y, str(player.is_on_floor()), path, img.save_png(path)])
	quit(0)
