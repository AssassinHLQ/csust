extends SceneTree
## 【诊断】为什么**飞高了就看不见校园泼溅**（用户 2026-11-13）。
##
## ── 用户报告 ──
##
##   「为什么飞高了就看不见校园泼溅了」
##   配图：相机在高空，视野里只有天空 + 三面深色墙，没有校园。
##
## ── 已经排除的（都由用户确认，别再往回猜）──
##
##   ✅ 不是 `FALL_LIMIT`（= -60，y=0.3 根本不会触发）
##   ✅ 不是 `hide_inside_aabb`（= y ∈ [-3, 16]，用户飞 20 m 以上已经出框）
##   ✅ 不是 `campus_ggs.gd` 的 `z < -74`（`_wants_campus_ggs()` 默认 false，
##      正常启动走的是 GDGS + `splat_scene.gd`）
##   ✅ 不是卸载（用户确认：落地**立刻**就回来，而重新解码要 40 s）
##
## ── 本探针干什么 ──
##
## 同一个水平位置（校园里，`z = -130`），把玩家抬到 5 个高度，
## 每个高度等稳定后打一次状态 + 出一张图 + 量一次"非天空占比"。
##
## 这一次性排除所有剩余候选：
##
##   ① `splat_node` 变 null          → 被卸载（但用户说立刻恢复，理论上不会）
##   ② `visible == false`            → 被藏起来
##   ③ `cam.far` 被 `splat_far_max` 截断 → 远平面切掉
##   ④ 上面都对但画面仍是天空         → GDGS 自己的 GPU 侧裁剪 / 渲染问题
##
## ── 窗口安全（`AGENTS.md` 硬要求）──
##
##   · `OffWin.apply()` 挪到 (-4000,-4000)，并**断言**确实挪走了
##   · 必须带 `--no-capture`，不收鼠标
##   · 跑完 `quit()`，不晾窗口
##
##   _tools/run_shot.sh res://scripts/_probe_campus_height.gd -- --no-capture
##   或：
##   godot --path . --script res://scripts/_probe_campus_height.gd -- --no-capture

const OffWin := preload("res://scripts/offscreen_window.gd")
const OUT_DIR := "C:/Users/WY157/Desktop/GODOT/_arisu_captures/_campus_height"

## 水平位置：校园里（和 `_probe_gdgs_campus_diag.gd` 用同一个点）
const SPOT_XZ := Vector2(0.0, -130.0)
## 要试的高度（米）。**上下都要**（用户 2026-11-13：
## 「对了，在下面也要看得到，不只是上面」）。
## 下界取到 -100：`_room_y_lo` 实测 -25.5，所以 -40/-60/-100 都在下界之外。
const HEIGHTS: Array[float] = [2.0, 20.0, 40.0, 80.0, -40.0, -60.0, -100.0]
## 每个高度等多久（帧）—— 让 `_update_room_exit_unload` / `_update_camera_far` 跑够
const SETTLE := 45


func _initialize() -> void:
	if not OS.get_cmdline_user_args().has("--no-capture"):
		push_error("[height] 缺 --no-capture，拒绝运行")
		quit(2)
		return
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


## 量一张图里"非天空"的占比。天空判据抄 `_probe_gdgs_campus_diag.gd`：
## 偏蓝且亮（本项目天空是淡蓝渐变）。**非天空占比高 = 看得见校园**。
func _non_sky_ratio(img: Image) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var step := 8
	var n := 0
	var sky := 0
	for y in range(0, h, step):
		for x in range(0, w, step):
			var c := img.get_pixel(x, y)
			var l := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
			if l > 0.72 and c.b >= c.r:
				sky += 1
	if n == 0:
		return 0.0
	return 1.0 - float(sky) / float(n)


## 打印某一个高度下的全部相关状态。
func _report(campus: Node, player: Node3D, cam: Camera3D, height: float) -> Dictionary:
	var node: Node3D = null
	if campus != null and is_instance_valid(campus):
		node = campus.get("splat_node") as Node3D
	var pts := -1
	if node != null:
		var g = node.get("gaussian")
		if g != null:
			pts = int(g.get("point_count"))
	var vis := "无节点"
	if node != null:
		vis = str(node.visible)
	# `_is_inside_room()` 是 `_update_room_exit_unload()` 的判据 —— 它触发卸载
	var inside := "?"
	if campus != null and is_instance_valid(campus) and campus.has_method("_is_inside_room"):
		inside = str(bool(campus.call("_is_inside_room", player.global_position)))
	var y_lo := 0.0
	var y_hi := 0.0
	if campus != null and is_instance_valid(campus):
		y_lo = float(campus.get("_room_y_lo"))
		y_hi = float(campus.get("_room_y_hi"))
	var far := 0.0
	if cam != null:
		far = cam.far
	var d := {
		"height": height,
		"splat_alive": node != null,
		"points": pts,
		"visible": vis,
		"inside": inside,
		"y_lo": y_lo,
		"y_hi": y_hi,
		"cam_far": far,
		"cam_y": cam.global_position.y if cam != null else 0.0,
	}
	print("[height] y=%5.1f  splat=%s 点=%-8d 可见=%-6s inside=%-5s  判据y=%.1f~%.1f  cam.far=%.0f  cam.y=%.1f"
		% [height, "有" if node != null else "**无**", pts, vis, inside, y_lo, y_hi, far,
		d["cam_y"]])
	return d


func _run() -> void:
	await OffWin.apply(self, Vector2i(960, 540))
	var safe0: Array = OffWin.is_safe()
	if not bool(safe0[0]):
		push_error("[height] 窗口没挪到屏幕外，拒绝出图：%s" % str(safe0[1]))
		quit(2)
		return
	print("[height] 窗口安全：%s" % str(safe0[1]))
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	var ps := load("res://scenes/next_level.tscn") as PackedScene
	if ps == null:
		push_error("[height] 加载不了关卡")
		quit(1)
		return
	var level := ps.instantiate()
	root.add_child(level)
	await OffWin.apply(self, Vector2i(960, 540))

	var player := level.get_node_or_null("Player") as Node3D
	if player == null:
		push_error("[height] 缺 Player")
		quit(1)
		return
	var campus := level.get_node_or_null("Campus")
	if campus == null:
		push_error("[height] 缺 Campus 节点")
		quit(1)
		return
	# 跳过 start_delay，立刻开始解码
	campus.set("start_delay", 0.0)
	campus.set("low_priority", false)
	campus.call("force_start")

	player.global_position = Vector3(SPOT_XZ.x, 2.0, SPOT_XZ.y)
	player.set("velocity", Vector3.ZERO)

	# 等就绪（最长 240 s）
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 240000:
		if bool(campus.call("is_ready")):
			break
		await process_frame
	print("[height] ★ 就绪耗时 %d ms" % (Time.get_ticks_msec() - t0))
	await _wait(180)   # 稳 3 s

	var cam := root.get_viewport().get_camera_3d()
	if cam == null:
		push_error("[height] 没有活动相机")
		quit(1)
		return
	print("[height] 相机「%s」  fov=%.1f  far=%.0f" % [cam.name, cam.fov, cam.far])
	print("[height] ================= 逐高度对比 =================")

	var rows: Array[Dictionary] = []
	for h: float in HEIGHTS:
		player.global_position = Vector3(SPOT_XZ.x, h, SPOT_XZ.y)
		player.set("velocity", Vector3.ZERO)
		await _wait(SETTLE)
		var d := _report(campus, player, cam, h)
		# 出图 + 量像素
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var ratio := _non_sky_ratio(img)
		d["non_sky"] = ratio
		print("[height]        → 非天空占比 %.1f%%%s"
			% [ratio * 100.0, "   ← 看得见校园" if ratio > 0.25 else "   ← **几乎只有天空**"])
		# 负高度用 m 前缀，避免文件名里出现 `y_-100.png` 那种带减号的路径
		var tag_name := "y_%03d" % int(h) if h >= 0.0 else "y_m%03d" % int(-h)
		img.save_png("%s/%s.png" % [OUT_DIR, tag_name])
		rows.append(d)

	print("[height] ================= 结论 =================")
	# ── 判据演进（两次都踩了坑，留档）──
	#   ① 第一版只看「非天空占比」→ y=80 时 `splat=**无**` 却报 48.2%「看得见」。
	#      那 48% 是**楼体网格**（`CampusCollision`），不是泼溅。假阳性。
	#   ② 第二版加了「节点在 + 可见」，但没排除**玩家被关卡传送**的情形：
	#      y=-40 / -60 时玩家掉进 `next_level.tscn` 的 `FallReset`（Area3D），
	#      被 `_on_fall()` 传回 `SpawnPoint`（大厅里，|x|<15 且 |z|<10），
	#      于是 `next_level.gd::_update_campus_visibility` 按设计把校园藏了 ——
	#      报成「泼溅丢失」，其实是**玩家已经不在那个高度了**。
	#   ③ 现在加一条「传送检测」：相机实际 y 和被设置的高度差太多 ⇒ 这一档作废。
	var first_broken := -1.0
	var all_ok := true
	var skipped := 0
	for d in rows:
		var drift: float = absf(float(d["cam_y"]) - float(d["height"]))
		# 第三人称弹簧臂会把相机甩开几米，所以阈值给宽一点；
		# 被传送回出生点是几十上百米的差，不会误判。
		var teleported := drift > 30.0 and float(d["height"]) < 0.0
		if teleported:
			skipped += 1
			continue
		var ok: bool = bool(d["splat_alive"]) and str(d["visible"]) == "true" \
			and float(d["non_sky"]) > 0.25
		if not ok:
			all_ok = false
			if first_broken < 0.0:
				first_broken = float(d["height"])
	if all_ok:
		print("[height] [PASS] 所有有效高度都保住泼溅（节点在、可见、画面有内容）")
		if skipped > 0:
			print("[height]        跳过 %d 档负高度：玩家被关卡 `FallReset` 传送走了，"
				% skipped + "不构成泼溅问题")
	else:
		print("[height] [FAIL] 自 y=%.0f 起泼溅丢失" % first_broken)
	print("[height] 逐行判定:")
	for d in rows:
		var drift2: float = absf(float(d["cam_y"]) - float(d["height"]))
		var teleported2 := drift2 > 30.0 and float(d["height"]) < 0.0
		var ok2: bool = bool(d["splat_alive"]) and str(d["visible"]) == "true" \
			and float(d["non_sky"]) > 0.25
		var mark := "✗"
		if teleported2:
			mark = "-（被 FallReset 传送，不计）"
		elif ok2:
			mark = "✓"
		print("[height]   y=%5.1f  %-6s %-6s %5.1f%%  %s"
			% [float(d["height"]), "有" if bool(d["splat_alive"]) else "**无**",
			str(d["visible"]), float(d["non_sky"]) * 100.0, mark])
	print("[height] 图片输出目录：%s" % OUT_DIR)
	quit(0 if all_ok else 1)
