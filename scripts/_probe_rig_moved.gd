extends SceneTree
## 验收：5090 工作站已从部室搬到电竞房北墙。
##   _tools/run_shot.sh res://scripts/_probe_rig_moved.gd -- --splat=off --story=off


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(cam: Camera3D, pos: Vector3, look: Vector3, path: String) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	await _wait(20)
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("[mv] → %s" % path)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(180)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var old_rig := game.get_node_or_null("GameDevRoom/PC5090Rig")
	var new_rig := game.get_node_or_null("EsportsRoom/PC5090Rig") as Node3D
	print("[mv] 部室 PC5090Rig 存在=%s（应为 false）" % str(old_rig != null))
	print("[mv] 电竞房 PC5090Rig 存在=%s" % str(new_rig != null))
	if new_rig != null:
		# pc_rig.gd 里机箱要「买过」才显示，拍照先强制打开
		new_rig.set_process(false)
		new_rig.visible = true
		print("[mv] 位置=%s rot=%s 可见=%s 子节点=%d" % [
			str(new_rig.global_position.snappedf(0.01)),
			str(new_rig.global_rotation_degrees.snappedf(1.0)),
			str(new_rig.visible), new_rig.get_child_count()])
		var mn := Vector3(1e9, 1e9, 1e9)
		var mx := Vector3(-1e9, -1e9, -1e9)
		for mi in new_rig.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			var ab: AABB = m.global_transform * m.get_aabb()
			for i in 3:
				mn[i] = minf(mn[i], ab.position[i])
				mx[i] = maxf(mx[i], ab.position[i] + ab.size[i])
		print("[mv] 世界包围盒 min=%s size=%s" % [
			str(mn.snappedf(0.01)), str((mx - mn).snappedf(0.01))])

	var cam := Camera3D.new()
	cam.far = 400.0
	cam.near = 0.05
	cam.fov = 70.0
	root.add_child(cam)
	cam.current = true

	# 电竞房：正对北墙看机箱（房间世界原点 52, 0.01, 13；北墙 z=8.1）
	await _shot(cam, Vector3(55.2, 1.55, 12.2), Vector3(55.2, 1.35, 8.5),
		"res://_log/rig_in_esports.png")
	# 从门口往屋里看整体
	await _shot(cam, Vector3(44.5, 1.7, 13.0), Vector3(52.0, 1.3, 13.0),
		"res://_log/rig_in_esports_wide.png")
	# 部室：原来挂机箱那面墙（世界 x≈48.2, z≈5.0）
	await _shot(cam, Vector3(48.2, 1.6, 2.0), Vector3(48.2, 1.4, 5.0),
		"res://_log/gamedev_without_rig.png")
	quit(0)