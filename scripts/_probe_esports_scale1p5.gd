extends SceneTree
## 核对：电竞房 1.5 倍后**是否完全落在铺装内**、室内地面高度是否没变，并出图。
##
## 用户 2026-11-12：「电竞房大小不对，比例放大 1.5 倍，包括碰撞，但是不要超出边界」
## → 方案 A：铺装（边界）跟着一起扩大。
##
## ⚠️ 这个探针**只测量、不改任何东西**（第一版会在内存里改 scale，
##    结果文件改完之后再跑一次就变成 1.5×1.5 = 2.25 倍，坑）。
##    改动全部落在 `scenes/game.tscn` 与 `scenes/lot_east.tscn` 里。
##
## ⚠️ 地面基准的教训：本喵第一版从 y=30 往下打射线量「室内地面」，
##    结果**先撞到屋顶**，量到 3.655（≈节点原点），把基准设错了、房间整体下沉 2.6 m。
##    正确基准是**铺装顶面 y = 0.00**（房间的 BaseSteps 台阶环就在 0.04~0.34，
##    正好坐在铺装面上）。这里直接读铺装 AABB 的顶面。
##
##   godot --path . --script res://scripts/_probe_esports_scale1p5.gd -- --splat=off --story=off

const OFF := preload("res://scripts/offscreen_window.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await OFF.apply(self, Vector2i(1600, 900))
	for _i in 3:
		await process_frame
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 60:
		await process_frame
	paused = false

	var room := game.get_node_or_null("EsportsRoom") as Node3D
	var lot := game.get_node_or_null("LotEast") as Node3D
	if room == null or lot == null:
		print("❌ 找不到 EsportsRoom / LotEast")
		quit(1)
		return
	room.visible = true
	var proxy := game.get_node_or_null("RoomProxy") as Node3D
	if proxy != null:
		proxy.visible = false

	var box := _aabb(room)
	var lb := _aabb(lot)
	print("\n======== 现状 ========")
	print("  EsportsRoom scale = %s   节点原点 y = %.3f"
		% [str(room.scale.snappedf(0.001)), room.global_position.y])
	_print_box("电竞房", box)
	_print_box("铺装 LotEast", lb)
	print("  铺装顶面 y = %.3f（房间地面基准应与它一致）" % lb.end.y)

	var ok_x := box.position.x >= lb.position.x and box.end.x <= lb.end.x
	var ok_z := box.position.z >= lb.position.z and box.end.z <= lb.end.z
	print("\n======== 判定 ========")
	print("  房间尺寸 = %.2f × %.2f m（XZ）" % [box.size.x, box.size.z])
	print("  X 方向在铺装内：%s   Z 方向在铺装内：%s" % [str(ok_x), str(ok_z)])
	print("  四边余量：-X %.2f / +X %.2f / -Z %.2f / +Z %.2f m"
		% [box.position.x - lb.position.x, lb.end.x - box.end.x,
			box.position.z - lb.position.z, lb.end.z - box.end.z])
	print("  房间底面 y = %.2f（低于铺装顶面是地基，正常）  顶面 y = %.2f"
		% [box.position.y, box.end.y])

	# 出图
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_esports_scale")
	DirAccess.make_dir_recursive_absolute(out)
	var cam := Camera3D.new()
	cam.far = 600.0
	game.add_child(cam)
	for shot in [
		{"n": "topdown", "p": Vector3(53.0, 60.0, 13.0), "t": Vector3(53.0, 0.0, 13.0), "f": 60.0},
		{"n": "iso", "p": Vector3(30.0, 14.0, -16.0), "t": Vector3(53.0, 2.0, 13.0), "f": 55.0},
		{"n": "inside", "p": Vector3(49.0, 1.7, 13.0), "t": Vector3(64.0, 1.2, 13.0), "f": 72.0},
	]:
		cam.fov = float(shot["f"])
		cam.global_position = shot["p"]
		cam.look_at(shot["t"], Vector3.UP if String(shot["n"]) != "topdown" else Vector3.FORWARD)
		cam.make_current()
		await process_frame
		await process_frame
		cam.make_current()
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out.path_join("%s.png" % String(shot["n"])))
			print("  [img] %s" % out.path_join("%s.png" % String(shot["n"])))
	quit(0)


func _print_box(name: String, b: AABB) -> void:
	print("  %-16s XZ x %.2f~%.2f / z %.2f~%.2f   y %.2f~%.2f   size=(%.2f, %.2f, %.2f)"
		% [name, b.position.x, b.end.x, b.position.z, b.end.z,
			b.position.y, b.end.y, b.size.x, b.size.y, b.size.z])


func _aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var b: AABB = m.global_transform * m.mesh.get_aabb()
		out = b if first else out.merge(b)
		first = false
	for ci in n.find_children("*", "CollisionShape3D", true, false):
		var cs := ci as CollisionShape3D
		if cs.shape is BoxShape3D:
			var half: Vector3 = cs.global_transform.basis.get_scale().abs() \
				* (cs.shape as BoxShape3D).size * 0.5
			var b := AABB(cs.global_position - half, half * 2.0)
			out = b if first else out.merge(b)
			first = false
	return out
