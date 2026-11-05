extends SceneTree
## 帧成本 A/B 探针：把「场景1（画室609）」的每一层渲染代价**逐项**关掉量一遍。
##
## 目的：用户反馈「好卡」，但**泼溅外观不许动**。所以先把非泼溅的开销拆开：
##   阴影（含阴影 pass 的 draw call 翻倍）、SSAO、辉光、雾、MSAA、软阴影滤波。
## 再配合 `--splat=off` 的一轮，就能算出泼溅本身占多少。
##
## 用法（必须真窗口：GDGS/GG 的 float 纹理在 headless 下拿不到）：
##   _tools/run_shot.sh res://scripts/_probe_frame_cost.gd
##   _tools/run_shot.sh res://scripts/_probe_frame_cost.gd -- --splat=off
##   _tools/run_shot.sh res://scripts/_probe_frame_cost.gd -- --res=2560x1440 --scale=0.5
##
## 输出：stdout + <工程>/_log/frame_cost.txt
##
## ⚠️ 垂直同步必须关、`Engine.max_fps` 必须清 0，否则全部档位都被削到同一个数
##    （`game.gd::_apply_quality()` 会按画质档位写 max_fps）。

const WARMUP := 20
const MEASURE := 90
const WATCHDOG_MS := 600000

## 每一档只动「后处理/阴影」这些和泼溅无关的东西。labels 会打进表里。
const CONFIGS := [
	{"name": "base", "label": "现状（全开）"},
	{"name": "no_shadow", "label": "关定向光阴影"},
	{"name": "shadow_near25", "label": "阴影，但最大距离 60→25"},
	{"name": "soft_shadow_low", "label": "软阴影滤波 3→0"},
	{"name": "no_ssao", "label": "关 SSAO"},
	{"name": "no_glow", "label": "关辉光"},
	{"name": "no_fog", "label": "关雾"},
	{"name": "no_post", "label": "关 SSAO+辉光+雾"},
	{"name": "no_msaa", "label": "关 MSAA"},
	{"name": "lean", "label": "关阴影 + 关全部后处理"},
]

var _res := Vector2i(1600, 900)
var _scale := 0.5
var _scene := "res://scenes/game.tscn"
var _env: Environment = null
var _lights: Array[DirectionalLight3D] = []
var _lines: PackedStringArray = PackedStringArray()
var _deadline := 0


func _initialize() -> void:
	_deadline = Time.get_ticks_msec() + WATCHDOG_MS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--res="):
			var parts := a.substr(6).split("x")
			if parts.size() == 2:
				_res = Vector2i(int(parts[0]), int(parts[1]))
		elif a.begins_with("--scale="):
			_scale = float(a.substr(8))
		elif a.begins_with("--scene="):
			_scene = "res://scenes/" + a.substr(8) + ".tscn"
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size = _res
	await process_frame
	await process_frame
	root.size = _res
	await process_frame
	await process_frame

	var packed: PackedScene = load(_scene)
	if packed == null:
		_log("载入不了 %s" % _scene)
		quit(1)
		return
	var game: Node = packed.instantiate()
	root.add_child(game)

	# 等泼溅就位（画室609 解码 2.4~4.0 s；校园更久）
	var w0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() < _deadline and Time.get_ticks_msec() - w0 < 120000:
		var ok := _splat_ready(game)
		if ok:
			break
		await process_frame

	# 收噪声：同伴/Boss 的动画每帧都在变，A/B 时它们只会加方差
	for c in game.get_children():
		var n := String(c.name)
		if n.begins_with("Companion") or n.begins_with("Target") or n.begins_with("Boss"):
			(c as Node).process_mode = Node.PROCESS_MODE_DISABLED

	var we := _find_env(game)
	_env = we.environment if we != null else null
	_collect_lights(game)

	_log("场景 %s   视口 %s   3D 缩放 %.3f   垂直同步 %s" % [
		_scene, str(root.size), _scale, str(DisplayServer.window_get_vsync_mode())])
	_log("泼溅：%s   方向光阴影：%d 盏   环境：%s" % [
		"关" if _splat_off() else "开", _lights.size(), "有" if _env != null else "无"])
	_log("每档：预热 %d 帧 → 连续测 %d 帧" % [WARMUP, MEASURE])
	_log("")

	# 先把所有档位碰一遍：切 SSAO/阴影会重建渲染管线，编译停顿不能算进测量
	for cfg in CONFIGS:
		_apply(cfg)
		for i in 12:
			await process_frame

	var rows: Array = []
	for cfg in CONFIGS:
		_apply(cfg)
		var r := await _measure()
		rows.append({"cfg": cfg, "r": r})
		_log("%-16s %-24s p50 %6.2f  p99 %6.2f  max %7.2f ms   %6.1f fps   draw %5d  图元 %8d  显存 %6.0f MiB" % [
			String(cfg["name"]), String(cfg["label"]),
			r["p50"], r["p99"], r["max"], r["fps"], r["draw"], r["prim"], r["vram"]])

	_log("")
	_log("基准 = base；差值就是那一项的开销（负数 = 关掉它反而更慢，属于噪声）")
	var base: Dictionary = rows[0]["r"]
	for row in rows:
		var r: Dictionary = row["r"]
		_log("  %-16s Δp50 %+7.2f ms   Δp99 %+7.2f ms   Δdraw %+5d" % [
			String(row["cfg"]["name"]), r["p50"] - base["p50"],
			r["p99"] - base["p99"], r["draw"] - base["draw"]])

	_write_out()
	quit(0)


## 场景1 的 SplatScene 在 Room609 下；场景2 的校园挂在 campus_ggs 上。
func _splat_ready(game: Node) -> bool:
	for path in ["Room609", "Campus"]:
		var n: Node = game.get_node_or_null(path)
		if n != null:
			if n.get("splat_node") != null:
				return true
			if n.get("is_loaded") == true:
				return true
	var gg: Node = game.get_node_or_null("CampusGGS")
	if gg != null and gg.get("rasterizer") != null:
		return true
	# 没有泼溅的场景（--splat=off）：等 3 s 就开测
	return Time.get_ticks_msec() - _deadline + WATCHDOG_MS > 3000


func _splat_off() -> bool:
	for a in OS.get_cmdline_user_args():
		if a == "--splat=off" or a == "--no-splat":
			return true
	return false


func _find_env(node: Node) -> WorldEnvironment:
	var we := node as WorldEnvironment
	if we != null and we.environment != null:
		return we
	for c in node.get_children():
		var found := _find_env(c)
		if found != null:
			return found
	return null


func _collect_lights(node: Node) -> void:
	var dl := node as DirectionalLight3D
	if dl != null:
		_lights.append(dl)
	for c in node.get_children():
		_collect_lights(c)


func _apply(cfg: Dictionary) -> void:
	var name := String(cfg["name"])
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.scaling_3d_scale = _scale

	var want_shadow := name != "no_shadow" and name != "lean"
	var near_only := name == "shadow_near25"
	for dl in _lights:
		if not is_instance_valid(dl):
			continue
		dl.shadow_enabled = want_shadow
		dl.directional_shadow_max_distance = 25.0 if near_only else 60.0
	RenderingServer.directional_soft_shadow_filter_set_quality(
		0 if name == "soft_shadow_low" else 3)

	if _env == null:
		return
	var post := name != "no_post" and name != "lean"
	_env.ssao_enabled = post and name != "no_ssao"
	_env.glow_enabled = post and name != "no_glow"
	_env.fog_enabled = post and name != "no_fog"
	root.msaa_3d = Viewport.MSAA_DISABLED if name == "no_msaa" else Viewport.MSAA_4X


func _measure() -> Dictionary:
	for i in WARMUP:
		await process_frame
	var dts := PackedFloat32Array()
	var prev := Time.get_ticks_usec()
	for i in MEASURE:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		dts.append(float(now - prev) / 1000.0)
		prev = now
	var sorted := PackedFloat32Array(dts)
	sorted.sort()
	var n := sorted.size()
	var sum := 0.0
	for v in sorted:
		sum += v
	return {
		"p50": sorted[int(n * 0.50)],
		"p99": sorted[mini(int(n * 0.99), n - 1)],
		"max": sorted[n - 1],
		"fps": 1000.0 / maxf(sum / float(n), 1e-6),
		"draw": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"prim": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"obj": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"vram": float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0,
	}


func _write_out() -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("_log")
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("frame_cost.txt"), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))
		f.close()


func _log(s: String) -> void:
	print("[cost] " + s)
	_lines.append(s)
