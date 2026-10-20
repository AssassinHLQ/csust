extends SceneTree
## 探针：**609 代理门（淡黄门板 + 门框）的顶部**，专门拍用户截图那个角度。
##
## 用户 2026-10-21：「门这里上面有破绽要去除」（截图 = 站在门外、镜头略仰，看到门框
## 顶横条与墙的交界）。这个探针复现那个机位，再补两张顶角特写，用来判断「破绽」到底是
##   ① 门框横条与门楣之间的缝 / ② 门框横条与墙不共面（台阶 + 阴缝）/ ③ 门洞上沿漏光。
##
## 用法：godot --path <工程> --script res://scripts/_probe_roomdoor.gd [-- --splat=off]
## 出图：…/_arisu_captures/_roomdoor/*.png

const OUT_SUB := "_roomdoor"

var _cam: Camera3D
var _out: String


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 90:
		await process_frame
	var player := game.get_node_or_null("Player") as Player
	if player != null:
		player.set_process_input(false)
	for n in ["HUD", "SettingsMenu", "DialogueBox", "Parkour/ParkourHUD",
			"Parkour/Futures/FuturesHUD"]:
		var c := game.get_node_or_null(n)
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false

	var proxy := game.get_node_or_null("RoomProxy") as Node3D
	if proxy == null:
		print("[roomdoor] 没有 RoomProxy")
		quit(1)
		return
	var panel := proxy.get_node_or_null("DoorPanel") as MeshInstance3D
	var frame_t := proxy.get_node_or_null("DoorFrameT") as MeshInstance3D
	var lintel := proxy.get_node_or_null("DoorLintel") as MeshInstance3D
	for pair in [["DoorPanel", panel], ["DoorFrameT", frame_t], ["DoorLintel", lintel]]:
		var mi := pair[1] as MeshInstance3D
		if mi == null:
			print("[roomdoor] %s = 没有" % pair[0])
			continue
		var bb := (mi.mesh as BoxMesh).size * mi.global_transform.basis.get_scale()
		print("[roomdoor] %-12s 世界中心 %s  尺寸 (%.3f, %.3f, %.3f)" % [
			pair[0], str(mi.global_position.snappedf(0.001)),
			bb.x, bb.y, bb.z])

	# 玩家站到门外 —— 代理墙环/门板只在「人在屋外」时显示
	if player != null:
		player.global_position = Vector3(7.2, 0.4, -2.7)
		player.velocity = Vector3.ZERO
		for _i in 40:
			await process_frame

	_out = ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_SUB)
	DirAccess.make_dir_recursive_absolute(_out)
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.near = 0.03
	_cam.far = 500.0
	_cam.current = true
	root.add_child(_cam)

	# 门扇中心 ≈ (4.8, 1.4, -2.7)（见 `_probe_door_shot.gd` 的 2_close）
	await _shot("1_whole", Vector3(9.0, 1.60, -2.7), Vector3(4.85, 1.60, -2.7))
	await _shot("2_like_user", Vector3(8.2, 1.55, -2.7), Vector3(4.85, 2.35, -2.7))
	await _shot("3_top_close", Vector3(6.6, 2.10, -2.7), Vector3(4.85, 2.62, -2.7))
	await _shot("4_top_left", Vector3(6.4, 2.10, -1.9), Vector3(4.85, 2.62, -3.4))
	await _shot("5_top_right", Vector3(6.4, 2.10, -3.5), Vector3(4.85, 2.62, -2.0))
	print("\n出图目录：%s" % _out)
	quit(0)


func _shot(name: String, pos: Vector3, look: Vector3) -> void:
	_cam.global_position = pos
	_cam.look_at(look, Vector3.UP)
	var before := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	while Engine.get_frames_drawn() == before and Time.get_ticks_msec() - t0 < 3000:
		await process_frame
	if Engine.get_frames_drawn() == before:
		print("  [img] 跳过 %s（3 s 内没有新帧）" % name)
		return
	for _i in 8:
		await process_frame
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
	print("[roomdoor] %s ← 相机 %s" % [name, str(pos.snappedf(0.1))])
