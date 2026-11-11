extends SceneTree
## 复现「从厅里走上桥、再往前一步就整屏白」（用户 2026-11-11 报的第二次）。
##
## 做法：把玩家放在厅门口，沿 −Z 一小步一小步挪，每步抓一帧、
## 算「近白像素占比」，一旦 >90% 就停下并打印**当时校园渲染器的全部状态**。
## 这样这个 bug 就从「偶发、靠人肉描述」变成「可重复、有数字」。
##
##   & <godot> --path . --position -4000,-4000 --resolution 1280x720 --windowed \
##       --audio-driver Dummy --script res://scripts/_probe_campus_white_walk.gd -- \
##       --no-capture [--ggs-chunks=res://splatdata/campus_chunks10w/chunks.json]
##
## 用哪套分块由命令行给（和出图探针一个套路），方便新旧两条路 A/B。

const OffWin := preload("res://scripts/offscreen_window.gd")
const LEVEL := "res://scenes/next_level.tscn"

var _from_z := -55.0
var _to_z := -110.0
var _step := 1.0
var _y := 1.0
var _x := 0.0
## 每步等多少帧。⚠️ 必须 > `campus_ggs.gd` 的 `WINDOW_POLL`（0.5 s = 30 帧 @60fps），
## 否则 `_maybe_switch_window` 一次都不会被触发 —— 第一版只等 20 帧，
## 等于整段走位一次换窗口都没有，那正是漏掉这个 bug 的原因。
var _dwell := 45
## `true` = 让物理自己起作用（不锁 y、不清速度），只沿 XZ 推玩家。
## ⚠️ 这是**忠实复现**必须的：第一版把玩家硬按在 `y=1.0`，
##    而校园点云的世界 y 范围是 −47~+78 —— 等于把相机塞进云层内部，
##    四面都是泼溅，量到的白是这个原因，不是用户看到的那种。
var _physics := false


func _initialize() -> void:
	if not OS.get_cmdline_user_args().has("--no-capture"):
		push_error("[white] 缺 --no-capture，拒绝运行")
		quit(2)
		return
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--x="):
			_x = float(s.substr(4))
		elif s.begins_with("--y="):
			_y = float(s.substr(4))
		elif s.begins_with("--from="):
			_from_z = float(s.substr(7))
		elif s.begins_with("--to="):
			_to_z = float(s.substr(5))
		elif s.begins_with("--step="):
			_step = maxf(0.25, float(s.substr(7)))
		elif s.begins_with("--dwell="):
			_dwell = maxi(30, int(s.substr(8)))
		elif s == "--physics":
			_physics = true
	_run.call_deferred()


func _run() -> void:
	await OffWin.apply(self)
	var ps := load(LEVEL) as PackedScene
	if ps == null:
		push_error("[white] 加载不了关卡")
		quit(1)
		return
	var level := ps.instantiate()
	root.add_child(level)
	await OffWin.apply(self)
	for _i in 120:
		await process_frame
	var ggs := level.get_node_or_null("CampusGGS")
	var player := level.get_node_or_null("Player")
	if ggs == null or player == null:
		push_error("[white] 缺 CampusGGS 或 Player")
		quit(1)
		return
	print("[white] 分块清单 = %s" % str(ggs.get("chunks_json")))
	print("[white] 从 z=%.1f 走到 z=%.1f，每步 %.1f m" % [_from_z, _to_z, _step])
	print("")
	print("   z(m)   近白%    active  window  fine  coarse  fine层  coarse层")

	var hit_z := 999.0
	var z := _from_z
	# 先让物理把玩家放到地面上（`--physics` 模式），否则后面的 y 全是假的
	if _physics:
		for _i in 120:
			await process_frame
		print("[white] 落定后玩家位置 %s" % str(player.global_position.snappedf(0.01)))
	while z >= _to_z:
		if _physics:
			# 只推 XZ，y 交给物理（走路/落地）
			var cur: Vector3 = player.global_position
			player.global_position = Vector3(_x, cur.y, z)
			for _i in _dwell:
				await process_frame
		else:
			player.global_position = Vector3(_x, _y, z)
			player.set("velocity", Vector3.ZERO)
			player.call("set_flight_lock", true)
			for _i in _dwell:
				player.global_position = Vector3(_x, _y, z)
				await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.resize(160, 90, Image.INTERPOLATE_BILINEAR)
		var w := _white_ratio(img)
		var r = ggs.get("rasterizer")
		var cr = ggs.get("coarse_rasterizer")
		print("  %7.1f  %6.1f%%   %-6s  %-6d  %-4s  %-6s  %-6s  %s   y=%.1f" % [
			z, w * 100.0, str(ggs.get("_active")),
			(ggs.get("_window_names") as PackedStringArray).size(),
			str(_fine_ready(ggs)), str(ggs.get("_coarse_ready")),
			str(r != null and bool(r.is_loaded)),
			str(cr != null and bool(cr.is_loaded)),
			player.global_position.y])
		if w > 0.9:
			hit_z = z
			# 抓下此刻的完整状态 + 原尺寸图，别只留个数字
			var stamp := "z%.0f" % z
			root.get_texture().get_image().save_png(
				"C:/Users/WY157/Desktop/GODOT/_arisu_learn/_log/_white_walk_%s.png" % stamp)
			print("[white]   截图 _log/_white_walk_%s.png" % stamp)
			# ⚠️ 必须 await：`_layer_diag` 里面有 await process_frame，
			#    不 await 的话主流程直接 break → quit()，那段根本没跑完（第一版就是这样）。
			await _layer_diag(ggs, stamp)
			break
		z -= _step

	print("")
	if hit_z < 900.0:
		print("[white] ★ 复现：z = %.1f 处近白 %.0f%%" % [hit_z, 100.0])
		print("[white]   分块清单 %s" % str(ggs.get("chunks_json")))
		print("[white]   _bin_path = %s" % str(ggs.get("_bin_path")))
		print("[white]   窗口 = %s" % ", ".join(ggs.get("_window_names")))
	else:
		print("[white] 这一段走完没有出现整屏白")
	quit(0)


## 近白像素占比（三通道都 > 245）
func _white_ratio(img: Image) -> float:
	var n := 0
	var w := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			n += 1
			if c.r > 0.961 and c.g > 0.961 and c.b > 0.961:
				w += 1
	return float(w) / maxf(float(n), 1.0)


func _fine_ready(ggs: Node) -> String:
	var v = ggs.get("_fine_ready")
	return "%.0f" % float(v) if v != null else "?"


## 白屏瞬间的分层归因：分别只留粗层 / 只留细层 / 都不留，各抓一帧。
## 哪一档白，就是那一层的纹理/光栅器出了问题。
## ⚠️ 这里直接改 `_quad_mat` 的着色器参数（矩阵里那两个开关就是干这个的）：
##    `fine_ready` / `coarse_ready` 置 0 = 该层完全不采样。
func _layer_diag(ggs: Node, stamp: String) -> void:
	var mat = ggs.get("_quad_mat")
	if mat == null:
		print("[white]   拿不到 _quad_mat，没法分层诊断")
		return
	var fine0 = ggs.get("_fine_ready")
	var coarse0 = ggs.get("_coarse_ready")
	print("[white]   ── 分层诊断（矩阵开关，改完会还原）──")
	# 先把细层光栅器的关键字段打出来：尺寸/缩放/加载数对不上，投出去就是满屏
	var r = ggs.get("rasterizer")
	print("[white]   视口=%s  _want_size=%s" % [
		str(root.get_visible_rect().size), str(ggs.get("_want_size"))])
	if r != null:
		print("[white]   rasterizer: render_scale=%s texture_size=%s is_loaded=%s loaded=%s/%s" % [
			str(r.render_scale), str(r.texture_size), str(r.is_loaded),
			str(r.num_splats_loaded[0]), str(ggs.get("_total"))])
		print("[white]   cov_scale=%s cov_limit=%s model_scale=%s" % [
			str(r.cov_scale), str(r.cov_limit), str(r.model_scale)])
	var t = ggs.get("tex")
	if t != null and r != null and r.render_texture != null:
		print("[white]   tex.rid=%s  render_texture.rid=%s  same=%s" % [
			str(t.texture_rd_rid), str(r.render_texture.texture_rd_rid),
			str(t.texture_rd_rid == r.render_texture.texture_rd_rid)])
	for cfg in [["只有粗层", 0.0, 1.0], ["只有细层", 1.0, 0.0], ["两层都不采", 0.0, 0.0]]:
		mat.set_shader_parameter("fine_ready", float(cfg[1]))
		mat.set_shader_parameter("coarse_ready", float(cfg[2]))
		for _i in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		var im := root.get_texture().get_image()
		im.save_png("C:/Users/WY157/Desktop/GODOT/_arisu_learn/_log/_white_layer_%s_%s.png"
			% [stamp, cfg[0]])
		var im2 := im.duplicate()
		im2.resize(160, 90, Image.INTERPOLATE_BILINEAR)
		print("[white]     %-12s 近白 %5.1f%%   → _log/_white_layer_%s_%s.png"
			% [cfg[0], _white_ratio(im2) * 100.0, stamp, cfg[0]])
	mat.set_shader_parameter("fine_ready", float(fine0))
	mat.set_shader_parameter("coarse_ready", float(coarse0))
	for _i in 4:
		await process_frame
