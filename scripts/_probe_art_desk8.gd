extends SceneTree
## 探针 8：把探针 3 找到的 20 个「水平面块」各自染成**唯一颜色**、按真实尺寸贴回
## 出生点视角，再在画面下方放一排编号色卡。桌面上盖着哪块颜色，就是哪个候选。
##
## 为什么用颜色而不是标签：3D 里的 `Label3D` 会被 GaussianCompositorEffect 吃掉，
## 2D 的 `Label` 在 2560 px 渲染下又小到读不出。颜色块是**几十像素见方**的实心面，
## 无论缩略图怎么缩都能认。编号 ↔ 颜色由下方的色卡给出。
##
## 输出 `_arisu_captures/_artdesk/probe08.txt` + `p8_00_swatch.png`
## 用法：godot --path . --script res://scripts/_probe_art_desk8.gd

const OUT_ABS := "C:/Users/WY157/Desktop/GODOT/_arisu_captures/_artdesk"
const GAME_PATH := "res://scenes/game.tscn"

## 探针 3 的 20 个水平面块：id, x0, z0, x1, z1, y
const PLANES := [
	["A1", -4.82, 2.14, -3.42, 3.26, 0.687],
	["A2", 2.34, 4.06, 2.98, 4.94, 0.885],
	["A3", 1.74, 5.70, 2.42, 6.54, 0.863],
	["A4", -4.62, 4.30, -3.74, 5.22, 0.878],
	["A5", -4.70, 3.30, -3.58, 3.98, 0.715],
	["A6", 1.74, 7.50, 2.50, 8.54, 0.803],
	["A7", -3.94, -2.06, -3.42, -1.50, 0.874],
	["A8", 2.38, 10.14, 3.14, 11.02, 0.878],
	["A9", -4.14, 9.38, -3.26, 10.10, 0.814],
	["A10", -5.22, -0.70, -4.74, 0.22, 0.690],
	["A11", -2.82, 8.46, -2.30, 9.02, 0.841],
	["A12", -3.14, 3.74, -2.62, 4.30, 0.878],
	["A13", 2.94, 9.46, 3.42, 9.98, 0.867],
	["A14", 3.46, -0.98, 4.14, -0.38, 0.853],
	["A15", -4.50, 6.82, -3.86, 7.42, 0.674],
	["A16", -3.54, 0.46, -3.02, 0.94, 0.876],
	["A17", -3.54, 12.06, -3.02, 12.62, 0.884],
	["A18", -3.62, 4.30, -3.10, 4.82, 0.676],
	["A19", -2.34, 3.86, -1.86, 4.26, 0.676],
	["A20", -2.82, 2.58, -2.18, 2.94, 0.669],
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_ABS)
	var game: Node = (load(GAME_PATH) as PackedScene).instantiate()
	root.add_child(game)
	var room := game.get_node_or_null("Room609") as Node3D
	var waited := 0
	while waited < 9000 and (room == null or not bool(room.call("is_ready"))):
		await process_frame
		waited += 1
	paused = false
	for c in game.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
		elif c is Companion:
			(c as Node3D).visible = false

	var sensei := game.get_node_or_null("Sensei") as Node3D
	var sp := sensei.global_position if sensei != null else Vector3(1.8, 0.0, 2.6)
	var player := game.get_node_or_null("Player") as Node3D
	var ppos := player.global_position if player != null else Vector3(0.0, 0.0, 6.0)
	var eye := Vector3(ppos.x, ppos.y + 1.57, ppos.z)

	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.02
	cam.far = 400.0
	root.add_child(cam)
	cam.global_position = eye
	cam.look_at(Vector3(sp.x, sp.y + 1.30, sp.z), Vector3.UP)
	cam.make_current()
	for _i in 10:
		await process_frame
	print("[p8] 等 %d 帧；相机 %s → Sensei %s" % [waited, str(eye), str(sp)])

	# 每个候选一个纯色薄板（真实尺寸，贴在候选高度上）
	var lines := PackedStringArray()
	lines.append("id  颜色(R,G,B)        世界 x0,x1  z0,z1  y   尺寸")
	for k in PLANES.size():
		var e: Array = PLANES[k]
		var id := String(e[0])
		var x0 := float(e[1])
		var z0 := float(e[2])
		var x1 := float(e[3])
		var z1 := float(e[4])
		var y := float(e[5])
		var col := Color.from_hsv(float(k) / float(PLANES.size()), 1.0, 1.0)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(maxf(x1 - x0, 0.02), 0.012, maxf(z1 - z0, 0.02))
		mi.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = col
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true
		mat.render_priority = 8
		mi.material_override = mat
		root.add_child(mi)
		mi.global_position = Vector3((x0 + x1) * 0.5, y + 0.012, (z0 + z1) * 0.5)
		lines.append("%-4s %5.2f,%5.2f,%5.2f  x[%6.2f,%6.2f] z[%6.2f,%6.2f] %.3f  %.2f×%.2f"
			% [id, col.r, col.g, col.b, x0, x1, z0, z1, y, x1 - x0, z1 - z0])

	# 2D 色卡：两行十列
	var layer := CanvasLayer.new()
	layer.layer = 110
	root.add_child(layer)
	var vp := root.get_visible_rect().size
	var cw := minf(vp.x / 10.0, 200.0)
	var ch := 54.0
	for k in PLANES.size():
		var col2 := Color.from_hsv(float(k) / float(PLANES.size()), 1.0, 1.0)
		var row := 0 if k < 10 else 1
		var cx := float(k % 10) * cw
		var cy := vp.y - ch * 2.0 + float(row) * ch
		var cr := ColorRect.new()
		cr.color = col2
		cr.position = Vector2(cx, cy)
		cr.size = Vector2(cw - 2.0, ch - 2.0)
		layer.add_child(cr)
		var l := Label.new()
		l.text = "%s" % String((PLANES[k] as Array)[0])
		l.position = Vector2(cx + 6.0, cy + 4.0)
		l.add_theme_color_override("font_color", Color(1, 1, 1))
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		l.add_theme_constant_override("outline_size", 8)
		l.add_theme_font_size_override("font_size", 32)
		layer.add_child(l)

	for _i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT_ABS.path_join("p8_00_swatch.png"))
	print("[p8] 出图 p8_00_swatch.png")

	var f := FileAccess.open(OUT_ABS.path_join("probe08.txt"), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\n")
		f.close()
		print("[p8] 写入 probe08.txt")
	for s in lines:
		print(s)
	quit(0)
