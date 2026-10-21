extends SceneTree
## 探针：**霍德的骨骼动画**出图 —— 待机 / 瞄准 / 开火 三个瞬间，同一机位。
## 顺便打印骨骼 pose 是否真的在动（`_aim` / `_pulse` 是否生效）。
##
## 用法：godot --path <工程> --script res://scripts/_probe_hod_anim.gd [-- --splat=off]
## 出图：…/_arisu_captures/_hodanim/*.png

const OUT_SUB := "_hodanim"

var _cam: Camera3D
var _out: String
var _db: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1200, 900)
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
		print("HODANIM 找不到 DarkGate")
		quit(1)
		return
	if player != null:
		player.global_position = gate.global_position + Vector3(-6.0, 2.2, 0.0)
	for _i in 30:
		await process_frame
	_db = game.get_node_or_null("Parkour/Route/DarkBoss") as Node3D
	if _db == null:
		print("HODANIM boss 没出来")
		quit(1)
		return
	# 把它摆在玩家正前方 8 m、高 4 m 处，镜头好拍
	if player != null:
		player.global_position = Vector3(-15.0, 1.0, 4.0)
		player.velocity = Vector3.ZERO
		for _i in 20:
			await process_frame
	var ppos := player.global_position
	_db.global_position = ppos + Vector3(0.0, 4.5, -8.0)
	_db.set_physics_process(false)      # 别让它飞走，固定机位
	await _wait(30)

	_out = ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_SUB)
	DirAccess.make_dir_recursive_absolute(_out)
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.near = 0.05
	_cam.far = 600.0
	_cam.current = true
	root.add_child(_cam)

	var mid: Vector3 = _db.global_position + Vector3(0.0, 1.0, 0.0)
	# 侧后方固定机位：把头、两条主触手、骨链都框进来
	_cam.global_position = _db.global_position + Vector3(-7.5, 3.4, 6.5)
	_cam.look_at(mid, Vector3.UP)
	await _wait(10)
	await _seq("idle", 8)              # 待机 8 帧
	_db.set("_laser_state", 1)         # 瞄准 → `_aim` 涨满（4 帧 ≈ 0.7 s）
	await _seq("aim", 4)
	_db.set("_laser_state", 2)
	_db.set("_pulse", 1.0)
	await _seq("fire", 4)
	print("\n出图目录：%s" % _out)
	quit(0)


## 固定机位连拍 `n` 张（每张间隔 ~0.18 s），用来拼「动作分解图」
func _seq(prefix: String, n: int) -> void:
	for i in n:
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 180:
			await process_frame
		await process_frame
		root.get_texture().get_image().save_png(_out.path_join("%s_%d.png" % [prefix, i]))
		print("HODANIM %s_%d  aim=%.2f pulse=%.2f" % [prefix, i,
			float(_db.get("_aim")), float(_db.get("_pulse"))])


func _shot(name: String, pos: Vector3, look: Vector3) -> void:
	_cam.global_position = pos
	_cam.look_at(look, Vector3.UP)
	var before := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	while Engine.get_frames_drawn() == before and Time.get_ticks_msec() - t0 < 3000:
		await process_frame
	for _i in 4:
		await process_frame
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("HODANIM %s ← 相机 %s" % [name, str(pos.snappedf(0.1))])


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
