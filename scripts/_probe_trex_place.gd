extends SceneTree
## 在校园碰撞网格（竖面）里数：三只霸王龙脚下 4 m 内有没有墙。
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	for _i in 5:
		await process_frame
	var col := level.get_node_or_null("CampusCollision")
	var faces := PackedVector3Array()
	for cs in col.find_children("*", "CollisionShape3D", true, false):
		var sh := (cs as CollisionShape3D).shape
		if sh is ConcavePolygonShape3D:
			faces = (sh as ConcavePolygonShape3D).get_faces()
			break
	print("[place] 三角面顶点 %d" % faces.size())
	var names := ["TrexBossA", "TrexBossB", "TrexBossC"]
	var pts: Array[Vector2] = []
	for nm in names:
		var b := level.get_node(nm) as Node3D
		pts.append(Vector2(b.global_position.x, b.global_position.z))
	var near := [0, 0, 0]
	var nearest := [INF, INF, INF]
	var i := 0
	while i < faces.size():
		var c := (faces[i] + faces[i + 1] + faces[i + 2]) / 3.0
		i += 3
		if c.y > 12.0 or c.y < -3.0:
			continue
		for k in range(3):
			var d := Vector2(c.x, c.z).distance_to(pts[k])
			if d < nearest[k]:
				nearest[k] = d
			if d < 4.0:
				near[k] += 1
	for k in range(3):
		print("[place] %s 4 m 内墙面三角 %d 个，最近墙面 %.1f m" % [names[k], near[k], nearest[k]])
	quit(0)
