extends SceneTree
## 验图：① 门把手贴在门板上（门内、门外两个机位） ② 芹香身高 1.55 m 且循环待机
##   godot --path . --script res://scripts/_probe_knob_clerk_shot.gd -- --splat=off
## 输出：_arisu_captures/_knob/{inside,outside,clerk}.png
func _initialize() -> void:
	_run.call_deferred()


func _shoot(cam: Camera3D, out: String, nm: String) -> void:
	cam.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, nm])


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 60:
		await process_frame
	paused = false
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_knob")
	DirAccess.make_dir_recursive_absolute(out)

	var proxy := game.get_node_or_null("RoomProxy") as Node3D
	var knob := proxy.get_node_or_null("DoorKnob") as Node3D if proxy != null else null
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.near = 0.02
	cam.far = 60.0
	root.add_child(cam)
	if knob != null:
		var k := knob.global_position
		# ① 站在门内侧、斜着看门板
		cam.global_position = k + Vector3(-2.6, 0.35, 1.7)
		cam.look_at(k, Vector3.UP)
		await _shoot(cam, out, "inside")
		# ② 站在门外、正对门板
		cam.global_position = k + Vector3(2.6, 0.35, 1.5)
		cam.look_at(k, Vector3.UP)
		await _shoot(cam, out, "outside")
		print("[knob] 世界位置 %s" % str(k.snappedf(0.001)))

	# ③ 店员：站在柜台前看芹香
	var clerk := game.get_node_or_null("Shop/ClerkSerika") as Node3D
	if clerk != null:
		var c := clerk.global_position
		for spec in [["xm", Vector3(-3.0, 1.55, 0.0)], ["xp", Vector3(3.0, 1.55, 0.0)],
				["zm", Vector3(0.0, 1.55, -3.0)]]:
			cam.global_position = c + (spec[1] as Vector3)
			cam.look_at(c + Vector3(0.0, 0.9, 0.0), Vector3.UP)
			await _shoot(cam, out, "clerk_%s" % spec[0])
		var ap := clerk.get("_idle") as AnimationPlayer
		if ap != null:
			var p1 := ap.current_animation_position
			for _i in 25:
				await process_frame
			print("[clerk] 25 帧内动画位置 %.3f → %.3f（应该在动）" % [
				p1, ap.current_animation_position])
	print("[截图] %s/{inside,outside,clerk}.png" % out)
	quit(0)
