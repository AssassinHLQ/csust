extends SceneTree
## 探针：找出「面与面几乎共面且互相重叠」的网格对（z-fighting 的来源）。
##   godot --path . --script res://scripts/_probe_zfight.gd -- --splat=off
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 40:
		await process_frame
	var shop := game.get_node_or_null("Shop") as Node3D
	var list: Array = []
	for mi in shop.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		list.append({"n": m.name, "a": m.global_transform * m.mesh.get_aabb()})
	print("网格 %d 个" % list.size())
	const EPS := 0.002
	var found := 0
	var hits: Array = []
	for i in list.size():
		for j in range(i + 1, list.size()):
			var a: AABB = list[i]["a"]
			var b: AABB = list[j]["a"]
			for axis in 3:
				var a0: float = a.position[axis]
				var a1: float = a0 + a.size[axis]
				var b0: float = b.position[axis]
				var b1: float = b0 + b.size[axis]
				var coplanar := false
				if absf(a1 - b1) < EPS or absf(a0 - b0) < EPS:
					coplanar = true
				elif absf(a1 - b0) < EPS or absf(a0 - b1) < EPS:
					continue    # 贴边对接，不算重叠
				if not coplanar:
					continue
				# 另外两轴的**真实重叠面积**
				var area := 1.0
				for ax in 3:
					if ax == axis:
						continue
					var lo: float = maxf(a.position[ax], b.position[ax])
					var hi: float = minf(a.position[ax] + a.size[ax], b.position[ax] + b.size[ax])
					area *= maxf(hi - lo, 0.0)
				if area > 0.10:
					found += 1
					hits.append({"a": list[i]["n"], "b": list[j]["n"], "axis": axis,
						"area": area, "plane1": a1 if absf(a1 - b1) < EPS else a0,
						"plane2": b1 if absf(a1 - b1) < EPS else b0})
	hits.sort_custom(func(x, y): return float(x["area"]) > float(y["area"]))
	for h in hits.slice(0, 20):
		print("  %-22s ↔ %-22s 轴%d  面积 %.3f m²  平面 %.3f / %.3f" % [
			h["a"], h["b"], h["axis"], h["area"], h["plane1"], h["plane2"]])
	print("共面重叠对 %d 组" % found)
	quit(0)
