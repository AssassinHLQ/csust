extends SceneTree
## 验数：**算出**芹香蒙皮后网格的最低点（不靠肉眼）。
##   godot --path . --headless --script res://scripts/_probe_skinned_min_y.gd -- --splat=off
##
## ── 为什么要自己算 ──
## 前面试过三种都不行：
##   ① `mesh.get_aabb()` —— 那是**绑定姿势**的包围盒，和屏幕上的姿势无关；
##   ② 脚骨（`Bip001 L/R Foot`）—— 她骨架里**没有 toe 骨**，这条骨到底在踝
##      还是脚掌、离鞋底多少，和玩家那套不一样，拿玩家的数当尺子就量错了
##      （上次定到 +0.007，结果脚陷进地里）；
##   ③ 截图目测 —— 她的鞋底和地面都是深色，缩略图上看不出差 5 cm 还是 15 cm。
##
## 所以直接算：对每个带蒙皮的 `MeshInstance3D`，取顶点（绑定姿势）+ 骨骼索引 +
## 权重，按 `Σ w · (bone_global_pose · bind_pose) · v` 求出蒙皮后的位置，
## 再变换到世界，取最小 y。这是**屏幕上真正画出来的**那个最低点。
##
## 同一套代码顺便量玩家（已知他站得对），可以互相对照。
func _initialize() -> void:
	_run.call_deferred()


var _alt_mi := INF


## 返回 {min_y, alt, count, surfaces}；`node` 是角色的根节点
func _skinned_min_y(node: Node) -> Dictionary:
	_alt_mi = INF
	var best := INF
	var count := 0
	var surfaces := 0
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		# ⚠️ Godot 4 里 `MeshInstance3D.skeleton` 是 **NodePath**（不是对象引用），
		#    要自己 `get_node_or_null` 解析；直接当 Skeleton3D 用会报类型错。
		var skel: Skeleton3D = null
		if not mi.skeleton.is_empty():
			skel = mi.get_node_or_null(mi.skeleton) as Skeleton3D
		if skel == null:
			# 兜底：往上层找最近的 Skeleton3D
			var up: Node = mi.get_parent()
			while up != null and skel == null:
				skel = up as Skeleton3D
				if skel == null:
					skel = up.find_child("*", false, false) as Skeleton3D
				up = up.get_parent()
		if skel == null:
			continue
		var skin := mi.skin
		var xform := mi.global_transform
		for si in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if verts.is_empty():
				continue
			surfaces += 1
			# 三种变换都留一份，靠「玩家应该 ≈ 0」来定哪一种是正确的
			var x_skel: Transform3D = skel.global_transform
			var x_mi: Transform3D = mi.global_transform
			var bones = arrays[Mesh.ARRAY_BONES]
			var weights = arrays[Mesh.ARRAY_WEIGHTS]
			if bones == null or weights == null or skin == null:
				# 没有蒙皮信息：当成静态顶点直接量
				for v in verts:
					var wy: float = (xform * v).y
					best = minf(best, wy)
					count += 1
				continue
			var per_vertex: int = int(bones.size() / maxi(verts.size(), 1))
			for vi in verts.size():
				var p := Vector3.ZERO
				for k in per_vertex:
					var bi: int = bones[vi * per_vertex + k]
					var w: float = weights[vi * per_vertex + k]
					if w <= 0.0:
						continue
					if bi < 0 or bi >= skin.get_bind_count():
						continue
					var bone: int = skin.get_bind_bone(bi)
					if bone < 0:
						continue
					var m: Transform3D = skel.get_bone_global_pose(bone) \
						* skin.get_bind_pose(bi)
					p += m * verts[vi] * w
				best = minf(best, (x_skel * p).y)
				_alt_mi = minf(_alt_mi, (x_mi * p).y)
				count += 1
	return {"min_y": best, "alt": _alt_mi, "count": count, "surfaces": surfaces}


func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 130:
		await process_frame
	paused = false

	# ── 玩家：已知站得对，当对照 ──
	var player := game.get("_player") as Node3D
	if player != null:
		var pr := _skinned_min_y(player)
		print("玩家：最低点(skel 变换) = %+.4f   (mesh 变换) = %+.4f   顶点 %d、面 %d  原点 y %+.4f"
			% [float(pr["min_y"]), float(pr["alt"]), int(pr["count"]),
				int(pr["surfaces"]), player.global_position.y])

	# ── 芹香 ──
	var clerk := game.get_node_or_null("Shop/ClerkSerika") as Node3D
	if clerk == null:
		print("[错误] 没有 ClerkSerika")
		quit(1)
		return
	var model: Node3D = null
	for c in clerk.get_children():
		if c is Node3D and not (c is CollisionObject3D):
			model = c as Node3D
			break
	if model == null:
		print("[错误] 找不到模型")
		quit(1)
		return
	var r := _skinned_min_y(clerk)
	print("\n芹香：蒙皮后最低点 y = %+.4f（顶点 %d、面 %d）" % [
		float(r["min_y"]), int(r["count"]), int(r["surfaces"])])
	print("      角色原点 y = %+.4f，模型 position.y = %+.4f"
		% [clerk.global_position.y, model.position.y])
	print("      → 让鞋底落在 y=0 需要的抬脚值 = %+.4f" % (-float(r["min_y"])))

	# 顺便验证：把抬脚改成这个值，复量应该 ≈ 0
	var want := -float(r["min_y"])
	model.position.y = want
	for _f in 5:
		await process_frame
	var r2 := _skinned_min_y(clerk)
	print("      改成 %+.4f 之后复量 = %+.4f" % [want, float(r2["min_y"])])
	quit(0)
