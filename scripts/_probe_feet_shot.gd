extends SceneTree
## 验图：① 芹香脚踩地（低机位） ② 柜台后露出多少 ③ 从屋外二层窗口看吊灯
##   godot --path . --script res://scripts/_probe_feet_shot.gd -- --splat=off
## 输出：_arisu_captures/_feet2/{clerk_low,clerk_wide,hut_window}.png
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
	for _i in 90:
		await process_frame
	paused = false
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_feet2")
	DirAccess.make_dir_recursive_absolute(out)
	var cn := game.get_node_or_null("HUD") as CanvasLayer
	if cn != null:
		cn.visible = false
	for c in game.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.near = 0.02
	cam.far = 400.0
	root.add_child(cam)

	var clerk := game.get_node_or_null("Shop/ClerkSerika") as Node3D
	if clerk != null:
		var base := clerk.global_position
		var counter := game.get_node_or_null("Shop/Counter") as Node3D
		var away := Vector3(0, 0, 1)
		if counter != null:
			var d := base - counter.global_position
			d.y = 0.0
			if d.length() > 0.01:
				away = d.normalized()
		# ① 低机位看脚：贴地面看过去，脚和地板的关系一目了然
		cam.fov = 40.0
		cam.global_position = base + away * 1.5 + Vector3(0, 0.30, 0)
		cam.look_at(base + Vector3(0, 0.16, 0), Vector3.UP)
		await _shoot(cam, out, "clerk_low")
		# ② 正常视高、退远一点看全身 + 柜台
		cam.fov = 55.0
		cam.global_position = base + away * 3.4 + Vector3(0.6, 1.35, 0)
		cam.look_at(base + Vector3(0, 0.95, 0), Vector3.UP)
		await _shoot(cam, out, "clerk_wide")

	# ③ 屋外、二层窗口高度往屋里看（用户第一张图大概就是这个视角）
	var hut := game.get_node_or_null("MeshHut") as Node3D
	if hut != null:
		cam.fov = 32.0
		cam.global_position = hut.to_global(Vector3(0.0, 4.15, 6.2))
		cam.look_at(hut.to_global(Vector3(0.0, 3.95, 0.0)), Vector3.UP)
		await _shoot(cam, out, "hut_window")
	print("[截图] %s" % out)
	quit(0)
