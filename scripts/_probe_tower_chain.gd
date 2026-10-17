extends SceneTree
## 螺旋塔逐跳验收（绕开「合成按键有时不被 `is_action_just_pressed` 看到」这个测试坑）：
## 用 `player.gd` 自己的跳跃缓冲变量 `_jump_at` 触发跳跃，走的仍是同一套
## `_physics_process` / `move_and_slide` / 重力 / 空中加速。
##
## 每一跳都按真实玩法：站在起跳角落、朝向下一块板中心、起跳后按住 W+Shift
## 并每帧把镜头拧向目标中心（模拟人看着下一块板跑）。
##
## 用法：
##   godot --headless --path <工程> --script res://scripts/_probe_tower_chain.gd -- --splat=off

var _p: Player
var _pk: Parkour
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 12:
		await process_frame
	_p = game.get_node_or_null("Player") as Player
	_pk = game.get_node_or_null("Parkour") as Parkour
	if _p == null or _pk == null:
		print("!! 缺 Player / Parkour")
		quit(1)
		return
	_pk.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	for i in range(28, 35):      # W1..W7 → W2..C4（7 跳版）
		var from_i := i
		var to_i := i + 1
		var res := await _hop(from_i, to_i)
		var ok: bool = bool(res["ok"])
		if not ok:
			_fail += 1
		print("[chain] %-4s→%-4s %s 起跳 (%+.2f,%+.2f) 必须跨 %.2f 抬升 %+.2f  落点 %s  y=%.2f  %s"
			% [_pk.label_at(from_i), _pk.label_at(to_i), "✓" if ok else "✗",
				float(res["takeoff"].x), float(res["takeoff"].z), float(res["required"]),
				float(res["rise"]), str((res["pos"] as Vector3).snappedf(0.01)),
				float((res["pos"] as Vector3).y), String(res["why"])])
	print("[chain] 结果：%d 跳失败 %d 跳" % [_fail, 7])
	quit(0 if _fail == 0 else 1)


func _hop(from_i: int, to_i: int) -> Dictionary:
	var a := _pk.box_at(from_i)
	var b := _pk.box_at(to_i)
	var h := _pk.hop_analysis(a, b, Player.JUMP_VELOCITY, Player.GRAVITY, Player.SPEED_RUN)
	var takeoff: Vector3 = h["takeoff"]
	var center := b.position + b.size * 0.5
	var dir := Vector2(center.x - takeoff.x, center.z - takeoff.z).normalized()

	# 站在起跳角落（稍微往回 5 cm，别和下一块板的侧面重叠）
	_release_all()
	_p.global_position = Vector3(takeoff.x - dir.x * 0.05, _pk.top_at(from_i) + 0.05,
		takeoff.z - dir.y * 0.05)
	_p.velocity = Vector3.ZERO
	_aim(dir)
	# 等真正踩稳（连续两帧 on_floor）
	var n := 0
	while n < 2:
		await physics_frame
		n = (n + 1) if _p.is_on_floor() else 0
	# 同一刻：起跳 + 按住方向（空中加速从 0 开始，复刻「站定短跳」）
	Input.action_press("move_forward")
	Input.action_press("sprint")
	var t_jump := Time.get_ticks_msec()
	_p.velocity.y = Player.JUMP_VELOCITY
	await physics_frame
	var t_after := Time.get_ticks_msec()
	print("[chain]   起跳帧：floor=%s v.y=%+.2f 墙钟 %d ms  pos=%s" % [
		str(_p.is_on_floor()), _p.velocity.y, t_after - t_jump,
		str(_p.global_position.snappedf(0.01))])
	await physics_frame
	if _p.velocity.y <= 0.5 and _p.is_on_floor():
		_release_all()
		return {"ok": false, "pos": _p.global_position, "takeoff": takeoff,
			"required": h["required"], "rise": h["rise"], "why": "没跳起来(v.y=%.2f)" % _p.velocity.y}

	var t0 := Time.get_ticks_msec()
	var end := _p.global_position
	var landed := false
	while Time.get_ticks_msec() - t0 < 2200:
		await process_frame
		var ps := _p.global_position
		var vs := Vector2(center.x - ps.x, center.z - ps.z)
		if vs.length() > 0.05:
			_aim(vs.normalized())
		if _p.is_on_floor() and Time.get_ticks_msec() - t0 > 120:
			landed = true
			end = ps
			break
		if ps.y < _pk.top_at(to_i) - 4.0:
			end = ps
			break
		end = ps
	_release_all()
	var on := _pk._station_at(end) == to_i
	var y_ok := absf(end.y - _pk.top_at(to_i)) < 0.35
	var ok := landed and on and y_ok
	return {"ok": ok, "pos": end, "takeoff": takeoff,
		"required": h["required"], "rise": h["rise"],
		"why": "" if ok else ("landed=%s station=%d" % [str(landed), _pk._station_at(end)])}


func _aim(dir: Vector2) -> void:
	_p._yaw = atan2(-dir.x, -dir.y)
	_p._facing_yaw = _p._yaw + PI
	_p.model_root.rotation.y = _p._facing_yaw
	_p.get_node("CameraRig").rotation.y = _p._yaw


func _release_all() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "sprint", "crouch", "jump"]:
		Input.action_release(a)
