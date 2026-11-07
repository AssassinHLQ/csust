extends SceneTree
## 临时：量游戏开发部部室/东侧地块的包围盒，给新电竞房选位置。

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 8:
		await process_frame
	var room := game.get_node("GameDevRoom") as Node3D
	var box := AABB()
	var first := true
	for mi in room.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var b := m.global_transform * m.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	print("room AABB pos=", box.position.snappedf(0.01), " size=", box.size.snappedf(0.01))
	var col := room.get_node_or_null("Model/Collision/Mesh") as CollisionShape3D
	if col != null and col.shape is ConcavePolygonShape3D:
		var lo := Vector3(1e9, 1e9, 1e9)
		var hi := Vector3(-1e9, -1e9, -1e9)
		for v in (col.shape as ConcavePolygonShape3D).get_faces():
			var w := col.global_transform * v
			lo = lo.min(w)
			hi = hi.max(w)
		print("room collision pos=", lo.snappedf(0.01), " size=", (hi - lo).snappedf(0.01))
	for nm in ["LotEast", "Shop", "MeshHut", "Parkour", "Player"]:
		var n := game.get_node_or_null(nm) as Node3D
		if n != null:
			print(nm, " pos=", n.global_position.snappedf(0.01))
	quit()
