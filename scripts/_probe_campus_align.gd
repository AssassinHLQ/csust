extends SceneTree
## 把 `CampusCollision` 的墙面染成半透明绿色叠在点云上，一张图判断
## 「可见校园」和「能撞到的墙」对不对得上（位置 / 上下 / 缩放）。
##
##   _tools/run_shot.sh res://scripts/_probe_campus_align.gd -- --no-capture
##
## 关键点（都是踩过的坑）：
##   · 玩家必须挪进校园，否则 `_update_room_exit_unload()` 会把泼溅放掉，拍到空景
##   · 关雾，否则 576 m 的场子沿地面看全是粉
##   · 绿色材质 `no_depth_test = false`（要能判断前后），不做深度测试会糊成一片

const OffWin := preload("res://scripts/offscreen_window.gd")
const OUT_DIR := "C:/Users/WY157/Desktop/GODOT/_arisu_captures/_gdgs_campus"


func _initialize() -> void:
	if not OS.get_cmdline_user_args().has("--no-capture"):
		push_error("[align] 缺 --no-capture")
		quit(2)
		return
	_run.call_deferred()


func _collect_faces(n: Node, xs: Array) -> void:
	var cs := n as CollisionShape3D
	if cs != null and cs.shape is ConcavePolygonShape3D:
		var f: PackedVector3Array = (cs.shape as ConcavePolygonShape3D).get_faces()
		xs.append(cs.global_transform * f)
	for c in n.get_children():
		_collect_faces(c, xs)


func _shoot(cam: Camera3D, from_: Vector3, to_: Vector3, tag: String) -> void:
	for _i in 24:
		cam.look_at_from_position(from_, to_, Vector3.UP)
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var err := img.save_png("%s/%s.png" % [OUT_DIR, tag])
	var step := 8
	var sum := 0.0
	var nn := 0
	var green := 0
	var dark := 0
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			var c := img.get_pixel(x, y)
			sum += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			nn += 1
			if c.g > 0.35 and c.g > c.r * 1.6 and c.g > c.b * 1.6:
				green += 1
			if 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b < 0.35:
				dark += 1
	print("[align] %s err=%d 亮度 %.3f 绿 %.1f%% 暗 %.1f%%" % [
		tag, err, sum / maxf(1.0, float(nn)),
		100.0 * float(green) / maxf(1.0, float(nn)),
		100.0 * float(dark) / maxf(1.0, float(nn))])


func _run() -> void:
	await OffWin.apply(self, Vector2i(1280, 720))
	var safe0: Array = OffWin.is_safe()
	if not bool(safe0[0]):
		push_error("[align] 窗口没挪到屏幕外：%s" % str(safe0[1]))
		quit(2)
		return

	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	await process_frame

	var we := level.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		we.environment.fog_enabled = false

	# ★ 玩家必须踩在校园里，否则泼溅会被判定「离开范围」放掉
	var player := level.get_node_or_null("Player") as Node3D
	player.global_position = Vector3(-20.0, 2.0, -210.0)
	player.set("velocity", Vector3.ZERO)

	var campus: Node3D = level.get_node_or_null("Campus")
	campus.set("start_delay", 0.0)
	campus.set("low_priority", false)
	campus.call("force_start")
	var t0 := Time.get_ticks_msec()
	while not bool(campus.call("is_ready")) and Time.get_ticks_msec() - t0 < 240000:
		await process_frame
	print("[align] 就绪 %d ms" % (Time.get_ticks_msec() - t0))
	var ab: AABB = campus.call("content_world_aabb")
	print("[align] 点云盒 y %.2f~%.2f  x %.2f~%.2f  z %.2f~%.2f"
		% [ab.position.y, ab.end.y, ab.position.x, ab.end.x, ab.position.z, ab.end.z])

	# 画碰撞网格（绿色半透明）
	var xs: Array = []
	var col := level.get_node_or_null("CampusCollision")
	if col != null:
		_collect_faces(col, xs)
	print("[align] 碰撞面批次 %d" % xs.size())
	for f in xs:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = f
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.05, 1.0, 0.25, 0.5)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.disable_fog = true
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		level.add_child(mi)

	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.05
	cam.far = 4000.0
	level.add_child(cam)
	cam.make_current()

	# ① 贴地视线高度：看「墙」和「可见建筑」是不是站在同一块地上
	#    ⚠️ 机位别选在霸王龙身上：TrexBossA/B/C 摆在 (-95,-96)/(-120,-115)/(-135,-140)，
	#    站在那儿镜头会插进恐龙肚子里（第一版就是这么翻车的）。
	await _shoot(cam, Vector3(-20.0, 1.7, -210.0), Vector3(-20.0, 1.4, -290.0), "i_对齐_贴地")
	# ② 侧视 45°：一眼看出上下有没有反、有没有整体错位
	await _shoot(cam, Vector3(-260.0, 60.0, -60.0), Vector3(0.0, 10.0, -300.0), "j_对齐_侧45")
	# ③ 高空俯视：平面位置对不对
	await _shoot(cam, Vector3(0.0, 220.0, -120.0), Vector3(0.0, 0.0, -316.0), "k_对齐_俯视")

	print("[align] 完")
	quit(0)
