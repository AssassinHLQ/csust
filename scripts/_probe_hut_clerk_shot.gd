extends SceneTree
## 验图：① 小屋新高度（和商店对比） ② 芹香微笑 + 脚踩地
##   godot --path . --script res://scripts/_probe_hut_clerk_shot.gd -- --splat=off
## 输出：_arisu_captures/_hutshot/{hut,shop,clerk_face,clerk_side}.png
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
		.path_join("_arisu_captures").path_join("_hutshot")
	DirAccess.make_dir_recursive_absolute(out)
	var hud := game.get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		hud.visible = false
	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.05
	cam.far = 400.0
	root.add_child(cam)

	# ① 从平台中央看小屋（同时能看到右后的商店）
	cam.global_position = Vector3(14.0, 3.0, -1.5)
	cam.look_at(Vector3(14.0, 2.9, -15.5), Vector3.UP)
	await _shoot(cam, out, "hut")

	# ② 平视两张建筑（同一水平线，比高度）
	cam.global_position = Vector3(24.0, 4.0, 6.0)
	cam.look_at(Vector3(24.0, 3.0, -8.0), Vector3.UP)
	await _shoot(cam, out, "shop")

	# ③ 芹香的脸（微笑）
	var clerk := game.get_node_or_null("Shop/ClerkSerika") as Node3D
	if clerk != null:
		var base := clerk.global_position
		cam.fov = 34.0
		cam.global_position = base + Vector3(-1.25, 1.42, 0.0)
		cam.look_at(base + Vector3(0.0, 1.18, 0.0), Vector3.UP)
		await _shoot(cam, out, "clerk_face")
		cam.fov = 60.0
		cam.global_position = base + Vector3(-2.6, 1.2, 2.2)
		cam.look_at(base + Vector3(0.0, 0.8, 0.0), Vector3.UP)
		await _shoot(cam, out, "clerk_side")
	print("[截图] %s" % out)
	quit(0)
