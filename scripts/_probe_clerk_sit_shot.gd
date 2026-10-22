extends SceneTree
## 渲图探针：① 芹香在柜台的近景  ② 按 F 之后爱丽丝在凳子上的样子（覆盖层临时藏起来）
##   godot --path . --script res://scripts/_probe_clerk_sit_shot.gd -- --splat=off
## 输出：_arisu_captures/_clerk/{clerk,clerk_close,sit}.png

func _initialize() -> void:
	_run.call_deferred()


func _shoot(cam: Camera3D, out: String, nm: String) -> void:
	cam.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, nm])


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
	var player := game.get_node_or_null("Player") as Node3D
	if player != null:
		player.set_physics_process(false)
		player.set_process(false)

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_clerk")
	DirAccess.make_dir_recursive_absolute(out)

	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.near = 0.04
	cam.far = 80.0
	root.add_child(cam)

	# ① 芹香：柜台外侧、能看见上半身
	var clerk := game.get_node_or_null("Shop/ClerkSerika") as Node3D
	if clerk != null:
		var p := clerk.global_position
		print("[clerk-shot] 芹香世界坐标 %s" % str(p.snappedf(0.01)))
		cam.global_position = p + Vector3(-1.9, 1.45, 0.9)
		cam.look_at(p + Vector3(0.0, 1.0, 0.0), Vector3.UP)
		await _shoot(cam, out, "clerk")
		cam.global_position = p + Vector3(-0.95, 1.45, 0.35)
		cam.look_at(p + Vector3(0.0, 1.15, 0.0), Vector3.UP)
		await _shoot(cam, out, "clerk_close")
	else:
		print("[clerk-shot] 找不到 Shop/ClerkSerika")

	# ② 坐姿：打开电脑 → 把覆盖层藏起来 → 从侧面拍（能看到「站着塞进凳子」）
	var pc := game.get_node_or_null("MeshHut/HutComputer") as HutComputer
	if pc != null:
		pc.use_for_test()
		var overlay := pc.get_node_or_null("ComputerUI/Overlay") as Control
		if overlay != null:
			overlay.visible = false
		await process_frame
		var seat := pc.to_global(Vector3(-0.6, 0.0, -1.30))
		print("[clerk-shot] 凳子世界坐标 %s，玩家 %s"
			% [str(seat.snappedf(0.01)), str(player.global_position.snappedf(0.01))])
		cam.global_position = seat + Vector3(1.55, 1.35, 1.15)
		cam.look_at(seat + Vector3(0.0, 0.75, -0.55), Vector3.UP)
		await _shoot(cam, out, "sit")
		pc.close_for_test()
	quit(0)
