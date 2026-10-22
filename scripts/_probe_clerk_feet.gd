extends SceneTree
## 探针：芹香的脚到底在哪儿 —— 用**骨骼**量（蒙皮后的网格 AABB 是绑定姿势，会骗人）。
##   godot --path . --script res://scripts/_probe_clerk_feet.gd -- --splat=off
## 参考：玩家的脚骨高度（`player.tscn` 里 Arisu 的 −0.035 是调准过的）。
func _initialize() -> void:
	_run.call_deferred()


func _bones(node: Node, kw: Array) -> Array:
	var out: Array = []
	var skel: Skeleton3D = null
	for s in node.find_children("*", "Skeleton3D", true, false):
		var sk := s as Skeleton3D
		if skel == null or sk.get_bone_count() > skel.get_bone_count():
			skel = sk
	if skel == null:
		return out
	for i in skel.get_bone_count():
		var n := skel.get_bone_name(i).to_lower()
		for k in kw:
			if n.contains(k):
				out.append({"n": skel.get_bone_name(i),
					"y": (skel.global_transform * skel.get_bone_global_pose(i).origin).y})
				break
	out.sort_custom(func(a, b): return a["y"] < b["y"])
	return out


func _report(tag: String, node: Node3D) -> void:
	var feet := _bones(node, ["foot", "toe", "ankle"])
	var parts: Array = []
	for i in mini(4, feet.size()):
		parts.append("%s=%.3f" % [feet[i]["n"], feet[i]["y"]])
	print("%-10s 原点 y %+.3f   脚骨 %s" % [tag, node.global_position.y, " ".join(parts)])


func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 90:
		await process_frame
	paused = false
	for _f in 60:
		await process_frame
	var player := game.get("_player") as Node3D
	var clerk := game.get_node_or_null("Shop/ClerkSerika") as Node3D
	if player != null:
		_report("玩家", player)
		print("           玩家位置 %s" % str(player.global_position.snapped(Vector3.ONE * 0.001)))
	if clerk != null:
		_report("芹香", clerk)
		print("           芹香位置 %s  下层 y %+.3f" % [
			str(clerk.global_position.snapped(Vector3.ONE * 0.001)), clerk.position.y])
	else:
		print("场景里没有 Shop/ClerkSerika")
	quit(0)
