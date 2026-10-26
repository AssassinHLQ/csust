extends SceneTree
## 画室家具定标 v3：**贴地网格 + 斜视机位**（这个机位在前面验证过能看清桌子）。
##   godot --path . --script res://scripts/_probe_room_grid3.gd
##
## 三次踩坑记录（写给以后的我）：
##   ① 射线打不通：画室是高斯泼溅，**泼溅没有碰撞体**，射线只打得到 5 面墙。
##   ② 正交俯视 y = 40：泼溅把**天花板**也画出来，整屏是一层粉色，什么家具都看不见。
##   ③ 正交俯视 y = 2.60（屋里）：泼溅在近距离的正交投影下糊成白噪。
##   ④ **不要给网格线开 `no_depth_test`**：开了就永远画在最上层，桌子完全被网格盖住，
##      看不出轮廓。这里网格**贴地 y = 0.04 且正常深度测试** —— 桌子会把网格挡住，
##      于是「网格在哪里断掉」就是桌子的边界，这才是能量出来的信息。
##
## 出图：_arisu_captures/_fix1026/{g3_desk, g3_desk_hi, g3_room}.png

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


func _box(game: Node3D, pos: Vector3, size: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.position = pos
	game.add_child(mi)


func _floor_grid(game: Node3D, lo: Vector3, hi: Vector3, y: float) -> void:
	var x := floorf(lo.x)
	while x <= hi.x + 0.01:
		var major := absf(x - roundf(x)) < 0.01
		_box(game, Vector3(x, y, (lo.z + hi.z) * 0.5),
			Vector3(0.020 if major else 0.005, 0.006, hi.z - lo.z),
			Color(0.05, 0.55, 1.0) if major else Color(0.35, 0.70, 1.0))
		x += CELL
	var z := floorf(lo.z)
	while z <= hi.z + 0.01:
		var major2 := absf(z - roundf(z)) < 0.01
		_box(game, Vector3((lo.x + hi.x) * 0.5, y, z),
			Vector3(hi.x - lo.x, 0.006, 0.020 if major2 else 0.005),
			Color(1.0, 0.45, 0.05) if major2 else Color(1.0, 0.65, 0.30))
		z += CELL


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

	# 网格贴在**地面**（y = 0.04），正常深度测试 ⇒ 桌子挡得住它
	_floor_grid(game, lo, hi, 0.04)
	# 锚点：红方块 = 老师站位（0.40 m 见方，够显眼）
	_box(game, Vector3(sp.x, 0.05, sp.z), Vector3(0.40, 0.008, 0.40), Color(1, 0, 0))
	print("地面网格已铺：每 %.2f m 一条细线，每 1 m 一条粗线（蓝 = x 常值、橙 = z 常值）" % CELL)
	print("红方块 = 老师站位（1.80, 2.60），边长 0.40 m —— 拿它当尺子")

	var cam := Camera3D.new()
	cam.near = 0.05
	cam.far = 400.0
	root.add_child(cam)

	# ① 和 `desk_top.png` 同一个机位（那个机位渲得最清楚）
	cam.fov = 60.0
	cam.global_position = Vector3(sp.x - 0.60, 2.80, sp.z + 4.20)
	cam.look_at(Vector3(sp.x + 0.20, 0.20, sp.z - 0.40), Vector3.UP)
	await _shot(cam, "g3_desk")

	# ② 更高一点、更正一点，桌子在画面中央
	cam.fov = 45.0
	cam.global_position = Vector3(sp.x - 0.20, 3.60, sp.z + 3.40)
	cam.look_at(Vector3(sp.x - 0.60, 0.10, sp.z + 0.20), Vector3.UP)
	await _shot(cam, "g3_desk_hi")

	# ③ 整间（从南墙内往前看）
	cam.fov = 75.0
	cam.global_position = Vector3((lo.x + hi.x) * 0.5, 2.60, hi.z - 0.80)
	cam.look_at(Vector3((lo.x + hi.x) * 0.5, 0.60, lo.z + 2.0), Vector3.UP)
	await _shot(cam, "g3_room")

	print("\n[截图] %s" % out)
	quit(0)
