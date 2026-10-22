extends SceneTree
## 渲图探针：渲染距离的**视觉**对照 —— 同一机位，1000 / 300 / 100 m 各一张。
##
## 用法：godot --path <工程> --script res://scripts/_probe_rd_shot.gd -- --splat=off
## 输出：_arisu_captures/_rd/{1000,300,100}.png
##
## 机位选在**跑酷起点往 -X 看**：整条路线一直铺到 598 m 外的小岛，
## 这里正是「远近」差别最明显的地方。

func _initialize() -> void:
	_run.call_deferred()


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

	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.05
	root.add_child(cam)
	cam.make_current()
	# 站在起点垫子上方一点点，稍微抬头，让路线一路铺向远处
	cam.global_position = Vector3(-8.0, 3.2, 9.0)
	cam.look_at(Vector3(-620.0, 14.0, -24.0), Vector3.UP)

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_rd")
	DirAccess.make_dir_recursive_absolute(out)

	var rd_node := game.get_node_or_null("RenderDistance") as RenderDistance
	var old := float(GameSettings.value("render_distance"))
	for rd in [1000, 300, 100]:
		GameSettings.set_value("render_distance", float(rd))
		cam.far = float(rd)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var file := "%s/%d.png" % [out, rd]
		root.get_texture().get_image().save_png(file)
		var st: Dictionary = rd_node.stats if rd_node != null else {}
		print("[rd-shot] %4d m  far=%6.1f  可见 %d/%d 簇、%d/%d 网格  → %s"
			% [rd, cam.far, int(st.get("visible_clusters", 0)), int(st.get("clusters", 0)),
				int(st.get("visible_meshes", 0)), int(st.get("meshes", 0)), file])
	GameSettings.set_value("render_distance", old)
	quit(0)
