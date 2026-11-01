extends SceneTree
## 判图：芹鞋底到底在哪个高度 —— 她背后摆一排**已知高度的彩色横线**，侧视拍一张。
##   godot --path . --script res://scripts/_probe_clerk_ruler.gd -- --splat=off
## 输出：_arisu_captures/_ruler/ruler.png
##
## 为什么用这个办法：绑定姿势 AABB、脚骨高度、蒙皮公式三种都试过，都和屏幕不符
## （蒙皮公式量玩家得到 +0.25 m，而他明明站得住 —— 说明公式用错了，不再依赖它）。
## 摆标尺是**所见即所得**：图上鞋底压在哪条线，就是哪个高度，不需要任何换算。
const OUT_ABS := "C:/Users/WY157/Desktop/GODOT/_arisu_captures/_ruler"
## 标尺线：{高度, 颜色}
const LINES := [
	[0.000, Color(1.0, 0.0, 0.0)],      # 红 = 地面
	[0.050, Color(1.0, 0.55, 0.0)],     # 橙
	[0.100, Color(1.0, 1.0, 0.0)],      # 黄
	[0.150, Color(0.0, 1.0, 0.2)],      # 绿
	[0.200, Color(0.0, 0.9, 1.0)],      # 青
	[0.300, Color(0.6, 0.2, 1.0)],      # 紫
]


func _initialize() -> void:
	_run.call_deferred()


func _line(parent: Node3D, y: float, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3.0, 0.006, 0.02)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 2.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.position = Vector3(0.0, y, 0.0)
	parent.add_child(mi)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_ABS)
	root.size = Vector2i(700, 900)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 130:
		await process_frame
	paused = false
	for c in game.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false

	var clerk := game.get_node_or_null("Shop/ClerkSerika") as Node3D
	if clerk == null:
		print("[错误] 没有 ClerkSerika")
		quit(1)
		return
	var model: Node3D = null
	for c in clerk.get_children():
		if c is Node3D and not (c is CollisionObject3D):
			model = c as Node3D
			break
	clerk.global_position = Vector3(28.0, 0.0, 6.0)
	for _f in 8:
		await process_frame
	var base := clerk.global_position

	# 标尺放在她**身后 0.9 m**（相机在更远的 −Z 侧，所以标尺被她挡住的部分看得出来）
	var ruler := Node3D.new()
	ruler.position = Vector3(base.x, 0.0, base.z - 0.90)
	game.add_child(ruler)
	for spec in LINES:
		_line(ruler, float(spec[0]), spec[1] as Color)

	# 长焦侧视：距离 7 m、fov 9° → 透视畸变很小，鞋底和标尺线基本在同一张平面上
	var cam := Camera3D.new()
	cam.fov = 9.0
	cam.near = 0.05
	cam.far = 400.0
	root.add_child(cam)
	cam.global_position = Vector3(base.x, 0.10, base.z + 7.00)
	cam.look_at(Vector3(base.x, 0.10, base.z), Vector3.UP)
	cam.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/ruler.png" % OUT_ABS)
	print("当前 model.position.y = %+.4f" % model.position.y)
	print("[截图] %s" % OUT_ABS)
	quit(0)
