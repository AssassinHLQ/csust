extends SceneTree
## 验两件事：
##   1. **校园泼溅现在是独立场景** `scenes/campus_venue.tscn` —— 单独实例化能正常加载、
##      摆放参数（×25 / 自动居中 / 顶面沉到 −top_gap）都对
##   2. **游戏场景里已经没有校园了**（用户要求「先把学校去掉，我以后放到别的场景」），
##      平台本身还是 40 × 40、**没有护栏**（走出去会掉、掉太深会被保险送回出生点）
##
## 用法（要真渲染，不要 --headless）：
##   godot --path <工程> --script res://scripts/_verify_splat.gd
## 首次会解码 615 万点（约 50 s）；有缓存时 1 s。

var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)

	print("========== 1. 校园独立场景：加载与摆放 ==========")
	var venue: Node = (load("res://scenes/campus_venue.tscn") as PackedScene).instantiate()
	root.add_child(venue)
	await _wait(20)
	var campus: SplatScene = venue as SplatScene
	_check(campus != null, "campus_venue.tscn 的根节点是 SplatScene")
	if campus == null:
		_quit()
		return
	_check(campus.venue == "campus", "venue = campus（实测 %s）" % campus.venue)
	_check(campus.display_name == "校园", "display_name = 校园")

	var guard := 0
	while guard < 60000 and not campus.is_ready():
		await process_frame
		guard += 1
	_check(campus.is_ready(), "校园泼溅加载成功")
	if not campus.is_ready():
		_quit()
		return
	print("  点数 = %s   耗时 = %.1f s" % [_fmt(campus.point_count), campus.elapsed_seconds])
	_check(campus.point_count == 6150154, "点数 = 6,150,154（实测 %s）" % _fmt(campus.point_count))
	_check(is_equal_approx(campus.world_scale, 75.0), "world_scale = 75（放大 3 倍）")
	_check(campus.auto_place, "auto_place 打开")

	var aabb := campus.content_world_aabb()
	var c := aabb.get_center()
	print("  内容世界包围盒 pos %s size %s" % [
		str(aabb.position.snappedf(0.1)), str(aabb.size.snappedf(0.1))])
	print("  水平中心 = (%.2f, %.2f)   顶面 y = %.2f" % [c.x, c.z, campus.content_top_y()])
	_check(absf(c.x) < 2.0, "校园水平居中 x（%.2f m）" % c.x)
	_check(absf(c.z) < 2.0, "校园水平居中 z（%.2f m）" % c.z)
	_check(absf(campus.content_top_y() + campus.top_gap) < 1.0,
		"校园顶面沉在平台下方 %.1f m（实测 %.2f）" % [campus.top_gap, -campus.content_top_y()])
	_check(campus.content_top_y() < -6.0, "校园整体在平台下方")
	print("  世界尺寸 = %s（X/Z 应为真实校园尺度）" % str(aabb.size.snappedf(0.1)))
	_check(aabb.size.x > 150.0 and aabb.size.z > 100.0, "校园是世界尺度（>150 × >100 m）")

	# 一处渲染，确认这个场景单独拿出来也能看
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_splat")
	DirAccess.make_dir_recursive_absolute(out)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.fov = 60.0
	cam.global_position = Vector3(0, 120, 90)
	cam.look_at(Vector3(0, -12, 0), Vector3.UP)
	cam.make_current()
	await _wait(30)
	await _shot(out.path_join("90_campus_venue_alone.png"))
	cam.queue_free()
	venue.queue_free()
	await _wait(5)

	print("\n========== 2. 游戏场景里已经没有校园 ==========")
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(30)
	var splats: Array[String] = []
	for child in game.get_children():
		if child is SplatScene:
			splats.append("%s(venue=%s)" % [child.name, (child as SplatScene).venue])
	print("  游戏场景里的泼溅节点：%s" % ("（无）" if splats.is_empty() else str(splats)))
	_check(not game.has_node("SplatScene"), "校园节点 SplatScene 已不在游戏场景里")
	_check(game.has_node("Room609"), "画室609 还在")
	var campus_nodes := 0
	for child in game.get_children():
		if child is SplatScene and (child as SplatScene).venue == "campus":
			campus_nodes += 1
	_check(campus_nodes == 0, "游戏场景里没有任何 venue=campus 的泼溅")
	_check(splats.size() == 1, "游戏场景只剩 1 份泼溅（实测 %d）" % splats.size())

	print("\n========== 3. 悬浮平台（无护栏）==========")
	var floor_mesh: MeshInstance3D = game.get_node("Floor/Mesh")
	var box := floor_mesh.mesh as BoxMesh
	print("  地面尺寸 = %s" % str(box.size))
	_check(absf(box.size.x - 40.0) < 0.01 and absf(box.size.z - 40.0) < 0.01,
		"竞技场缩成 40 × 40 悬浮平台")
	for w in ["WallPX", "WallNX", "WallPZ", "WallNZ"]:
		_check(not game.has_node(w), "护栏 %s 已删除" % w)

	var player: Player = game.get_node_or_null("Player")
	_check(player != null, "场景里有 Player")
	if player == null:
		_quit()
		return
	player.set_process_input(false)
	# ⚠️ 起点要选**房间外面**的那条平台边缘带：画室609 在 ×5 下占
	#    x ∈ [−14.5, 13.6]、z ∈ [−12.0, 20.0]，从 z=12 往 +Z 跑会先撞上房间后墙
	#    （本喵就被这个坑了一次，看到「没掉下去」还以为是护栏没删干净）。
	#    这里走 +X 方向的边缘带（x ∈ [13.6, 20] 是空的）。
	player.global_position = Vector3(16.5, 0.05, 0)
	player.velocity = Vector3.ZERO
	player._yaw = 0.0
	player.rig.rotation.y = 0.0
	await _wait(10)
	Input.action_press("move_right")
	Input.action_press("sprint")
	var fell := false
	var g := 0
	while g < 3000:
		await process_frame
		g += 1
		if player.global_position.y < -3.0:
			fell = true
			break
	Input.action_release("sprint")
	Input.action_release("move_right")
	print("  从 x=16.5 起跑 %d 帧后位置 = %s（平台边 x=20，跑出去了就该往下掉）" % [
		g, str(player.global_position.snappedf(0.01))])
	_check(fell, "没有护栏：走出平台边缘就掉下去（y = %.2f）" % player.global_position.y)

	var guard2 := 0
	while guard2 < 9000 and player.global_position.y > -60.0:
		await process_frame
		guard2 += 1
	await _wait(60)
	print("  继续下落到 y = %.1f 后，位置 = %s（应回到出生点附近）" % [
		player.global_position.y, str(player.global_position.snappedf(0.1))])
	_check(player.global_position.z > 0.0, "掉太深会被保险送回出生点")

	print("\n================ 结果 ================")
	print("失败 %d 项" % _fail)
	_quit()


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("  [img] %s" % path)


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  [PASS] ", label)
	else:
		print("  [FAIL] ", label)
		_fail += 1


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame


func _fmt(value: int) -> String:
	var s := str(absi(value))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if value < 0 else "") + out


func _quit() -> void:
	quit(1 if _fail > 0 else 0)
