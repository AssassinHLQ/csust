extends SceneTree
## 验图：7 名同伴逐个站在小屋地板上，低机位拍脚 —— 谁浮空一眼就能看出来。
##   godot --path . --script res://scripts/_probe_companion_lineup.gd -- --splat=off
## 输出：_arisu_captures/_feet/<名字>.png
func _initialize() -> void:
	_run.call_deferred()


func _shoot(cam: Camera3D, out: String, nm: String) -> void:
	cam.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, nm])


func _run() -> void:
	root.size = Vector2i(640, 640)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 60:
		await process_frame
	paused = false
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_feet")
	DirAccess.make_dir_recursive_absolute(out)
	var hud := game.get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		hud.visible = false
	var hut := game.get_node_or_null("MeshHut") as Node3D
	var cam := Camera3D.new()
	cam.fov = 45.0
	cam.near = 0.02
	cam.far = 400.0
	root.add_child(cam)
	var comps: Array = game.get("_companions")
	for i in comps.size():
		var comp := comps[i] as Node3D
		if not is_instance_valid(comp):
			continue
		# 屋里正中间，逐个摆；关掉跟随，免得她自己走开
		comp.set("_standby", false)
		comp.global_position = hut.to_global(Vector3(0.0, 0.06, 0.4))
		comp.rotation.y = 0.0
		comp.set_physics_process(false)
		for _j in 30:
			await process_frame
		var base := comp.global_position
		cam.global_position = base + Vector3(1.5, 0.42, 1.5)
		cam.look_at(base + Vector3(0.0, 0.22, 0.0), Vector3.UP)
		await _shoot(cam, out, str(comp.name))
		comp.set_physics_process(true)
	print("[截图] %s" % out)
	quit(0)
