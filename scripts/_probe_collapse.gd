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

	var base_size := box0.size
	var bad := 0
	print("[collapse] t      系数k    期望尺寸            实测尺寸            比值    期望比  判定")
	for t in _steps:
		scene.call("set_collapse", t)
		await _frames(14)
		var k := float(scene.call("collapse_factor"))
		var box: AABB = scene.call("content_world_aabb")
		var want := base_size * k
		var ratio := box.size.length() / maxf(base_size.length(), 1e-6)
		var want_ratio := k
		# 尺寸随 k 等比，所以逐轴相对误差应当极小；用长度比做单一判据。
		var ok := absf(ratio - want_ratio) <= maxf(0.002, want_ratio * 0.02)
		if not ok:
			bad += 1
		print("[collapse] %-6.3f %-8.5f %-19s %-19s %-7.4f %-7.4f %s" % [
			t, k, str(want.snappedf(0.01)), str(box.size.snappedf(0.01)),
			ratio, want_ratio, "OK" if ok else "**不符**"])
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		img.save_png(out.path_join("%st%03d.png" % [_tag, int(round(t * 100.0))]))

	print("[collapse] 输出目录 %s" % out)
	print("[collapse] 尺寸校验：%d 档，%d 档不符" % [_steps.size(), bad])
	quit(1 if bad > 0 else 0)


func _frames(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame


func _on_progress(phase: String, done: int, total: int) -> void:
	if done >= total:
		print("  [加载] %s 完成" % phase)
