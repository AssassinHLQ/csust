extends SceneTree
## 探针（要真渲染）：开局的三个症状 + 「地板中间」到底是什么。
##
## 用户 2026-10-18 报的四件事：
##   ① 角色一开局**光站着**（没有待机动画）
##   ② **不加载高斯泼溅**
##   ③ 语音在**看见画面之前**就开始播
##   ④ **地板中间没填满**
##
## 想量清楚的是：
##   · 开局那一刻 `get_tree().paused`、房间代理网格 (`RoomProxy`)、泼溅节点
##     的 visible 各是什么 —— 决定「看见的是代理还是扫描」
##   · 暂停期间角色的 AnimationPlayer **播放位置动不动**（动 = 有待机动画）
##   · 房间footprint 中间那一块，**头顶往下看**究竟是谁在挡着：
##     把所有 MeshInstance3D 的世界包围盒打出来，逐个看覆盖关系
##
## 用法（**别加 --headless**；`--venue=room` 只加载画室609，省显存）：
##   godot --path <工程> --script res://scripts/_probe_startup.gd -- --venue=room
## 输出：`_arisu_captures/_startup/`

const OUT_DIR := "_arisu_captures/_startup"
const SIZE := Vector2i(960, 600)
const WAIT_READY_FRAMES := 600


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = SIZE
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out)

	var game: Node3D = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	# 开局第一眼（泼溅还没就绪）：这一帧就是用户看到「空房间」的那一帧
	print("[st] ── t≈0（泼溅未就绪）──")
	_dump_state(game, "t0")
	await _shot(out.path_join("0_t0.png"))

	# 等房间泼溅就绪（`_process` 不暂停，所以代理会在这一帧之后被替换）
	var waited := 0
	var room: Node = null
	while waited < WAIT_READY_FRAMES:
		room = _first_ready_splat(game)
		if room != null:
			break
		await process_frame
		waited += 1
	print("[st] 等泼溅就绪：%d 帧" % waited)
	await process_frame
	await process_frame
	print("[st] ── 泼溅就绪之后 ──")
	_dump_state(game, "ready")

	# 房间包围盒（代理建出来后由 game.gd 记着）
	var box: AABB = game.get("_room_box")
	var mid := box.position + box.size * 0.5
	print("[st] 房间矩形 %s 中心 %s" % [str(box.size.snappedf(0.01)), str(mid.snappedf(0.01))])

	# 开局时**暂停**（开场剧情就是这么做的）：量角色的动画还动不动
	await _idle_test(game, "before")

	# 四向平视 + 俯视：看清房间地板到底是什么
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 400.0
	root.add_child(cam)
	cam.make_current()
	for i in 4:
		var ang := TAU * float(i) / 4.0
		cam.global_position = mid + Vector3(0.0, 1.6, 0.0)
		cam.look_at(mid + Vector3(sin(ang) * 8.0, 0.0, cos(ang) * 8.0), Vector3.UP)
		await _shot(out.path_join("1_dir_%d.png" % i), "房间内 yaw %d°" % int(rad_to_deg(ang)))
	cam.global_position = mid + Vector3(0.0, 26.0, 0.001)
	cam.look_at(mid, Vector3.UP)
	await _shot(out.path_join("2_top.png"), "房间俯视")

	# 从平台上看房间外面那一圈：洞收小之后，泼溅里「窗外的校园」那些点会落到
	# 地砖上方 —— 这两张就是查「地砖上有没有漂浮碎片」的。
	var k := 0
	for pos in [Vector3(-18.0, 2.2, 20.0), Vector3(16.5, 2.2, 3.5)]:
		cam.global_position = pos
		cam.look_at(Vector3(mid.x, 1.0, mid.z), Vector3.UP)
		await _shot(out.path_join("4_outside_%d.png" % k), "平台上看房间 %s" % str(pos))
		k += 1

	# 强行点亮泼溅节点，再拍一张：用来区分「节点被藏了」和「节点可见但渲染不出来」
	if room != null and room.get("splat_node") != null:
		var sn := room.get("splat_node") as Node3D
		print("[st] 泼溅节点：visible=%s  pos=%s  children=%d" % [
			str(sn.visible), str(sn.global_position.snappedf(0.01)), sn.get_child_count()])
		sn.visible = true
		for c in sn.get_children(true):
			if c is GeometryInstance3D:
				var gi := c as GeometryInstance3D
				print("[st]   %s visible=%s aabb=%s extra_cull=%s" % [
					String(gi.name), str(gi.visible),
					str((gi.global_transform * gi.get_aabb()).size.snappedf(0.1)),
					str(gi.extra_cull_margin)])
		await _shot(out.path_join("3_forced.png"), "泼溅强行可见")

	# 谁挡在中间那块地板上面？（只有覆盖 footprint 的才打）
	_dump_floor_cover(game, box)
	print("[st] 输出目录 %s" % out)
	quit(0)


func _dump_state(game: Node3D, tag: String) -> void:
	var proxy := game.get_node_or_null("RoomProxy")
	var splat_vis := "-"
	var splat_ready := "-"
	var room := _room_scene(game)
	if room != null:
		splat_ready = str(room.call("is_ready"))
		if room.get("splat_node") != null:
			splat_vis = str((room.get("splat_node") as Node3D).visible)
	print("[st] %s: paused=%s  inside=%s  proxy=%s  splat ready=%s visible=%s" % [
		tag, str(paused), str(game.get("_room_inside")),
		"无" if proxy == null else str((proxy as Node3D).visible),
		splat_ready, splat_vis])


func _room_scene(game: Node3D) -> Node:
	for c in game.get_children():
		if c is SplatScene and String(c.venue) == "room":
			return c
	return null


func _first_ready_splat(game: Node3D) -> Node:
	for c in game.get_children():
		if c is SplatScene and c.is_ready():
			return c
	return null


## 暂停一下，量同伴 / 主角的 AnimationPlayer 播放位置动不动。
## 期望：动（说明暂停期间待机动画仍在走）。
func _idle_test(game: Node3D, tag: String) -> void:
	paused = true
	await process_frame
	await process_frame
	var rows: Array = []
	for c in game.get_children():
		if not (c is Companion):
			continue
		var ap := _find_ap(c)
		if ap == null:
			rows.append([String(c.name), "**没有 AnimationPlayer**", -1.0, -1.0])
			continue
		rows.append([String(c.name), ap.current_animation,
			ap.current_animation_position, 1.0 if ap.is_playing() else 0.0])
	var again: Array = []
	for _i in 30:
		await process_frame
	for c in game.get_children():
		if not (c is Companion):
			continue
		var ap := _find_ap(c)
		again.append(-1.0 if ap == null else ap.current_animation_position)
	print("[st] 暂停期间待机动画（%s）：" % tag)
	var i := 0
	for r in rows:
		var d: float = -1.0
		if float(again[i]) >= 0.0 and float(r[2]) >= 0.0:
			d = float(again[i]) - float(r[2])
		print("[st]   %-20s clip=%-16s from %.3f → %.3f（Δ %.3f s，playing=%s）" % [
			String(r[0]), String(r[1]), float(r[2]), float(again[i]), d, str(float(r[3]) > 0.5)])
		i += 1
	var papt := _find_ap(game.get_node_or_null("Player"))
	if papt != null:
		var a: float = papt.current_animation_position
		for _i in 30:
			await process_frame
		print("[st]   %-20s clip=%-16s %.3f → %.3f（Δ %.3f s）" % [
			"Player", papt.current_animation, a, papt.current_animation_position,
			papt.current_animation_position - a])
	paused = false


func _find_ap(n: Node) -> AnimationPlayer:
	if n == null:
		return null
	for c in n.find_children("*", "AnimationPlayer", true, false):
		return c as AnimationPlayer
	return null


## 把所有「可能挡在房间地板上面」的网格打出来：世界包围盒与房间矩形相交、
## 且竖向落在 y ∈ [-1, 2] 的。
func _dump_floor_cover(game: Node3D, box: AABB) -> void:
	print("[st] ── 房间 footprint 里、y∈[-1,2] 的网格 ──")
	var found := 0
	var stack: Array[Node] = [game]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var mi := n as MeshInstance3D
		if mi == null:
			continue
		var ab: AABB = mi.global_transform * mi.get_aabb()
		if ab.end.y < -1.0 or ab.position.y > 2.0:
			continue
		if not ab.intersects(box):
			continue
		found += 1
		var mat := mi.get_active_material(0) as StandardMaterial3D
		print("[st]   %-46s visible=%-5s aabb=%s albedo=%s" % [
			String(game.get_path_to(mi)), str(mi.visible),
			str(ab.size.snappedf(0.01)),
			"无" if mat == null else str(mat.albedo_color)])
	print("[st]   共 %d 个" % found)


func _shot(file: String, tag := "") -> void:
	for _i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(file)
	if not tag.is_empty():
		print("[st]   [img] %s（%s）" % [file, tag])
