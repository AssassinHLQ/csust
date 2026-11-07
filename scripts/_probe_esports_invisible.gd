extends SceneTree
## 玩家站进电竞房，查它的网格到底被谁藏了（重点看 RenderDistance 的 _hidden）。
##   _tools/run_shot.sh res://scripts/_probe_esports_invisible.gd -- --splat=off --story=off


const SPOT := Vector3(52.0, 0.6, 13.0)


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(180)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var rd: Node = null
	for c in game.get_children():
		if c is RenderDistance or String(c.get_class()).contains("Render"):
			rd = c
		if c.get_script() != null and String(c.get_script().resource_path).ends_with("render_distance.gd"):
			rd = c
	print("[esp] RenderDistance 节点 = %s" % (str(rd) if rd != null else "没找到"))

	var room := game.get_node_or_null("EsportsRoom") as Node3D
	if room == null:
		print("[esp] 没有 EsportsRoom")
		quit(1)
		return

	var player := game.get_node_or_null("Player") as Node3D
	player.global_position = SPOT
	player.set("velocity", Vector3.ZERO)
	await _wait(120)

	print("[esp] 玩家在 %s，EsportsRoom 直接子节点：" % str(player.global_position.snappedf(0.1)))
	for c in room.get_children():
		var n3 := c as Node3D
		print("[esp]   %-22s %-18s visible=%s" % [
			String(c.name), c.get_class(), str(n3.visible) if n3 != null else "-"])

	if rd != null:
		var hidden: Dictionary = rd.get("_hidden")
		print("[esp] RenderDistance 藏了 %d 个簇：" % hidden.size())
		for id in hidden.keys():
			var n := instance_from_id(int(id)) as Node3D
			print("[esp]   %-24s 原本 visible=%s" % [
				(n.name if n != null else "已释放"), str(hidden[id])])
		var stats: Dictionary = rd.get("stats")
		print("[esp] 距离统计：%s" % str(stats))

	# 拍一张，看是不是只有碰撞和道具
	debug_collisions_hint = true
	var cam := Camera3D.new()
	cam.far = 400.0
	cam.near = 0.05
	cam.fov = 70.0
	root.add_child(cam)
	cam.current = true
	cam.global_position = Vector3(45.5, 1.7, 13.0)
	cam.look_at(Vector3(53.0, 1.2, 13.0), Vector3.UP)
	await _wait(30)
	root.get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://_log/esp_inside.png"))
	print("[esp] 截图 → res://_log/esp_inside.png")
	quit(0)