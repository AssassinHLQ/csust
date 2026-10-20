extends SceneTree
## 探针：最后平台的结算小屋 / 挪到传送台上的信号塔 / 牢笼 + 倭瓜优香。
##
## 用法：
##   godot --path <工程> --script res://scripts/_probe_trap.gd
## 输出：…/_arisu_captures/_trap/*.png

const OUT_SUB := "_trap"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var pk := (load("res://scenes/parkour.tscn") as PackedScene).instantiate() as Parkour
	root.add_child(pk)
	for _i in 30:
		await process_frame

	var shed := pk.get_node_or_null("Island/Props/Shed") as Node3D
	var pad := pk.get_node_or_null("Island/Props/ReturnPad") as Node3D
	var tower := pk.get_node_or_null("Island/Props/Tower") as Node3D
	var gpu := pk.get_node_or_null("Island/Props/Shed/RTX5090") as Node3D
	var sp := pk.get_node_or_null("Island/Props/Shed/Settlement") as Node3D
	print("[trap] Shed %s\n[trap] ReturnPad %s\n[trap] Tower %s\n[trap] 5090 %s\n[trap] Settlement %s" % [
		str(shed.global_position.snappedf(0.01)) if shed else "没有",
		str(pad.global_position.snappedf(0.01)) if pad else "没有",
		str(tower.global_position.snappedf(0.01)) if tower else "没有",
		str(gpu.global_position.snappedf(0.01)) if gpu else "没有",
		str(sp.global_position.snappedf(0.01)) if sp else "没有"])

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_SUB)
	DirAccess.make_dir_recursive_absolute(out)

	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color(0.64, 0.66, 0.78)
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = Color(1, 1, 1)
	we.environment.ambient_light_energy = 1.3
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, 32.0, 0.0)
	sun.light_energy = 1.4
	root.add_child(sun)

	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.near = 0.05
	cam.far = 900.0
	root.add_child(cam)
	cam.make_current()

	if shed != null:
		var c := shed.global_position
		await _shot(cam, out, "1_shed", c + Vector3(5.5, 2.6, -5.5), c + Vector3(0, 1.2, 0))
		await _shot(cam, out, "2_inside", c + Vector3(0, 1.5, -2.6), c + Vector3(0, 1.3, 1.0))
	if pad != null:
		var c := pad.global_position
		await _shot(cam, out, "3_tower", c + Vector3(7.0, 3.0, -7.0), c + Vector3(0, 4.0, 0))

	# 直接触发陷阱（不需要玩家）
	pk.call("trap_sequence")
	await _wait_ms(900)
	if pad != null:
		var c := pad.global_position
		await _shot(cam, out, "4_cage", c + Vector3(7.0, 3.5, -6.0), c + Vector3(0, 1.5, 0))
		await _shot(cam, out, "5_boss", c + Vector3(9.0, 4.0, 6.0), c + Vector3(2.0, 1.0, 0.0))
	print("\n出图目录：%s" % out)
	quit(0)


func _wait_ms(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame


func _shot(cam: Camera3D, out: String, name: String, pos: Vector3, look: Vector3) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	var before := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	while Engine.get_frames_drawn() == before and Time.get_ticks_msec() - t0 < 4000:
		await process_frame
	await process_frame
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("[trap] %s ← %s" % [name, str(pos.snappedf(0.1))])
