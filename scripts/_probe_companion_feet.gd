extends SceneTree
## 探针：7 名同伴站定之后，模型最底下那个面在哪儿（离地多少）。
##   godot --path . --script res://scripts/_probe_companion_feet.gd -- --splat=off
func _initialize() -> void:
	_run.call_deferred()


func _aabb(node: Node) -> AABB:
	var box := AABB()
	var first := true
	var list: Array = []
	if node is MeshInstance3D:
		list.append(node)
	list.append_array(node.find_children("*", "MeshInstance3D", true, false))
	for mi in list:
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree():
			continue
		var a: AABB = m.global_transform * m.get_aabb()
		box = a if first else box.merge(a)
		first = false
	return box


func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 60:
		await process_frame
	paused = false
	game.call("_on_summon")
	for _i in 40:
		await process_frame
	var comps: Array = game.get("_companions")
	var lo: Array = []
	var hi: Array = []
	for i in comps.size():
		lo.append(INF)
		hi.append(-INF)
	# 采集 3 秒（180 帧）待机
	for _f in 180:
		await process_frame
		for i in comps.size():
			var comp := comps[i] as Node3D
			if not is_instance_valid(comp):
				continue
			var b := _aabb(comp).position.y
			lo[i] = minf(lo[i], b)
			hi[i] = maxf(hi[i], b)
	print("—— 3 秒待机里「模型最低点」的世界 y（地面 y = 0）——")
	for i in comps.size():
		var comp := comps[i] as Node3D
		if not is_instance_valid(comp):
			continue
		var model := comp.get_node_or_null("Rig") as Node3D
		var moff := 0.0
		var mp := ""
		if model != null and model.get_child_count() > 0:
			moff = (model.get_child(0) as Node3D).position.y
			var c := model.get_child(0) as Node
			mp = str(c.get("model_path"))
		print("%-16s 原点 y %+.3f  最低点 %+.3f ~ %+.3f  补偿前 model.y %+.3f  模型 %s" % [
			comp.name, comp.global_position.y, lo[i], hi[i], moff, mp.get_file()])
	quit(0)
