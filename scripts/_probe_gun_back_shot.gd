extends SceneTree
## 渲图探针：① 爱丽丝走路时枪背在身后（两个机位）  ② 芹香 `Cafe_Idle` 不拿枪
##   godot --path . --script res://scripts/_probe_gun_back_shot.gd -- --splat=off
## 输出：_arisu_captures/_gun/{back,side,clerk}.png

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

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_gun")
	DirAccess.make_dir_recursive_absolute(out)

	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.near = 0.03
	cam.far = 80.0
	root.add_child(cam)
	cam.make_current()

	var player := game.get_node_or_null("Player") as Node3D
	var driver := game.get_node_or_null("Player/Arisu/Model/AnimDriver")
	if player == null:
		quit(1)
		return

	# 让它真的走起来（按住 W），这样播的是 Cafe_Walk
	Input.action_press("move_forward")
	for _i in 45:
		await process_frame

	var p := player.global_position
	print("[gun] 玩家 %s  速度字段 %s" % [str(p.snappedf(0.01)), str(driver.get("_speed"))])
	# ① 背后机位（正对背部）
	cam.global_position = p + Vector3(0.10, 1.35, 2.35)
	cam.look_at(p + Vector3(0.0, 1.05, 0.0), Vector3.UP)
	await _shoot(cam, out, "back")
	# ② 斜后方
	cam.global_position = p + Vector3(1.85, 1.30, 1.85)
	cam.look_at(p + Vector3(0.0, 1.00, 0.0), Vector3.UP)
	await _shoot(cam, out, "side")
	Input.action_release("move_forward")

	# ③ 芹香：Cafe_Idle 应该不拿枪
	var clerk := game.get_node_or_null("Shop/ClerkSerika") as Node3D
	if clerk != null:
		var c := clerk.global_position
		cam.global_position = c + Vector3(-1.75, 1.55, 0.85)
		cam.look_at(c + Vector3(0.0, 1.25, 0.0), Vector3.UP)
		await _shoot(cam, out, "clerk")
	quit(0)
