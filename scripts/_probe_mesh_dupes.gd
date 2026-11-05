extends SceneTree
## 重复网格盘点：archviz 场景最肥的一刀在「同一个网格被复制成很多个独立节点」。
##
## 判据：按 `Mesh` 资源分组。同一份 Mesh 出现 N 次 ⇒ 用 MultiMesh 或
## `GeometryInstance3D` 共享网格就能省 (N-1) 份顶点数据 + 让 GPU 侧实例化。
## 注意「共享 Mesh 资源」本来就只占一份显存，真正省的是 **draw call 和提交开销**。
##
## 用法：
##   _tools/run_probe.sh res://scripts/_probe_mesh_dupes.gd

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene_name := "esports_room"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			scene_name = a.substr(8)
	var inst := (load("res://scenes/%s.tscn" % scene_name) as PackedScene).instantiate()
	root.add_child(inst)
	await process_frame

	var meshes: Array[MeshInstance3D] = []
	_collect(inst, meshes)

	# 按 Mesh 资源分组
	var groups := {}
	for m in meshes:
		if m.mesh == null:
			continue
		var key := m.mesh.get_instance_id()
		if not groups.has(key):
			groups[key] = {"mesh": m.mesh, "nodes": [], "prim": _tris(m.mesh)}
		groups[key]["nodes"].append(m)

	var dup_total := 0
	var dup_saved := 0
	var rows: Array = []
	for k in groups:
		var g: Dictionary = groups[k]
		var n: int = (g["nodes"] as Array).size()
		var prim: int = int(g["prim"])
		dup_total += n
		if n > 1:
			dup_saved += (n - 1) * prim
			rows.append({"n": n, "prim": prim, "name": String((g["nodes"][0] as MeshInstance3D).name)})

	_log("网格节点 %d，唯一 Mesh %d" % [dup_total, groups.size()])
	_log("重复出现的网格组：%d 组" % rows.size())
	rows.sort_custom(func(a, b): return int(a["n"]) * int(a["prim"]) > int(b["n"]) * int(b["prim"]))
	_log("")
	_log("重复最多的（按浪费的三角数排）：")
	var shown := 0
	for r in rows:
		if shown >= 15:
			break
		_log("  ×%-3d  %8d 三角/份   %-30s  共浪费 %9d 三角" % [
			int(r["n"]), int(r["prim"]), String(r["name"]).substr(0, 30),
			(int(r["n"]) - 1) * int(r["prim"])])
		shown += 1

	_log("")
	_log("若把这些重复组改成 MultiMesh/实例化：")
	_log("  节点数 %d → 约 %d（每组 1 个实例节点）" % [dup_total, groups.size()])
	_log("  每帧少提交约 %d 个重复实例的三角（%d）" % [
		dup_saved, dup_saved])
	quit(0)


func _tris(mesh: Mesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		if mesh is ArrayMesh:
			var a: Array = (mesh as ArrayMesh).surface_get_arrays(s)
			if a.size() > Mesh.ARRAY_INDEX and a[Mesh.ARRAY_INDEX] != null:
				n += (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			elif a.size() > Mesh.ARRAY_VERTEX and a[Mesh.ARRAY_VERTEX] != null:
				n += (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


func _collect(node: Node, out: Array[MeshInstance3D]) -> void:
	var mi := node as MeshInstance3D
	if mi != null:
		out.append(mi)
	for c in node.get_children():
		_collect(c, out)


var _lines: PackedStringArray = PackedStringArray()


func _log(s: String) -> void:
	print("[dupes] " + s)
	_lines.append(s)
