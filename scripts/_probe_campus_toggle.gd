extends SceneTree
## 探针：反复穿过「校园显示开关」的边界，看会不会把画面洗白。
##
## 用法：_tools/run_shot.sh res://scripts/_probe_campus_toggle.gd
##
## 背景：用户「第二场景高斯泼溅,一开始是正常的,突然变成这样子白屏」。
## 实测那张图是**纯中性白 RGB(255,255,255)**（190 万像素里 99.97% 就是这一个值），
## 说明整帧被推爆 —— 不是遮罩、不是天空。
##
## 而 `campus_ggs.gd` 里校园 quad 的显示有两个开关：
##   · 玩家 `global_position.z < -74.0` 才 `_active`
##   · `hide_inside_aabb`：人在楼内时整块藏掉
## 走出走进这栋楼 = 反复切这两个开关。本探针就在边界上来回穿，每次采样帧亮度。

const LEVEL := "res://scenes/next_level.tscn"
const OUT_SUB := "_campustoggle"

var _out := ""


func _initialize() -> void:
	# 不抢用户前台（AGENTS.md 硬要求，2026-11-09）：取消最大化 + 禁止聚焦 + 挪出屏幕
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	_out = ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_SUB)
	DirAccess.make_dir_recursive_absolute(_out)

	var level := (load(LEVEL) as PackedScene).instantiate() as Node3D
	root.add_child(level)
	current_scene = level
	for c in level.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false
	paused = false
	for _i in 120:
		await process_frame

	var player := level.get_node_or_null("Player") as Node3D
	if player == null:
		print("[tog] 拿不到 Player")
		quit(1)
		return
	var ggs := level.get_node_or_null("CampusGGS")
	if ggs == null:
		print("[tog] 没有 CampusGGS")
		quit(1)
		return

	# 等细层上传
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 90000:
		await process_frame
		var fine = ggs.get("rasterizer")
		if fine != null and bool(fine.get("is_loaded")):
			break
	print("[tog] 细层已就绪，开始来回穿边界")

	# 楼在 z≈0 附近；校园 quad 要 z < -74
	var far := Vector3(0.0, 0.2, -80.0)
	var inside := Vector3(0.0, 0.2, 0.0)
	var cam := level.get_viewport().get_camera_3d()
	var bad := -1
	for round_i in 8:
		player.global_position = far
		for _i in 25:
			await process_frame
		if cam != null:
			cam.global_position = Vector3(0.0, 14.0, -80.0)
			cam.look_at(Vector3(0.0, -4.0, -140.0))
		var s1 := await _sample("第%d次 楼外" % (round_i + 1))

		player.global_position = inside
		for _i in 25:
			await process_frame
		player.global_position = far
		for _i in 25:
			await process_frame
		if cam != null:
			cam.global_position = Vector3(0.0, 14.0, -80.0)
			cam.look_at(Vector3(0.0, -4.0, -140.0))
		var s2 := await _sample("第%d次 进出后回楼外" % (round_i + 1))

		if s1["white"] or s2["white"]:
			bad = round_i
			break

	print("\n========== 结果 ==========")
	if bad >= 0:
		print("  ✘ 第 %d 次来回就白了" % (bad + 1))
	else:
		print("  ✔ 8 次进出边界都没白")
	quit(0)


func _sample(tag: String) -> Dictionary:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img == null:
		print("[tog]   %-22s 取不到帧" % tag)
		return {"white": false}
	var w := img.get_width()
	var h := img.get_height()
	var n := 0
	var s := 0.0
	var s2 := 0.0
	for y in range(int(h * 0.15), int(h * 0.85), 18):
		for x in range(int(w * 0.15), int(w * 0.85), 22):
			var c := img.get_pixel(x, y)
			var l := (c.r * 0.299 + c.g * 0.587 + c.b * 0.114) * 255.0
			s += l
			s2 += l * l
			n += 1
	var mean := s / float(n)
	var sd := sqrt(maxf(0.0, s2 / float(n) - mean * mean))
	var white := mean > 250.0 and sd < 6.0
	print("[tog]   %-22s 均值 %6.1f  标准差 %5.1f  %s" % [
		tag, mean, sd, "**白屏**" if white else ""])
	if white:
		img.save_png(_out.path_join("white_%s.png" % tag.replace(" ", "_")))
	return {"white": white}
