extends SceneTree
## 眉毛「分层」到底该怎么判 —— 用户 2026-10-26：
## 「为什么爱丽丝变成了白色眉毛，其他人眉毛有点小错误」
##   godot --path . --headless --script res://scripts/_probe_brow_layers.gd -- --splat=off
##
## 已知（上一版 `simplify_brows` 用「z 中心四舍五入到 0.01」分组）：
##   · 爱丽丝变白眉 → 她那 16 块被**误判成多层**、压掉一大半；
##   · 其他人留了「细线」→ 压平顶点后**蒙皮又把它们拉开了**（压平 ≠ 消失）。
##
## 本探针只回答一个问题：**用「相邻块的 z 间隙」当分层判据，阈值该取多少**。
## 打印每个角色所有块按 z 排序后的**相邻间隙**，一眼看得出「同一层的碎片」
## 和「不同层」差几个数量级。

func _initialize() -> void:
	_run.call_deferred()


func _find_brow(node: Node3D) -> Array:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not (m.mesh is ArrayMesh):
			continue
		var am := m.mesh as ArrayMesh
		for s in am.get_surface_count():
			var mat := am.surface_get_material(s)
			if mat != null and String(mat.resource_name).to_lower().contains("brow"):
				return [m, am, s]
	return []


## 连通块：返回每个块的 z 中心 / z 范围 / 顶点数
func _blocks(arr: Array) -> Array:
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var parent := PackedInt32Array()
	parent.resize(vs.size())
	for i in vs.size():
		parent[i] = i

	var find := func(p: PackedInt32Array, i: int) -> int:
		var r := i
		while p[r] != r:
			r = p[r]
		return r

	var t := 0
	while t + 2 < idx.size():
		var a: int = find.call(parent, idx[t])
		var b: int = find.call(parent, idx[t + 1])
		var c: int = find.call(parent, idx[t + 2])
		var mn := mini(a, mini(b, c))
		parent[a] = mn
		parent[b] = mn
		parent[c] = mn
		t += 3
	var groups := {}
	for i in vs.size():
		var r: int = find.call(parent, i)
		if not groups.has(r):
			groups[r] = PackedInt32Array()
		var g: PackedInt32Array = groups[r]
		g.append(i)
		groups[r] = g
	var out: Array = []
	for k in groups:
		var g2: PackedInt32Array = groups[k]
		var lo := 1e9
		var hi := -1e9
		for i in g2:
			lo = minf(lo, vs[i].z)
			hi = maxf(hi, vs[i].z)
		out.append({"n": g2.size(), "lo": lo, "hi": hi, "z": (lo + hi) * 0.5,
			"tris": g2.size()})
	out.sort_custom(func(x, y): return float(x["z"]) < float(y["z"]))
	return out


func _report(tag: String, node: Node3D) -> void:
	var hit := _find_brow(node)
	if hit.is_empty():
		print("\n%s：没有 Eyebrow surface" % tag)
		return
	var am := hit[1] as ArrayMesh
	var surf := int(hit[2])
	var arr := am.surface_get_arrays(surf)
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var bl := _blocks(arr)
	print("\n%s：%d 块、%d 个顶点、%d 个索引（%d 三角形）"
		% [tag, bl.size(), (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
			idx.size(), idx.size() / 3])
	var gaps: Array[float] = []
	for i in bl.size():
		var g := ""
		if i > 0:
			var d: float = float(bl[i]["lo"]) - float(bl[i - 1]["hi"])
			gaps.append(d)
			g = "   ← 与上一块的间隙 %+.4f" % d
		print("  块 %2d: 顶点 %2d  z %+.4f ~ %+.4f%s"
			% [i, int(bl[i]["n"]), float(bl[i]["lo"]), float(bl[i]["hi"]), g])
	if not gaps.is_empty():
		var mn := 1e9
		var mx := -1e9
		var mx_pos := 0.0
		for i in gaps.size():
			mn = minf(mn, gaps[i])
			if gaps[i] > mx:
				mx = gaps[i]
				mx_pos = float(bl[i]["lo"])
		print("  间隙：最小 %+.4f、**最大 %+.4f**（出现在 z=%+.4f）" % [mn, mx, mx_pos])
		# 按不同阈值分组，看哪种最合理
		for eps in [0.010, 0.015, 0.020, 0.030, 0.050]:
			var layers := 1
			for i in gaps.size():
				if gaps[i] > eps:
					layers += 1
			print("    阈值 %.3f → %d 层%s" % [eps, layers,
				"  ← 和实测层数一致" if layers > 1 else ""])


func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 120:
		await process_frame
	paused = false
	for pair in [["Player", "爱丽丝"], ["CompanionKoyuki", "小雪"],
			["CompanionYuuka", "优香"], ["CompanionNoa", "诺亚"],
			["CompanionMomoi", "小桃"], ["CompanionMidori", "小绿"],
			["CompanionYuzu", "柚子"], ["CompanionKei", "凯伊"],
			["Shop/ClerkSerika", "芹香"]]:
		var nd := game.get_node_or_null(String(pair[0])) as Node3D
		if nd == null:
			continue
		_report(String(pair[1]), nd)
	quit(0)
