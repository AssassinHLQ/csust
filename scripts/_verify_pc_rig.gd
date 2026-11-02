extends SceneTree
## 验：买完电脑后活动室南墙出现壁挂白色机箱，能挡人、按 F 能开机。
##   _tools/run_shot.sh res://scripts/_verify_pc_rig.gd -- --splat=off --story=off

func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(cam: Camera3D, p: Vector3, t: Vector3, nm: String) -> void:
	cam.global_position = p
	cam.look_at(t, Vector3.UP)
	await _wait(8)
	await RenderingServer.frame_post_draw
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_gamedev")
	DirAccess.make_dir_recursive_absolute(out)
	root.get_texture().get_image().save_png(out.path_join(nm + ".png"))
	print("[rig] shot ", nm)


func _run() -> void:
	ShopClerk._bought = true
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(90)
	for c in game.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false
	var rig := game.get_node_or_null("GameDevRoom/PC5090Rig") as Node3D
	if rig == null:
		print("[rig] 没找到 PC5090Rig")
		quit(1); return
	var shape := rig.get_node("Body/Collision") as CollisionShape3D
	print("[rig] visible=", rig.visible, " 碰撞关=", shape.disabled,
		" pos=", rig.global_position.snappedf(0.01))

	var cam := Camera3D.new()
	cam.fov = 58.0
	cam.near = 0.05
	root.add_child(cam)
	cam.current = true
	await _shot(cam, Vector3(48.2, 1.55, 2.55), Vector3(48.2, 1.55, 5.03), "32_pc_wall_case")

	var player := game.get_node("Player") as CharacterBody3D
	player.global_position = Vector3(48.2, 0.8, 3.1)
	player.velocity = Vector3.ZERO
	player.set("_yaw", PI)
	player.set("_pitch", 0.0)
	await _wait(20)
	var start_z := player.global_position.z
	Input.action_press("move_forward")
	for _f in 160:
		await process_frame
	Input.action_release("move_forward")
	await _wait(8)
	print("[rig] 撞托板：z %.2f → %.2f（托板前沿约 4.70）" % [
		start_z, player.global_position.z])
	await _shot(cam, Vector3(48.2, 1.55, 2.55), Vector3(48.2, 1.55, 5.03), "35_pc_wall_case_hint")

	var ev := InputEventKey.new()
	ev.keycode = KEY_F
	ev.pressed = true
	rig.call("_unhandled_input", ev)
	await _wait(6)
	print("[rig] 开机 booted=", rig.get("_booted"),
		" 灯=", (rig.get_node("Light") as OmniLight3D).light_energy,
		" 状态牌=", (rig.get_node("Status") as Label3D).visible)
	await _shot(cam, Vector3(48.2, 1.55, 2.55), Vector3(48.2, 1.55, 5.03), "33_pc_wall_case_on")
	await _shot(cam, Vector3(47.15, 1.78, 2.95), Vector3(48.2, 1.55, 5.03), "34_pc_wall_case_angle")
	quit(0)
