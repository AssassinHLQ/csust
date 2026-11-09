extends SceneTree
## 数一数 EsportsRoom 下**到底有几套碰撞**，查「碰撞重复」。
##
##   godot --path . --headless --script res://scripts/_probe_esports_dupcol.gd

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
		print("[dup] !! 没有 EsportsRoom")
		quit(1)
		return

	# 所有 StaticBody3D / Area3D 及其下的 CollisionShape3D
	print("[dup] ── EsportsRoom 下所有碰撞体 ──")
	var total_shapes := 0
	for n in room.find_children("*", "CollisionObject3D", true, false):
		var co := n as CollisionObject3D
		var cnt := 0
		for c in co.get_children():
			if c is CollisionShape3D:
				cnt += 1
		total_shapes += cnt
		print("[dup]   %-40s %-16s 形状 %d  layer=%d" % [
			String(room.get_path_to(co)), co.get_class(), cnt, co.collision_layer])
	print("[dup] 合计形状 %d" % total_shapes)

	# 顶层子节点一览（看有没有意外的重复实例）
	print("[dup] ── EsportsRoom 的直接子节点 ──")
	for c in room.get_children():
		print("[dup]   %-24s %s" % [String(c.name), c.get_class()])

	# 精确重复检测：把所有 AutoCol 下的形状 (中心, 尺寸) 收集起来找重复
	print("[dup] ── 精确重复的形状（中心+尺寸都一样）──")
	var seen := {}
	var dup := 0
	for n in room.find_children("*", "CollisionShape3D", true, false):
		var cs := n as CollisionShape3D
		if not (cs.shape is BoxShape3D):
			continue
		var s: Vector3 = (cs.shape as BoxShape3D).size
		var key := "%s|%.3f,%.2f,%.2f" % [
			str(cs.global_position.snappedf(0.001)), s.x, s.y, s.z]
		if seen.has(key):
			dup += 1
		else:
			seen[key] = true
	print("[dup] 完全重复的形状 %d 个 / 共 %d 个" % [dup, seen.size() + dup])

	# 近似重复：尺寸一模一样、中心距离 < 0.15 m 的盒子 ——
	# 这是**模型里有镜像/复制件**的特征（3ds Max 里很常见）
	print("[dup] ── 近似重复的盒子（同尺寸 + 中心距 <0.15 m）──")
	var all: Array = []
	for n in room.find_children("*", "CollisionShape3D", true, false):
		var cs := n as CollisionShape3D
		if not (cs.shape is BoxShape3D):
			continue
		all.append({"p": cs.global_position, "s": (cs.shape as BoxShape3D).size,
			"n": String(cs.name)})
	var near := 0
	var groups := {}
	for a in all:
		var key := "%.2f,%.2f,%.2f" % [a["s"].x, a["s"].y, a["s"].z]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(a)
	for k in groups:
		var g: Array = groups[k]
		if g.size() < 2:
			continue
		for i in g.size():
			for j in range(i + 1, g.size()):
				# ⚠️ 只比**不同物体**之间的：同一物体被本喵拆成两半时，
				#    两半尺寸一样、中心也近，会被误判成「重复」。
				#    名字形如 `P0056_0`，取 `P0056` 当物体 id。
				var pi: String = String(g[i]["n"]).get_slice("_", 0)
				var pj: String = String(g[j]["n"]).get_slice("_", 0)
				if pi == pj:
					continue
				if (g[i]["p"] as Vector3).distance_to(g[j]["p"] as Vector3) < 0.15:
					near += 1
	print("[dup] 近似重复的盒子对 %d 组（**跨物体**，已排除同物体拆出来的兄弟块）" % near)
	# 打印几个例子
	var shown := 0
	for k in groups:
		var g: Array = groups[k]
		if g.size() < 2 or shown >= 5:
			continue
		for i in g.size():
			for j in range(i + 1, g.size()):
				if String(g[i]["n"]).get_slice("_", 0) == String(g[j]["n"]).get_slice("_", 0):
					continue
				if (g[i]["p"] as Vector3).distance_to(g[j]["p"] as Vector3) < 0.15:
					print("[dup]   %s @%s  ==  %s @%s  尺寸(%s)" % [
						g[i]["n"], str((g[i]["p"] as Vector3).snappedf(0.01)),
						g[j]["n"], str((g[j]["p"] as Vector3).snappedf(0.01)),
						k])
					shown += 1
					break
			if shown >= 5:
				break
	print("[dup] 完成")
	quit(0)
