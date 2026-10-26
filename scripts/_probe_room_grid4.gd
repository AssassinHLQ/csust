extends SceneTree
## 把网格画在**桌面高度**（y = 0.79）并标上世界坐标文字 —— 桌角落在哪两条线之间一眼可读。
##   godot --path . --script res://scripts/_probe_room_grid4.gd
##
## 前三次的教训：
##   ① 射线打不通（泼溅没碰撞）→ 只能看图；
##   ② 正交俯视 y=40 全是天花板；
##   ③ 正交俯视 y=2.6 泼溅糊成白噪；
##   ④ 地面网格（y=0.04）被桌子挡住 → 看不到桌沿落在哪条线。
##
## 这次：网格抬到 **y = 0.79**（桌面 0.78 之上 1 cm，视差 ≈ 1 px），
## 每 0.25 m 一条细线、每 0.5 m 一条中线、每 1 m 一条粗线 + 一个 `Label3D` 标号。
## 桌沿落在哪两条线之间，直接读得出来。
##
## 出图：_arisu_captures/_fix1026/{g7_deskgrid, g7_deskzoom}.png

const OUT := "_arisu_captures/_fix1026"
const GRID_Y := 0.79
var _out_abs := ""


func _initialize() -> void:
	_run.call_deferred()


func _shot(cam: Camera3D, nm: String) -> void:
	cam.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [_out_abs, nm])


func _line(game: Node3D, centre: Vector3, size: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.position = centre
	game.add_child(mi)


func _label(game: Node3D, pos: Vector3, txt: String, col: Color) -> void:
	var lb := Label3D.new()
	lb.text = txt
	lb.font_size = 64
	lb.pixel_size = 0.0030          # 64 × 0.0030 ≈ 0.19 m 高
	lb.outline_size = 12
	lb.outline_modulate = Color(0, 0, 0, 0.85)
	lb.modulate = col
	lb.no_depth_test = true         # 字永远压在最上面，桌子挡不住
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.shaded = false
	lb.position = pos
	game.add_child(lb)


func _run() -> void:
	root.size = Vector2i(1600, 1100)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 150:
		await process_frame
	paused = false
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join(OUT)
	DirAccess.make_dir_recursive_absolute(out)
	_out_abs = out
	for c in game.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
	for c in game.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false

	var sensei := game.get_node_or_null("Sensei") as Node3D
	var sp := sensei.global_position
	print("老师锚点 (%.2f, %.2f, %.2f)" % [sp.x, sp.y, sp.z])

	# 只铺桌子四周那一小片：x −1.5 ~ +3.0、z 0.0 ~ +5.0
	var x0 := -1.5
	var x1 := 3.0
	var z0 := 0.0
	var z1 := 5.0
	var x := x0
	while x <= x1 + 0.001:
		var is_int := absf(x - roundf(x)) < 0.01
		var is_half := absf(x * 2.0 - roundf(x * 2.0)) < 0.01
		var w := 0.030 if is_int else (0.014 if is_half else 0.007)
		var col := Color(0.0, 1.0, 1.0) if is_int else (
			Color(0.0, 0.6, 0.7) if is_half else Color(0.0, 0.35, 0.45))
		_line(game, Vector3(x, GRID_Y, (z0 + z1) * 0.5),
			Vector3(w, 0.004, z1 - z0), col)
		if is_int:
			_label(game, Vector3(x, GRID_Y + 0.02, z0 - 0.12), "x%+.0f" % x,
				Color(0.0, 1.0, 1.0))
		x += 0.25
	var z := z0
	while z <= z1 + 0.001:
		var is_int2 := absf(z - roundf(z)) < 0.01
		var is_half2 := absf(z * 2.0 - roundf(z * 2.0)) < 0.01
		var w2 := 0.030 if is_int2 else (0.014 if is_half2 else 0.007)
		var col2 := Color(1.0, 0.62, 0.0) if is_int2 else (
			Color(0.7, 0.42, 0.0) if is_half2 else Color(0.45, 0.28, 0.0))
		_line(game, Vector3((x0 + x1) * 0.5, GRID_Y, z),
			Vector3(x1 - x0, 0.004, w2), col2)
		if is_int2:
			_label(game, Vector3(x0 - 0.16, GRID_Y + 0.02, z), "z%+.0f" % z,
				Color(1.0, 0.75, 0.2))
		z += 0.25
	print("网格已铺在 y = %.2f（桌面 0.78 之上 1 cm）；青色 = x 常值，橙色 = z 常值" % GRID_Y)
	print("细线 0.25 m、中线 0.5 m、粗线 1 m；整米处有 Label3D 标号")

	var cam := Camera3D.new()
	cam.near = 0.05
	cam.far = 400.0
	root.add_child(cam)
	cam.fov = 50.0
	cam.global_position = Vector3(sp.x - 0.30, 3.20, sp.z + 3.60)
	cam.look_at(Vector3(sp.x - 0.80, 0.60, sp.z + 0.10), Vector3.UP)
	await _shot(cam, "g7_deskgrid")

	cam.fov = 40.0
	cam.global_position = Vector3(sp.x - 1.00, 2.10, sp.z + 2.60)
	cam.look_at(Vector3(sp.x - 1.20, 0.70, sp.z - 0.10), Vector3.UP)
	await _shot(cam, "g7_deskzoom")
	print("\n[截图] %s" % out)
	quit(0)
