extends SceneTree
## 验：电竞房是不是**上下反了**（天花板和地板对调）。
##   _tools/run_probe.sh res://scripts/_probe_esports_flip.gd -- --splat=off --story=off
##
## 判据：把模型按 0.6 m 一层切成水平切片，统计每层的
##   · 面法线朝 **+Y**（地板朝上的面）的面积
##   · 面法线朝 **-Y**（天花板朝下的面）的面积
## 正常房间：朝上的面集中在 y≈0（地板），朝下的面集中在 y≈3.4（天花板）。
## 如果反了：会看到 y≈0 处集中大量「朝下」的面、y≈3.4 处集中「朝上」的面。
##
## 同时打印：最低/最高的网格是什么、它们在 y 上的分布 —— 落地演出家在哪一层。

const GLB := "res://models/esports_room/esports_room.glb"
const BIN := 0.30


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _run() -> void:
	var room := (load(GLB) as PackedScene).instantiate() as Node3D
	root.add_child(room)
	var meshes := room.find_children("*", "MeshInstance3D", true, false)

	var lo := 1e9
	var hi := -1e9
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var a: AABB = mi.global_transform * mi.mesh.get_aabb()
		lo = minf(lo, a.position.y)
		hi = maxf(hi, a.position.y + a.size.y)
	print("[flip] y 范围 [%.2f, %.2f]" % [lo, hi])
	var nb := int(ceil((hi - lo) / BIN))
	var up := PackedFloat64Array()
	var down := PackedFloat64Array()
	var side := PackedFloat64Array()
	up.resize(nb); down.resize(nb); side.resize(nb)

	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := mi.global_transform
		for s in range(mi.mesh.get_surface_count()):
			var arr := mi.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var n := idx.size() / 3
			for t in n:
				var p0 := xf * vs[idx[t * 3]]
				var p1 := xf * vs[idx[t * 3 + 1]]
				var p2 := xf * vs[idx[t * 3 + 2]]
				var cr := (p1 - p0).cross(p2 - p0)
				var area := cr.length() * 0.5
				if area <= 0.0:
					continue
				var ny := cr.normalized().y
				var cy := (p0.y + p1.y + p2.y) / 3.0
				var b := clampi(int((cy - lo) / BIN), 0, nb - 1)
				if absf(ny) < 0.5:
					side[b] += area
				elif ny > 0.0:
					up[b] += area
				else:
					down[b] += area

	print("[flip] 层(y)      朝上面积   朝下面积   竖直面积")
	for b in nb:
		var y0 := lo + b * BIN
		print("[flip]  %5.2f  %9.1f  %9.1f  %9.1f" % [y0, up[b], down[b], side[b]])

	# 结论：最低那一层里"朝下"和"朝上"谁大
	var low_up := up[0] + (up[1] if nb > 1 else 0.0)
	var low_down := down[0] + (down[1] if nb > 1 else 0.0)
	var top_up := up[nb - 1] + (up[nb - 2] if nb > 1 else 0.0)
	var top_down := down[nb - 1] + (down[nb - 2] if nb > 1 else 0.0)
	print("[flip] 底部两层：朝上 %.0f / 朝下 %.0f" % [low_up, low_down])
	print("[flip] 顶部两层：朝上 %.0f / 朝下 %.0f" % [top_up, top_down])
	if low_down > low_up * 1.5 and top_up > top_down * 1.5:
		print("[flip] 结论：上下反了 —— 底部是朝下的面（本该是天花板），顶部是朝上的面")
	elif low_up > low_down and top_down > top_up * 0.5:
		print("[flip] 结论：正常 —— 底部朝上（地板）、顶部朝下（天花板）")
	else:
		print("[flip] 结论：不明显，看上面的逐层数据")
	quit(0)
