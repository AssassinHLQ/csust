extends SceneTree
## 把 AutoCol 建的每个盒子都打印出来（世界坐标 + 尺寸），
## 直接看 +Z 那面墙到底建了什么、门楣在不在。
##
##   & godot --script res://scripts/_dump_esports_boxes.gd -- --splat=off --story=off

func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	await _wait(3)
	var room: Node3D = load("res://scenes/esports_room.tscn").instantiate()
	root.add_child(room)
	room.global_position = Vector3(52, 0.01, 13)
	await _wait(30)

	var body := room.get_node_or_null("AutoCol") as StaticBody3D
	if body == null:
		print("[dump] 没有 AutoCol")
		quit(1)
		return

	var idx := 0
	var rows := []
	for c in body.get_children():
		var cs := c as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		var bs := cs.shape as BoxShape3D
		var p := cs.global_position
		var s := bs.size
		rows.append([idx, p, s])
		idx += 1

	print("[dump] 共 %d 个盒子（房间中心应在 (52.0, ?, 13.0)，+Z 墙在 z=21.42）" % rows.size())
	print("[dump] ---- 按 z 从大到小（最靠近 +Z 墙的先看）----")
	rows.sort_custom(func(a, b): return (a[1] as Vector3).z > (b[1] as Vector3).z)
	for r in rows.slice(0, 14):
		var p: Vector3 = r[1]
		var s: Vector3 = r[2]
		print("[dump] #%-3d pos(%7.2f,%6.2f,%7.2f) size(%5.2f,%5.2f,%5.2f)"
			% [r[0], p.x, p.y, p.z, s.x, s.y, s.z])

	print("[dump] ---- 只列 +Z 墙附近（z > 20.5）----")
	var n_wall := 0
	for r in rows:
		var p: Vector3 = r[1]
		if p.z <= 20.5:
			continue
		var s: Vector3 = r[2]
		print("[dump] #%-3d pos(%7.2f,%6.2f,%7.2f) size(%5.2f,%5.2f,%5.2f)  x范围[%.2f,%.2f]  y范围[%.2f,%.2f]"
			% [r[0], p.x, p.y, p.z, s.x, s.y, s.z,
			   p.x - s.x * 0.5, p.x + s.x * 0.5,
			   p.y - s.y * 0.5, p.y + s.y * 0.5])
		n_wall += 1
	print("[dump] +Z 墙附近共 %d 个盒子" % n_wall)
	quit(0)
