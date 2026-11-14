extends SceneTree
## 出图 v2：电竞房街机柜。
##
## ── v1 的两个坑（都记在这儿，免得再踩）──
## ① 为了清屏把 `level` 下**所有** `CanvasLayer` 都 `visible = false` 了 ——
##    结果柜子自己的 UI 层（提示行 + 全屏覆盖层）也被藏掉，「按 F 之后」那张
##    拍出来还是 3D 画面。现在只藏 **`EsportsArcade` 以外**的层。
## ② 正对柜子那张看着像镜头钻进柜子 —— 所以这一版每张都**打印相机的全局
##    变换和柜子的真实世界 AABB**，出问题时能一眼看出是机位错了还是柜子错了。
##
##   godot --path . --script res://scripts/_probe_esports_arcade_shot.gd -- --no-capture --splat=off --story=off

const OFF := preload("res://scripts/offscreen_window.gd")
const OUT_DIR := "res://_tools/_tmp/esports_arcade2"
const FLOOR_Y := 0.51
const EYE := 1.62


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	await OFF.apply(self, Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	var level := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(level)
	for _f in 150:
		await process_frame
	paused = false
	await _wait(20)

	var room := level.get_node_or_null("EsportsRoom") as Node3D
	var arcade := level.get_node_or_null("EsportsArcade") as Node3D
	if room == null or arcade == null:
		print("!! 缺房间或街机柜")
		quit(1)
		return
	room.visible = true
	await _wait(10)

	# ── 只藏 HUD，别动柜子自己的 UI 层 ──
	for n in level.get_children():
		if n is CanvasLayer:
			(n as CanvasLayer).visible = false
	for c in level.find_children("*", "CanvasLayer", true, false):
		if arcade.is_ancestor_of(c):
			continue
		(c as CanvasLayer).visible = false
	await _wait(30)

	# ── 柜子到底在哪、多大 ──
	var box := AABB()
	var first := true
	var names := []
	for mi in arcade.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var b: AABB = m.global_transform * m.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
		names.append(m.name)
	print("\n[shot] 柜子世界位置 %s  旋转 Y = %.1f°"
		% [str(arcade.global_position.snappedf(0.01)), arcade.rotation_degrees.y])
	print("[shot] 柜子世界 AABB：x %.2f~%.2f  y %.2f~%.2f  z %.2f~%.2f（%d 个网格）"
		% [box.position.x, box.end.x, box.position.y, box.end.y,
		   box.position.z, box.end.z, names.size()])
	print("[shot] 网格：%s" % str(names))

	var out := ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out)

	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.05
	cam.far = 3000.0
	level.add_child(cam)
	cam.make_current()
	await process_frame

	# 正面中心（屏幕中心世界坐标 = 柜子位置 + 高度）
	var front_x: float = box.end.x
	var scr_mesh: MeshInstance3D = arcade.call("screen_mesh") as MeshInstance3D
	var scr_y: float = scr_mesh.global_position.y
	print("[shot] 柜子正面 x=%.2f，屏幕中心 y=%.2f" % [front_x, scr_y])

	var shots := [
		# 从 1.5 m 外正对屏幕（人玩的时候的视角）
		["front_15", Vector3(front_x + 1.5, scr_y + 0.25, 11.60), Vector3(front_x, scr_y, 11.60)],
		# 从 2.6 m 外，稍微低一点，看整体
		["front_26", Vector3(front_x + 2.6, FLOOR_Y + EYE, 11.60), Vector3(front_x - 0.3, 1.0, 11.60)],
		# 斜 45°，看厚度和灯带
		["diag", Vector3(front_x + 1.9, FLOOR_Y + EYE, 9.70), Vector3(front_x - 0.3, 1.05, 11.60)],
	]
	for s in shots:
		var tag: String = s[0]
		cam.global_position = s[1]
		await process_frame
		cam.look_at(s[2], Vector3.UP)
		for _f in 6:
			await process_frame
		print("[shot] %-9s 机位 %s  朝 %s" % [tag,
			str(cam.global_position.snappedf(0.01)), str(s[2])])
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		if img != null:
			img.save_png(out.path_join("%s.png" % tag))

	# ── 按 F（探针直开）→ 拍全屏小游戏 ──
	var player := level.get("_player") as CharacterBody3D
	if player != null:
		player.global_position = Vector3(front_x + 1.0, FLOOR_Y + 0.2, 11.60)
		player.velocity = Vector3.ZERO
		for _f in 20:
			await physics_frame
	# ── 用**真按键事件**走一遍「靠近 → 按 F」，不是直接调 open_for_test ──
	# `Input.parse_input_event` 会把事件丢进正常的输入分发链，能验出
	# 「_in_range 判定 + _input 拦截 + 打开」整条路；顺手确认没被别的节点抢走 F。
	await _wait(6)
	var key := InputEventKey.new()
	key.keycode = KEY_F
	key.physical_keycode = KEY_F
	key.pressed = true
	Input.parse_input_event(key)
	for _f in 12:
		await process_frame
	var opened_by_key: bool = bool(arcade.call("is_open"))
	print("[shot] 按 F 之后 is_open = %s（真事件链路）" % str(opened_by_key))
	if not opened_by_key:
		print("[shot] ⚠️ 真按键没打开，改用 open_for_test 继续拍图（链路问题要单独查）")
		arcade.call("open_for_test")
	for _f in 40:
		await process_frame
	print("[shot] 已打开=%s  玩家脚底 y=%.2f" % [str(arcade.call("is_open")),
		player.global_position.y if player != null else -1.0])
	await RenderingServer.frame_post_draw
	var img2 := root.get_texture().get_image()
	if img2 != null:
		img2.save_png(out.path_join("opened.png"))
		print("[shot] opened.png（全屏覆盖层）")
	# 关掉，再看柜子屏幕上是不是同一局
	arcade.call("close_for_test")
	for _f in 6:
		await process_frame
	print("[shot] 输出目录 %s" % out)
	quit(0)
