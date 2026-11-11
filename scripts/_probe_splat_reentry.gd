extends SceneTree
## 复现「F4 切走再切回来，609 的泼溅就没了」（用户 2026-11-11 实拍）。
##
## F4 的实质是 `SceneFlowDev.switch_scene()` = **释放旧场景 + 实例化新场景**。
## 所以这里不去加载 next_level（太慢），直接做等价动作：
##   ① 实例化 `game.tscn` → 等泼溅就绪 → 记录状态 + 拍图
##   ② 释放它（走 `queue_free`，与 `change_scene` 同一条退树路径）
##   ③ **再实例化一次** `game.tscn` → 等泼溅就绪 → 记录状态 + 拍图
## 对比两次的 `ready / point_count / splat_node.visible / 位置`，就能判断
## 到底是「第二次压根没解码」「解出来了但被藏了」还是「点数为 0」。
##
##   godot --path . --script res://scripts/_probe_splat_reentry.gd -- --no-capture
##
## ⚠️ **不能加 `--splat=off`** —— 泼溅就是被测对象。
## ⚠️ 出图必须真窗口。

const WAIT_MAX := 120.0
const OUT_DIR := "_arisu_captures/_splat_reentry"

var _game: Node = null


func _initialize() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	await _round(1, "第一次进入")
	await _round(2, "切走再切回（等价 F4 回程）")
	print("\n==== 完成 ====")
	quit(0)


func _round(n: int, title: String) -> void:
	print("\n================ 第 %d 次：%s ================" % [n, title])
	var t_inst := Time.get_ticks_msec()
	_game = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(_game)
	print("  实例化耗时 %d ms" % (Time.get_ticks_msec() - t_inst))
	for _i in 10:
		await process_frame
	paused = false
	var dlg := _game.get_node_or_null("DialogueBox") as CanvasLayer
	if dlg != null:
		dlg.visible = false
		if dlg.has_method("skip_all"):
			dlg.call("skip_all")

	var splats: Array = []
	for c in _game.get_children():
		if c is SplatScene:
			splats.append(c)
	print("  场景里的 SplatScene 数量 = %d" % splats.size())
	for s in splats:
		var sc := s as SplatScene
		print("    %-14s venue=%-6s 路径=%s" % [String(sc.name), String(sc.venue),
			String(sc.sog_path)])

	# 等解码
	var t0 := Time.get_ticks_msec()
	var waited := 0.0
	while waited < WAIT_MAX:
		var all_ready := not splats.is_empty()
		for s in splats:
			if not (s as SplatScene).is_ready():
				all_ready = false
		if all_ready:
			break
		await process_frame
		waited = float(Time.get_ticks_msec() - t0) / 1000.0
	print("  等了 %.1f s 后的状态：" % waited)
	for s in splats:
		var sc := s as SplatScene
		print("    %-14s ready=%-5s points=%-8d 节点可见=%-5s loading=%-5s failed=%s"
			% [String(sc.name), str(sc.is_ready()), int(sc.point_count),
				str(sc.splat_node != null and sc.splat_node.visible),
				str(sc.loading), str(sc.load_failed)])

	var player := _game.get_node_or_null("Player") as Node3D
	if player != null:
		print("  玩家位置 %s" % str(player.global_position.snappedf(0.01)))

	await _shot(n, splats, player)

	# 释放（等价切场景的退树）
	var t_free := Time.get_ticks_msec()
	_game.queue_free()
	_game = null
	for _i in 20:
		await process_frame
	print("  释放并等 20 帧，耗时 %d ms" % (Time.get_ticks_msec() - t_free))


func _shot(n: int, splats: Array, player: Node3D) -> void:
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out)
	# 自己挂一台相机俯视 609，别用玩家相机（它每帧在动）
	var cam := Camera3D.new()
	_game.add_child(cam)
	cam.fov = 70.0
	cam.far = 600.0
	cam.global_position = Vector3(6.0, 12.0, -6.0)
	cam.look_at(Vector3(2.0, 0.5, -2.0), Vector3.UP)
	cam.make_current()
	for _i in 3:
		await process_frame
	cam.make_current()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var f := "%s/round%d.png" % [out, n]
		root.get_texture().get_image().save_png(f)
		print("  [img] %s" % f)
