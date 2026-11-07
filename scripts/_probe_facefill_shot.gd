extends SceneTree
## FaceFill「只照角色」前后对比：在玩家脸前 1.2 m 放一块临时墙，
## 只切 `light_cull_mask`，两张图必须一张有光斑、一张没有。
##   _tools/run_shot.sh res://scripts/_probe_facefill_shot.gd -- --splat=off --story=off


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await _wait(30)
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("[fillshot] → %s" % path)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(150)

	var player := game.get_node_or_null("Player") as Node3D
	var fill := game.get_node_or_null("Player/FaceFill") as OmniLight3D
	if player == null or fill == null:
		print("[fillshot] 缺 Player / FaceFill")
		quit(1)
		return

	# 临时墙：直接放在补光正前方（补光在 Player 局部 (0,1.55,0.95)）
	var wall := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(4.0, 3.0, 0.2)
	wall.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.86, 0.84, 0.88)
	mat.roughness = 0.9
	wall.material_override = mat
	game.add_child(wall)
	wall.global_position = player.global_position + Vector3(0.0, 1.4, 1.6)
	print("[fillshot] 临时墙在 %s（玩家 %s）" % [
		str(wall.global_position.snappedf(0.01)), str(player.global_position.snappedf(0.01))])

	var cam := Camera3D.new()
	cam.far = 400.0
	cam.near = 0.05
	cam.fov = 70.0
	root.add_child(cam)
	cam.current = true
	cam.global_position = player.global_position + Vector3(1.6, 1.9, -1.8)
	cam.look_at(player.global_position + Vector3(0.0, 1.35, 0.6), Vector3.UP)

	var role_layers := 0
	for n in player.find_children("*", "MeshInstance3D", true, false):
		role_layers = (n as VisualInstance3D).layers
		break
	print("[fillshot] 角色 layers=%d  墙 layers=%d  FaceFill mask=%d" % [
		role_layers, wall.layers, fill.light_cull_mask])

	fill.light_cull_mask = 0xFFFFFFFF
	await _shot("res://_log/facefill_before.png")

	fill.light_cull_mask = 1 << 1
	await _shot("res://_log/facefill_after.png")
	quit(0)