extends SceneTree
## 探针：新 Boss「倭瓜优香」装进 `game.tscn` 之后对不对 —— 出图 + 打印绑定情况。
##
## 查四件事：
##   1. 节点真的被 `game.gd` 按类型收到了（三位 Boss）
##   2. 模型载入（`.obj` 走的是 `Mesh` 分支，见 `boss.gd::_build_model`）
##   3. 4 个材质各自的贴图有没有绑上（`texture_map` 的键对不对）
##   4. 朝向 / 尺寸 / 碰撞盒：出两张图（正面 + 3/4）人眼确认
##
## 用法：godot --path <工程> --script res://scripts/_probe_boss_squash_shot.gd -- --splat=off
## 输出：`_arisu_captures/_boss/70_squash_front.png` / `71_squash_quarter.png`

var _cam: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 20:
		await process_frame
	for n in ["HUD", "SettingsMenu", "DialogueBox", "Parkour/ParkourHUD"]:
		var c := game.get_node_or_null(n) as CanvasLayer
		if c != null:
			c.visible = false
	var bosses: Array = []
	for ch in game.get_children():
		if ch is Boss:
			bosses.append(ch)
	print("[probe] 场上 Boss %d 位：%s"
		% [bosses.size(), ", ".join(bosses.map(func(b): return (b as Boss).display_name))])
	var sq := game.get_node_or_null("BossSquash") as Boss
	if sq == null:
		print("!! 场景里没有 BossSquash")
		quit(1)
		return
	print("[probe] 倭瓜优香：血 %.0f/%.0f，身高 %.2f，碰撞盒 %s，模型 %s"
		% [sq.health, sq.max_health, sq.visual_size.y,
			str(sq.get_node_or_null("Collision").shape.get_rect().size) if false else "-",
			"载入" if sq.model != null else "**没载入**"])
	var meshes := _all(sq, "MeshInstance3D")
	print("[probe] 网格 %d 个" % meshes.size())
	for mi in meshes:
		var m := mi as MeshInstance3D
		var am := m.mesh as ArrayMesh
		if am == null:
			continue
		for s in am.get_surface_count():
			var mat := am.surface_get_material(s)
			var key := ""
			var tex := ""
			if mat is StandardMaterial3D:
				var sm := mat as StandardMaterial3D
				key = sm.resource_name
				if sm.albedo_texture != null:
					tex = sm.albedo_texture.resource_path.get_file()
			print("    surface %d  「%s」→ %s" % [s, key, tex if tex != "" else "**无贴图**"])

	var out_dir := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_boss")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_cam = Camera3D.new()
	_cam.fov = 45.0
	_cam.near = 0.05
	_cam.far = 300.0
	root.add_child(_cam)
	_cam.make_current()
	var c := sq.global_position + Vector3(0, sq.visual_size.y * 0.5, 0)
	_cam.global_position = c + Vector3(0, 0.4, -9.0)      # 从北侧看它的正面（它朝 -Z）
	_cam.look_at(c, Vector3.UP)
	await _shot(out_dir.path_join("70_squash_front.png"))
	_cam.global_position = c + Vector3(6.4, 2.4, -6.4)
	_cam.look_at(c, Vector3.UP)
	await _shot(out_dir.path_join("71_squash_quarter.png"))
	print("\n出图目录：%s" % out_dir)
	quit(0)


func _shot(path: String) -> void:
	var before := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	while Engine.get_frames_drawn() == before and Time.get_ticks_msec() - t0 < 2000:
		await process_frame
	for _i in 6:
		await process_frame
	root.get_texture().get_image().save_png(path)
	print("[shot] %s" % path.get_file())


func _all(node: Node, cls: String) -> Array:
	var out: Array = []
	if node.is_class(cls):
		out.append(node)
	for c in node.get_children():
		out.append_array(_all(c, cls))
	return out
