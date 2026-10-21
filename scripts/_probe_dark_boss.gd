extends SceneTree
## 探针：**黑市那只霍德**——名字 / 模型 / 血量 + 「是不是真的在爱丽丝附近飞来飞去」，
## 顺带出两张图（玩家视角 + 高空视角），看它飞起来是不是还生硬。
##
## 用法：godot --path <工程> --script res://scripts/_probe_dark_boss.gd [-- --splat=off]
## 出图：…/_arisu_captures/_darkboss/*.png

const OUT_SUB := "_darkboss"

var _cam: Camera3D
var _out: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 40:
		await process_frame
	var player := game.get_node_or_null("Player") as Player
	if player != null:
		player.set_process_input(false)
	for n in ["HUD", "SettingsMenu", "DialogueBox", "Parkour/ParkourHUD",
			"Parkour/Futures/FuturesHUD"]:
		var c := game.get_node_or_null(n)
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false

	var gate := game.get_node_or_null("Parkour/Route/DarkGate") as Node3D
	if gate == null:
		print("DARK 找不到 DarkGate")
		quit(1)
		return
	print("DARK 闸门 x = %.2f（玩家跑过去就会把 boss 喊出来）" % gate.global_position.x)
	# 把人塞到闸门西边 → 触发
	if player != null:
		player.global_position = gate.global_position + Vector3(-6.0, 2.2, 0.0)
		player.velocity = Vector3.ZERO
	for _i in 30:
		await process_frame
	var db := game.get_node_or_null("Parkour/Route/DarkBoss")
	if db == null:
		print("DARK 闸门没把 boss 喊出来")
		quit(1)
		return
	print("DARK 名字「%s」 血量 %.0f 模型 %s" % [
		String(db.get("display_name")), float(db.get("max_health")),
		String(db.get("model_path")).get_file()])
	print("DARK 绕飞参数：半径 %.1f~%.1f m / 高度 +%.1f m / 最高速 %.1f m/s / %.1f s 换一个点" % [
		float(db.get("fly_radius_min")), float(db.get("fly_radius_max")),
		float(db.get("fly_height")), float(db.get("fly_speed_max")),
		float(db.get("fly_retarget"))])
	# 闸门在 340 m 外，boss 出生点也在那边；为了量「绕飞」，先把它挪到玩家头顶附近。
	# ⚠️ 玩家必须站在**有地板**的地方 —— 塞到闸门那儿会掉下去、然后重生回平台，
	#    绕飞中心一秒钟跳 340 m，量出来的距离带就没意义了（第一版就是这样）。
	if player != null:
		player.global_position = Vector3(-15.0, 1.0, 4.0)      # 出生平台
		player.velocity = Vector3.ZERO
		for _i in 30:
			await process_frame
	var ppos := player.global_position if player != null else Vector3.ZERO
	db.global_position = ppos + Vector3(7.0, 7.0, 0.0)
	print("DARK 玩家 %s；把 boss 挪到 %s，开始量绕飞" % [
		str(ppos.snappedf(0.01)), str(db.global_position.snappedf(0.01))])
	# 采样 4 秒：路径长度 / 水平距离带 / 最小-最大距离
	var samples: Array[Vector3] = []
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 4000:
		await process_frame
		if samples.is_empty() or samples[-1].distance_to(db.global_position) > 0.02:
			samples.append(db.global_position)
	var travel := 0.0
	var dmin := 999.0
	var dmax := 0.0
	for i in range(1, samples.size()):
		travel += samples[i - 1].distance_to(samples[i])
	for s in samples:
		var d := Vector2(s.x - ppos.x, s.z - ppos.z).length()
		dmin = minf(dmin, d)
		dmax = maxf(dmax, d)
	print("DARK 4 s 内：路径 %.1f m（%d 个采样点）；水平距离 %.1f ~ %.1f m" % [
		travel, samples.size(), dmin, dmax])
	print("DARK 高度范围 y %.1f ~ %.1f（玩家脚底 %.1f）" % [
		samples.map(func(v): return v.y).min(), samples.map(func(v): return v.y).max(),
		ppos.y])

	_out = ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_SUB)
	DirAccess.make_dir_recursive_absolute(_out)
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.near = 0.05
	_cam.far = 600.0
	_cam.current = true
	root.add_child(_cam)
	await _shot("1_player_view", ppos + Vector3(0.0, 2.2, 0.0),
		db.global_position + Vector3(0.0, 1.0, 0.0))
	await _shot("2_side", db.global_position + Vector3(-14.0, 3.0, 10.0),
		db.global_position + Vector3(0.0, 1.0, 0.0))
	await _shot("3_wide", db.global_position + Vector3(-22.0, 12.0, 18.0),
		db.global_position + Vector3(0.0, 0.0, 0.0))
	print("\n出图目录：%s" % _out)
	quit(0)


func _shot(name: String, pos: Vector3, look: Vector3) -> void:
	_cam.global_position = pos
	_cam.look_at(look, Vector3.UP)
	var before := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	while Engine.get_frames_drawn() == before and Time.get_ticks_msec() - t0 < 3000:
		await process_frame
	for _i in 8:
		await process_frame
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("DARK %s ← 相机 %s" % [name, str(pos.snappedf(0.1))])
