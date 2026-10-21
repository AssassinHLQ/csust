extends SceneTree
## 探针：把 `RoomProxy` 底下每个节点的**世界 AABB** 打出来（墙 / 屋顶 / 门楣 / 门框 /
## 门板 / 把手）。用户 2026-10-21 第三张图里「门框上方一道竖线 + 屋顶边缘一个缺口」，
## 需要知道是谁先谁后、谁比谁凸出来多少 —— 只看代码猜不出来。
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_proxy_dump.gd [-- --splat=off]

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _i in 30:
		await process_frame
	var proxy := game.get_node_or_null("RoomProxy") as Node3D
	if proxy == null:
		print("PROXY 没有 RoomProxy")
		quit(1)
		return
	print("PROXY 节点 %d 个（世界 AABB：x0 x1 / y0 y1 / z0 z1）" % proxy.get_child_count())
	for c in proxy.get_children():
		var n3 := c as Node3D
		if n3 == null:
			continue
		var bb := AABB()
		var has := false
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			bb = (c as MeshInstance3D).global_transform * (c as MeshInstance3D).mesh.get_aabb()
			has = true
		if not has:
			print("  %-12s %s" % [String(c.name), c.get_class()])
			continue
		print("  %-12s x %7.3f~%7.3f  y %7.3f~%7.3f  z %7.3f~%7.3f" % [
			String(c.name), bb.position.x, bb.position.x + bb.size.x,
			bb.position.y, bb.position.y + bb.size.y,
			bb.position.z, bb.position.z + bb.size.z])
	# 屋顶是谁？
	var roof := proxy.get_node_or_null("Roof")
	if roof != null:
		print("PROXY Roof 节点存在：%s" % str((roof as Node3D).global_position.snappedf(0.01)))
	quit(0)
