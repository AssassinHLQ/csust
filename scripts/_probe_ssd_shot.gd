extends SceneTree
## 给机箱里新加的 M.2 拍两张：整机正面 + 硬盘特写，确认位置和朝向。
##   _tools/run_shot.sh res://scripts/_probe_ssd_shot.gd -- --splat=off --story=off


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
	print("[ssdshot] → %s  cam=%s" % [path, str(pos.snappedf(0.01))])


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(180)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var rig := game.get_node_or_null("GameDevRoom/PC5090Rig") as Node3D
	if rig == null:
		print("[ssdshot] 找不到 PC5090Rig")
		quit(1)
		return
	# pc_rig.gd 里机箱要「买过」才显示；拍照先强制打开并停掉它自己的 _process
	rig.set_process(false)
	rig.visible = true
	var s0 := rig.get_node_or_null("SSD0") as Node3D
	var s1 := rig.get_node_or_null("SSD1") as Node3D
	print("[ssdshot] rig 世界位置 %s" % str(rig.global_position.snappedf(0.01)))
	if s0 != null:
		print("[ssdshot] SSD0 世界位置 %s  子网格数=%d" % [
			str(s0.global_position.snappedf(0.001)),
			s0.find_children("*", "MeshInstance3D", true, false).size()])
	if s1 != null:
		print("[ssdshot] SSD1 世界位置 %s" % str(s1.global_position.snappedf(0.001)))

	var cam := Camera3D.new()
	cam.far = 400.0
	cam.near = 0.05
	cam.fov = 70.0
	root.add_child(cam)
	cam.current = true

	var c := rig.global_position
	var mid := c + Vector3(-0.20, 0.095, -0.0615)   # 两颗硬盘的中点
	# 特写：正对玻璃那一面（看标签朝没朝外）
	await _shot(cam, mid + Vector3(0.0, 0.02, -0.30), mid, "res://_log/ssd_close_front.png")
	# 45° 侧看（看是不是立着贴在背板上）
	await _shot(cam, mid + Vector3(0.30, 0.14, -0.26), mid, "res://_log/ssd_close_side.png")
	# 整机正面
	await _shot(cam, c + Vector3(0.0, 0.75, -2.6), c + Vector3(0.0, 0.62, 0.0),
		"res://_log/ssd_case_front.png")
	quit(0)