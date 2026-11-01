extends SceneTree
## 探针 2：把探针 1 找到的「桌面候选」逐个拍近景，并用正交俯视图把它们摆回房间平面。
##
## 为什么要这一步：高度图只能给出一堆 1~3 m² 的连通块，画架托盘、凳子面、桌子面
## 都是 0.8 m 高，**几何上分不开**。用户说的是「一张有两个抽屉柜的木办公桌」，
## 那只能靠眼睛在渲染图上认。
##
## 输出：`_arisu_captures/_artdesk/probe02.txt` + `p2_*.png`
## 用法：godot --path . --script res://scripts/_probe_art_desk2.gd

const OUT_ABS := "C:/Users/WY157/Desktop/GODOT/_arisu_captures/_artdesk"
const GAME_PATH := "res://scenes/game.tscn"
## 挑出来的候选（照抄探针 1 的输出，世界 XZ）
const PICKS := [
	{"id": 1, "lo": Vector3(-4.60, 0.86, -2.23), "hi": Vector3(-2.75, 0.86, 0.97)},
	{"id": 2, "lo": Vector3(-4.85, 0.75, 2.12), "hi": Vector3(-2.95, 0.75, 4.27)},
	{"id": 3, "lo": Vector3(-3.25, 0.91, 2.92), "hi": Vector3(-1.85, 0.91, 4.97)},
	{"id": 4, "lo": Vector3(1.70, 0.83, 7.17), "hi": Vector3(2.95, 0.83, 8.62)},
	{"id": 6, "lo": Vector3(1.70, 0.85, 5.07), "hi": Vector3(2.45, 0.85, 6.57)},
	{"id": 9, "lo": Vector3(2.30, 0.91, 3.87), "hi": Vector3(3.05, 0.91, 4.97)},
	{"id": 30, "lo": Vector3(0.00, 0.94, 0.92), "hi": Vector3(0.50, 0.94, 1.52)},
	{"id": 11, "lo": Vector3(-5.30, 0.76, -0.83), "hi": Vector3(-4.45, 0.76, 0.72)},
]

var _rep := PackedStringArray()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
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
	_p("等泼溅 %d 帧；Sensei=%s" % [waited,
		str(sensei.global_position) if sensei != null else "—"])

	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.02
	cam.far = 400.0
	root.add_child(cam)
	cam.make_current()

	# ── 1. 从玩家出生点看 Sensei（复现玩家第一眼看到的那一幕） ──────────────
	var player := game.get_node_or_null("Player") as Node3D
	var eye := Vector3(0.0, 1.62, 6.0)
	if player != null:
		eye = player.global_position + Vector3(0.0, 1.62, 0.0)
	_p("玩家出生点 = %s" % str(eye))
	await _look(cam, eye, Vector3(1.8, 1.30, 2.6), OUT_ABS.path_join("p2_00_from_spawn.png"))
	await _look(cam, eye, eye + (Vector3(1.8, 1.30, 2.6) - eye).normalized() * 10.0
		+ Vector3(-4.2, 0.0, -2.2), OUT_ABS.path_join("p2_01_spawn_left.png"))
	await _look(cam, eye, eye + (Vector3(1.8, 1.30, 2.6) - eye).normalized() * 10.0
		+ Vector3(3.6, 0.0, 2.4), OUT_ABS.path_join("p2_02_spawn_right.png"))

	# ── 2. 每个候选的近景（相机在桌子前 2.2 m，视线高度 1.55 m） ─────────────
	for pk in PICKS:
		var d: Dictionary = pk
		var lo: Vector3 = d["lo"]
		var hi: Vector3 = d["hi"]
		var ctr := (lo + hi) * 0.5
		# 从房间中心方向拍（桌子多靠墙，所以从屋里往墙拍）
		var inward := (Vector3(-0.5, 0.0, 3.5) - ctr)
		inward.y = 0.0
		if inward.length() < 0.5:
			inward = Vector3(0.0, 0.0, 1.0)
		inward = inward.normalized()
		var cam_pos := ctr + inward * 2.2
		cam_pos.y = 1.55
		await _look(cam, cam_pos, Vector3(ctr.x, 0.85, ctr.z),
			OUT_ABS.path_join("p2_c%02d.png" % int(d["id"])))
		# 再来一张稍高的俯视，能看清桌面 + 桌下柜体
		var hi_pos := ctr + inward * 1.6
		hi_pos.y = 2.15
		await _look(cam, hi_pos, Vector3(ctr.x, 0.70, ctr.z),
			OUT_ABS.path_join("p2_c%02d_hi.png" % int(d["id"])))

	# ── 3. 正交俯视平面图 + 编号标签 ────────────────────────────────────────
	var ortho := Camera3D.new()
	ortho.projection = Camera3D.PROJECTION_ORTHOGONAL
	ortho.size = 21.0
	ortho.near = 0.02
	ortho.far = 60.0
	root.add_child(ortho)
	ortho.make_current()
	var ctr_room := Vector3(-0.50, 0.0, 3.54)
	ortho.global_position = Vector3(ctr_room.x, 2.30, ctr_room.z)
	ortho.look_at(Vector3(ctr_room.x, 0.0, ctr_room.z), Vector3(0.0, 0.0, -1.0))
	for pk in PICKS:
		var d: Dictionary = pk
		_mark(ortho, (d["lo"] as Vector3).lerp(d["hi"] as Vector3, 0.5),
			"#%d" % int(d["id"]), Color(1.0, 0.25, 0.2))
	if sensei != null:
		_mark(ortho, sensei.global_position + Vector3(0.0, 0.30, 0.0), "SENSEI",
			Color(0.2, 0.95, 0.4))
	await _settle()
	await _shot(ortho, OUT_ABS.path_join("p2_90_plan.png"))

	_flush()
	quit(0)


## 在 3D 里放一个永远面向相机、不吃深度的文字标签（正交俯视时能当图例用）
func _mark(cam: Camera3D, pos: Vector3, text: String, col: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 96
	l.pixel_size = 0.006
	l.modulate = col
	l.outline_size = 24
	l.outline_modulate = Color(0.0, 0.0, 0.0)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 10
	root.add_child(l)
	l.global_position = pos + Vector3(0.0, 0.35, 0.0)
	var _unused := cam


func _look(cam: Camera3D, from: Vector3, to: Vector3, path: String) -> void:
	cam.global_position = from
	cam.look_at(to, Vector3.UP)
	await _settle()
	await _shot(cam, path)


func _settle() -> void:
	for _i in 8:
		await process_frame


func _shot(cam: Camera3D, path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	_p("[img] %-26s 相机(%7.2f,%5.2f,%7.2f) 朝向 %s" % [path.get_file(),
		cam.global_position.x, cam.global_position.y, cam.global_position.z,
		str(-cam.global_transform.basis.z.snappedf(0.01))])


func _p(s: String) -> void:
	_rep.append(s)


func _flush() -> void:
	var f := FileAccess.open(OUT_ABS.path_join("probe02.txt"), FileAccess.WRITE)
	if f == null:
		print("\n".join(_rep))
		return
	f.store_string("\n".join(_rep) + "\n")
	f.close()
	print("[probe2] 写入 %s/probe02.txt" % OUT_ABS)
