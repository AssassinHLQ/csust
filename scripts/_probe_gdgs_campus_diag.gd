extends SceneTree
## GDGS（Compute）全量校园：**为什么什么都看不见**。
##
## 干三件事：
##   1) 每 5 s 打一次状态（is_ready / splat_node / 点数 / 可见性 / 相机 compositor）
##   2) 就绪后出 3 张图（玩家机位 + 俯瞰机位 + 45 度机位）
##   3) 顺手把「像素里到底有没有非天空内容」量出来（亮度直方图 + 非天空占比）
##
##   _tools/run_shot.sh res://scripts/_probe_gdgs_campus_diag.gd -- --no-capture
##
## ⚠️ 窗口安全靠 `OffWin.is_safe()` 实测，不看命令行参数（`--position` 会被引擎吃掉）。

const OffWin := preload("res://scripts/offscreen_window.gd")
const OUT_DIR := "C:/Users/WY157/Desktop/GODOT/_arisu_captures/_gdgs_campus"


func _initialize() -> void:
	if not OS.get_cmdline_user_args().has("--no-capture"):
		push_error("[diag] 缺 --no-capture，拒绝运行")
		quit(2)
		return
	_run.call_deferred()


func _report(level: Node, campus: Node, player: Node3D, el: int) -> void:
	var ready_ := false
	if campus != null and is_instance_valid(campus):
		ready_ = bool(campus.call("is_ready"))
	var node: Node3D = null
	if campus != null and is_instance_valid(campus):
		node = campus.get("splat_node") as Node3D
	var pts := -1
	if node != null:
		var g = node.get("gaussian")
		if g != null:
			pts = int(g.get("point_count"))
	var vis := "?"
	if node != null:
		vis = str(node.visible)
	var cam := root.get_viewport().get_camera_3d()
	var comp := "无相机"
	if cam != null:
		comp = "有" if cam.compositor != null else "无"
	var attached := -1
	var sc := root.get_node_or_null("SplatCompositor")
	if sc != null:
		attached = (sc.get("_attached") as Dictionary).size()
	print("[diag %6d ms] campus=%s ready=%s splat=%s 点=%d 可见=%s 相机「%s」compositor=%s 已挂=%d 玩家=%s 判据 y=%.1f~%.1f"
		% [el, str(campus != null and is_instance_valid(campus)), str(ready_),
		str(node != null), pts, vis, cam.name if cam else "-", comp, attached,
		str(player.global_position.round()),
		float(campus.get("_room_y_lo")) if campus != null else 0.0,
		float(campus.get("_room_y_hi")) if campus != null else 0.0])


## 量一张图里「像不像只有天空」。
func _measure(img: Image, tag: String) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var step := 8
	var hist := [0, 0, 0, 0, 0]
	var n := 0
	var sky := 0
	var sum := 0.0
	# 天空判据：偏蓝且亮（R<B 且 L>0.72）——本项目天空是淡蓝渐变
	for y in range(0, h, step):
		for x in range(0, w, step):
			var c := img.get_pixel(x, y)
			var l := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			sum += l
			n += 1
			var b := int(clampf(l * 5.0, 0.0, 4.0))
			hist[b] += 1
			if l > 0.72 and c.b >= c.r:
				sky += 1
	print("[量 %s] 采样 %d 平均亮度 %.3f  直方图(0-0.2/0.2-0.4/0.4-0.6/0.6-0.8/0.8-1)=%s  疑似天空占比 %.1f%%"
		% [tag, n, sum / maxf(1.0, float(n)), str(hist), 100.0 * float(sky) / maxf(1.0, float(n))])


func _shot(name_: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name_]
	var err := img.save_png(path)
	print("[图] %s → %s err=%d size=%s" % [name_, path, err, str(img.get_size())])
	if err == OK:
		_measure(img, name_)


func _run() -> void:
	await OffWin.apply(self, Vector2i(1280, 720))
	var safe0: Array = OffWin.is_safe()
	if not bool(safe0[0]):
		push_error("[diag] 窗口没挪到屏幕外，拒绝出图：%s" % str(safe0[1]))
		quit(2)
		return
	print("[diag] 窗口安全：%s" % str(safe0[1]))
	print("[diag] 后端设置 = %s；渲染方法 = %s" % [
		str(ProjectSettings.get_setting("gdgs/rendering/backend", "?")),
		str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"))])

	var ps := load("res://scenes/next_level.tscn") as PackedScene
	if ps == null:
		push_error("[diag] 加载不了关卡")
		quit(1)
		return
	var level := ps.instantiate()
	root.add_child(level)
	await OffWin.apply(self, Vector2i(1280, 720))

	var player := level.get_node_or_null("Player") as Node3D
	if player == null:
		push_error("[diag] 缺 Player")
		quit(1)
		return
	# 先把玩家挪到校园里：`_update_campus_visibility()` 在 |x|<=15 且 |z|<=10（大厅）里
	# 会主动把泼溅藏起来，留在出生点看不出任何东西
	player.global_position = Vector3(0.0, 2.0, -130.0)
	player.set("velocity", Vector3.ZERO)

	var campus := level.get_node_or_null("Campus")
	if campus == null:
		push_error("[diag] 缺 Campus 节点（也许被 --campus-splat=off 放掉了）")
		quit(1)
		return
	# 跳过 start_delay=8 s，立刻开始解码
	campus.set("start_delay", 0.0)
	campus.set("low_priority", false)
	campus.call("force_start")

	# 等就绪，每 5 s 报一次
	var t0 := Time.get_ticks_msec()
	var next_report := 0
	while Time.get_ticks_msec() - t0 < 240000:
		var el := Time.get_ticks_msec() - t0
		if el >= next_report:
			next_report += 5000
			_report(level, campus, player, el)
		if bool(campus.call("is_ready")):
			break
		await process_frame
	var ready_ms := Time.get_ticks_msec() - t0
	_report(level, campus, player, ready_ms)
	print("[diag] ★ 就绪耗时 %d ms" % ready_ms)

	# 就绪后再等 3 s，让合成缓冲稳定
	for _i in 180:
		await process_frame

	# 机位 A：玩家第一人称前方（贴地看校园）
	var cam := root.get_viewport().get_camera_3d()
	await _shot("a_player")
	print("[diag] 机位A 相机「%s」compositor=%s" % [
		cam.name if cam else "-", str(cam != null and cam.compositor != null)])

	# 机位 B：自己架一台俯瞰相机
	var cam2 := Camera3D.new()
	cam2.fov = 55.0
	cam2.near = 0.05
	level.add_child(cam2)
	cam2.make_current()
	var target := Vector3(0.0, 0.0, -300.0)
	cam2.global_position = target + Vector3(0.0, 120.0, 200.0)
	cam2.look_at(target, Vector3.UP)
	for _i in 30:
		cam2.global_position = target + Vector3(0.0, 120.0, 200.0)
		cam2.look_at(target, Vector3.UP)
		await process_frame
	await _shot("b_aerial")
	print("[diag] 机位B 相机「%s」compositor=%s" % [
		cam2.name, str(cam2.compositor != null)])

	# 机位 C：贴地 45 度
	var cam3 := Camera3D.new()
	cam3.fov = 60.0
	cam3.near = 0.05
	level.add_child(cam3)
	cam3.make_current()
	var p3 := Vector3(0.0, 3.0, -130.0)
	cam3.look_at_from_position(p3, Vector3(0.0, 3.0, -220.0), Vector3.UP)
	for _i in 30:
		cam3.look_at_from_position(p3, Vector3(0.0, 3.0, -220.0), Vector3.UP)
		await process_frame
	await _shot("c_ground")
	print("[diag] 机位C 相机「%s」compositor=%s" % [
		cam3.name, str(cam3.compositor != null)])

	_report(level, campus, player, Time.get_ticks_msec() - t0)

	# 机位 D/E：真正的「玩家视线高度」（1.7 m）站在校园路面上。
	# 机位 A/C 的 z=-130 那一带是树丛，镜头埋在树冠里，看不出路面质量。
	var eye_spots := [
		["d_road_a", Vector3(-95.0, 1.7, -96.0), Vector3(-95.0, 1.4, -160.0)],
		["e_road_b", Vector3(0.0, 1.7, -300.0), Vector3(0.0, 1.4, -380.0)],
	]
	var cam_eye := Camera3D.new()
	cam_eye.fov = 70.0
	cam_eye.near = 0.05
	cam_eye.far = 2000.0
	level.add_child(cam_eye)
	cam_eye.make_current()
	for item in eye_spots:
		var tag := String(item[0])
		var from_: Vector3 = item[1]
		var to_: Vector3 = item[2]
		for _i in 20:
			cam_eye.look_at_from_position(from_, to_, Vector3.UP)
			await process_frame
		await _shot(tag)

	print("[diag] 完")
	quit(0)
