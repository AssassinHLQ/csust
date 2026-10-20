extends SceneTree
## 探针：跑酷起跑区俯视图 —— 准备区（金垫子）现在多大、跑道在哪儿、平台边缘在哪儿。
##
## 用法：
##   godot --path <工程> --script res://scripts/_probe_ready_zone.gd
## 输出：…/_arisu_captures/_readyzone/*.png

const OUT_SUB := "_readyzone"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var pk := (load("res://scenes/parkour.tscn") as PackedScene).instantiate() as Parkour
	root.add_child(pk)
	for _i in 20:
		await process_frame

	var zone := pk.get_node_or_null("ReadyZone") as ParkourReadyZone
	print("[rz] 准备区 @ %s  尺寸 %s" % [
		str(zone.global_position.snappedf(0.01)), str(zone.zone_size)])
	for nm in ["Launch", "Route/P1", "Route/P2"]:
		var nd := pk.get_node_or_null(nm) as Node3D
		if nd == null:
			continue
		var b: AABB = pk.call("_world_aabb", nd) if pk.has_method("_world_aabb") else AABB()
		print("[rz] %-10s @ %s  AABB %s ~ %s" % [nm,
			str(nd.global_position.snappedf(0.01)),
			str(b.position.snappedf(0.01)), str(b.end.snappedf(0.01))])
	var plat := pk.get_node_or_null("Platform/Mesh") as MeshInstance3D
	pk._build_route()
	var b0 := pk.box_at(0)
	var b1 := pk.box_at(1)
	print("[rz] 第0站 AABB %s ~ %s" % [str(b0.position.snappedf(0.01)), str(b0.end.snappedf(0.01))])
	print("[rz] 第1站 AABB %s ~ %s" % [str(b1.position.snappedf(0.01)), str(b1.end.snappedf(0.01))])

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_SUB)
	DirAccess.make_dir_recursive_absolute(out)

	# parkour.tscn 自带的灯都在段上（这一段没有），补一盏 + 环境光才看得清地面字
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color(0.42, 0.52, 0.66)
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = Color(1, 1, 1)
	we.environment.ambient_light_energy = 1.1
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	sun.light_energy = 1.4
	root.add_child(sun)

	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.near = 0.05
	cam.far = 400.0
	root.add_child(cam)
	cam.make_current()
	await _shot(cam, out, "1_top", Vector3(-6, 26, 4), Vector3(-6, 0, 4))
	await _shot(cam, out, "2_top_wide", Vector3(-6, 40, 4), Vector3(-6, 0, 4))
	await _shot(cam, out, "3_ground", Vector3(2.0, 1.7, 4.0), Vector3(-16.0, 0.2, 4.0))
	await _shot(cam, out, "4_pad", Vector3(-4.0, 2.2, 4.0), Vector3(-14.0, 0.0, 4.0))
	print("\n出图目录：%s" % out)
	quit(0)


func _shot(cam: Camera3D, out: String, name: String, pos: Vector3, look: Vector3) -> void:
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)
	var before := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	while Engine.get_frames_drawn() == before and Time.get_ticks_msec() - t0 < 4000:
		await process_frame
	await process_frame
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("[rz] %s ← %s" % [name, str(pos.snappedf(0.1))])
