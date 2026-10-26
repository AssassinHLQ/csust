extends SceneTree
## 判图：只拍大楼门口 —— 招牌、门洞、门口灯。
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
	for _i in 120:
		await process_frame
	paused = false
	var house := game.get_node_or_null("MondrianHouse") as Node3D
	var hp := house.global_position
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_mondrian")
	DirAccess.make_dir_recursive_absolute(out)
	# 藏 HUD：**递归**（期货那行字挂在 `Parkour/Futures/FuturesHUD` 底下，
	# 只遍历 Game 的直接子节点会漏，实测图上顶着「保证金 ¥10.00 万…」）
	for c in game.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
	for c in game.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false
	var cam := Camera3D.new()
	cam.near = 0.05
	cam.far = 500.0
	root.add_child(cam)
	# 站在门前空地里、正对门口，平视。
	# ⚠️ 2026-10-26 楼退到 z = +13.50（门前 20 m 空场），机位也从 hp.z − 9.20 起算 ——
	#    离门 4.30 m，画面里正好是门洞 + 门头那条黑线。
	cam.fov = 62.0
	cam.global_position = Vector3(hp.x, 1.65, hp.z - 9.20)
	cam.look_at(Vector3(hp.x, 2.10, hp.z - 6.0), Vector3.UP)
	await _shoot(cam, out, "door")
	# 稍微抬一点看**门头**（2026-10-26 起门头上没有招牌字，只有那条黑门头）
	cam.fov = 58.0
	cam.global_position = Vector3(hp.x, 2.20, hp.z - 10.00)
	cam.look_at(Vector3(hp.x, 3.30, hp.z - 6.0), Vector3.UP)
	await _shoot(cam, out, "door_head")
	print("[截图] %s" % out)
	quit(0)
