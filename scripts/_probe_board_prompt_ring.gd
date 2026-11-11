extends SceneTree
## 探针：用户截图里那个机位 —— 玩家**正对门**、站在门口，看会不会出「按 F 上箭」。
##
## 用户 2026-11-11 的截图（`image.png`）：抬头看 42 m 的箭身，画面里**没有 F 提示**。
## 那条提示的 Label 在屏幕下方居中（`offset_top = -150`，1280×720 下 y ≈ 570~616），
## 截图底部正好被裁掉了 —— 所以「截图里看不见」不等于「没有」。
##
## 但更可能的是：玩家就站在 `FinishPortal` 那个 0.9 m 的触发盒里侧，人在门口晃，
## 这时 `_riding` 已经是 true（门自动把人拉走），提示本来就不该出现。
##
## 本探针在**四圈距离 × 四个方向**上各量一次 owner，并把结论画成一张表。
##
## 用法（要出图，所以开窗口 —— 已用 offscreen_window 挪出屏幕、禁止聚焦）：
##   godot --path . --script res://scripts/_probe_board_prompt_ring.gd -- --no-capture

const OFFWIN := preload("res://scripts/offscreen_window.gd")

var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("========== 门口一圈：谁挂得上提示 ==========")
	await OFFWIN.apply(self)
	root.size = Vector2i(1280, 720)

	var rm := load("res://scripts/run_memory.gd")
	rm.call("wipe")
	rm.call("set_parkour_done", true)

	var pk := (load("res://scenes/parkour.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(pk)
	var player := (load("res://scenes/player.tscn") as PackedScene).instantiate() as Node3D
	player.add_to_group("player")
	root.add_child(player)
	for _i in 40:
		await physics_frame
	pk.set("_player", player)

	var home: Vector3 = pk.call("_home_spot")
	var door := pk.get_node_or_null("FinishPortal") as Node3D
	if door != null:
		print("  门 = %s / 停机位 = %s / 相距 %.2f m" % [
			str(door.global_position.snappedf(0.01)), str(home.snappedf(0.01)),
			door.global_position.distance_to(home)])
	var fut := get_first_node_in_group("futures")
	if fut == null:
		print("!! 没有 Futures")
		quit(1)
		return
	var lab := fut.get_node_or_null("FuturesHUD/Prompt") as Label
	print("  锚点 _board_anchor() = %s" % str(pk.call("_board_anchor").snappedf(0.01)))
	print("  半径 BOARD_RADIUS  = %.1f" % float(pk.get("BOARD_RADIUS") if pk.get("BOARD_RADIUS") != null else 0.0))

	print("\n  距离(m) | 方向   | owner        | _riding | HUD 文本")
	print("  --------+--------+--------------+---------+--------------------")
	for dist in [0.0, 1.5, 3.0, 5.0, 7.0, 9.0, 12.0]:
		for dir_v in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
			# 先回到一个远点、并让门的状态复位（否则上一圈的骑乘还没结束）
			player.global_position = Vector3(200.0, 20.0, 200.0)
			for _i in 4:
				await physics_frame
			player.global_position = home + dir_v * dist + Vector3(0.0, 1.2, 0.0)
			for _i in 10:
				await physics_frame
			var own = fut.call("prompt_owner")
			print("  %6.1f | %-6s | %-12s | %-7s | %s" % [
				dist,
				"X+" if dir_v.x > 0 else ("X-" if dir_v.x < 0 else ("Z+" if dir_v.z > 0 else "Z-")),
				"Parkour" if own == pk else ("null" if own == null else "别的"),
				str(pk.get("_riding")),
				lab.text if lab != null else "(无 Label)"])
			# 骑乘途中下一圈会乱：等它飞完
			var g := 0
			while bool(pk.get("_riding")) and g < 1200:
				g += 1
				await physics_frame

	# ── 出图：正对门的机位，看看 HUD 提示到底在不在屏幕里 ──
	print("\n── 出图：站在门侧 3 m 正对门 ──")
	player.global_position = home + Vector3(3.0, 1.2, 0.0)
	for _i in 20:
		await physics_frame
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.near = 0.1
	cam.far = 3000.0
	root.add_child(cam)
	cam.global_position = home + Vector3(4.0, 1.7, 0.0)
	cam.look_at(home + Vector3(-2.0, 12.0, 0.0), Vector3.UP)
	await RenderingServer.frame_post_draw
	for _i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img != null:
		var out := ProjectSettings.globalize_path("res://").path_join("..") \
			.path_join("_arisu_captures").path_join("_board_prompt")
		DirAccess.make_dir_recursive_absolute(out)
		var f := out.path_join("door_side_3m.png")
		img.save_png(f)
		print("  已存 %s" % f)
		print("  HUD 文本此刻 = 「%s」 alpha = %.2f" % [
			lab.text if lab != null else "", lab.modulate.a if lab != null else 0.0])

	print("\n========== 完成 ==========")
	quit(0)
