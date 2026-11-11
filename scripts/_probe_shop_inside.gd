extends SceneTree
## 探针：柴关电脑城**室内**到底亮不亮 —— 先找对机位，再测。
##
## ⚠️ 为什么返工：`_probe_shop_light_budget.gd` 用 `sp + (0, 1.62, +6.0)` 当视点，
##    结果整块墙糊成一片纯白 —— 相机其实**埋进了墙/柜体里**，
##    拍到的不是室内景。那种图上的"过曝比例"是假的。
##    本探针先沿 -Z 打射线找一个**确实在店里面、且前面没有遮挡**的落点，再拍。
##
## 用法：& <godot_console.exe> --path . --script res://scripts/_probe_shop_inside.gd -- --splat=off --no-capture
## 出图：_arisu_captures/_shop_inside/{12,21}_*.png

const OffWin := preload("res://scripts/offscreen_window.gd")
const OUT_DIR := "_shop_inside"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await OffWin.apply(self, Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)

	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 150:
		await process_frame
	paused = false
	for _f in 30:
		await process_frame
	for c in game.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false

	var shop := game.get_node_or_null("Shop") as Node3D
	if shop == null:
		print("[错误] 没有 Shop")
		quit(1)
		return
	var sp := shop.global_position
	var tod := get_root().get_node_or_null("TimeOfDay")
	if tod != null:
		tod.call("set_day_minutes", 0.0)

	# ── ① 先摸清店的真实范围（沿门中线 -Z 打射线）──
	# 店门朝 -Z（`shop_baked.tscn` 里 SignBoard 在 z = +3.06，门牌朝外）
	print("\n① 沿门中线打射线（x = %.2f，y = 1.62）" % sp.x)
	var space := shop.get_world_3d().direct_space_state
	var z := sp.z + 14.0
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(sp.x, 1.62, z), Vector3(sp.x, 1.62, z - 30.0))
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		print("   没打到东西 —— 门中线是空的")
	else:
		print("   打进 在 z = %.2f  %s" % [(hit["position"] as Vector3).z, str(hit["collider"])])

	# ── ② 用探针射线逐点扫，找"最里面且不贴墙"的落点 ──
	# 从门外往店里，每隔 0.5 m 取一个候选，量它到**后方 1.5 m 内**有没有东西挡
	var inside: Array[Vector3] = []
	var zz := sp.z + 8.0
	while zz > sp.z - 12.0:
		var q2 := PhysicsRayQueryParameters3D.create(
			Vector3(sp.x, 1.62, zz), Vector3(sp.x, 1.62, zz - 2.0))
		q2.collide_with_areas = false
		var h2 := space.intersect_ray(q2)
		if h2.is_empty():
			inside.append(Vector3(sp.x, 1.62, zz))
		zz -= 0.5
	print("   无遮挡落点 %d 个" % inside.size())
	for p in inside:
		print("     世界 (%.2f, %.2f, %.2f)  局部 (%.2f, %.2f, %.2f)"
			% [p.x, p.y, p.z, p.x - sp.x, p.y - sp.y, p.z - sp.z])

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out)

	var cam := Camera3D.new()
	cam.near = 0.05
	cam.far = 500.0
	cam.fov = 70.0
	root.add_child(cam)

	# 取最靠里的那个落点，朝门外（+Z）看 —— 这样能看到货架、柜台、门口
	var eye: Vector3 = inside[inside.size() - 1] if not inside.is_empty() \
		else Vector3(sp.x, 1.62, sp.z)
	print("\n② 定机位 %s（朝 +Z 看，即朝门口）" % str(eye.round()))

	cam.global_position = eye
	# 门在 +Z 方向（SignBoard z=+3.06），朝那边看才能看到"店里往门口"
	cam.look_at(Vector3(eye.x, 1.35, eye.z + 9.0), Vector3.UP)

	for h in [12.0, 21.0]:
		if tod != null:
			tod.call("set_hours", h)
		for _f in 60:
			await process_frame
		await _shot(cam, out, "%02d_look_out" % int(h), "朝门口")

	# 反向：朝店里最深处看
	cam.global_position = Vector3(sp.x, 1.62, sp.z + 5.5)
	cam.look_at(Vector3(sp.x, 1.35, sp.z - 6.0), Vector3.UP)
	for h in [12.0, 21.0]:
		if tod != null:
			tod.call("set_hours", h)
		for _f in 60:
			await process_frame
		await _shot(cam, out, "%02d_look_in" % int(h), "朝深处")

	print("\n[截图] %s" % out)
	quit(0)


func _shot(cam: Camera3D, out: String, nm: String, note: String) -> void:
	cam.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [out, nm])
	print("   %-14s %s → %s" % [nm, note, _stats(img)])


func _stats(img: Image) -> String:
	var a := img.duplicate() as Image
	a.convert(Image.FORMAT_RGBA8)
	var data := a.get_data()
	var n := a.get_width() * a.get_height()
	var blown := 0
	var sum := 0.0
	for i in n:
		var o := i * 4
		var r := data[o]
		var g := data[o + 1]
		var b := data[o + 2]
		if r >= 245 and g >= 245 and b >= 245:
			blown += 1
		sum += 0.2126 * float(r) + 0.7152 * float(g) + 0.0722 * float(b)
	return "过曝 %.2f%%｜平均 %.1f" % [100.0 * float(blown) / float(n), sum / float(n)]
