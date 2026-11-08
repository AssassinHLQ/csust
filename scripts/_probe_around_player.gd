extends SceneTree
## 查：玩家所在位置 (49.74, 0.00, -6.66) 附近，场上有哪些节点？哪些可见？
## 用来判断「游戏开发部里啥都没有」是因为被 hide 了，还是真的没东西。
##
##   & godot --script res://scripts/_probe_around_player.gd -- --splat=off --story=off

const AT := Vector3(49.74, 0.0, -6.66)
const RADIUS := 30.0


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _run() -> void:
	for _i in 3:
		await process_frame

	var game: Node = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	for _i in 20:
		await process_frame

	print("======== 顶层节点 ========")
	for c in game.get_children():
		var vis := ""
		if c is Node3D:
			var n3 := c as Node3D
			var d := n3.global_position.distance_to(AT)
			var v := (c as Node3D).is_visible_in_tree()
			vis = " visible=%s dist=%.1fm pos=%s" % [str(v), d, str(n3.global_position)]
		else:
			vis = " visible=%s" % str(c.is_visible_in_tree()) if c.has_method("is_visible_in_tree") else ""
		print("  %-24s (%s)%s" % [c.name, c.get_class(), vis])

	print("======== %s 附近 30m 内的 MeshInstance3D 统计 ========" % str(AT))
	var all_mi := 0
	var near := 0
	var near_visible := 0
	var by_parent := {}
	for n in _all_mesh(game):
		all_mi += 1
		var mi := n as MeshInstance3D
		var wp := mi.global_position
		if wp.distance_to(AT) > RADIUS:
			continue
		near += 1
		if mi.is_visible_in_tree():
			near_visible += 1
		var top := mi
		while top.get_parent() != null and top.get_parent() != game:
			top = top.get_parent()
		var key := top.name
		if not by_parent.has(key):
			by_parent[key] = [0, 0]
		by_parent[key][0] += 1
		if mi.is_visible_in_tree():
			by_parent[key][1] += 1

	print("  全场网格 %d，30m 内 %d，其中可见 %d" % [all_mi, near, near_visible])
	print("  ---- 按顶层父节点分组（近处网格 / 其中可见）----")
	for k in by_parent.keys():
		var v = by_parent[k]
		print("    %-24s %d / %d" % [k, v[0], v[1]])

	print("======== 东侧三块的直接子节点可见性 ========")
	for nm in ["LotEast", "GameDevRoom", "EsportsRoom", "MondrianHouse"]:
		var n := game.get_node_or_null(nm)
		if n == null:
			print("  %-16s <不存在>" % nm)
			continue
		var n3 := n as Node3D
		print("  %-16s visible=%s  in_tree_visible=%s  pos=%s  children=%d"
			% [nm, str(n3.visible), str(n3.is_visible_in_tree()),
			   str(n3.global_position) if n3 else "?", n.get_child_count()])

	print("======== ShopClerk 是否已成交 ========")
	var clerk := game.get_node_or_null("ShopClerk")
	if clerk != null:
		print("  ShopClerk 存在，is_bought=%s" % str(clerk.call("is_bought") if clerk.has_method("is_bought") else "无此方法"))
	else:
		print("  ShopClerk 不存在")

	quit(0)


func _all_mesh(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_mesh(c))
	return out
