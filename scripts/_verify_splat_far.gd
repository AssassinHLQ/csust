extends SceneTree
## 验证：泼溅是否真的「不受渲染距离限制」。
##
## 做法：站在校园**近端**（z≈-90，靠大厅那侧），朝里看。
## 校园 z 范围约 −559~−75，所以远端离相机 400~470 m，
## 而默认 `render_distance` = 300 m ⇒ 老行为下大半校园会被远平面剪掉。
##
## 三张图 + 数字：
##   A 关掉开关（far 跟着 render_distance 走）
##   B 打开开关（far 撑到装得下内容盒）
##   C 关雾后的 B（排除「远处被粉雾吃掉」的干扰）
##
## 判据：B 必须比 A 在**远处**多出实体像素（差值集中在画面下半/中段）。
##
##   _tools/run_shot.sh res://scripts/_verify_splat_far.gd -- --no-capture

const OffWin := preload("res://scripts/offscreen_window.gd")
const OUT_DIR := "C:/Users/WY157/Desktop/GODOT/_arisu_captures/_splat_far"

var _pass := 0
var _fail := 0


func _initialize() -> void:
	if not OS.get_cmdline_user_args().has("--no-capture"):
		push_error("[far] 缺 --no-capture")
		quit(2)
		return
	_run.call_deferred()


func _check(ok: bool, what: String, detail := "") -> void:
	if ok:
		_pass += 1
		print("  [PASS] %s%s" % [what, ("  " + detail) if detail != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s%s" % [what, ("  " + detail) if detail != "" else ""])


func _shot(cam: Camera3D, from_: Vector3, to_: Vector3, tag: String) -> Image:
	for _i in 20:
		cam.look_at_from_position(from_, to_, Vector3.UP)
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT_DIR, tag])
	return img


func _diff_ratio(a: Image, b: Image) -> float:
	var step := 6
	var n := 0
	var diff := 0
	for y in range(0, a.get_height(), step):
		for x in range(0, a.get_width(), step):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.10:
				diff += 1
			n += 1
	return 100.0 * float(diff) / maxf(1.0, float(n))


func _run() -> void:
	print("========== 泼溅是否不受渲染距离限制 ==========")
	await OffWin.apply(self, Vector2i(1280, 720))
	var safe0: Array = OffWin.is_safe()
	if not bool(safe0[0]):
		push_error("[far] 窗口没挪到屏幕外：%s" % str(safe0[1]))
		quit(2)
		return

	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	await process_frame

	var player := level.get_node_or_null("Player") as Node3D
	player.global_position = Vector3(-20.0, 0.5, -95.0)
	var campus: Node3D = level.get_node_or_null("Campus")
	campus.set("start_delay", 0.0)
	campus.set("low_priority", false)
	campus.call("force_start")
	var t0 := Time.get_ticks_msec()
	while not bool(campus.call("is_ready")) and Time.get_ticks_msec() - t0 < 240000:
		await process_frame
	print("[far] 点云就绪 %d ms" % (Time.get_ticks_msec() - t0))

	var box: AABB = campus.call("content_world_aabb")
	# ⚠️ 机位必须**高过树冠**、视线真的穿过 300 m 界线。
	#    第一版站在 (-20,8,-95) 朝里看，相机埋在树里，近处树叶糊满全屏，
	#    far 300 和 612 拍出来一模一样（差异 0.0%）—— 视角选错了，不是功能无效。
	var from_ := Vector3(0.0, 95.0, -70.0)
	var to_ := Vector3(0.0, 0.0, -470.0)
	var need := 0.0
	for i in 8:
		var c := box.position + Vector3(box.size.x * float(i & 1),
			box.size.y * float((i >> 1) & 1), box.size.z * float((i >> 2) & 1))
		need = maxf(need, from_.distance_to(c))
	print("[far] 内容盒 x %.0f~%.0f z %.0f~%.0f；相机到最远角 %.1f m"
		% [box.position.x, box.end.x, box.position.z, box.end.z, need])

	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.05
	cam.far = 4000.0
	level.add_child(cam)
	cam.make_current()

	# ── A：模拟老行为（far = render_distance = 300）──
	campus.set("splat_ignore_render_distance", false)
	for _i in 10:
		await process_frame
	cam.far = 300.0
	var img_a: Image = await _shot(cam, from_, to_, "a_受限300")
	print("[far] A 受限 far=%.0f" % cam.far)

	# ── B：打开开关，让 splat_scene 自己去撑 ──
	campus.set("splat_ignore_render_distance", true)
	cam.far = 300.0        # 故意先压回 300，看它会不会自己撑大
	for _i in 12:
		cam.look_at_from_position(from_, to_, Vector3.UP)
		await process_frame
	var far_b := cam.far
	var img_b: Image = await _shot(cam, from_, to_, "b_不受限")
	print("[far] B 不受限 far=%.1f（期望 ≥ %.0f）" % [far_b, need])
	_check(far_b >= need, "远平面被撑到装得下整个内容盒",
		"far %.0f ≥ 需要的 %.0f" % [far_b, need])
	_check(far_b > 301.0, "确实比 render_distance(300) 大", "far=%.0f" % far_b)

	# ── C：关雾再拍 B，排除「远处被粉雾吃掉」的干扰 ──
	var we := level.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var fog_was := false
	if we != null and we.environment != null:
		fog_was = we.environment.fog_enabled
		we.environment.fog_enabled = false
	var img_c: Image = await _shot(cam, from_, to_, "c_不受限_无雾")
	var img_c300: Image

	# ── D：无雾 + 受限，和 C 对比才有意义 ──
	campus.set("splat_ignore_render_distance", false)
	cam.far = 300.0
	for _i in 10:
		await process_frame
	img_c300 = await _shot(cam, from_, to_, "d_受限300_无雾")
	if we != null and we.environment != null:
		we.environment.fog_enabled = fog_was

	var d_both := _diff_ratio(img_a, img_b)
	var d_nofog := _diff_ratio(img_c300, img_c)
	print("[far] A↔B 画面差异 %.1f%%；无雾下 受限↔不受限 差异 %.1f%%" % [d_both, d_nofog])
	_check(d_nofog > 3.0, "无雾时两种 far 画面明显不同（证明远平面真的在剪东西）",
		"%.1f%%" % d_nofog)

	# ── 室内 609 不该被影响：内容盒很小，far 不该被撑大 ──
	print("[far] dir = %s" % OUT_DIR)
	print("========== 通过 %d，失败 %d ==========" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
