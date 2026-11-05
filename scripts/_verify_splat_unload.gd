extends SceneTree
## 验收「出画室609 就释放泼溅显存」这个开关（`splat_unload_outside`）。
##
## 要证明四件事：
##   1. 开关默认是**关**的，且关着的时候出门**不释放**（行为不变）；
##   2. 打开之后，站在 609 里点云在；
##   3. 走出范围 → 节点被释放、**显存真的掉下来**（这是这个功能的意义）；
##   4. 走回范围 → 自动重解码，画面回来、显存涨回去。
##
## ⚠️ 必须真窗口（要读 `RENDER_VIDEO_MEM_USED`，headless 下没有渲染设备）。
## ⚠️ 全程**不弹前台**：`run_shot.sh` 把窗口扔在 -4000,-4000 且 NO_FOCUS。
##
## 用法：
##   _tools/run_shot.sh res://scripts/_verify_splat_unload.gd
## 输出：stdout + <工程>/_log/splat_unload.txt

const WATCHDOG_MS := 900000

var _lines: PackedStringArray = PackedStringArray()
var _fails := 0
var _game: Node = null
var _room: Node = null
var _player: Node3D = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size = Vector2i(1280, 720)
	await process_frame
	await process_frame
	Engine.max_fps = 0
	root.scaling_3d_scale = 0.5

	_game = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(_game)
	current_scene = _game

	_room = _game.get_node_or_null("Room609")
	_player = _game.get_node_or_null("Player") as Node3D
	if _room == null or _player == null:
		_log("缺 Room609 或 Player，放弃")
		quit(1)
		return

	_log("=== 出画室609 释放泼溅显存：验收 ===")
	_log("")

	# ── 1. 默认值 ──
	# ⚠️ 先显式写回默认再读：这个探针自己会把开关打开（第 ③ 步），
	#    而 `set_value()` 是**落盘**的 —— 不清掉的话第二次跑会读到上次留下的 true，
	#    看起来像「默认不是关」（本喵第一版就踩了）。
	GameSettings.set_value("splat_unload_outside", false)
	await process_frame
	var dflt := bool(GameSettings.value("splat_unload_outside"))
	_log("① 设置默认值 = %s（要求 false）" % str(dflt))
	if dflt:
		_fails += 1
		_log("   ✗ 默认不是关！")
	else:
		_log("   ✓ 默认关闭")

	# 人先站进 609 里，等点云就位
	_player.global_position = Vector3(0.0, 0.5, 4.0)
	await _wait_splat(true, 150000)
	if _room.get("splat_node") == null:
		_log("✗ 点云一直没加载出来，后面的用例没法做")
		quit(1)
		return
	var vram_in := _vram()
	_log("   点云就位，显存 %.0f MiB" % vram_in)

	# ── 2. 关着的时候出门：不许释放 ──
	_go_outside()
	await _wait_seconds(3.0)
	var still := _room.get("splat_node") != null
	_log("② 开关关着、走到室外 3 s：泼溅节点仍然存在 = %s（要求 true）" % str(still))
	if still:
		_log("   ✓ 行为未改变（出去的还是常驻那一份）")
	else:
		_fails += 1
		_log("   ✗ 关着也释放了！")

	# ── 3. 打开开关，出门 → 释放 + 显存下降 ──
	GameSettings.set_value("splat_unload_outside", true)
	await process_frame
	# ⚠️ 必须等**真实时间**：`unload_delay` 是 1.5 秒，而探针里一帧只要 0.1 ms，
	#    数 200 帧才 0.02 秒，永远等不到（本喵第一版就是这么「测不出释放」的）。
	await _wait_seconds(3.0)
	# 先把人放回屋里等它上满，再出门，这样测的是「真的掉了多少」
	_player.global_position = Vector3(0.0, 0.5, 4.0)
	await _wait_splat(true, 90000)
	var before_out := _vram()
	_go_outside()
	var released := await _wait_splat(false, 30000)
	var after_out := _vram()
	_log("③ 开关打开、走出范围：节点已释放 = %s" % str(released))
	_log("   显存 %.0f MiB → %.0f MiB（Δ %+.0f MiB）" % [
		before_out, after_out, after_out - before_out])
	if released:
		_log("   ✓ 真的释放了")
	else:
		_fails += 1
		_log("   ✗ 没释放")
	if after_out < before_out - 200.0:
		_log("   ✓ 显存确实降下来了（>200 MiB）")
	else:
		_fails += 1
		_log("   ✗ 显存没明显下降，功能等于没生效")

	# ── 4. 走回屋里 → 自动重载 ──
	_player.global_position = Vector3(0.0, 0.5, 4.0)
	var t0 := Time.get_ticks_msec()
	var back := await _wait_splat(true, 90000)
	var reload_s := float(Time.get_ticks_msec() - t0) / 1000.0
	var after_in := _vram()
	_log("④ 回到范围：自动重载 = %s，用时 %.1f s" % [str(back), reload_s])
	_log("   显存 %.0f MiB → %.0f MiB" % [after_out, after_in])
	if back:
		_log("   ✓ 画面回来了（代价就是这 %.1f s 的等待）" % reload_s)
	else:
		_fails += 1
		_log("   ✗ 没自动重载")

	# ── 5. 关掉开关也要能恢复（不能把人卡在「没泼溅」的状态）──
	GameSettings.set_value("splat_unload_outside", false)
	await process_frame
	await process_frame
	var restored := _room.get("splat_node") != null
	_log("⑤ 关掉开关后仍有点云 = %s" % str(restored))
	if not restored:
		_fails += 1

	GameSettings.set_value("splat_unload_outside", false)
	_log("")
	_log("结论：%s" % ("全部通过" if _fails == 0 else "%d 项失败" % _fails))
	_write_out()
	quit(0 if _fails == 0 else 1)


## 等真实时间（秒）。`unload_delay` / `reload_delay` 都按秒算，数帧不可靠。
func _wait_seconds(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while float(Time.get_ticks_msec() - t0) / 1000.0 < sec:
		await process_frame


func _go_outside() -> void:
	# 院子外面。**必须把玩家的物理关掉**：
	# 实测直接把 `global_position` 挪到 40 m 外，人会掉进虚空（y 一路 −0.8 → −4.5 → −9），
	# 然后被 `_die_and_respawn()` 送回存档点 `(-15, 0, 4)` —— 那是房间**里面**，
	# 于是「出房间」这个条件永远不成立，测出来的当然是「没释放」。
	# 这个验收只关心泼溅的释放逻辑，不需要玩家真的会走路，所以关掉物理最干净。
	_player.set_physics_process(false)
	_player.global_position = Vector3(0.0, 0.5, 40.0)


## 等到「有泼溅 / 没泼溅」。返回是否达成。
func _wait_splat(want_present: bool, timeout_ms: int) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < timeout_ms:
		var present: bool = _room.get("splat_node") != null
		if present == want_present:
			# 再多等几帧，让 GPU 上传/释放真正结算
			for i in 10:
				await process_frame
			return true
		await process_frame
	return false


func _vram() -> float:
	return float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0


func _write_out() -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("_log")
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("splat_unload.txt"), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))
		f.close()


func _log(s: String) -> void:
	print("[unload] " + s)
	_lines.append(s)
