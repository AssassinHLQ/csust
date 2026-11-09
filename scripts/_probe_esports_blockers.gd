extends SceneTree
## 找出电竞房里**堵住通道**的碰撞盒是哪个网格生成的。
##
##   godot --path . --headless --script res://scripts/_probe_esports_blockers.gd

const GAME := "res://scenes/game.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := (load(GAME) as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	for _i in 20:
		await process_frame

	var room := game.get_node_or_null("EsportsRoom") as Node3D
	if room == null:
		print("[blk] !! 没有 EsportsRoom")
		quit(1)
		return

	var low := room.get_node_or_null("Room") as Node3D
	var box := AABB()
	var first := true
	for m in low.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var a: AABB = mi.global_transform * mi.mesh.get_aabb()
		box = a if first else box.merge(a)
		first = false
	var c := box.position + box.size * 0.5
	print("[blk] 房间世界 AABB pos=%s size=%s" % [
		str(box.position.snappedf(0.01)), str(box.size.snappedf(0.01))])
	print("[blk] 房间中轴 (%.2f, *, %.2f)，地面应在 y=%.2f" % [
		c.x, c.z, box.position.y + 0.22])

	# 列每个网格 → 它会生成的盒子，找出「盖住中轴、又太大」的那些
	print("[blk] ══ 盖住房间中轴、且 y 范围压到人高度的网格（会挡路）══")
	var rows: Array = []
	for m in low.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var a: AABB = mi.global_transform * mi.mesh.get_aabb()
		var covers := (a.position.x <= c.x and c.x <= a.position.x + a.size.x
			and a.position.z <= c.z and c.z <= a.position.z + a.size.z)
		if not covers:
			continue
		# 占住人走路的高度带（0.4 ~ 2.0）才算挡路
		if a.position.y > 2.0 or a.position.y + a.size.y < 0.4:
			continue
		rows.append({"name": String(mi.name), "aabb": a, "size": a.size})
	rows.sort_custom(func(a, b):
		var va: float = a["size"].x * a["size"].y * a["size"].z
		var vb: float = b["size"].x * b["size"].y * b["size"].z
		return va > vb)
	for r in rows:
		var a: AABB = r["aabb"]
		var s: Vector3 = r["size"]
		print("[blk]   %-32s x %6.2f~%6.2f  y %5.2f~%5.2f  z %6.2f~%6.2f  体积 %6.1f" % [
			r["name"], a.position.x, a.position.x + s.x,
			a.position.y, a.position.y + s.y,
			a.position.z, a.position.z + s.z, s.x * s.y * s.z])
	print("[blk]   （共 %d 个盖住中轴）" % rows.size())

	print("[blk] 完成")
	quit(0)
