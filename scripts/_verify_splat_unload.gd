extends SceneTree
## 验收「出画室609 / 校园 就释放泼溅显存」这个开关（`splat_unload_outside`）。
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
	# ⚠️ 2026-11-08：用户要求默认改成**开启**（「出门就释放，进门再开」）。
	#    这里写回 `true` 再读，验证默认值确实是新的。
	GameSettings.set_value("splat_unload_outside", true)
	await process_frame
	var dflt := bool(GameSettings.value("splat_unload_outside"))
	_log("① 设置默认值 = %s（要求 true）" % str(dflt))
	if not dflt:
		_fails += 1
		_log("   ✗ 默认不是开！")
	else:
		_log("   ✓ 默认开启")

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
	# 默认是开的，所以这里要先**显式关掉**，测的才是「开关关着」这条分支。
	GameSettings.set_value("splat_unload_outside", false)
	await process_frame
	await process_frame
	_go_outside()
	await _wait_seconds(3.0)
	var still := _room.get("splat_node") != null
	_log("② 开关关着、走到室外 3 s：泼溅节点仍然存在 = %s（要求 true）" % str(still))
	if still:
		_log("   ✓ 行为未改变（出去的还是常驻那一份）")
	else:
		_fails += 1
		_log("   ✗ 关着也释放了！")

	# ── 2.5 跨门框判据（2026-11-08 用户：「跨出门框就释放，进门再开」）──
	# 先确认判据真的是**墙框**，不是点云大盒（后者永远走不出去）。
	var room_xz: Rect2 = _room.get("_room_xz")
	var x0 := room_xz.position.x
	var z0 := room_xz.position.y
	var x1 := x0 + room_xz.size.x
	var z1 := z0 + room_xz.size.y
	_log("②.5 房间判据 x %.2f~%.2f，z %.2f~%.2f（要求贴近墙框 −5.95~6.10 / −6.93~14.02）" % [
		x0, x1, z0, z1])
	if z0 < -10.0 or z1 > 18.0:
		_fails += 1
		_log("   ✗ 判据还是点云大盒（门框失效，人根本走不出去）")
	else:
		_log("   ✓ 判据是墙框")

	GameSettings.set_value("splat_unload_outside", true)
	await process_frame
	await process_frame

	# 门里侧：先把点云等回来，再断言「站着不动不会被释放」。
	# ⚠️ 不能只等两帧：上一步（②）结束时人在 z=40 门外，点云早被释放掉了，
	#    进门重载要 1~2 s。只等两帧就断言，测到的是「还没加载完」而不是「被释放」
	#    （本喵第一版就是这么误报的）。
	_stand_just_inside_the_door()
	var back_in := await _wait_splat(true, 90000)
	if not back_in:
		_fails += 1
		_log("   ✗ 门里侧点云没加载回来，后面的门框用例没法做")
	else:
		# 再站 1.5 s，确认「在门里侧待着」不会触发释放
		await _wait_seconds(1.5)
		if _room.get("splat_node") != null:
			_log("   ✓ 门里侧（z=−6.0）站 1.5 s 仍有点云")
		else:
			_fails += 1
			_log("   ✗ 门里侧就把点云释放了，进出门会闪")

	# 刚跨出门框：应当立刻释放
	_go_just_outside_the_door()
	var t_door := Time.get_ticks_msec()
	var rel_door := await _wait_splat(false, 10000)
	var door_s := float(Time.get_ticks_msec() - t_door) / 1000.0
	_log("   %s 跨出门框（z=−7.2）0.0x 秒内释放（实测 %.2f s）" % [
		"✓" if rel_door else "✗", door_s])
	if not rel_door:
		_fails += 1

	# 回到门里侧：应当自动重载
	_stand_just_inside_the_door()
	var t_back := Time.get_ticks_msec()
	var rel_back := await _wait_splat(true, 90000)
	_log("   %s 跨回门框内自动重载（%.2f s）" % [
		"✓" if rel_back else "✗", float(Time.get_ticks_msec() - t_back) / 1000.0])
	if not rel_back:
		_fails += 1

	# ── 2.6 站在屋顶上不许加载（2026-11-08 用户：「为什么上面也加载?!」）──
	# 用户实测坐标 (-1.30, 5.80, 3.84)：水平在门框矩形内，y 在屋顶板上。
	# 609 墙顶 5.65、屋顶板顶面 5.80 —— 所以 y 上限必须**严格取墙顶**，
	# 加一点正余量就会把 5.80 包进去（本喵第一版加 0.30 就是这么错的）。
	var ylo: float = _room.get("_room_y_lo")
	var yhi: float = _room.get("_room_y_hi")
	_log("   房间高度窗口 y %.2f~%.2f（要求上限 ≤ 5.65，即墙顶）" % [ylo, yhi])
	if yhi > 5.70:
		_fails += 1
		_log("   ✗ 高度上限太高，站在屋顶（y=5.80 附近）会被判成屋里")
	else:
		_log("   ✓ 高度上限卡在墙顶")

	_player.set_physics_process(false)
	_player.global_position = Vector3(-1.30, 5.80, 3.84)
	var t_roof := Time.get_ticks_msec()
	var rel_roof := await _wait_splat(false, 15000)
	_log("   %s 站屋顶 (-1.30, 5.80, 3.84) 不加载（%.2f s）" % [
		"✓" if rel_roof else "✗", float(Time.get_ticks_msec() - t_roof) / 1000.0])
	if not rel_roof:
		_fails += 1

	# 从屋顶走回屋里：应当重新加载
	_player.global_position = Vector3(0.0, 0.5, 4.0)
	var t_down := Time.get_ticks_msec()
	var rel_down := await _wait_splat(true, 90000)
	_log("   %s 从屋顶回到屋里自动加载（%.2f s）" % [
		"✓" if rel_down else "✗", float(Time.get_ticks_msec() - t_down) / 1000.0])
	if not rel_down:
		_fails += 1

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


## 走到**门框线上**再往外一点（2026-11-08 新需求：「跨出门框就释放」）。
## 609 的墙框实测 z −6.93~14.02，门在 z− 面，所以 z = −7.2 正好刚出门。
func _go_just_outside_the_door() -> void:
	_player.set_physics_process(false)
	_player.global_position = Vector3(0.0, 0.5, -7.2)


## 站在**门里侧**（应算房内，不许释放）。
func _stand_just_inside_the_door() -> void:
	_player.set_physics_process(false)
	_player.global_position = Vector3(0.0, 0.5, -6.0)


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
