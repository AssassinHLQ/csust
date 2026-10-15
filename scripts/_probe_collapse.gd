extends SceneTree
## 探针：动态 3DGS「坍缩」效果验证 + 出图。
##
## 把一份 .sog/.sogdata 挂成 SplatScene，按给定进度逐档 set_collapse() 后渲染。
## 同时打印每档的世界包围盒尺寸：因为
##     world 点 = basis · 源点 + offset，而 basis 里含坍缩系数 k
## 所以包围盒尺寸应当**精确**等于 k × 原尺寸 —— 这比肉眼看图硬得多。
##
## 摆位：加载后读 content_min/max，把内容中心平移到世界原点，
## 于是 offset 就是原点 ⇒ **坍缩点恰好是 (0,0,0)**，不用猜地板在哪。
##
## 用法：
##   godot --path <工程> --script res://scripts/_probe_collapse.gd -- \
##         --sog=res://splatdata/collapse_test.sogdata --scale=2.5 \
##         --t=0,0.25,0.5,0.7,0.85,0.95,1.0 --fade=1
## 输出：…/_arisu_captures/_collapse/*.png

const SplatSceneScript := preload("res://scripts/splat_scene.gd")

var _source := "res://splatdata/collapse_test.sogdata"
var _scale := 2.5
var _yaw := 0.0
var _steps: PackedFloat32Array = PackedFloat32Array([0.0, 0.25, 0.5, 0.7, 0.85, 0.95, 1.0])
var _fade := false
var _crop := false
var _tag := ""
var _easing := "in_cubic"
var _duration := 6.0
var _mode := "uniform"
var _stagger := 0.6
var _brown := 0.0
var _brown_freq := 1.0
var _brown_seed := 0
var _rise := 0.0
var _rise_jitter := 0.8
var _rise_span := 1.0
var _rise_loop := false
var _rise_side := 0.0
var _rise_step := 0.25


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sog="):
			_source = a.substr(6)
		elif a.begins_with("--scale="):
			_scale = float(a.substr(8))
		elif a.begins_with("--yaw="):
			_yaw = float(a.substr(6))
		elif a.begins_with("--fade="):
			_fade = a.substr(7) != "0"
		elif a.begins_with("--crop="):
			_crop = a.substr(7) != "0"
		elif a.begins_with("--easing="):
			_easing = a.substr(9)
		elif a.begins_with("--duration="):
			_duration = float(a.substr(11))
		elif a.begins_with("--mode="):
			_mode = a.substr(7)
		elif a.begins_with("--stagger="):
			_stagger = float(a.substr(10))
		elif a.begins_with("--brown="):
			_brown = float(a.substr(8))
		elif a.begins_with("--brownfreq="):
			_brown_freq = float(a.substr(12))
		elif a.begins_with("--brownseed="):
			_brown_seed = int(a.substr(12))
		elif a.begins_with("--risejitter="):
			_rise_jitter = float(a.substr(13))
		elif a.begins_with("--rise="):
			_rise = float(a.substr(7))
		elif a.begins_with("--risespan="):
			_rise_span = float(a.substr(11))
		elif a.begins_with("--riseloop="):
			_rise_loop = a.substr(11) != "0"
		elif a.begins_with("--riseside="):
			_rise_side = float(a.substr(11))
		elif a.begins_with("--risestep="):
			_rise_step = float(a.substr(11))
		elif a.begins_with("--tag="):
			_tag = a.substr(6)
		elif a.begins_with("--t="):
			_steps = PackedFloat32Array()
			for s in a.substr(4).split(","):
				if s.strip_edges() != "":
					_steps.append(float(s))

	root.size = Vector2i(1600, 900)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.08, 0.11)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var scene: Node3D = SplatSceneScript.new()
	scene.name = "CollapseProbe"
	scene.set("sog_path", _source)
	scene.set("display_name", "collapse")
	scene.set("world_scale", _scale)
	scene.set("yaw_degrees", _yaw)
	scene.set("auto_place", false)
	scene.set("use_anchor", false)
	scene.set("crop_enabled", _crop)
	scene.set("cache_mode", "auto")
	scene.set("auto_start", false)
	scene.set("collapse_enabled", true)
	scene.set("collapse_fade", _fade)
	scene.set("collapse_duration", _duration)
	scene.set("collapse_easing", _easing)
	scene.set("collapse_mode", _mode)
	scene.set("collapse_stagger", _stagger)
	scene.set("collapse_shader_ease", "in_cubic")
	scene.set("collapse_shader_fade", 1.0 if _mode == "staggered" else 0.0)
	scene.set("brownian_amp", _brown)
	scene.set("brownian_freq", _brown_freq)
	scene.set("brownian_seed", _brown_seed)
	scene.set("rise_speed", _rise)
	scene.set("rise_jitter", _rise_jitter)
	scene.set("rise_span", _rise_span)
	scene.set("rise_loop", _rise_loop)
	scene.set("rise_side", _rise_side)
	# 上升的判据要完全确定，不能被帧率影响：所以探针里改用手动时钟，
	# 每档显式推进 _rise_step 秒。否则 --t=0,0,0 两次拍摄之间到底过了多少
	# 真实时间取决于渲染帧率，重心位移量会飘。
	scene.set("dynamic_auto_time", _rise <= 0.0)
	scene.set("dynamic_time", 0.0)
	root.add_child(scene)

	var t0 := Time.get_ticks_msec()
	scene.call("load_now", Callable(self, "_on_progress"))
	if not scene.call("is_ready"):
		push_error("泼溅没建立起来：%s" % _source)
		quit(1)
		return
	print("[collapse] %s：%d 点，解码+建节点 %.1f s" % [
		_source.get_file(), int(scene.get("point_count")),
		(Time.get_ticks_msec() - t0) / 1000.0])

	# --- 居中 + 定坍缩点：用锚点，不用 offset ---
	#
	# 关键：所有点最终都收敛到 offset 上（basis→0 时 world→offset），
	# 所以想让「坍缩点」是某个世界点，必须让 offset 就等于它，而不是把
	# offset 当居中的临时量用。用锚点正好：offset = anchor_world − basis·anchor_source，
	# basis→0 时 offset→anchor_world，且 anchor_source 在整个过程中都钉在 anchor_world 上。
	var cmin: Vector3 = scene.get("content_min")
	var cmax: Vector3 = scene.get("content_max")
	var center := (cmin + cmax) * 0.5
	scene.set("anchor_source", center)
	scene.set("anchor_world", Vector3.ZERO)
	scene.set("use_anchor", true)
	scene.call("apply_transform")
	await _frames(4)

	# --- 相机：固定不动，一次框住整个内容，之后各档都用同一机位比对 ---
	var box0: AABB = scene.call("content_world_aabb")
	var c := box0.get_center()
	var radius := maxf(box0.size.length() * 0.5, 0.5)
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.near = 0.01
	cam.far = 20000.0
	root.add_child(cam)
	cam.global_position = c + Vector3(0.8, 0.5, 0.8).normalized() * radius * 2.3
	cam.look_at(c, Vector3.UP)
	cam.make_current()
	await _frames(4)

	print("[collapse] 世界包围盒 pos %s size %s，坍缩点 = %s" % [
		str(box0.position.snappedf(0.01)), str(box0.size.snappedf(0.01)),
		str(scene.get("offset").snappedf(0.01))])
	print("[collapse] 相机 %s → 看 %s" % [
		str(cam.global_position.snappedf(0.1)), str(c.snappedf(0.1))])
	print("[collapse] 缓动 %s，时长 %.1f s，淡出 %s" % [_easing, _duration, str(_fade)])

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_collapse")
	DirAccess.make_dir_recursive_absolute(out)

	var staggered := _mode == "staggered"
	var rising := _rise > 0.0
	var base_size := box0.size
	var bad := 0
	var cov0 := -1.0
	var cov_last := -1.0
	var cy0 := -2.0
	var cy_last := -2.0
	print("[collapse] 模式 %s%s%s%s" % [
		_mode,
		("（错峰 %.2f）" % _stagger) if staggered else "",
		("（布朗 amp=%.4f freq=%.1f seed=%d）" % [_brown, _brown_freq, _brown_seed])
			if _brown > 0.0 else "",
		("（上升 %.3f/秒 jitter=%.2f loop=%s span=%.2f side=%.3f）"
			% [_rise, _rise_jitter, str(_rise_loop), _rise_span, _rise_side])
			if rising else ""])
	var criterion := "包围盒尺寸必须 = k × 原尺寸"
	if staggered:
		criterion = "画面覆盖率（逐高斯坍缩不缩放节点，包围盒判据失效）"
	if rising:
		criterion = "亮度重心必须上移（行号变小）"
	print("[collapse] 判据：%s" % criterion)
	print("[collapse] t       系数k     覆盖率   重心y    期望尺寸        实测尺寸        k比值  判定")
	for si in _steps.size():
		var t := _steps[si]
		if rising:
			scene.set("dynamic_time", float(si) * _rise_step)
		scene.call("set_collapse", t)
		await _frames(14)
		var k := float(scene.call("collapse_factor"))
		var box: AABB = scene.call("content_world_aabb")
		var ratio := box.size.length() / maxf(base_size.length(), 1e-6)
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		img.save_png(out.path_join("%st%03d_i%d.png" % [_tag, int(round(t * 100.0)), si]))
		var cov := _coverage(img)
		var cy := _centroid_y(img)
		if cov0 < 0.0:
			cov0 = cov
			cy0 = cy
		cov_last = cov
		cy_last = cy
		var ok := true
		if not staggered and not rising:
			# 尺寸随 k 等比，所以相对误差应当极小；用长度比做单一判据。
			ok = absf(ratio - k) <= maxf(0.002, k * 0.02)
			if not ok:
				bad += 1
		print("[collapse] %-7.3f %-9.5f %-8.4f %-8.4f %-15s %-15s %-6.4f %s" % [
			t, k, cov, cy,
			str((base_size * k).snappedf(0.01)) if not staggered else "-",
			str(box.size.snappedf(0.01)),
			ratio, "OK" if ok else "**不符**"])

	if rising:
		# 上升判据对整体缩放免疫：等比放大会把所有像素一起放大，
		# 亮度重心不动 —— 所以重心上移只可能来自粒子真的往上走。
		var moved_up := cy_last >= 0.0 and cy0 >= 0.0 and cy_last < cy0 - 0.002
		if not moved_up:
			bad += 1
		print("[collapse] 亮度重心 %.4f → %.4f（要变小 = 上移）：%s" % [
			cy0, cy_last, "OK" if moved_up else "**不符**"])
	elif staggered:
		var shrunk := cov_last <= cov0 * 0.25
		if not shrunk:
			bad += 1
		print("[collapse] 覆盖率 %.4f → %.4f（要降到 25%% 以下）：%s" % [
			cov0, cov_last, "OK" if shrunk else "**不符**"])
	else:
		print("[collapse] 尺寸校验：%d 档，%d 档不符" % [_steps.size(), bad])

	print("[collapse] 输出目录 %s" % out)
	quit(1 if bad > 0 else 0)


## 画面覆盖率代理：缩到 160×90 后统计明显亮于背景的像素占比。
## 背景是 (0.07, 0.08, 0.11)，所以阈值取 0.18。
func _coverage(img: Image) -> float:
	var small := Image.new()
	small.copy_from(img)
	small.resize(160, 90, Image.INTERPOLATE_BILINEAR)
	var hit := 0
	for y in 90:
		for x in 160:
			var c := small.get_pixel(x, y)
			if maxf(c.r, maxf(c.g, c.b)) > 0.18:
				hit += 1
	return float(hit) / float(160 * 90)


## 亮度加权重心所在行，归一化到 0（画面顶）~ 1（画面底）。
##
## 用来证明「粒子在往上走」：上升会让重心行号**变小**。
## 这条判据对整体缩放免疫 —— 等比放大会把所有像素一起放大，重心不动 ——
## 所以重心上移只可能来自粒子真的位移了。
func _centroid_y(img: Image) -> float:
	var small := Image.new()
	small.copy_from(img)
	small.resize(160, 90, Image.INTERPOLATE_BILINEAR)
	var wsum := 0.0
	var wysum := 0.0
	for y in 90:
		for x in 160:
			var c := small.get_pixel(x, y)
			var w := maxf(0.0, maxf(c.r, maxf(c.g, c.b)) - 0.18)
			wsum += w
			wysum += w * float(y)
	if wsum <= 0.0:
		return -1.0
	return wysum / wsum / 90.0


func _frames(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame


func _on_progress(phase: String, done: int, total: int) -> void:
	if done >= total:
		print("  [加载] %s 完成" % phase)
