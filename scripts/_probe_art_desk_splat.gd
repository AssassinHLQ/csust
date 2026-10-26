extends SceneTree
## 画室里老师那张桌子在哪 —— **必须开泼溅**（桌子在扫描数据里，关掉就只剩空盒子）。
##   godot --path . --script res://scripts/_probe_art_desk_splat.gd
##   （⚠️ 不要加 `--splat=off`：那会把 room609 整个关掉）
##
## 用户 2026-10-26：「老师左边桌子那里还没有加碰撞体吗?」
## Sensei 世界坐标 (1.8, 0.0, 2.6)（`game.tscn` 里量的），朝向 y = 180°。
## 本探针在他四周按 1 m 摆标记（红 = x 方向、蓝 = z 方向），出三个角度的图，
## 用来把「桌子」的位置读到 0.1 m 精度，再决定碰撞盒摆在哪。
## 另外把 `Room609` 的碰撞盒（5 面墙）也画出来，避免新盒子捅进墙里。

const OUT := "_arisu_captures/_fix1026"
var _out_abs := ""


func _initialize() -> void:
	_run.call_deferred()


func _shot(cam: Camera3D, nm: String) -> void:
	cam.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [_out_abs, nm])


func _marker(parent: Node3D, pos: Vector3, col: Color, size := 0.07) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size, 0.012, size)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)


func _run() -> void:
	root.size = Vector2i(1280, 720)
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
	if sensei == null:
		print("[错误] 没有 Sensei")
		quit(1)
		return
	var sp := sensei.global_position
	print("Sensei 世界坐标 %s（朝向 %.0f°）"
		% [str(sp.snappedf(0.01)), rad_to_deg(sensei.rotation.y)])
	var room := game.get_node_or_null("Room609") as Node3D
	if room != null:
		print("Room609 世界原点 %s" % str(room.global_position.snappedf(0.01)))
		var col := room.get_node_or_null("RoomCollision")
		if col != null:
			for c in col.get_children():
				var cs := c as CollisionShape3D
				if cs == null:
					continue
				var b := cs.shape as BoxShape3D
				if b == null:
					continue
				print("  墙盒 %-14s 中心 %s  尺寸 %s"
					% [String(cs.name), str(cs.global_position.snappedf(0.01)),
						str(b.size.snappedf(0.01))])

	# 1 m 标记：红 = x 方向、蓝 = z 方向（都从 Sensei 出发）
	for i in range(-5, 6):
		var f := float(i)
		var col_x := Color(0.95, 0.15, 0.15) if i % 5 == 0 else Color(0.90, 0.78, 0.20)
		_marker(game, Vector3(sp.x + f, 0.03, sp.z), col_x)
		var col_z := Color(0.25, 0.55, 0.95) if i % 5 == 0 else Color(0.90, 0.78, 0.20)
		_marker(game, Vector3(sp.x, 0.03, sp.z + f), col_z)
	# 半米小点，读数更细
	for i in range(-9, 10):
		var f2 := float(i) * 0.5
		if absf(fmod(f2, 1.0)) < 0.01:
			continue
		_marker(game, Vector3(sp.x + f2, 0.03, sp.z), Color(0.55, 0.55, 0.60, 1.0), 0.04)
		_marker(game, Vector3(sp.x, 0.03, sp.z + f2), Color(0.55, 0.55, 0.60, 1.0), 0.04)

	var cam := Camera3D.new()
	cam.near = 0.02
	cam.far = 500.0
	root.add_child(cam)
	# ① 俯瞰（略斜，避开天花板）：站在他南侧 4 m、2.8 m 高往下看
	cam.fov = 60.0
	cam.global_position = Vector3(sp.x - 0.6, 2.80, sp.z + 4.20)
	cam.look_at(Vector3(sp.x + 0.2, 0.20, sp.z - 0.40), Vector3.UP)
	await _shot(cam, "desk_top")
	# ② 平视（他南侧 2.6 m，1.55 m 高）
	cam.fov = 70.0
	cam.global_position = Vector3(sp.x, 1.55, sp.z + 2.60)
	cam.look_at(Vector3(sp.x, 0.95, sp.z - 0.60), Vector3.UP)
	await _shot(cam, "desk_south")
	# ③ 从他北侧往南看（左右反过来，方便判断「老师的左边」到底是哪一侧）
	cam.fov = 70.0
	cam.global_position = Vector3(sp.x, 1.55, sp.z - 3.20)
	cam.look_at(Vector3(sp.x, 0.95, sp.z + 0.60), Vector3.UP)
	await _shot(cam, "desk_north")
	print("\n[截图] %s（desk_top / desk_south / desk_north）" % out)
	quit(0)
