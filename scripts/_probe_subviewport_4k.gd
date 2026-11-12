extends SceneTree
## 验证：用 SubViewport 离屏渲染 4K（**完全不动窗口**）。
##
##   bash _tools/run_shot_direct.sh res://scripts/_probe_subviewport_4k.gd
##
## 背景（2026-11-12 用户第三次报 F8 闪退）：
##   真正的崩溃路径是「窗口最大化 → 切窗口化 → 瞬间拉 3840×2000」。
##   本喵的探针从窗口化 1600×900 起步，所以一直复现不出来。
##   既然窗口 resize 在这台机器上会崩 Vulkan，那就**别碰窗口**：
##   新建一个 3840×2160 的 SubViewport，共享同一个 World3D，
##   用一台副本相机渲染一帧，再 `get_texture().get_image()`。
##
## 本探针要回答两件事：
##   ① 离屏 4K 能不能出图（3840×2160）；
##   ② 高斯泼溅在 SubViewport 里渲不渲得出来
##      （要把它主相机那份 `compositor` 复制过来，否则 GDGS Compute 后端不出图）。

const SHOT_REL := "_arisu_captures/_4kprobe"

var _game: Node


func _initialize() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	# 看门狗：探针里任何一步报错都会让协程停住、进程不退（上一版就卡死了）。
	# 180 s 后无条件退出，别把窗口晾在那儿。
	var wd := create_timer(180.0, true)
	wd.timeout.connect(func() -> void:
		print("[sub4k] !! 看门狗超时，强制退出")
		quit(2))
	_run.call_deferred()


func _run() -> void:
	print("========== SubViewport 离屏 4K ==========")
	_game = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(_game)
	current_scene = _game
	for _i in 25:
		await process_frame

	# 等画室泼溅加载完（不带 --splat=off 时约 2~3 s；带 off 则立即通过）
	var room := _game.get_node_or_null("Room609")
	var t0 := Time.get_ticks_msec()
	while room != null and not bool(room.call("is_ready")) \
			and float(Time.get_ticks_msec() - t0) / 1000.0 < 45.0:
		await process_frame
	print("画室就绪=%s（等 %.1f s）" % [
		"-" if room == null else str(room.call("is_ready")),
		float(Time.get_ticks_msec() - t0) / 1000.0])
	for _i in 20:
		await process_frame

	# ── 主相机（玩家那台）──
	var main_vp := root
	var src_cam := main_vp.get_camera_3d()
	if src_cam == null:
		print("✗ 找不到主相机")
		quit(1)
		return
	print("主相机：%s  compositor=%s" % [
		src_cam.name, "有" if src_cam.compositor != null else "无"])

	# ── 建 4K SubViewport，共享同一个 World3D ──
	var sub := SubViewport.new()
	sub.name = "Offscreen4K"
	sub.size = Vector2i(3840, 2160)
	sub.own_world_3d = false
	sub.world_3d = main_vp.world_3d
	sub.transparent_bg = false
	sub.msaa_3d = main_vp.msaa_3d
	sub.screen_space_aa = main_vp.screen_space_aa
	sub.use_taa = main_vp.use_taa
	sub.scaling_3d_scale = 1.0
	sub.render_target_update_mode = SubViewport.UPDATE_ONCE
	root.add_child(sub)

	var sub_cam := Camera3D.new()
	sub_cam.name = "ShotCam"
	sub_cam.fov = src_cam.fov
	sub_cam.near = src_cam.near
	sub_cam.far = src_cam.far
	sub_cam.cull_mask = src_cam.cull_mask
	sub_cam.environment = src_cam.environment
	# Godot 4 里这个属性叫 `attributes`（不是 `camera_attributes`）
	sub_cam.attributes = src_cam.attributes
	# ★ 关键：GDGS Compute 后端靠相机上的 Compositor 把泼溅合成回画面，
	#   不复制这一份，SubViewport 里就**一张泼溅都没有**（很安静地没有）。
	sub_cam.compositor = src_cam.compositor
	sub.add_child(sub_cam)
	sub_cam.global_transform = src_cam.global_transform
	sub_cam.current = true
	print("SubViewport：%s，共享 world_3d=%s，相机 compositor=%s" % [
		str(sub.size), str(sub.world_3d == main_vp.world_3d),
		"有" if sub_cam.compositor != null else "无"])

	# 渲染几帧（第一帧要建 4K 渲染目标 + 泼溅排序）
	for i in 4:
		sub.render_target_update_mode = SubViewport.UPDATE_ONCE
		await process_frame
		print("  离屏第 %d 帧，RT 尺寸 %s" % [i + 1, str(sub.get_texture().get_size())])

	await RenderingServer.frame_post_draw
	var img := sub.get_texture().get_image()
	if img == null:
		print("✗ get_image() 返回 null")
		quit(1)
		return
	print("离屏出图：%d×%d" % [img.get_width(), img.get_height()])
	var dir := ProjectSettings.globalize_path("res://").path_join(SHOT_REL)
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("subviewport_4k.png")
	var err := img.save_png(path)
	print("保存 %s（错误 %d）" % [path, err])
	# 统计一下画面里是不是「只有黑/纯色」——如果泼溅没渲出来，往往整屏接近单色
	var px := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
	var px2 := img.get_pixel(img.get_width() / 3, img.get_height() / 3)
	print("采样：中心 %s，左上 %s" % [str(px), str(px2)])

	sub.queue_free()
	quit(0)
