extends SceneTree
## 验「悬浮记忆平台 + 下沉校园泼溅」这套接法：
##   1. 泼溅加载成功、点数正确
##   2. 校园水平居中、顶面沉在平台下方 top_gap 处、世界尺寸是真实尺度
##   3. 竞技场地面缩成 40×40 平台，四面隐形护栏真的挡得住
##   4. 渲图：默认视角 / 低头俯视校园
##
## 用法（要真渲染，不要 --headless）：
##   godot --path <工程> --script res://scripts/_verify_splat.gd
## 首次会解码 615 万点（约 50 s）；有缓存时 1 s。

var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(20)

	var player: Player = game.get_node("Player")
	var splat: SplatScene = game.get_node("SplatScene")

	print("========== 1. 泼溅加载 ==========")
	var guard := 0
	while guard < 30000 and not splat.is_ready():
		await process_frame
		guard += 1
	_check(splat.is_ready(), "泼溅节点已建立")
	if not splat.is_ready():
		_quit()
		return
	print("  点数 = %d   耗时 = %.1f s   缓存命中 = %s" % [
		splat.point_count, splat.elapsed_seconds, str(splat.elapsed_seconds < 5.0)])
	_check(splat.point_count == 6150154, "点数 = 6,150,154")

	print("\n========== 2. 摆放（校园在平台下方、水平居中）==========")
	var aabb := splat.content_world_aabb()
	var c := aabb.get_center()
	print("  内容世界包围盒 pos %s size %s" % [
		str(aabb.position.snappedf(0.1)), str(aabb.size.snappedf(0.1))])
	print("  水平中心 = (%.2f, %.2f)   顶面 y = %.2f" % [c.x, c.z, splat.content_top_y()])
	_check(absf(c.x) < 2.0, "校园水平居中 x（%.2f m）" % c.x)
	_check(absf(c.z) < 2.0, "校园水平居中 z（%.2f m）" % c.z)
	_check(absf(splat.content_top_y() + splat.top_gap) < 1.0,
		"校园顶面沉在平台下方 %.1f m（实测 %.2f）" % [splat.top_gap, -splat.content_top_y()])
	_check(splat.content_top_y() < -6.0, "校园整体在平台下方")
	print("  世界尺寸 = %s（X/Z 应为真实校园尺度）" % str(aabb.size.snappedf(0.1)))
	_check(aabb.size.x > 150.0 and aabb.size.z > 100.0, "校园是世界尺度（>150 × >100 m）")

	print("\n========== 3. 悬浮平台 + 隐形护栏 ==========")
	var floor_mesh: MeshInstance3D = game.get_node("Floor/Mesh")
	var box := floor_mesh.mesh as BoxMesh
	print("  地面尺寸 = %s" % str(box.size))
	_check(absf(box.size.x - 40.0) < 0.01 and absf(box.size.z - 40.0) < 0.01,
		"竞技场缩成 40 × 40 悬浮平台")
	for w in ["WallPX", "WallNX", "WallPZ", "WallNZ"]:
		_check(game.has_node(w), "护栏 %s 存在" % w)

	# 从离边缘还有 8 m 的地方起跑外推，确认「真的被挡住」而不是「出生点本来就在墙上」
	player.global_position = Vector3(0, 0.05, 12)
	player.velocity = Vector3.ZERO
	await _wait(10)
	Input.action_press("move_back")
	Input.action_press("sprint")
	await _wait(1200)
	Input.action_release("sprint")
	Input.action_release("move_back")
	var p := player.global_position
	print("  从 z=12 起跑外推后位置 = %s（护栏内面 z=19.5，胶囊半径 0.3）" % str(p.snappedf(0.01)))
	_check(p.z > 17.0, "确实跑到了边缘附近（z = %.2f > 17）" % p.z)
	_check(p.z < 19.25, "护栏挡住了（z = %.2f < 19.25）" % p.z)
	_check(p.y > -1.0, "角色仍站在平台上（y = %.2f）" % p.y)

	# 助跑起跳应该能翻出去（护栏只有 0.7 m，跳跃顶点 0.87 m）
	print("\n--- 助跑起跳能翻出去（能下去看校园）---")
	player.global_position = Vector3(0, 0.05, 15)
	player.velocity = Vector3.ZERO
	await _wait(10)
	Input.action_press("move_back")
	Input.action_press("sprint")
	await _wait(300)
	Input.action_press("jump")
	await _wait(6)
	Input.action_release("jump")
	var left := false
	var g := 0
	while g < 1500:
		await process_frame
		g += 1
		if player.global_position.y < -2.0:
			left = true
			break
	Input.action_release("sprint")
	Input.action_release("move_back")
	print("  %d 帧后位置 = %s（y < -2 说明已掉出平台）" % [
		g, str(player.global_position.snappedf(0.01))])
	_check(left, "助跑起跳能翻过 0.7 m 护栏掉下去")
	# 掉下去之后应该被下面的保险接住（y < -60 时回出生点）
	var guard2 := 0
	while guard2 < 4000 and player.global_position.y > -60.0:
		await process_frame
		guard2 += 1
	await _wait(60)
	print("  继续下落到 y = %.1f 后，位置 = %s（应回到出生点附近）" % [
		player.global_position.y, str(player.global_position.snappedf(0.1))])
	_check(player.global_position.z > 0.0, "掉太深会被保险送回出生点")

	print("\n========== 4. 渲图 ==========")
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_splat")
	DirAccess.make_dir_recursive_absolute(out)

	# ① 出生点默认视角
	player.global_position = Vector3(0, 0.05, 6)
	player._yaw = 0.0
	player._facing_yaw = PI
	player.model_root.rotation.y = PI
	player._pitch = -0.04
	await _wait(40)
	await _shot(out.path_join("40_spawn_default.png"))

	# ② 站到 -Z 边缘、低头 30° 看校园
	player.global_position = Vector3(0, 0.05, -16)
	player.rig.rotation.y = player._yaw
	player._pitch = -0.55
	await _wait(40)
	await _shot(out.path_join("41_edge_lookdown.png"))

	# ③ 站到 +X 边缘往侧下方看
	player.global_position = Vector3(16, 0.05, 0)
	player._yaw = -PI * 0.5
	player.rig.rotation.y = player._yaw
	player._pitch = -0.45
	await _wait(40)
	await _shot(out.path_join("42_side_lookdown.png"))

	# ④ 纯俯视：把相机临时拉到 120 m 高
	player._pitch = -1.1
	await _wait(40)
	await _shot(out.path_join("43_high_lookdown.png"))

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


func _quit() -> void:
	quit(1 if _fail > 0 else 0)
