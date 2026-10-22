extends SceneTree
## 只读探针：芹香到底多高、柜台多高（「只有天灵盖露出来」时先用它定位）。
##   godot --headless --path . --script res://scripts/_probe_clerk_size.gd

const GAME := "res://scenes/game.tscn"

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := (load(GAME) as PackedScene).instantiate()
	root.add_child(game)
	for _i in 20:
		await process_frame
	var clerk := game.get_node_or_null("Shop/ClerkSerika") as ShopClerk
	if clerk == null:
		print("[sz] 没有 ClerkSerika")
		quit(1)
		return
	var skel := clerk.skeleton
	if skel != null:
		for want in ["Bip001 Head", "Bip001 Neck", "Bip001 L Hand"]:
			var i := skel.find_bone(want)
			if i >= 0:
				var w := skel.global_transform * skel.get_bone_global_pose(i)
				print("[sz] %-16s 世界 y=%.2f" % [want, w.origin.y])
	# 本体（去掉光环）的世界 AABB
	var box := AABB()
	var first := true
	var stack: Array[Node] = [clerk]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			var nm := String(mi.name).to_lower()
			if not (nm.contains("halo") or nm.contains("光环")):
				var a: AABB = mi.global_transform * mi.mesh.get_aabb()
				if first:
					box = a
					first = false
				else:
					box = box.merge(a)
		for c in n.get_children():
			stack.append(c)
	print("[sz] 本体世界 AABB 底 %.2f 顶 %.2f（高 %.2f m），模型 scale=%.3f，y=%.2f"
		% [box.position.y, box.end.y, box.size.y, clerk.model.scale.y, clerk.model.position.y])
	# 柜台台面高度：Shop/Body 里最高的那个扁盒子？直接量收银台
	var body := game.get_node_or_null("Shop/Body")
	if body != null:
		var top := -1.0
		for n in body.get_children():
			var mi := n as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			var a2: AABB = mi.global_transform * mi.mesh.get_aabb()
			if String(mi.name).to_lower().contains("counter") and a2.end.y > top:
				top = a2.end.y
				print("[sz] 收银台 %s 台面 y=%.2f" % [mi.name, a2.end.y])
	quit(0)
