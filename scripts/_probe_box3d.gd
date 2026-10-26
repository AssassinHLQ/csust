extends SceneTree
## 在 3D 里画候选碰撞盒的**半透明线框**，和泼溅叠在一起拍 —— 这才是唯一没有投影误差的验法。
##   godot --path . --script res://scripts/_probe_box3d.gd
##
## 为什么不用「像素反投影」：桌面在 y = 0.78、地面在 y = 0，同一个屏幕像素投到
## 这两个平面上世界坐标差好几米；而且泼溅是斜的（yaw 248.6°），人眼读格子会偏。
## 直接把盒子画进 3D，看到的贴合就是真的贴合。
##
## 出图：_arisu_captures/_fix1026/{b3_desk, b3_desk_hi}.png

const OUT := "_arisu_captures/_fix1026"
## 候选盒：(名字, 世界 AABB, 颜色)
## 迭代记录（3D 线框直接叠在泼溅上，零投影误差）：
##   C: x 0.10~1.15、z 2.00~3.60 —— 右前角卡在桌角 ✓
##   D: x 0.02~1.15、z 1.90~3.56 —— **左沿偏宽 0.26 m、南沿偏长 0.75 m**
##      （读图：框左前竖线在画面 x≈400，桌子左沿 x≈470；框宽 305 px ↔ 1.13 m
##        ⇒ 70 px ≈ 0.26 m。南北同理：框 355 px ↔ 1.66 m，桌面南沿比框南沿近 160 px
##        ≈ 0.75 m。）
##   E: 按上面两个读数收紧。
const CANDIDATES := [
	["E", AABB(Vector3(0.28, 0.00, 1.90), Vector3(0.86, 0.78, 1.06)), Color(1, 0.1, 0.9)],
]
var _out_abs := ""


func _initialize() -> void:
	_run.call_deferred()


func _shot(cam: Camera3D, nm: String) -> void:
	cam.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [_out_abs, nm])


## 一个 AABB 的 12 条棱（每条是一根细长盒子）
func _wire(game: Node3D, box: AABB, col: Color, t := 0.012) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = true            # 盒子的线永远可见（泼溅挡不住它）
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color.a = 0.9
	var lo := box.position
	var hi := box.position + box.size
	# 底面 + 顶面各 4 条，竖着 4 条
	for y in [lo.y, hi.y]:
		for pair in [[Vector3(lo.x, y, lo.z), Vector3(hi.x, y, lo.z)],
				[Vector3(hi.x, y, lo.z), Vector3(hi.x, y, hi.z)],
				[Vector3(hi.x, y, hi.z), Vector3(lo.x, y, hi.z)],
				[Vector3(lo.x, y, hi.z), Vector3(lo.x, y, lo.z)]]:
			_seg(game, pair[0], pair[1], t, m)
	for cx in [lo.x, hi.x]:
		for cz in [lo.z, hi.z]:
			_seg(game, Vector3(cx, lo.y, cz), Vector3(cx, hi.y, cz), t, m)


func _seg(game: Node3D, a: Vector3, b: Vector3, t: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var d := b - a
	bm.size = Vector3(maxf(absf(d.x), t), maxf(absf(d.y), t), maxf(absf(d.z), t))
	mi.mesh = bm
	mi.material_override = mat
	mi.position = (a + b) * 0.5
	game.add_child(mi)


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
	for cand in CANDIDATES:
		var box: AABB = cand[1]
		_wire(game, box, cand[2] as Color)
		print("%s: x %.2f~%.2f  y %.2f~%.2f  z %.2f~%.2f  中心 %s 尺寸 %s"
			% [String(cand[0]), box.position.x, box.end.x, box.position.y, box.end.y,
				box.position.z, box.end.z,
				str(box.get_center().snappedf(0.01)), str(box.size.snappedf(0.01))])
	# 老师锚点：洋红十字（他脚下一块 0.3 m 的小方块轮廓）
	var anchor := AABB(Vector3(sp.x - 0.15, 0.02, sp.z - 0.15), Vector3(0.3, 0.02, 0.3))
	_wire(game, anchor, Color(1, 1, 0), 0.014)

	var cam := Camera3D.new()
	cam.near = 0.05
	cam.far = 400.0
	root.add_child(cam)
	cam.fov = 60.0
	cam.global_position = Vector3(sp.x - 0.60, 2.80, sp.z + 4.20)
	cam.look_at(Vector3(sp.x + 0.20, 0.20, sp.z - 0.40), Vector3.UP)
	await _shot(cam, "b3_desk")
	cam.fov = 40.0
	cam.global_position = Vector3(sp.x - 1.60, 2.30, sp.z + 3.20)
	cam.look_at(Vector3(sp.x - 1.00, 0.65, sp.z - 0.20), Vector3.UP)
	await _shot(cam, "b3_desk_hi")
	print("\n[截图] %s（b3_desk / b3_desk_hi；黄框 = 老师站位）" % out)
	quit(0)
