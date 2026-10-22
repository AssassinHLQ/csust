extends SceneTree
## 拍一张和用户那张一样的「幕墙斜视角」，并打印立面各块的世界位置
## 输出：_arisu_captures/_facade/look.png
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 60:
		await process_frame
	paused = false
	var hud := game.get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		hud.visible = false
	var shop := game.get_node_or_null("Shop") as Node3D
	for nm in ["PierW", "PierE", "GlassW", "MullionW", "HeadBand", "WallWest", "Ceiling"]:
		var m := shop.find_child(nm, true, false) as MeshInstance3D
		if m == null:
			continue
		var a := m.global_transform * m.mesh.get_aabb()
		print("  %-10s pos=%s size=%s" % [nm,
			str(a.position.snappedf(0.01)), str(a.size.snappedf(0.01))])
	var pier := shop.find_child("PierW", true, false) as MeshInstance3D
	var base := pier.global_position
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.near = 0.05
	cam.far = 200.0
	root.add_child(cam)
	cam.global_position = base + Vector3(-4.5, -1.6, -7.0)
	cam.look_at(base + Vector3(1.5, 1.6, 0.8), Vector3.UP)
	cam.make_current()
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_facade")
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("look.png"))
	print("[截图] %s/look.png" % out)
	quit(0)
