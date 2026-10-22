extends SceneTree
## 探针：初始房间（画室 609）的高斯泼溅在不在、代理有没有被藏掉。
##   godot --path . --script res://scripts/_probe_room_splat.gd
## 输出：_arisu_captures/_room_splat_{inside,top}.png
func _initialize() -> void:
	_run.call_deferred()


func _shoot(cam: Camera3D, out: String, nm: String) -> void:
	cam.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, nm])


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 90:
		await process_frame
	paused = false
	var dlg := game.get_node_or_null("DialogueBox") as CanvasLayer
	if dlg != null:
		dlg.visible = false
		if dlg.has_method("skip_all"):
			dlg.call("skip_all")
	# 等泼溅解码
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000:
		await process_frame
		var ok := true
		for s in game.get("_splats"):
			if not bool(s.call("is_ready")):
				ok = false
		if ok:
			break
	for _i in 20:
		await process_frame

	var proxy: Node3D = game.get("_room_proxy")
	var room: Node = game.get("_room_scene")
	print("[诊断] 泼溅 ready=%s  代理 visible=%s  inside=%s" % [
		str(room != null and bool(room.call("is_ready"))), str(proxy.visible),
		str(game.get("_room_inside"))])

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures")
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.03
	cam.far = 200.0
	root.add_child(cam)
	var p: Vector3 = (game.get("_player") as Node3D).global_position
	# ① 站在屋里、眼高，朝房间深处（−z）看
	cam.global_position = p + Vector3(0.0, 1.6, 0.0)
	cam.look_at(p + Vector3(0.0, 1.4, -6.0), Vector3.UP)
	# 先拍一张「旧 bug」：模拟修复前 `RenderDistance` 每 tick
	# 把 `_update_room_swap()` 刚藏掉的方盒代理写回 `true`
	proxy.visible = true
	await _shoot(cam, out, "_room_splat_before")
	proxy.visible = false
	await _shoot(cam, out, "_room_splat_inside")
	# ② 从平台上方俯视整间屋
	cam.global_position = p + Vector3(6.5, 7.0, 9.0)
	cam.look_at(p + Vector3(0.0, 0.5, 0.0), Vector3.UP)
	await _shoot(cam, out, "_room_splat_top")
	print("[截图] %s/_room_splat_{inside,top}.png" % out)
	quit(0)
