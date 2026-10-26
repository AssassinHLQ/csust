extends SceneTree
## 画室家具**视觉定标**：正交俯视 + 悬空网格，把每件家具的位置读到 0.25 m。
##   godot --path . --script res://scripts/_probe_room_grid.gd
##
## ⚠️ 为什么不用射线：这间画室是**高斯泼溅**，泼溅**没有碰撞体** ——
##    射线只打得到 `Room609/RoomCollision` 那 5 面墙，家具一个都打不到
##    （上一版扫出来的「家具候选」全是噪声，桌子根本没进结果）。
##    所以改成**看图量**：正交相机垂直往下，在 y = 1.15（比桌面 0.78 高）铺一层
##    网格线 —— 网格盖在桌面之上，图上一格 0.25 m，直接数格子。
##
## 出图：_arisu_captures/_fix1026/grid_top.png（整间）
##       _arisu_captures/_fix1026/grid_desk.png（桌子附近放大）

const OUT := "_arisu_captures/_fix1026"
const CELL := 0.25
var _out_abs := ""


func _initialize() -> void:
	_run.call_deferred()


func _shot(cam: Camera3D, nm: String) -> void:
	cam.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [_out_abs, nm])


## 一条水平细线（贴地，宽 0.012 m）
func _line(game: Node3D, a: Vector3, b: Vector3, y: float, w: float, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(maxf(absf(b.x - a.x), w), 0.004, maxf(absf(b.z - a.z), w))
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = true          # ← 关键：网格永远画在最上面，桌子挡不住
	mi.material_override = m
	mi.position = Vector3((a.x + b.x) * 0.5, y, (a.z + b.z) * 0.5)
	game.add_child(mi)


func _run() -> void:
	root.size = Vector2i(1200, 1500)
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

	# 房间内框（从五面墙反推）
	var body := game.get_node_or_null("Room609/RoomCollision") as Node3D
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	if body != null:
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
	print("房间内框 x %.2f~%.2f  z %.2f~%.2f" % [lo.x, hi.x, lo.z, hi.z])

	# 网格：y = 1.15（比桌面高），每 0.25 m 一条细线、每 1 m 一条粗线
	var gy := 1.15
	var x := floorf(lo.x)
	while x <= hi.x + 0.01:
		var major := absf(x - roundf(x)) < 0.01
		_line(game, Vector3(x, gy, lo.z), Vector3(x, gy, hi.z), gy,
			0.030 if major else 0.008,
			Color(0.10, 0.75, 0.95) if major else Color(0.45, 0.85, 1.0, 0.55))
		x += CELL
	var z := floorf(lo.z)
	while z <= hi.z + 0.01:
		var major2 := absf(z - roundf(z)) < 0.01
		_line(game, Vector3(lo.x, gy, z), Vector3(hi.x, gy, z), gy,
			0.030 if major2 else 0.008,
			Color(0.95, 0.55, 0.15) if major2 else Color(1.0, 0.75, 0.45, 0.55))
		z += CELL
	print("网格已铺：y = %.2f，细线 %.2f m、粗线每 1 m（蓝 = x 常值，橙 = z 常值）" % [gy, CELL])
	# 原点十字（x=0 / z=0）
	_line(game, Vector3(0, gy, lo.z), Vector3(0, gy, hi.z), gy, 0.06, Color(1, 0.15, 0.15))
	_line(game, Vector3(lo.x, gy, 0), Vector3(hi.x, gy, 0), gy, 0.06, Color(1, 0.15, 0.15))
	print("红色十字 = x / z 的原点")

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.near = 0.05
	cam.far = 200.0
	root.add_child(cam)
	# ⚠️ 相机必须**在屋里**（y = 2.60，天花板在 8 m）：正交相机架在 y = 40 时
	#    先穿过天花板，泼溅渲出来的是屋顶顶面（上一版就是一整屏糊掉的粉色）。
	#    放到 2.60 之后天花板在相机背后，画面里只剩地面和家具。
	#    网格线画在 y = 1.15、且 `no_depth_test`，永远压在桌面之上。
	cam.global_position = Vector3((lo.x + hi.x) * 0.5, 2.60, (lo.z + hi.z) * 0.5)
	cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	# 整间俯视
	cam.size = maxf(hi.x - lo.x, hi.z - lo.z) * 1.06
	await _shot(cam, "grid_top")
	# 桌子附近放大（老师 (1.8, 2.6) 西侧 3 m 范围）
	cam.size = 4.2
	cam.global_position = Vector3(1.2, 2.60, 2.8)
	await _shot(cam, "grid_desk")
	print("\n[截图] %s（grid_top 整间 / grid_desk 桌子附近，正交俯视）" % out)
	quit(0)
