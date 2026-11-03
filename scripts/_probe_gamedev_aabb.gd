extends SceneTree
## 对比「游戏开发部活动室」的**可见模型包围盒**与**碰撞体包围盒**是否重合。
##
##   _tools/run_probe.sh res://scripts/_probe_gamedev_aabb.gd -- --splat=off
##
## 判据：两个包围盒的中心差 > 0.3 m、或任一轴尺寸差 > 5%，就是错位
## （典型的错位是绕 Y 转了 90°，x / z 会互换）。

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(12)

	var room := game.get_node_or_null("GameDevRoom") as Node3D
	if room == null:
		print("!! 没有 GameDevRoom")
		quit(1)
		return

	# ── 可见网格 ──
	var vis := AABB()
	var vis_ok := false
	for n in room.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var w := mi.global_transform * mi.mesh.get_aabb()
		vis = w if not vis_ok else vis.merge(w)
		vis_ok = true

	# ── 碰撞体 ──
	var col := AABB()
	var col_ok := false
	for n in room.find_children("*", "CollisionShape3D", true, false):
		var cs := n as CollisionShape3D
		if cs.shape == null:
			continue
		var w := AABB()
		# CollisionShape3D 没有直接给 AABB 的接口；按 shape 自己算
		var s := cs.shape
		if s is BoxShape3D:
			var half := (s as BoxShape3D).size * 0.5
			w = cs.global_transform * AABB(-half, half * 2.0)
		elif s is ConcavePolygonShape3D:
			var pts: PackedVector3Array = (s as ConcavePolygonShape3D).get_faces()
			if pts.is_empty():
				continue
			var mn := pts[0]
			var mx := pts[0]
			for v in pts:
				mn = mn.min(v)
				mx = mx.max(v)
			w = AABB(mn, mx - mn)
			# ConcavePolygonShape3D 的点是**局部**的，要乘碰撞节点的全局变换
			w = cs.global_transform * w
		else:
			continue
		col = w if not col_ok else col.merge(w)
		col_ok = true

	print("[aabb] 可见模型 : %s ~ %s   尺寸 %s" % [
		str(vis.position.snappedf(0.01)), str(vis.end.snappedf(0.01)),
		str(vis.size.snappedf(0.01))])
	print("[aabb] 碰撞体   : %s ~ %s   尺寸 %s" % [
		str(col.position.snappedf(0.01)), str(col.end.snappedf(0.01)),
		str(col.size.snappedf(0.01))])

	if not vis_ok or not col_ok:
		print("[aabb] !! 没收集到数据")
		quit(1)
		return

	var dc := (vis.get_center() - col.get_center()).length()
	var ds := vis.size - col.size
	print("[aabb] 中心差 %.3f m   尺寸差 (%+.3f, %+.3f, %+.3f)" % [dc, ds.x, ds.y, ds.z])

	var bad := dc > 0.3 or absf(ds.x) > 0.5 or absf(ds.z) > 0.5
	print("[aabb] 结果：%s" % ("★ 错位" if bad else "重合"))
	quit(1 if bad else 0)


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
