extends SceneTree
## _dump：电竞房床铺定位。打印 AutoCol 全部碰撞盒（世界中心/尺寸）与 Room 网格 AABB，
## 供离线挑出床的实心盒与睡龛净高。只读，不改场景。
##   _tools/run_probe.sh res://scripts/_probe_esports_beds.gd

const LEVEL := "res://scenes/game.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var level := (load(LEVEL) as PackedScene).instantiate() as Node3D
	root.add_child(level)
	for i in 20:
		await process_frame
	var room := level.get_node_or_null("EsportsRoom") as Node3D
	if room == null:
		print("!! 无 EsportsRoom")
		quit(1)
		return
	room.visible = true
	for i in 10:
		await process_frame

	var auto_col := room.get_node_or_null("BakedCollision/AutoCol") as Node3D
	if auto_col == null:
		print("!! 无 AutoCol")
		quit(1)
		return
	print("== AutoCol %d 个子节点 ==" % auto_col.get_child_count())
	for c in auto_col.get_children():
		var cs := c as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		var half: Vector3 = cs.global_basis.get_scale().abs() * (cs.shape as BoxShape3D).size * 0.5
		var ctr := cs.global_position
		print("BOX %s c=(%.3f, %.3f, %.3f) s=(%.3f, %.3f, %.3f) disabled=%s" % [
			cs.name, ctr.x, ctr.y, ctr.z, half.x * 2, half.y * 2, half.z * 2, str(cs.disabled)])

	print("== Room 网格 ==")
	var glb := room.get_node_or_null("Room")
	for mi in glb.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m == null or m.mesh == null:
			continue
		var b: AABB = m.global_transform * m.mesh.get_aabb()
		print("MESH %s pos=(%.2f, %.2f, %.2f) size=(%.2f, %.2f, %.2f)" % [
			m.name, b.position.x, b.position.y, b.position.z, b.size.x, b.size.y, b.size.z])
	quit(0)