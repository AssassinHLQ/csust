extends SceneTree
## 摸清一个模型的「结构」：每个子物件多大、像墙还是像家具、有没有地板。
##
## 为什么需要：电竞酒店那个模型从俯视图看**大片空白**，怀疑没有墙和地板
## （可能 3ds Max 里是分层导出的，或者原工程就没做）。要不要给它补墙、
## 补地板，得先确认现状。
##
## 判据（很粗糙但够用）：
##   · **墙**：X 或 Z 跨度很大（> 3 m）、Y 也不小、厚度（另一轴）很薄（< 0.5 m）
##   · **地板**：Y 跨度很薄（< 0.3 m）、XZ 都很大
##   · **家具**：三个维度都适中
##
## 用法（headless 即可）：
##   _tools/run_probe.sh res://scripts/_probe_model_structure.gd -- --model=res://models/xxx.glb

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var model := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--model="):
			model = a.substr(8)
	if model == "" or not ResourceLoader.exists(model):
		print("[struct] 载入不了 %s" % model)
		quit(1)
		return

	var inst: Node = (load(model) as PackedScene).instantiate()
	root.add_child(inst)
	await process_frame

	var rows: Array = []
	for mi in _meshes(inst):
		if mi.mesh == null:
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		var s := b.size
		var tris := 0
		for i in mi.mesh.get_surface_count():
			if mi.mesh is ArrayMesh:
				var a: Array = (mi.mesh as ArrayMesh).surface_get_arrays(i)
				if a.size() > Mesh.ARRAY_INDEX and a[Mesh.ARRAY_INDEX] != null:
					tris += (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		rows.append({
			"name": String(mi.name), "size": s, "aabb": b, "tris": tris,
			"kind": _classify(s),
		})

	rows.sort_custom(func(a, b): return (a["size"] as Vector3).length() > (b["size"] as Vector3).length())

	var total := AABB()
	var first := true
	var kinds := {}
	for r in rows:
		kinds[r["kind"]] = int(kinds.get(r["kind"], 0)) + 1
		if first:
			total = r["aabb"]
			first = false
		else:
			total = total.merge(r["aabb"])

	print("[struct] 物件 %d，总包围盒 %s" % [rows.size(), str(total.size.snappedf(0.1))])
	print("[struct] 分类：" + ", ".join(kinds.keys().map(
		func(k): return "%s %d" % [k, kinds[k]])))
	print("[struct]")
	print("[struct] %-32s %-24s %10s  %s" % ["名称", "尺寸(m)", "三角", "判定"])
	for i in mini(rows.size(), 30):
		var r: Dictionary = rows[i]
		var s: Vector3 = r["size"]
		print("[struct] %-32s %-24s %10d  %s" % [
			String(r["name"]).substr(0, 32),
			"%.1f × %.1f × %.1f" % [s.x, s.y, s.z],
			int(r["tris"]), String(r["kind"])])

	# 底面检查：有没有东西铺在地面高度附近、覆盖很大面积
	var span := total.size
	var floor_cover := 0.0
	for r in rows:
		var s: Vector3 = r["size"]
		var b: AABB = r["aabb"]
		if s.y <= 0.4 and s.x > span.x * 0.5 and s.z > span.z * 0.5:
			floor_cover += 1.0
			print("[struct] 疑似地板：%s  %s" % [String(r["name"]), str(s.snappedf(0.1))])
	if floor_cover == 0.0:
		print("[struct] ⚠️ 没有找到「像地板」的物件（Y 跨度 ≤0.4 m 且 XZ 覆盖超过一半）")

	quit(0)


func _classify(s: Vector3) -> String:
	var dims := [s.x, s.y, s.z]
	dims.sort()
	var thin: float = dims[0]
	var mid: float = dims[1]
	var big: float = dims[2]
	if s.y <= 0.4 and s.x > 3.0 and s.z > 3.0:
		return "地板"
	if thin <= 0.5 and big > 3.0 and mid > 1.5:
		return "墙/板"
	if big > 3.0:
		return "大型"
	if big > 1.0:
		return "家具"
	return "小件"


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	_walk(node, out)
	return out


func _walk(node: Node, out: Array[MeshInstance3D]) -> void:
	var mi := node as MeshInstance3D
	if mi != null:
		out.append(mi)
	for c in node.get_children():
		_walk(c, out)
