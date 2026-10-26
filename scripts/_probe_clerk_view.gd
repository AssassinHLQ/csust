extends SceneTree
## 判图：芹香在店里的真实观感 —— 顾客侧 / 她身后 / 头顶俯视。
##   godot --path . --script res://scripts/_probe_clerk_view.gd -- --splat=off
func _initialize() -> void:
	_run.call_deferred()


func _shoot(cam: Camera3D, out: String, nm: String) -> void:
	cam.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, nm])


func _run() -> void:
	root.size = Vector2i(960, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 130:
		await process_frame
	paused = false
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_clerkview")
	DirAccess.make_dir_recursive_absolute(out)
	for c in game.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
	var clerk := game.get_node_or_null("Shop/ClerkSerika") as Node3D
	var base := clerk.global_position
	var cam := Camera3D.new()
	cam.near = 0.02
	cam.far = 400.0
	root.add_child(cam)

	# ① 顾客侧（柜台挡在前面）
	cam.fov = 55.0
	cam.global_position = Vector3(base.x - 3.6, 1.55, base.z + 1.5)
	cam.look_at(Vector3(base.x, 1.0, base.z), Vector3.UP)
	await _shoot(cam, out, "customer")

	# ② 她身后（玩家挤进柜台与东墙之间的空当，就是用户那张图的机位）
	cam.fov = 70.0
	cam.global_position = Vector3(base.x - 0.62, 1.05, base.z + 0.30)
	cam.look_at(Vector3(base.x, 0.72, base.z - 0.25), Vector3.UP)
	await _shoot(cam, out, "behind")

	# ③ 侧后方、低机位：专门看脚和地面的关系
	cam.fov = 52.0
	cam.global_position = Vector3(base.x - 1.75, 0.42, base.z + 1.30)
	cam.look_at(Vector3(base.x, 0.30, base.z), Vector3.UP)
	await _shoot(cam, out, "feet")
	print("[截图] %s" % out)
	quit(0)
