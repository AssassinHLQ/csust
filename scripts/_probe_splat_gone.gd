extends SceneTree
## 探针：**主场景里到底有没有高斯泼溅**——不是看代码，是把真场景跑起来看状态、拍图。
##
## 用户 2026-10-22：「为什么高斯泼溅不见了」。
## 先量三件事：
##   ① `game.tscn` 里到底挂着几个 `SplatScene`（有几个、venue 是什么、解码好没有、可见性）
##   ② 屋里的那份在「屋外」时是不是被藏起来了（`game.gd::_update_room_swap`）
##   ③ 站在平台上看出去，画面里到底是什么（渲图）
##
## 用法：godot --path <工程> --script res://scripts/_probe_splat_gone.gd
## 输出：_arisu_captures/_splatcheck/{platform,shop_view,topdown}.png

const WAIT_MAX := 90.0


func _initialize() -> void:
	# 不抢用户前台（AGENTS.md 硬要求，2026-11-09）：取消最大化 + 禁止聚焦 + 挪出屏幕
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 10:
		await process_frame
	paused = false
	var dlg := game.get_node_or_null("DialogueBox") as CanvasLayer
	if dlg != null:
		dlg.visible = false
		if dlg.has_method("skip_all"):
			dlg.call("skip_all")

	print("========== ① 场景里的 SplatScene ==========")
	var splats: Array = []
	for child in game.get_children():
		if child is SplatScene:
			splats.append(child)
	print("  数量 = %d" % splats.size())
	for s in splats:
		var sc := s as SplatScene
		print("  %-14s venue=%-8s 路径=%s" % [String(sc.name), String(sc.venue),
			String(sc.sog_path)])
	if splats.is_empty():
		print("  ⚠️ game.tscn 里**一个泼溅都没有**（这就是「不见了」的直接原因）")

	# 等解码（最多 WAIT_MAX 秒）
	var t0 := Time.get_ticks_msec()
	var waited := 0.0
	while waited < WAIT_MAX:
		var all_ready := true
		for s in splats:
			if not (s as SplatScene).is_ready():
				all_ready = false
		if all_ready and not splats.is_empty():
			break
		await process_frame
		waited = float(Time.get_ticks_msec() - t0) / 1000.0
	print("\n========== ② 解码状态（等了 %.1f s）==========" % waited)
	for s in splats:
		var sc := s as SplatScene
		print("  %-14s ready=%s  points=%d  node_visible=%s" % [String(sc.name),
			str(sc.is_ready()), int(sc.point_count),
			str(sc.splat_node != null and sc.splat_node.visible)])

	# 站到平台上（小屋与商店之间的空地）再看一眼
	var player := game.get_node_or_null("Player") as Node3D
	# ⚠️ 玩家的相机是 SpringArm3D 的子节点、`_physics_process` 每帧都在动它，
	#    所以先把玩家关掉，再自己挂一台相机（否则拍出来永远是玩家视角）。
	var player_node := game.get_node_or_null("Player")
	if player_node != null:
		player_node.set_physics_process(false)
		player_node.set_process(false)
	var cam := Camera3D.new()
	game.add_child(cam)
	cam.fov = 70.0
	cam.near = 0.05
	cam.far = 600.0
	print("\n========== ③ 换几个机位拍 ==========")
	print("  玩家位置 %s" % (str(player.global_position.snappedf(0.01)) if player != null else "无"))

	var shots := {
		"platform": [Vector3(6.0, 1.7, 0.0), Vector3(40.0, 0.4, -14.0)],
		"shop_view": [Vector3(10.0, 1.7, -6.0), Vector3(33.0, 1.2, -15.5)],
		"topdown": [Vector3(20.0, 30.0, 0.01), Vector3(20.0, 0.0, 0.0)],
	}
	if cam == null:
		print("!! 没有 Camera3D")
		quit(1)
		return
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_splatcheck")
	DirAccess.make_dir_recursive_absolute(out)
	for name in shots:
		var pos: Vector3 = shots[name][0]
		var look: Vector3 = shots[name][1]
		cam.global_position = pos
		cam.look_at(look, Vector3.UP if name != "topdown" else Vector3.FORWARD)
		cam.make_current()
		await process_frame
		await process_frame
		cam.make_current()
		print("  当前相机 = %s" % String(root.get_camera_3d().name))
		await RenderingServer.frame_post_draw
		var file := "%s/%s.png" % [out, name]
		root.get_texture().get_image().save_png(file)
		print("  [img] %s" % file)

	print("\n========== ④ 站到屋里再看（600×600 的房间里）==========")
	if player != null:
		player.global_position = Vector3(-0.5, 1.3, 3.5)
		for _i in 8:
			await process_frame
		for s in splats:
			var sc := s as SplatScene
			print("  %-14s inside→ node_visible=%s" % [String(sc.name),
				str(sc.splat_node != null and sc.splat_node.visible)])
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join("in_room.png"))
		print("  [img] %s" % out.path_join("in_room.png"))
	quit(0)


func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r != null:
			return r
	return null
