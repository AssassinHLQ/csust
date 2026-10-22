extends SceneTree
## 渲图探针：小屋电脑。三张 —— 桌子全景 / 显示器近景（3D 屏幕上的终端）/ 按 F 后的覆盖层。
##   godot --path . --script res://scripts/_probe_computer_shot.gd -- --splat=off
## 输出：_arisu_captures/_pc/{desk,monitor,overlay}.png

func _initialize() -> void:
	_run.call_deferred()


func _shot(cam: Camera3D, out: String, nm: String) -> void:
	cam.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var file := "%s/%s.png" % [out, nm]
	root.get_texture().get_image().save_png(file)
	print("[pc-shot] %s  相机 %s" % [file, str(cam.global_position.snappedf(0.01))])


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 60:
		await process_frame
	paused = false
	var dlg := game.get_node_or_null("DialogueBox") as CanvasLayer
	if dlg != null:
		dlg.visible = false
		if dlg.has_method("skip_all"):
			dlg.call("skip_all")

	var pc := game.get_node_or_null("MeshHut/HutComputer") as HutComputer
	if pc == null:
		print("[pc-shot] 找不到电脑")
		quit(1)
		return
	# 玩家不再抢摄像机
	var player := game.get_node_or_null("Player") as Node3D
	if player != null:
		player.set_physics_process(false)
		player.set_process(false)

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_pc")
	DirAccess.make_dir_recursive_absolute(out)

	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.03
	cam.far = 60.0
	root.add_child(cam)

	var screen_world: Vector3 = pc.screen_mesh().global_position
	print("[pc-shot] 屏幕世界坐标 %s" % str(screen_world.snappedf(0.01)))

	# ① 桌子全景：站在桌子斜前方，能看到凳子 + 显示器 + 键盘
	cam.global_position = screen_world + Vector3(1.45, 0.75, 1.55)
	cam.look_at(screen_world + Vector3(-0.15, -0.25, 0.0), Vector3.UP)
	await _shot(cam, out, "desk")

	# ② 显示器近景：正面平视屏幕，看 3D 屏幕上的终端是不是真画出来了
	cam.global_position = screen_world + Vector3(0.0, 0.02, 0.55)
	cam.look_at(screen_world, Vector3.UP)
	await _shot(cam, out, "monitor")

	# ③ 按 F 之后的全屏覆盖层
	pc.use_for_test()
	await process_frame
	await _shot(cam, out, "overlay")
	pc.close_for_test()
	quit(0)
