extends SceneTree
## 出图：电竞房「游戏开发部」美图组。
##
## 做法：把过场推进到「五人已落座 + 五块屏亮着彩虹猫」，然后**冻住过场时钟**
## （`play.set_process(false)`，否则它会自己走到 PLAY、全屏覆盖层盖上来），
## 再用手摆的机位逐张拍。
##
## 机位坐标全是实测的：
##   房间 x 46.2~60.3 / z 1.86~24.65，地面 y 0.51；
##   椅子 x≈53.45、z 10.68/12.17/13.69/15.16/16.66；
##   显示器 x≈54.4 朝 −X，屏心 y 1.86；走道 x 50~52.9。
##
##   godot --path . --script res://scripts/_probe_gamedev_beauty.gd -- --no-capture --splat=off --story=off

const OFF := preload("res://scripts/offscreen_window.gd")
const OUT_DIR := "res://../_arisu_captures/esports_gamedev"
const RES := Vector2i(2560, 1440)


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	await OFF.apply(self, RES)
	root.size = RES
	var level := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(level)
	for _f in 150:
		await process_frame
	paused = false
	await _wait(20)

	var room := level.get_node_or_null("EsportsRoom") as Node3D
	var play := level.get_node_or_null("EsportsDeskPlay") as Node3D
	var player := level.get("_player") as CharacterBody3D
	if room == null or play == null or player == null:
		print("!! 缺东西 room=%s play=%s player=%s" % [str(room), str(play), str(player)])
		quit(1)
		return
	room.visible = true
	await _wait(15)

	# ── 清屏：藏掉 HUD 等所有 CanvasLayer（留着过场节点自己的层，虽然它这时候是空的）──
	for c in level.find_children("*", "CanvasLayer", true, false):
		if play.is_ancestor_of(c):
			continue
		(c as CanvasLayer).visible = false
	for n in level.get_children():
		if n is CanvasLayer:
			(n as CanvasLayer).visible = false

	# ── 五人到走道上，按 F 起过场 ──
	player.global_position = Vector3(52.30, 1.05, 13.69)
	player.velocity = Vector3.ZERO
	var comps: Array = []
	for c in level.get_children():
		if c is Companion:
			comps.append(c)
	for i in comps.size():
		var c := comps[i] as Node3D
		c.global_position = Vector3(52.55, 1.05, 12.1 + float(i) * 1.05)
		if c is CharacterBody3D:
			(c as CharacterBody3D).velocity = Vector3.ZERO
	for _f in 40:
		await physics_frame
	play.call("begin")
	print("[美图] 过场开始，%d 位队友" % comps.size())

	# 推到「全亮」就把时钟冻住（不然会走到 PLAY 盖上全屏小游戏）
	var guard := 0
	while guard < 600:
		play.call("tick_for_test", 1.0 / 60.0)
		guard += 1
		if String(play.call("phase_name")) == "GLOW" and float(play.call("screen_level")) > 0.99:
			break
	play.set_process(false)
	print("[美图] 阶段=%s 屏幕亮度=%.2f（已冻结）"
		% [str(play.call("phase_name")), float(play.call("screen_level"))])

	var out := ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out)

	var cam := Camera3D.new()
	cam.near = 0.03
	cam.far = 300.0
	level.add_child(cam)
	cam.make_current()

	# 机位：位置 / 看向 / fov
	# ⚠️ 门口那一头 x < 52 的地方是**窗帘**（实拍 01/04 两版都拍成一整屏布），
	#    机位别往那边挪；椅子之间只有 z 11.05~11.80 这段缝能塞进显示器特写。
	var shots := [
		# 门口斜视整排（经典「电竞房」角度）
		["01_door_row", Vector3(52.05, 1.98, 9.35), Vector3(54.10, 1.55, 14.10), 68.0],
		# 走道中线平视：五人 + 五块屏
		["02_aisle_mid", Vector3(50.75, 1.85, 13.60), Vector3(54.10, 1.55, 13.60), 70.0],
		# 显示器特写（塞在两把椅子的缝里，正对彩虹猫）
		["03_monitor_close", Vector3(53.52, 1.90, 11.42), Vector3(54.36, 1.87, 11.92), 50.0],
		# 高机位俯瞰整排
		["04_high_angle", Vector3(51.80, 3.10, 10.05), Vector3(53.90, 1.20, 14.20), 64.0],
		# 从屋子另一头回看（门在远处）
		["05_reverse", Vector3(52.40, 1.95, 18.90), Vector3(53.90, 1.45, 11.40), 66.0],
		# 低机位：屏幕的冷光打在人身上
		["06_low_glow", Vector3(51.95, 1.02, 10.10), Vector3(53.95, 1.65, 13.40), 64.0],
	]

	for s in shots:
		var tag: String = s[0]
		cam.fov = float(s[3])
		cam.global_position = s[1]
		await process_frame
		cam.look_at(s[2], Vector3.UP)
		for _f in 10:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		if img == null:
			print("[美图] %s 拿不到画面" % tag)
			continue
		img.save_png(out.path_join("%s.png" % tag))
		print("[美图] %s.png  %s" % [tag, str((s[1] as Vector3).snappedf(0.05))])

	print("[美图] 输出目录 %s" % out)
	quit(0)
