extends SceneTree
## 量「真正的瞄准点」和「准星中心」各在哪个设备像素 —— 判断准星到底有没有偏。
##
## 做法：
##   ① 在相机正前方 0.5 m 放一个**无深度测试**的红色小球（屏幕空间里是个圆斑），
##      它的**像素重心**就是相机光轴落点 = 真正的瞄准点；
##   ② 藏掉准星拍一张，取红球重心；
##   ③ 亮出准星、藏掉红球拍一张，取准星像素包围盒与四条臂的间隙。
##
## 用法：_tools/run_shot.sh res://scripts/_probe_aim_vs_cross.gd
## 出图：_arisu_captures/_crosshair/{aim,cross}.png

const OUT_DIR := "_arisu_captures/_crosshair"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(2560, 1334)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 90:
		await process_frame
	paused = false
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out)

	var hud := game.get_node_or_null("HUD") as CanvasLayer
	var cross := game.get_node_or_null("HUD/Crosshair") as Control
	if hud == null or cross == null:
		print("[错误] 没有 HUD/Crosshair")
		quit(1)
		return

	# 只留 HUD 以外的 3D 世界：先藏掉所有 CanvasLayer
	for c in game.find_children("*", "CanvasLayer", true, false):
		var cl: CanvasLayer = c as CanvasLayer
		if cl != null:
			cl.visible = false

	var cam := game.get_viewport().get_camera_3d()
	if cam == null:
		print("[错误] 没找到 Camera3D")
		quit(1)
		return

	# 红球：小、无光照、无深度测试，画在所有 3D 之上
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.1
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 0, 0)
	mat.no_depth_test = true
	mi.material_override = mat
	mi.top_level = true
	game.add_child(mi)
	mi.global_position = cam.global_position + (-cam.global_basis.z) * 0.5
	for _f in 5:
		await process_frame

	# ① 瞄准点
	for _f in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var aim_img := root.get_texture().get_image()
	aim_img.save_png(out.path_join("aim.png"))
	var aim := _red_centroid(aim_img)
	print("瞄准点（红球重心）= %s" % str(aim))
	if aim == Vector2.ZERO:
		print("[警告] 红球没找到 —— 相机 %s，球 %s"
			% [str(cam.global_position), str(mi.global_position)])

	# ② 准星：先把 3D 世界（含红球）全藏掉，只留 HUD，逐像素相减才干净
	mi.visible = false
	for c in game.get_children():
		if c is Node3D:
			(c as Node3D).visible = false
	hud.visible = true
	for _f in 30:
		await process_frame
	hud.set_process(false)
	hud.call("_layout_crosshair")
	for _f in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var cross_img := root.get_texture().get_image()
	cross_img.save_png(out.path_join("cross.png"))
	cross.visible = false
	for _f in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var clean_img := root.get_texture().get_image()
	cross.visible = true

	var m := _diff_mask(cross_img, clean_img)
	print("准星像素重心 = %s；包围盒 %s" % [str(m["center"]), str(m["bbox"])])
	if aim != Vector2.ZERO and m["center"] != Vector2.ZERO:
		var d: Vector2 = (m["center"] as Vector2) - aim
		print("\n准星重心 - 瞄准点 = (%.3f, %.3f) 设备像素" % [d.x, d.y])
		print("（±0.5 以内是「像素中心 vs 格角」的物理极限，做不到更小）")
	quit(0)


## 红色像素的重心（红球）。只扫中心 ±120 px，避免场景里的红色物体混进来。
func _red_centroid(img: Image) -> Vector2:
	var sx := 0.0
	var sy := 0.0
	var n := 0
	var cx := img.get_width() / 2
	var cy := img.get_height() / 2
	for y in range(cy - 120, cy + 120):
		for x in range(cx - 120, cx + 120):
			var c := img.get_pixel(x, y)
			if c.r > 0.6 and c.g < 0.35 and c.b < 0.35:
				sx += x + 0.5
				sy += y + 0.5
				n += 1
	if n == 0:
		return Vector2.ZERO
	return Vector2(sx / n, sy / n)


## 准星像素（「有准星」与「无准星」两张图逐像素相减）的重心与包围盒。只扫中心 ±60 px。
func _diff_mask(a: Image, b: Image) -> Dictionary:
	var sx := 0.0
	var sy := 0.0
	var n := 0
	var mn := Vector2i(a.get_width(), a.get_height())
	var mx := Vector2i(-1, -1)
	var cx := a.get_width() / 2
	var cy := a.get_height() / 2
	for y in range(cy - 60, cy + 60):
		for x in range(cx - 60, cx + 60):
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				sx += x + 0.5
				sy += y + 0.5
				n += 1
				mn.x = mini(mn.x, x)
				mn.y = mini(mn.y, y)
				mx.x = maxi(mx.x, x)
				mx.y = maxi(mx.y, y)
	if n == 0:
		return {"center": Vector2.ZERO, "bbox": Rect2i()}
	return {"center": Vector2(sx / n, sy / n), "bbox": Rect2i(mn, mx - mn + Vector2i.ONE)}
