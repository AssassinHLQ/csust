extends SceneTree
## 诊断：柜子挖空为什么只挖掉 4 个（逐个盒子打印判定过程）。
##
##   godot --path . --script res://scripts/_probe_esports_cabinet_debug.gd -- --splat=off --story=off

const OFF := preload("res://scripts/offscreen_window.gd")
const CABINET_MESH := "M_Scene_-_Root"
const CABINET_KEEP_TOP := 0.75


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await OFF.apply(self, Vector2i(960, 540))
	for _i in 3:
		await process_frame
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 60:
		await process_frame
	paused = false

	var room := game.get_node_or_null("EsportsRoom") as Node3D
	var glb := room.get_node_or_null("Room")
	var cab := AABB()
	var found := false
	for mi in glb.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m == null or m.mesh == null or String(m.name) != CABINET_MESH:
			continue
		var b: AABB = m.global_transform * m.mesh.get_aabb()
		cab = b if not found else cab.merge(b)
		found = true
	print("柜子 AABB  x %.3f~%.3f  y %.3f~%.3f  z %.3f~%.3f  (%.3f×%.3f×%.3f)"
		% [cab.position.x, cab.end.x, cab.position.y, cab.end.y,
			cab.position.z, cab.end.z, cab.size.x, cab.size.y, cab.size.z])
	var ceiling := cab.end.y - CABINET_KEEP_TOP
	print("柜顶保留线 ceiling = %.3f\n" % ceiling)
	print("has_point(柜子中心) = %s\n" % str(cab.has_point(cab.get_center())))

	var auto_col := room.get_node_or_null("BakedCollision/AutoCol") as Node3D
	print("%-12s %-30s %-24s %-8s %-8s %s"
		% ["盒子", "世界 AABB(y)", "中心", "中心在柜内", "end.y>线", "判定"])
	for c in auto_col.get_children():
		var cs := c as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		var sz: Vector3 = (cs.shape as BoxShape3D).size
		var half: Vector3 = cs.global_basis.get_scale().abs() * sz * 0.5
		var cb := AABB(cs.global_position - half, half * 2.0)
		var probe := cb.grow(0.02)
		if not probe.intersects(cab):
			continue
		var centre := cb.get_center()
		var in_cab: bool = cab.has_point(centre)
		var above: bool = cb.end.y > ceiling + 0.01
		var verdict := "挖掉" if (in_cab and not above) else ("留（柜顶）" if above else "留（中心不在柜内）")
		print("%-12s y %.2f~%.2f (h%.2f)  (%.2f,%.2f,%.2f)  %-8s %-8s %s"
			% [String(cs.name), cb.position.y, cb.end.y, cb.size.y,
				centre.x, centre.y, centre.z, str(in_cab), str(above), verdict])
	quit(0)
