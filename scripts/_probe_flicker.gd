extends SceneTree
## 探针：把相机在店面前挪 5 mm 渲两帧，逐像素比对 —— 闪烁的面在两帧里会明显不同。
## 再把「差异像素」反查到屏幕坐标附近的网格（按屏幕空间 AABB 命中）。
##   godot --path . --script res://scripts/_probe_flicker.gd -- --splat=off
## 输出：_arisu_captures/_flicker/{a,b,diff}.png
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 60:
		await process_frame
	paused = false
	var hud := game.get_node_or_null("HUD") as CanvasLayer
	if hud != null:
		hud.visible = false
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_flicker")
	DirAccess.make_dir_recursive_absolute(out)

	# 店面那面幕墙：世界 z 最小那一面（金南面 = 门那侧）
	var shop := game.get_node_or_null("Shop") as Node3D
	var shop_aabb := AABB()
	var first := true
	for mi in shop.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var a := m.global_transform * m.mesh.get_aabb()
		if first:
			shop_aabb = a
			first = false
		else:
			shop_aabb = shop_aabb.merge(a)
	var facade := Vector3(shop_aabb.get_center().x, 2.6, shop_aabb.position.z)
	print("店铺 AABB %s  立面取 %s" % [str(shop_aabb.size.snappedf(0.1)),
		str(facade.snappedf(0.1))])

	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.near = 0.05
	cam.far = 200.0
	root.add_child(cam)
	cam.global_position = facade + Vector3(-6.0, 0.6, -9.0)
	cam.look_at(facade + Vector3(0, 0.6, 0), Vector3.UP)
	cam.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var a_img := root.get_texture().get_image()
	a_img.save_png(out.path_join("a.png"))

	cam.global_position += Vector3(0.005, 0.0, 0.005)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var b_img := root.get_texture().get_image()
	b_img.save_png(out.path_join("b.png"))

	# 逐像素差
	var w := a_img.get_width()
	var h := a_img.get_height()
	var diff := Image.create(w, h, false, Image.FORMAT_RGB8)
	var bad := 0
	var minx := w
	var maxx := 0
	var miny := h
	var maxy := 0
	for y in h:
		for x in w:
			var ca := a_img.get_pixel(x, y)
			var cb := b_img.get_pixel(x, y)
			var d := absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			if d > 0.06:
				bad += 1
				minx = mini(minx, x)
				maxx = maxi(maxx, x)
				miny = mini(miny, y)
				maxy = maxi(maxy, y)
				diff.set_pixel(x, y, Color(1, 0, 0))
			else:
				diff.set_pixel(x, y, Color(0.1, 0.1, 0.1))
	diff.save_png(out.path_join("diff.png"))
	print("差异像素 %d 个（阈值 0.06），包围盒 x %d..%d  y %d..%d" % [bad, minx, maxx, miny, maxy])

	# 反查：把每个网格的 AABB 八角投到屏幕，命中包围盒的列出来
	var cand := []
	for mi in shop.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var a := m.global_transform * m.mesh.get_aabb()
		var sx0 := INF
		var sx1 := -INF
		var sy0 := INF
		var sy1 := -INF
		for i in 8:
			var p := a.position + Vector3(
				a.size.x * float(i & 1), a.size.y * float((i >> 1) & 1),
				a.size.z * float((i >> 2) & 1))
			if cam.is_position_behind(p):
				continue
			var s := cam.unproject_position(p)
			sx0 = minf(sx0, s.x)
			sx1 = maxf(sx1, s.x)
			sy0 = minf(sy0, s.y)
			sy1 = maxf(sy1, s.y)
		if sx0 == INF:
			continue
		if sx1 > float(minx) and sx0 < float(maxx) and sy1 > float(miny) and sy0 < float(maxy):
			cand.append("%s(屏幕 %.0f..%.0f, %.0f..%.0f)" % [m.name, sx0, sx1, sy0, sy1])
	print("差异区域内的候选网格 %d 个：" % cand.size())
	for c in cand.slice(0, 12):
		print("   " + c)
	print("[截图] %s" % out)
	quit(0)
