extends SceneTree
## 从三层室内各打一条向下的射线，列出叠在一起的楼板/外壳面（找闪面）。
##   _tools/run_probe.sh res://scripts/_probe_hall_floor_layers.gd -- --splat=off --story=off


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _tri_hit(o: Vector3, d: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var e1 := b - a
	var e2 := c - a
	var p := d.cross(e2)
	var det := e1.dot(p)
	if absf(det) < 1e-9:
		return -1.0
	var inv := 1.0 / det
	var tv := o - a
	var u := tv.dot(p) * inv
	if u < -0.0001 or u > 1.0001:
		return -1.0
	var q := tv.cross(e1)
	var v := d.dot(q) * inv
	if v < -0.0001 or u + v > 1.0001:
		return -1.0
	var t := e2.dot(q) * inv
	return t if t > 0.0001 else -1.0


func _run() -> void:
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	await _wait(60)
	var hall := level.get_node("Hall")
	var mis := hall.find_children("*", "MeshInstance3D", true, false)
	print("[floor] 网格数 ", mis.size())

	for probe in [
		["L1", Vector3(0.0, 3.0, 0.0)],
		["L2", Vector3(-6.0, 7.2, 0.0)],
		["L3", Vector3(0.0, 11.2, 0.0)],
		["L3_goal", Vector3(2.6, 11.0, -3.0)],
	]:
		var nm: String = probe[0]
		var o: Vector3 = probe[1]
		var d := Vector3.DOWN
		var hits: Array[Dictionary] = []
		for node in mis:
			var mi := node as MeshInstance3D
			if mi.mesh == null:
				continue
			var xf := mi.global_transform
			var mesh := mi.mesh
			for s in mesh.get_surface_count():
				var arr := mesh.surface_get_arrays(s)
				var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
				if idx.is_empty():
					continue
				var t := 0
				while t + 2 < idx.size():
					var a := xf * vs[idx[t]]
					var b := xf * vs[idx[t + 1]]
					var c := xf * vs[idx[t + 2]]
					var h := _tri_hit(o, d, a, b, c)
					if h > 0.0:
						hits.append({"y": o.y - h, "node": mi.name})
					t += 3
		hits.sort_custom(func(x, y): return x["y"] > y["y"])
		var prev := INF
		print("[floor] ", nm, " 命中 ", hits.size())
		for h in hits:
			var y: float = h["y"]
			var gap := prev - y
			print("      y=%.4f node=%s%s" % [y, h["node"],
				"  <-- 间距 %.4f" % gap if gap < 0.06 else ""])
			prev = y
	quit(0)
