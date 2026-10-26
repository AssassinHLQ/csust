extends SceneTree
## 画室家具定标 v2：**正交俯视 + 已知锚点 + 网格**，把每件家具读到 0.25 m。
##   godot --path . --script res://scripts/_probe_room_grid2.gd
##
## ⚠️ 为什么是「看图」而不是射线：画室 609 是高斯泼溅，**泼溅没有碰撞体** ——
##    射线只打得到 `Room609/RoomCollision` 那 5 面墙，桌子/椅子/画架一个都打不到。
##
## ⚠️ 相机为什么架在 y = 40 而不是屋里：正交相机进到 y = 2.60 时，泼溅的排序在
##    近距离下会糊成一片白噪（上一版 `grid_desk.png` 就是）；y = 40 远距离俯视反而
##    能看到干净的地面颜色。
##
## 锚点：老师（`Sensei`）的世界坐标是**已知的**（1.80, 0.00, 2.60，`game.tscn` 量的），
## 这里在它脚下放一块 0.36 × 0.36 m 的**纯红**方块 —— 图上找到它就能把
## 「像素 → 世界」钉死，再靠 0.25 m 的网格线读别的家具。
##
## 出图：_arisu_captures/_fix1026/{g2_all, g2_desk, g2_desk_zoom}.png

const OUT := "_arisu_captures/_fix1026"
const CELL := 0.25
## 出图用的正交高度（远处俯视才干净）
const CAM_Y := 40.0
var _out_abs := ""


func _initialize() -> void:
	_run.call_deferred()


func _shot(cam: Camera3D, nm: String) -> void:
	cam.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [_out_abs, nm])


func _box(game: Node3D, pos: Vector3, size: Vector3, col: Color, no_depth := true) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = no_depth
	mi.material_override = m
	mi.position = pos
	game.add_child(mi)


func _grid(game: Node3D, lo: Vector3, hi: Vector3, y: float) -> void:
	var x := floorf(lo.x)
	while x <= hi.x + 0.01:
		var major := absf(x - roundf(x)) < 0.01
		_box(game, Vector3(x, y, (lo.z + hi.z) * 0.5),
			Vector3(0.022 if major else 0.006, 0.004, hi.z - lo.z),
			Color(0.05, 0.85, 1.0) if major else Color(0.35, 0.90, 1.0, 0.5))
		x += CELL
	var z := floorf(lo.z)
	while z <= hi.z + 0.01:
		var major2 := absf(z - roundf(z)) < 0.01
		_box(game, Vector3((lo.x + hi.x) * 0.5, y, z),
			Vector3(hi.x - lo.x, 0.004, 0.022 if major2 else 0.006),
			Color(1.0, 0.55, 0.10) if major2 else Color(1.0, 0.75, 0.40, 0.5))
		z += CELL


func _run() -> void:
	root.size = Vector2i(1600, 1200)
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

	var body := game.get_node_or_null("Room609/RoomCollision") as Node3D
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for c in body.get_children():
		var cs := c as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		var s: Vector3 = (cs.shape as BoxShape3D).size
		if minf(minf(s.x, s.y), s.z) > 0.35:
			continue
		var b: AABB = cs.global_transform * AABB(-s * 0.5, s)
		lo = lo.min(b.position)
		hi = hi.max(b.position + b.size)

	# 网格铺在 y = 1.60（比绝大多数家具高），no_depth_test ⇒ 永远压在家具上面
	_grid(game, lo, hi, 1.60)
	# 锚点：纯红方块（老师脚下）+ 纯绿方块（老师西侧 1 m、南侧 1 m，用来自检刻度）
	_box(game, Vector3(sp.x, 1.62, sp.z), Vector3(0.36, 0.004, 0.36), Color(1, 0, 0))
	_box(game, Vector3(sp.x - 1.0, 1.62, sp.z), Vector3(0.18, 0.004, 0.18), Color(0, 1, 0))
	_box(game, Vector3(sp.x, 1.62, sp.z + 1.0), Vector3(0.18, 0.004, 0.18), Color(0, 0, 1))
	print("锚点：红 = 老师站位，绿 = 他西侧 1 m，蓝 = 他南侧 1 m")

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.near = 1.0
	cam.far = 200.0
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	root.add_child(cam)
	cam.global_position = Vector3((lo.x + hi.x) * 0.5, CAM_Y, (lo.z + hi.z) * 0.5)
	cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)

	cam.size = maxf(hi.x - lo.x, hi.z - lo.z) * 1.05
	await _shot(cam, "g2_all")
	print("g2_all：中心 (%.2f, %.2f)、正交高 %.2f m"
		% [(lo.x + hi.x) * 0.5, (lo.z + hi.z) * 0.5, cam.size])

	cam.size = 6.0
	cam.global_position = Vector3(1.0, CAM_Y, 2.6)
	await _shot(cam, "g2_desk")
	print("g2_desk：中心 (1.00, 2.60)、正交高 6.00 m（每格 0.25 m）")

	cam.size = 2.6
	cam.global_position = Vector3(0.6, CAM_Y, 2.6)
	await _shot(cam, "g2_desk_zoom")
	print("g2_desk_zoom：中心 (0.60, 2.60)、正交高 2.60 m")
	print("\n[截图] %s" % out)
	quit(0)
