extends SceneTree
## 探针：7 名同伴的「脚骨」与「模型最低点」分别在哪 —— 用来判断最低点是不是鞋底。
##   godot --path . --script res://scripts/_probe_companion_bones.gd -- --splat=off
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
		var a: AABB = m.global_transform * m.mesh.get_aabb()
		box = a if first else box.merge(a)
		first = false
	return box


func _skel(node: Node) -> Skeleton3D:
	var best: Skeleton3D = null
	for s in node.find_children("*", "Skeleton3D", true, false):
		var sk := s as Skeleton3D
		if best == null or sk.get_bone_count() > best.get_bone_count():
			best = sk
	return best


## 名字里带 foot / toe / ankle 的骨头，取世界 y 最低的几个
func _foot_bones(skel: Skeleton3D) -> Array:
	var out: Array = []
	for i in skel.get_bone_count():
		var n := skel.get_bone_name(i).to_lower()
		if n.contains("foot") or n.contains("toe") or n.contains("ankle"):
			var p := skel.global_transform * skel.get_bone_global_pose(i).origin
			out.append({"n": skel.get_bone_name(i), "y": p.y})
	return out


func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 60:
		await process_frame
	paused = false
	game.call("_on_summon")
	for _i in 60:
		await process_frame
	var comps: Array = game.get("_companions")
	for i in comps.size():
		var comp := comps[i] as Node3D
		if not is_instance_valid(comp):
			continue
		var b := _aabb(comp).position.y
		var sk := _skel(comp)
		if sk == null:
			print("%-16s 没有骨架" % comp.name)
			continue
		var feet := _foot_bones(sk)
		feet.sort_custom(func(a, b2): return a["y"] < b2["y"])
		var parts: Array = []
		for k in mini(3, feet.size()):
			parts.append("%s=%.3f" % [feet[k]["n"], feet[k]["y"]])
		print("%-16s 模型底 %+.3f  最低脚骨 %s  （共 %d 根脚骨，骨架 %d 骨）" % [
			comp.name, b, " ".join(parts), feet.size(), sk.get_bone_count()])
	quit(0)
