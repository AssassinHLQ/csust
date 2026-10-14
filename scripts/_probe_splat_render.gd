extends SceneTree
## 探针：加载校园 SOG，量出**内容**的稳健包围盒，并按指定放大倍数渲出
## 「站在校园里」和「空中俯瞰」两种视角，用来定 world_scale 和摆放。
##
## 用法：
##   godot --path <工程> --script res://scripts/_probe_splat_render.gd -- --scale=25 --cache=auto
## 输出：…/_arisu_captures/_splat/*.png

const SogRuntime := preload("res://scripts/sog_runtime.gd")
const BYTES_PER_SPLAT := 240

var _t_last := 0
var _scale := 1.0
var _cache := "auto"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scale="):
			_scale = float(a.substr(8))
		elif a.begins_with("--cache="):
			_cache = a.substr(8)

	root.size = Vector2i(1280, 720)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.19, 0.26)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.88, 1.0)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -125, 0)
	sun.light_energy = 0.7
	root.add_child(sun)

	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.02
	cam.far = 5000.0
	root.add_child(cam)
	cam.make_current()

	var source := SogRuntime.find_source()
	print("[splat] source = %s   scale = %.2f   cache = %s" % [source, _scale, _cache])
	var t0 := Time.get_ticks_msec()
	var loaded: Dictionary = SogRuntime.load_sog(source, {
		"cache": _cache, "progress": Callable(self, "_on_progress")})
	if not bool(loaded.get("ok", false)):
		push_error("加载失败：%s" % str(loaded.get("message", loaded)))
		quit(1)
		return
	var res: Resource = loaded["resource"]
	print("[splat] 点数=%d  加载耗时=%.1f s  from_cache=%s" % [
		int(res.get("point_count")), (Time.get_ticks_msec() - t0) / 1000.0,
		str(loaded.get("from_cache", false))])

	# ---- 采样点数据，算内容稳健包围盒（aabb 会被离群 floaters 撑大）----
	var robust := _robust_bounds(res)
	var full: AABB = res.get("aabb")
	print("[splat] aabb（含 floaters）= pos %s size %s" % [
		str(full.position.snappedf(0.01)), str(full.size.snappedf(0.01))])
	print("[splat] 内容 1‰~99.9‰      = min %s  max %s" % [
		str(robust["min"].snappedf(0.01)), str(robust["max"].snappedf(0.01))])
	print("[splat] 内容尺寸            = %s" % str(robust["size"].snappedf(0.01)))
	print("[splat] 内容 5%%~95%%         = min %s  max %s" % [
		str(robust["min5"].snappedf(0.01)), str(robust["max95"].snappedf(0.01))])

	var s := _scale
	# 内容在「居中坐标系」里 → 节点缩放后世界坐标 = scale × p
	var cmin: Vector3 = robust["min"] * s
	var cmax: Vector3 = robust["max"] * s
	var csize := cmax - cmin
	var ccenter := (cmin + cmax) * 0.5
	print("[splat] 放大 %.1f 倍后：尺寸 %s   竖向高 %.1f" % [
		s, str(csize.snappedf(0.1)), csize.y])

	var node: Node3D = GaussianSplatNode.new()
	node.name = "SplatProbe"
	node.set("gaussian", res)
	node.transform = Transform3D(Basis.from_scale(Vector3(s, s, s)), Vector3.ZERO)
	root.add_child(node)
	await process_frame
	await process_frame

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_splat")
	DirAccess.make_dir_recursive_absolute(out)

	# 站在内容最低点上，人眼高 1.7 m
	var stand := Vector3(ccenter.x, cmin.y, ccenter.z)
	var horiz := Vector2(csize.x, csize.z).length()

	var views := {}
	# ① 游戏同款第三人称：身后 4.2 m、高 1.62 m、右肩 0.42 m，略俯视
	views["30_third_person"] = {
		"pos": stand + Vector3(0.42, 1.62, horiz * 0.30),
		"look": stand + Vector3(0.0, 1.4, -horiz * 0.30),
	}
	# ② 人眼平视（站在场地中央往一侧看）
	views["31_eye_level"] = {
		"pos": stand + Vector3(0.0, 1.7, 0.0),
		"look": stand + Vector3(0.0, 1.7, -horiz * 0.5),
	}
	# ③ 空中 3/4 俯瞰
	views["32_iso"] = {
		"pos": ccenter + Vector3(1.0, 0.6, 1.0).normalized() * horiz * 1.1,
		"look": ccenter,
	}
	# ④ 正俯视
	views["33_top"] = {
		"pos": ccenter + Vector3(0.0, horiz * 1.1, 0.001),
		"look": ccenter,
	}

	for key in views:
		var v: Dictionary = views[key]
		cam.global_position = v["pos"]
		cam.look_at(v["look"], Vector3.UP)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		img.save_png(out.path_join("s%03d_%s.png" % [int(s), key]))
		print("  [img] %-16s 相机 %s" % [key, str((v["pos"] as Vector3).snappedf(0.1))])

	print("[splat] 输出目录：%s" % out)
	quit(0)


## 抽样点数据，给出分位数包围盒。结构：每点 60 float，[0..2] = 已中心化的 xyz
func _robust_bounds(res: Resource) -> Dictionary:
	var bytes: PackedByteArray = res.get("point_data_byte")
	var count := int(res.get("point_count"))
	var stride := BYTES_PER_SPLAT
	if bytes.size() < count * stride:
		count = bytes.size() / stride
	var want := 20000
	var step := maxi(1, count / want)
	var xs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	var zs := PackedFloat32Array()
	var i := 0
	while i < count:
		var off := i * stride
		xs.append(bytes.decode_float(off))
		ys.append(bytes.decode_float(off + 4))
		zs.append(bytes.decode_float(off + 8))
		i += step
	xs.sort()
	ys.sort()
	zs.sort()
	var n := xs.size()
	print("[splat] 抽样 %d / %d 点算分位数" % [n, count])
	return {
		"min": Vector3(xs[int(n * 0.001)], ys[int(n * 0.001)], zs[int(n * 0.001)]),
		"max": Vector3(xs[int(n * 0.999)], ys[int(n * 0.999)], zs[int(n * 0.999)]),
		"min5": Vector3(xs[int(n * 0.05)], ys[int(n * 0.05)], zs[int(n * 0.05)]),
		"max95": Vector3(xs[int(n * 0.95)], ys[int(n * 0.95)], zs[int(n * 0.95)]),
		"size": Vector3(
			xs[int(n * 0.999)] - xs[int(n * 0.001)],
			ys[int(n * 0.999)] - ys[int(n * 0.001)],
			zs[int(n * 0.999)] - zs[int(n * 0.001)]),
	}


func _on_progress(phase: String, done: int, total: int) -> void:
	var now := Time.get_ticks_msec()
	if now - _t_last < 5000 and done < total:
		return
	_t_last = now
	print("  [进度] %-9s %d / %d" % [phase, done, total])
