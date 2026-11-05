extends SceneTree
## 复现用户报的「显存 6918 MiB」。
##
## 假设：GDGS 的 `GaussianGpuStateCache` 按**纹理尺寸**缓存 RenderState，
## 每个 state 自带一整套泼溅 GPU 缓冲（277 万点 ≈ 1.28 GB：splats 665 + culled 177
## + sort_keys/values 各 221 MB）。`MAX_RENDER_STATES = 4` ⇒ 最多留 **4 套 = 5.1 GB**。
## 用户「开 1 就变 7 fps、平时开 0.5」正好是在两个尺寸之间来回切。
##
## 本探针把这件事量出来：
##   1. 在 0.5 / 1.0 之间来回切 6 次 → state 数、显存各是多少
##   2. 依次设 5 个不同缩放 → 是否顶到上限 4 份
##   3. 每个 state 估多大
##
## 用法（必须真窗口）：
##   _tools/run_shot.sh res://scripts/_probe_render_states.gd
## 输出：stdout + <工程>/_log/render_states.txt

const WATCHDOG_MS := 600000

var _lines: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size = Vector2i(1600, 900)
	await process_frame
	await process_frame
	Engine.max_fps = 0

	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	var w0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - w0 < 120000:
		var room: Node = game.get_node_or_null("Room609")
		if room != null and room.get("splat_node") != null:
			break
		await process_frame
	for i in 30:
		await process_frame

	_log("=== RenderState 缓存 vs 显存 ===")
	_log("窗口 %s   顶点数 %d" % [str(root.size), int(_point_count())])
	_log("每个 state 的缓冲 = splats %.2f GB + culled %.2f GB + sort_keys %.2f GB + sort_values %.2f GB" % [
		N * 60.0 * 4.0 / 1073741824.0, N * 16.0 * 4.0 / 1073741824.0,
		N * 10.0 * 8.0 / 1073741824.0, N * 10.0 * 8.0 / 1073741824.0])
	_log("")

	_log("① 0.5 / 1.0 来回切 6 次（用户平时的操作）")
	for i in 6:
		var s := 0.5 if i % 2 == 0 else 1.0
		root.scaling_3d_scale = s
		for k in 12:
			await process_frame
		_log("   第 %d 次 → 缩放 %.1f  state 数 %d  显存 %6.0f MiB" % [
			i + 1, s, _state_count(), _vram()])
	_log("")

	_log("② 依次设 5 个不同缩放（每个都是一种新尺寸）")
	for s in [0.40, 0.50, 0.60, 0.70, 0.80]:
		root.scaling_3d_scale = s
		for k in 12:
			await process_frame
		_log("   缩放 %.2f  state 数 %d  显存 %6.0f MiB" % [s, _state_count(), _vram()])
	_log("")
	_log("③ 每个 state 的实际尺寸与纹理")
	for key in _state_keys():
		_log("   %s" % key)

	_write_out()
	quit(0)


const N := 2769855


func _gdgs():
	return GaussianRenderManager.get_instance()


func _point_count() -> int:
	var m = _gdgs()
	if m == null:
		return 0
	var reg = m.get("_scene_registry")
	return int(reg.call("get_point_count")) if reg != null else 0


func _state_cache():
	var m = _gdgs()
	return m.get("_gpu_state_cache") if m != null else null


func _state_count() -> int:
	var c = _state_cache()
	if c == null:
		return -1
	var d: Dictionary = c.get("_render_states")
	return d.size()


func _state_keys() -> PackedStringArray:
	var out := PackedStringArray()
	var c = _state_cache()
	if c == null:
		return out
	var d: Dictionary = c.get("_render_states")
	for k in d.keys():
		var st = d[k]
		out.append("尺寸 %s  texture=%s  depth=%s" % [
			str(k), str(st.get("descriptors").has("render_texture")),
			str(st.get("descriptors").has("depth_texture"))])
	return out


func _vram() -> float:
	return float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0


func _write_out() -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("_log")
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("render_states.txt"), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))
		f.close()


func _log(s: String) -> void:
	print("[states] " + s)
	_lines.append(s)
