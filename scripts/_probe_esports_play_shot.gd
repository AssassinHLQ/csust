extends SceneTree
## 出图：电竞房「坐下开黑」过场的四个瞬间。
##
## 相机**用玩家自己的相机**（第三人称，跟着爱丽丝），因为这就是使用者按下 F 之后
## 真正看到的画面 —— 另外搭机位会拍出「好看但不是他看到的」东西。
##
## 拍：
##   before    —— 站在爱丽丝椅子前的走道上（提示「按 F 和她们一起坐下开黑」）
##   sitting   —— 按 F 之后 0.2 s（五人正在飞向椅子）
##   lit       —— 五人落座、五块屏幕刚全亮、覆盖层还没盖上来（这一幕最要紧）
##   playing   —— 窗口已经变成小游戏
##
##   godot --path . --script res://scripts/_probe_esports_play_shot.gd -- --no-capture --splat=off --story=off

const OFF := preload("res://scripts/offscreen_window.gd")
const OUT_DIR := "res://_tools/_tmp/esports_play"
const TRIGGER := Vector3(52.35, 1.05, 13.78)


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
	var play := level.get_node_or_null("EsportsDeskPlay") as Node3D
	if room == null or play == null:
		print("!! 缺房间或过场节点（room=%s play=%s）" % [str(room), str(play)])
		quit(1)
		return
	room.visible = true
	await _wait(20)
	print("[shot] 过场节点 visible=%s  阶段=%s" % [str(play.visible), str(play.call("phase_name"))])

	var player := level.get("_player") as CharacterBody3D
	if player == null:
		print("!! 没有 player")
		quit(1)
		return
	# 玩家站到触发点
	player.global_position = TRIGGER
	player.velocity = Vector3.ZERO
	# 四位队友也搬到走道上（不然它们还在小屋，会走「瞬移落座」分支，动画看不见）
	var comps: Array = []
	for c in level.get_children():
		if c is Companion:
			comps.append(c)
	print("[shot] 队友 %d 位：%s" % [comps.size(),
		str(comps.map(func(x): return String(x.display_name)))])
	for i in comps.size():
		var c := comps[i] as Node3D
		c.global_position = Vector3(52.6, 1.05, 12.2 + float(i) * 1.1)
		if c is CharacterBody3D:
			(c as CharacterBody3D).velocity = Vector3.ZERO
	for _f in 45:
		await physics_frame
	print("[shot] 玩家落定 %s  在范围内=%s"
		% [str(player.global_position.snappedf(0.01)), str(play.call("in_range"))])

	var out := ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out)

	# ── 先量一下工位剖面（人到底该坐哪）──
	_scan_workstation(level, 10.79)
	_scan_workstation(level, 13.78)

	# ① 站定（提示应该在）
	await _wait(6)
	await _shot(out, play, "before")

	# ② 按 F
	var fkey := InputEventKey.new()
	fkey.keycode = KEY_F
	fkey.physical_keycode = KEY_F
	fkey.pressed = true
	play.call("_input", fkey)
	print("[shot] 按 F → 阶段 %s" % str(play.call("phase_name")))
	await _wait(12)                       # ≈0.2 s，人正飞向椅子
	await _shot(out, play, "sitting")

	# ③ 等「屏幕全亮、覆盖层还没盖上来」
	# 先等屏幕亮到一半：这时候拍近景，不会被覆盖层挡住
	var guard := 0
	while guard < 300:
		await process_frame
		guard += 1
		if String(play.call("phase_name")) == "GLOW" and float(play.call("screen_level")) > 0.45:
			break
	var cam_node := play.get("_cutscene_cam") as Camera3D
	if cam_node != null:
		var keep_pos: Vector3 = cam_node.global_position
		var keep_rot: Vector3 = cam_node.global_rotation
		cam_node.global_position = Vector3(51.75, 1.72, 10.45)
		cam_node.look_at(Vector3(53.55, 1.30, 10.68), Vector3.UP)
		await _wait(3)
		await _shot(out, play, "seat_closeup")
		cam_node.global_position = keep_pos
		cam_node.global_rotation = keep_rot
	# 再等全亮
	while guard < 300:
		await process_frame
		guard += 1
		if String(play.call("phase_name")) == "GLOW" and float(play.call("screen_level")) > 0.95:
			break
	await _shot(out, play, "lit")


	# ④ 等到 PLAY（覆盖层盖上来）
	guard = 0
	while String(play.call("phase_name")) != "PLAY" and guard < 300:
		await process_frame
		guard += 1
	await _wait(30)                       # 让小游戏自己跑几帧出画面
	await _shot(out, play, "playing")
	print("[shot] 已打开=%s  屏幕亮度=%.2f"
		% [str(play.call("is_playing")), float(play.call("screen_level"))])

	# ⑤ 按 Esc 退出，拍「跳下来」
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	play.call("_input", esc)
	print("[shot] 按 Esc → 阶段 %s" % str(play.call("phase_name")))
	await _wait(8)
	await _shot(out, play, "jumping")

	# ⑥ 等 STAND 走完，确认人回到原位（顺手留一张恢复后的图）
	await _wait(90)
	await _shot(out, play, "after_stand")

	print("[shot] 输出目录 %s" % out)
	quit(0)


## 存一张图（普通函数，别写成 lambda —— `await Callable.call()` 不是协程）
func _shot(out: String, play: Node3D, tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img == null:
		print("[shot] %s 拿不到画面" % tag)
		return
	img.save_png(out.path_join("%s.png" % tag))
	print("[shot] %s.png（阶段 %s）" % [tag, str(play.call("phase_name"))])


## 在某条 z 线上从走道（−X）往 +X 打射线，打印各高度第一次撞到的东西。
## 这就是「工位剖面」：桌沿在哪、显示器在哪、椅子在哪，一目了然。
func _scan_workstation(level: Node3D, z: float) -> void:
	var space: PhysicsDirectSpaceState3D = level.get_world_3d().direct_space_state
	print("\n[scan] z = %.2f 的工位剖面（从 x=50.0 往 +X 打射线）" % z)
	for y in [0.55, 0.75, 1.00, 1.20, 1.60, 1.90, 2.10, 2.40]:
		var from := Vector3(50.0, y, z)
		var q := PhysicsRayQueryParameters3D.create(from, Vector3(56.0, y, z))
		var h := space.intersect_ray(q)
		if h.is_empty():
			print("  y=%.2f  →  6 m 内没东西" % y)
		else:
			var p: Vector3 = h["position"]
			print("  y=%.2f  →  x=%.2f（%s）" % [y, p.x, str(h.get("collider"))])
