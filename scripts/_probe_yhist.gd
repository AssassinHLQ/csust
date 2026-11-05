extends SceneTree
## 找「真正的地面在哪」：按顶点做 Y 方向直方图。
##
## 为什么需要：电竞酒店那个模型总包围盒 Y 有 41 米，但渲染图里家具都挤在一起
## —— 说明有几个**离群物件**把包围盒撑大了。直接在包围盒里按比例取高度
## 会站到地板下或天花板外（本喵第一版就把相机放到 -5.4 m，人在椅子下面）。
##
## 做法：抽 20 万个顶点，按 Y 分 40 个桶数一数，看**质量集中**在哪一段。
##
## 用法：
##   _tools/run_probe.sh res://scripts/_probe_yhist.gd -- --model=res://models/xxx.glb

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var model := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--model="):
			model = a.substr(8)
	var inst: Node = (load(model) as PackedScene).instantiate()
	root.add_child(inst)
	await process_frame

	var lo := INF
	var hi := -INF
	var samples: Array[float] = []
	for mi in _meshes(inst):
		if mi.mesh == null or not (mi.mesh is ArrayMesh):
			continue
		var xf := mi.global_transform
		for si in mi.mesh.get_surface_count():
			var arr: Array = (mi.mesh as ArrayMesh).surface_get_arrays(si)
			if arr.size() <= Mesh.ARRAY_VERTEX or arr[Mesh.ARRAY_VERTEX] == null:
				continue
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var step := maxi(1, verts.size() / 4000)
			var i := 0
			while i < verts.size():
				var w := xf * verts[i]
				samples.append(w.y)
				lo = minf(lo, w.y)
				hi = maxf(hi, w.y)
				i += step

	if samples.is_empty():
		print("[yh] 没有顶点")
		quit(1)
		return

	print("[yh] 采样 %d 个顶点，Y 范围 %.2f ~ %.2f（跨度 %.2f m）" % [
		samples.size(), lo, hi, hi - lo])

	const BUCKETS := 40
	var counts := PackedInt32Array()
	counts.resize(BUCKETS)
	var span := maxf(hi - lo, 1e-6)
	for y in samples:
		var b := clampi(int((y - lo) / span * BUCKETS), 0, BUCKETS - 1)
		counts[b] += 1

	var peak := 0
	for c in counts:
		peak = maxi(peak, c)
	print("[yh]")
	print("[yh] Y 区间           顶点数   占比   直方图")
	for b in BUCKETS:
		var y0 := lo + span * b / BUCKETS
		var y1 := lo + span * (b + 1) / BUCKETS
		var c := counts[b]
		var pct := 100.0 * c / samples.size()
		var bar := "#".repeat(int(60.0 * c / maxi(peak, 1)))
		if c > 0:
			print("[yh] %7.2f~%7.2f  %7d  %5.1f%%  %s" % [y0, y1, c, pct, bar])

	# 累计 80% 质量所在区间 —— 这才是「人真正会待的高度」
	var acc := 0
	var y80lo := lo
	var y80hi := hi
	var found_lo := false
	for b in BUCKETS:
		acc += counts[b]
		if not found_lo and acc >= samples.size() * 0.1:
			y80lo = lo + span * b / BUCKETS
			found_lo = true
		if acc >= samples.size() * 0.9:
			y80hi = lo + span * (b + 1) / BUCKETS
			break
	print("[yh]")
	print("[yh] 80%% 顶点集中在 Y %.2f ~ %.2f（厚 %.2f m）⇒ 人站的高度大概在这段" % [
		y80lo, y80hi, y80hi - y80lo])
	quit(0)


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
