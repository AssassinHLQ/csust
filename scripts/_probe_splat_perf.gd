extends SceneTree
## 探针：把「提高 3D 渲染分辨率」的代价测**准**。
##
## 为什么另开一个：`_probe_splat_quality.gd` 的三次跑里同一档的帧率差了 2~30 倍，
## 说明那个计时harness不可靠。已知的两个污染源在这里都掐掉：
##   ① **垂直同步** —— 开着的话能跑满 60 的档会被削到 60，看不出差别；
##   ② **只测一轮 + 预热不足** —— 切 SSAO/分辨率会重建渲染管线，第一轮里混着编译停顿。
##
## 所以：关垂直同步、每档先空跑 15 帧、再连续测 40 帧，而且**同一组配置重复 3 轮**
## 交错测（C1 C2 C3 × 3），看重复性。
##
## 用法：
##   godot --path <工程> --script res://scripts/_probe_splat_perf.gd
## 输出：stdout 的帧率表 + …/_arisu_captures/_quality/_perf.txt

const OUT_REL := "..\\_arisu_captures\\_quality"
const WARMUP_FRAMES := 15
const MEASURE_FRAMES := 40
const REPS := 3

## 三档配置。`env` 决定后处理：full = 今天的全套，light = 只留 ACES。
const CONFIGS := [
	{"name": "C1_today", "scale": 0.6494, "msaa": 2, "env": "full",
		"label": "今天：scale 0.649 + MSAA4x + ACES/辉光/SSAO/雾/调色"},
	{"name": "C2_native_same_post", "scale": 1.0, "msaa": 0, "env": "full",
		"label": "原生 1.0 + 关 MSAA，后处理全套不变"},
	{"name": "C3_native_light_post", "scale": 1.0, "msaa": 0, "env": "light",
		"label": "原生 1.0 + 关 MSAA + 只留 ACES（关辉光/SSAO/雾/调色）"},
]

var _env: Environment = null
var _vp: Viewport = null
var _lines: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	# 可选：强制后端。后端选择是会话内一次性的，所以必须在 game.tscn 出生前写。
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--backend="):
			ProjectSettings.set_setting("gdgs/rendering/backend", a.substr(10))
			print("[perf] 强制后端 = %s" % a.substr(10))
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(2560, 1400)
	await process_frame
	await process_frame
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size = Vector2i(2560, 1400)
	await process_frame
	await process_frame
	_vp = root

	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)

	var room: Node = game.get_node_or_null("Room609")
	var deadline := Time.get_ticks_msec() + 200000
	while Time.get_ticks_msec() < deadline and room.get("splat_node") == null:
		await process_frame
	if room == null or room.get("splat_node") == null:
		_log("画室609 没加载出来")
		quit(1)
		return

	for c in game.get_children():
		var n := String(c.name)
		if n.begins_with("Companion") or n.begins_with("Target") or n.begins_with("Boss"):
			(c as Node).process_mode = Node.PROCESS_MODE_DISABLED
	var hud: Node = game.get_node_or_null("HUD")
	if hud != null:
		(hud as CanvasLayer).visible = false

	var we: WorldEnvironment = game.get_node_or_null("WorldEnvironment")
	_env = we.environment if we != null else null

	_log("视口渲染尺寸 = %s   垂直同步 = %s" % [
		str(root.size), str(DisplayServer.window_get_vsync_mode())])
	_log("每档：预热 %d 帧 → 连续测 %d 帧，整组重复 %d 轮交错" % [
		WARMUP_FRAMES, MEASURE_FRAMES, REPS])

	# 第一次先把三档各碰一遍，把管线编译的代价挪出正式测量。
	for cfg in CONFIGS:
		_apply(cfg)
		for i in 10:
			await process_frame

	var results := {}
	for rep in REPS:
		for cfg in CONFIGS:
			_apply(cfg)
			var fps := await _measure()
			var key := String(cfg["name"])
			if not results.has(key):
				results[key] = PackedFloat32Array()
			results[key].append(fps)
			_log("  第 %d 轮  %-22s %6.1f fps" % [rep + 1, key, fps])

	_log("")
	_log("%-24s %-34s %s" % ["配置", "说明", "三轮 fps / 中位"])
	for cfg in CONFIGS:
		var key := String(cfg["name"])
		var arr: PackedFloat32Array = results[key]
		var s := PackedFloat32Array(arr)
		s.sort()
		var median := s[s.size() / 2]
		_log("%-24s %-34s %s  → 中位 %6.1f fps" % [
			key, String(cfg["label"]), _join(arr), median])

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_quality")
	DirAccess.make_dir_recursive_absolute(out)
	var f := FileAccess.open(out.path_join("_perf.txt"), FileAccess.WRITE)
	f.store_string("\n".join(_lines))
	f.close()
	_log("输出：%s" % out.path_join("_perf.txt"))
	quit(0)


func _apply(cfg: Dictionary) -> void:
	_vp.scaling_3d_scale = float(cfg["scale"])
	_vp.msaa_3d = int(cfg["msaa"])
	if _env == null:
		return
	var full := String(cfg["env"]) == "full"
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.glow_enabled = full
	_env.ssao_enabled = full
	_env.fog_enabled = full
	_env.adjustment_enabled = full


func _measure() -> float:
	for i in WARMUP_FRAMES:
		await process_frame
	var t0 := Time.get_ticks_usec()
	for i in MEASURE_FRAMES:
		await RenderingServer.frame_post_draw
	var seconds := (Time.get_ticks_usec() - t0) / 1000000.0
	return MEASURE_FRAMES / maxf(seconds, 1e-6)


func _join(arr: PackedFloat32Array) -> String:
	var parts := PackedStringArray()
	for v in arr:
		parts.append("%6.1f" % v)
	return "[" + " ".join(parts) + "]"


func _log(s: String) -> void:
	print("[perf] " + s)
	_lines.append(s)
