extends SceneTree
## 探针：最后平台掩体屋顶的 RTX 5090 + 内存条市场头顶那排（2026-10-20 改完看效果）。
##
## 用法：
##   godot --path <工程> --script res://scripts/_probe_roof_gpu.gd
## 输出：…/_arisu_captures/_gpu/*.png

const OUT_SUB := "_gpu"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var pk := (load("res://scenes/parkour.tscn") as PackedScene).instantiate() as Parkour
	root.add_child(pk)
	for _i in 30:
		await process_frame

	var shed := pk.get_node_or_null("Island/Props/Shed") as Node3D
	var gpu := pk.get_node_or_null("Island/Props/Shed/RTX5090") as Node3D
	print("[gpu] Shed @ %s  屋顶顶面 y = %.2f" % [
		str(shed.global_position.snappedf(0.01)) if shed else "没有",
		(shed.global_position.y + 2.5) if shed else -1.0])
	if gpu == null:
		print("[gpu] 没有 RTX5090")
		quit(1)
		return
	var holder := gpu.get_child(0) as Node3D
	var mi := holder.get_node_or_null("Mesh") as MeshInstance3D
	if mi != null:
		print("[gpu] 原始 AABB %s  旋转 %s  缩放 %s  世界尺寸 %s" % [
			str(mi.mesh.get_aabb().size.snappedf(0.01)),
			str(holder.rotation.snappedf(0.01)), str(holder.scale.snappedf(0.0001)),
			str((holder.global_transform * mi.mesh.get_aabb()).size.snappedf(0.01))])
	print("[gpu] 价格 ¥%d" % gpu.call("price"))

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join(OUT_SUB)
	DirAccess.make_dir_recursive_absolute(out)

	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color(0.62, 0.62, 0.72)
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = Color(1, 1, 1)
	we.environment.ambient_light_energy = 1.3
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	sun.light_energy = 1.4
	root.add_child(sun)

	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.near = 0.05
	cam.far = 800.0
	root.add_child(cam)
	cam.make_current()

	var gp := gpu.global_position
	await _shot(cam, out, "1_roof", gp + Vector3(5.0, 2.0, 5.0), gp)
	await _shot(cam, out, "2_close", gp + Vector3(1.4, 0.8, 1.4), gp)
	await _shot(cam, out, "3_ground", gp + Vector3(6.0, -2.2, 6.0), gp + Vector3(0, -1.0, 0))
	# 内存条市场头顶那排：看 5 根是否还叠在一起
	await _shot(cam, out, "4_hanging", Vector3(-403.0, 12.2, 6.5), Vector3(-410.0, 10.2, -4.9))
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
	print("[gpu] %s ← %s" % [name, str(pos.snappedf(0.1))])
