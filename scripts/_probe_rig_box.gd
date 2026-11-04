extends SceneTree
## 定位机箱在场景里的真实位置/朝向，别再靠推算。
##   _tools/run_shot.sh res://scripts/_probe_rig_box.gd -- --splat=off --story=off


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(150)

	var rig := game.get_node_or_null("GameDevRoom/PC5090Rig") as Node3D
	if rig == null:
		print("[box] 找不到 rig")
		quit(1)
		return
	print("[box] rig 路径=%s 可见=%s 父=%s" % [
		str(rig.get_path()), str(rig.visible), str(rig.get_parent().name)])
	print("[box] rig rot=%s scale=%s" % [str(rig.global_rotation_degrees.snappedf(0.1)),
		str(rig.global_scale)])

	var mn := Vector3(1e9, 1e9, 1e9)
	var mx := Vector3(-1e9, -1e9, -1e9)
	var n := 0
	for mi in rig.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var ab: AABB = m.global_transform * m.get_aabb()
		for i in 3:
			mn[i] = minf(mn[i], ab.position[i])
			mx[i] = maxf(mx[i], ab.position[i] + ab.size[i])
		n += 1
	print("[box] 机箱整体：网格 %d 个，世界包围盒 min=%s max=%s size=%s" % [
		n, str(mn.snappedf(0.01)), str(mx.snappedf(0.01)), str((mx - mn).snappedf(0.01))])

	for nm in ["Shell", "Glass", "SSD0", "SSD1", "Backplane", "PSU", "GPU0"]:
		var c := rig.get_node_or_null(nm) as Node3D
		if c != null:
			print("[box]   %-10s 世界位置 %s  可见=%s" % [
				nm, str(c.global_position.snappedf(0.01)), str(c.visible)])

	var room := game.get_node_or_null("GameDevRoom") as Node3D
	print("[box] GameDevRoom 世界位置 %s rot=%s" % [
		str(room.global_position.snappedf(0.01)), str(room.global_rotation_degrees.snappedf(0.1))])
	quit(0)