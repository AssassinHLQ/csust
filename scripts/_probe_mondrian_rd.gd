extends SceneTree
## 验数：① 大楼有没有进渲染距离的裁切簇 ② 远处看不见时会不会把自己裁掉
##   godot --path . --headless --script res://scripts/_probe_mondrian_rd.gd -- --splat=off
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 120:
		await process_frame
	paused = false
	var house := game.get_node_or_null("MondrianHouse") as Node3D
	var rd := game.get_node_or_null("RenderDistance") as Node
	if house == null or rd == null:
		print("[错误] 缺节点（house=%s rd=%s）" % [str(house), str(rd)])
		quit(1)
		return

	# 数一下大楼下有多少网格，其中多少还 visible
	var total := 0
	var hidden := 0
	for mi in house.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		total += 1
		if not m.is_visible_in_tree():
			hidden += 1
	print("RenderDistance 就位：%s" % rd.get_class())
	print("大楼网格 %d 个，当前不可见 %d 个" % [total, hidden])

	# 把玩家挪到很远的地方（内存条市场那边），看大楼会不会被正确裁掉
	var player := game.get("_player") as Node3D
	var far := Vector3(-450.0, 1.0, 6.0)
	player.global_position = far
	print("\n把玩家挪到 %s（距大楼约 %.0f m）" % [
		str(far), far.distance_to(house.global_position)])
	for _i in 40:
		await process_frame
	hidden = 0
	for mi in house.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		if not m.is_visible_in_tree():
			hidden += 1
	print("远处时大楼不可见网格 %d / %d（渲染距离内的簇会显示）" % [hidden, total])

	# 关键：玩家自己可见吗（之前修过一次「跑到内存条那里看不见自己人」）
	var pm := player.get_node_or_null("Arisu") as Node3D
	if pm != null:
		print("玩家模型 visible_in_tree = %s" % str(pm.is_visible_in_tree()))

	# 回到大楼门口，确认恢复显示
	print("\n把玩家挪回大楼门口")
	player.global_position = Vector3(house.global_position.x, 0.1, house.global_position.z - 9.0)
	for _i in 40:
		await process_frame
	hidden = 0
	for mi in house.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		if not m.is_visible_in_tree():
			hidden += 1
	print("近处时大楼不可见网格 %d / %d（应接近 0）" % [hidden, total])
	quit(0)
