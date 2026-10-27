extends SceneTree
## 验：蒙德里安二楼的入口能把玩家送到下一场景，并且**旧场景真的被释放**。
##
##   _tools/run_shot.sh res://scripts/_verify_scene_gate.gd
##
## 必须用 run_shot（真窗口）：`Performance.RENDER_VIDEO_MEM_USED` 在 headless 下恒为 0。
## 走完整条路：game.tscn（等 609 泼溅解码）→ 门「MondrianGate2F」→ next_level.tscn
## → 返回门 → game.tscn。每一步都量显存 / 纹理 / 缓冲 / 节点数。

const SceneFlow := preload("res://scripts/scene_flow.gd")

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
	print("  [%s] %s" % ["PASS" if ok else "FAIL", what])


func _mib(monitor: int) -> float:
	return float(Performance.get_monitor(monitor)) / 1048576.0


func _mem() -> String:
	return "VRAM %.1f MiB｜纹理 %.1f MiB｜缓冲 %.1f MiB｜节点 %d" % [
		_mib(Performance.RENDER_VIDEO_MEM_USED),
		_mib(Performance.RENDER_TEXTURE_MEM_USED),
		_mib(Performance.RENDER_BUFFER_MEM_USED),
		get_node_count()]


## 等当前场景换成指定名字（最多 `seconds` 秒）。
func _await_scene(scene_name: String, seconds: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while true:
		await process_frame
		if current_scene != null and current_scene.name == scene_name:
			return true
		if float(Time.get_ticks_msec() - t0) / 1000.0 > seconds:
			return false
	return false


## 把玩家放到门前、等 Area3D 认到人，然后按「F」（直接调 enter()）。
func _use_gate(gate: Node3D, player: Node3D) -> void:
	player.global_position = gate.call("arrival_point")
	(player as CharacterBody3D).velocity = Vector3.ZERO
	for _i in 6:
		await physics_frame
	var prompt := gate.get_node_or_null("Prompt") as Label3D
	print("[探针] 站到「%s」前：Trigger 认到人 = %s（提示牌 visible = %s）"
		% [gate.get("title"), str(gate.get("_in_range")), str(prompt.visible if prompt else false)])
	# 走真实的 F 键分支（把事件直接喂给门的 _input，不依赖窗口焦点）
	var ev := InputEventKey.new()
	ev.keycode = KEY_F
	ev.physical_keycode = KEY_F
	ev.pressed = true
	gate.call("_input", ev)


func _run() -> void:
	root.size = Vector2i(1600, 900)
	print("=== 场景入口 + 显存回收 ===")
	var err := change_scene_to_file("res://scenes/game.tscn")
	_check(err == OK, "加载 game.tscn（%s）" % error_string(err))
	await _await_scene("Game", 20.0)
	_check(current_scene != null and current_scene.name == "Game", "当前场景 = Game")

	var game := current_scene
	var splat := game.get_node_or_null("Room609")
	var t0 := Time.get_ticks_msec()
	while splat != null and not bool(splat.call("is_ready")):
		await process_frame
		if float(Time.get_ticks_msec() - t0) / 1000.0 > 40.0:
			break
	var splat_ready := splat != null and bool(splat.call("is_ready"))
	print("[探针] 画室609 泼溅就绪 = %s（等了 %.1f s）"
		% [str(splat_ready), float(Time.get_ticks_msec() - t0) / 1000.0])

	var gate := game.find_child("MondrianGate", true, false) as Node3D
	_check(gate != null, "game.tscn 里有 MondrianGate")
	if gate == null:
		print("=== 结果：%d 项失败 ===" % _fails)
		quit(1)
		return
	_check(absf(gate.global_position.y - 4.2) < 0.01,
		"入口在蒙德里安二层（y = %.2f）" % gate.global_position.y)
	print("[探针] 入口世界坐标 %s，朝向 +Z（本地）" % str(gate.global_position.snappedf(0.01)))

	var player := game.get_node_or_null("Player") as Node3D
	_check(player != null, "game.tscn 里有 Player")
	if player == null:
		print("=== 结果：%d 项失败 ===" % _fails)
		quit(1)
		return

	# 先量切换前（泼溅已经进了显存）
	await process_frame
	var vram_before := _mib(Performance.RENDER_VIDEO_MEM_USED)
	var tex_before := _mib(Performance.RENDER_TEXTURE_MEM_USED)
	var buf_before := _mib(Performance.RENDER_BUFFER_MEM_USED)
	var nodes_before := get_node_count()
	print("[探针] 切换前：%s" % _mem())

	await _use_gate(gate, player)
	var ok_next := await _await_scene("NextLevel", 20.0)
	_check(ok_next, "按 F 后当前场景 = NextLevel（实际 %s）"
		% (current_scene.name if current_scene != null else "null"))
	if not ok_next:
		print("=== 结果：%d 项失败 ===" % _fails)
		quit(1)
		return

	await create_timer(2.0, true).timeout
	var vram_after := _mib(Performance.RENDER_VIDEO_MEM_USED)
	var tex_after := _mib(Performance.RENDER_TEXTURE_MEM_USED)
	var buf_after := _mib(Performance.RENDER_BUFFER_MEM_USED)
	var nodes_after := get_node_count()
	print("[探针] 切换后：%s" % _mem())
	print("[探针] 差值与切换前比：VRAM %+.1f MiB｜纹理 %+.1f MiB｜缓冲 %+.1f MiB｜节点 %+d"
		% [vram_after - vram_before, tex_after - tex_before,
			buf_after - buf_before, nodes_after - nodes_before])
	_check(root.get_node_or_null("Game") == null, "旧场景 Game 已从根节点摘掉（被 free）")
	_check(vram_after < vram_before - 256.0,
		"显存下降 > 256 MiB（实际 %.1f MiB）" % (vram_before - vram_after))
	_check(nodes_after < nodes_before,
		"节点数下降（%d → %d）" % [nodes_before, nodes_after])

	var next_scene := current_scene
	var next_player := next_scene.get_node_or_null("Player") as Node3D
	var next_hud := next_scene.get_node_or_null("HUD")
	var return_gate := next_scene.get_node_or_null("ReturnGate") as Node3D
	_check(next_player != null, "门厅里玩家还在（HUD = %s）" % str(next_hud != null))
	_check(return_gate != null, "门厅里有返回门 ReturnGate")
	if next_player == null or return_gate == null:
		print("=== 结果：%d 项失败 ===" % _fails)
		quit(1)
		return

	await _use_gate(return_gate, next_player)
	var ok_back := await _await_scene("Game", 30.0)
	_check(ok_back, "按 F 后回到 Game（实际 %s）"
		% (current_scene.name if current_scene != null else "null"))
	if not ok_back:
		print("=== 结果：%d 项失败 ===" % _fails)
		quit(1)
		return

	# 黑屏预载 + 淡入：等 SceneFlow.switching 归零（预载可能要几秒）
	var t_fade := Time.get_ticks_msec()
	while SceneFlow.switching and Time.get_ticks_msec() - t_fade < 30000:
		await process_frame
	print("[探针] 返回淡入完成：黑屏共 %.1f s"
		% (float(Time.get_ticks_msec() - t_fade) / 1000.0))
	await create_timer(0.5, true).timeout
	var back_game := current_scene
	var back_gate := back_game.find_child("MondrianGate", true, false) as Node3D
	var back_player := back_game.get_node_or_null("Player") as Node3D
	var landing: Vector3 = back_gate.call("arrival_point")
	_check(back_player != null and back_player.global_position.distance_to(landing) < 0.05,
		"回到蒙德里安二层门前：%s（应在 %s）"
		% [str(back_player.global_position.snappedf(0.01)) if back_player else "null",
			str(landing.snappedf(0.01))])
	_check(back_player != null and absf(back_player.global_position.y - 4.25) < 0.05,
		"落点在二层地面高度（y = %.2f）"
		% (back_player.global_position.y if back_player else -999.0))
	_check(not SceneFlow.entered_via_gate and SceneFlow.pending_spawn.is_empty(),
		"落点状态已被 game.gd 消费（不会影响下一次）")
	print("[探针] 回到主场景后：%s" % _mem())

	# ── 场景门预载：黑屏期间已经把目标场景的泼溅加载完，进场后不该再卡 ──
	var room := back_game.get_node_or_null("Room609")
	_check(room != null and bool(room.call("is_ready")),
		"返回时画室609 泼溅已在黑屏内预载完成（进场不再卡）")
	print("[探针] 泼溅已就绪：%s" % _mem())

	print("=== 结果：%d 项失败 ===" % _fails)
	quit(0 if _fails == 0 else 1)
