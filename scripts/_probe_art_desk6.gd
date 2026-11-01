extends SceneTree
## 探针 6：给出生点视角**铺一张带坐标刻度的网格**，好把桌子的矩形边界读准。
##
## 为什么需要：前两版靠肉眼估 uv，一次偏左框到椅子、一次偏右框到画架。人眼在
## 1114 px 宽的缩略图上判断 ±0.02 的归一化误差就是 ±50 px，框到不该框的东西。
## 铺上 0.05 一格、带数字的网格之后，桌子的四条边可以直接读出来。
##
## 输出 `_arisu_captures/_artdesk/p6_grid.png`
## 用法：godot --path . --script res://scripts/_probe_art_desk6.gd

const OUT_ABS := "C:/Users/WY157/Desktop/GODOT/_arisu_captures/_artdesk"
const GAME_PATH := "res://scenes/game.tscn"


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
	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.02
	cam.far = 400.0
	root.add_child(cam)
	cam.global_position = Vector3(ppos.x, ppos.y + 1.57, ppos.z)
	cam.look_at(Vector3(sp.x, sp.y + 1.30, sp.z), Vector3.UP)
	cam.make_current()
	for _i in 10:
		await process_frame
	print("[p6] 等 %d 帧，视口 %s" % [waited, str(root.get_visible_rect().size)])

	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	var vp := root.get_visible_rect().size
	# 竖线：每 0.05 一条，0.10 处加粗并标数字
	var u := 0.0
	while u <= 1.001:
		var major := absf(fmod(u * 10.0 + 0.001, 1.0)) < 0.02
		var cr := ColorRect.new()
		cr.color = Color(1.0, 0.9, 0.1, 0.85) if major else Color(0.3, 1.0, 1.0, 0.45)
		cr.position = Vector2(u * vp.x - (1.0 if major else 0.5), 0.0)
		cr.size = Vector2(2.0 if major else 1.0, vp.y)
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(cr)
		if major:
			var l := _lab("u%.1f" % u, Vector2(u * vp.x + 3.0, 34.0))
			layer.add_child(l)
		u += 0.05
	var v := 0.0
	while v <= 1.001:
		var major2 := absf(fmod(v * 10.0 + 0.001, 1.0)) < 0.02
		var cr2 := ColorRect.new()
		cr2.color = Color(1.0, 0.9, 0.1, 0.85) if major2 else Color(0.3, 1.0, 1.0, 0.45)
		cr2.position = Vector2(0.0, v * vp.y - (1.0 if major2 else 0.5))
		cr2.size = Vector2(vp.x, 2.0 if major2 else 1.0)
		cr2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(cr2)
		if major2:
			layer.add_child(_lab("v%.1f" % v, Vector2(4.0, v * vp.y + 2.0)))
		v += 0.05
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT_ABS.path_join("p6_grid.png"))
	print("[p6] 出图 p6_grid.png（视口 %s）" % str(vp))
	quit(0)


func _lab(text: String, pos: Vector2) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_color_override("font_color", Color(1.0, 0.95, 0.2))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 7)
	l.add_theme_font_size_override("font_size", 26)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
