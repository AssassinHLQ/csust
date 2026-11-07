extends SceneTree
## 判门：不靠射线（模型没有碰撞体，射线全穿过去），改用**几何统计**。
##   _tools/run_probe.sh res://scripts/_probe_esports_door.gd -- --splat=off --story=off
##
## 思路：房间是个长 16.84（沿 Z）的盒子，两头 ±Z 是短墙、长边 ±X 是长墙。
## 门洞那一头，近距离（贴墙 0.4 m 厚的切片里）的**墙面网格面积**明显比另一头小，
## 因为整块墙被掏空了。所以：分别统计 z ∈ [minZ, minZ+0.4] 和 [maxZ-0.4, maxZ] 里
## 所有三角形面积 + 顶点数，多的那头是实墙、少的那头是门。
##
## 顺带：也统计 ±X 两侧，确认长墙上没有门洞（使用者给的图里门都在短墙上）。

const GLB := "res://models/esports_room/esports_room.glb"
const SLICE := 1.20


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _run() -> void:
	var room := (load(GLB) as PackedScene).instantiate() as Node3D
	root.add_child(room)
	var meshes := room.find_children("*", "MeshInstance3D", true, false)

	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var a: AABB = mi.global_transform * mi.mesh.get_aabb()
		lo = Vector3(minf(lo.x, a.position.x), minf(lo.y, a.position.y), minf(lo.z, a.position.z))
		hi = Vector3(maxf(hi.x, a.position.x + a.size.x),
			maxf(hi.y, a.position.y + a.size.y), maxf(hi.z, a.position.z + a.size.z))
	print("[door] 包围盒 x[%.2f, %.2f] y[%.2f, %.2f] z[%.2f, %.2f]" % [
		lo.x, hi.x, lo.y, hi.y, lo.z, hi.z])

	# 六个区域：-Z / +Z / -X / +X 各一片贴墙切片
	var zones := {
		"-Z": [lo.z, lo.z + SLICE, "z"],
		"+Z": [hi.z - SLICE, hi.z, "z"],
		"-X": [lo.x, lo.x + SLICE, "x"],
		"+X": [hi.x - SLICE, hi.x, "x"],
	}
	var area := {}
	var verts := {}
	for k in zones.keys():
		area[k] = 0.0
		verts[k] = 0
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := mi.global_transform
		for s in range(mi.mesh.get_surface_count()):
			var arr := mi.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var tri_n := idx.size() / 3
			for t in tri_n:
				var p0 := xf * vs[idx[t * 3]]
				var p1 := xf * vs[idx[t * 3 + 1]]
				var p2 := xf * vs[idx[t * 3 + 2]]
				var c := (p0 + p1 + p2) / 3.0
				var cr := (p1 - p0).cross(p2 - p0)
				var tri_area := cr.length() * 0.5
				# 只数**竖向**三角形（法线 y 分量小）：墙和门框；地板/天花板不算
				if absf(cr.normalized().y) > 0.5:
					continue
				for k in zones.keys():
					var z: Array = zones[k]
					var v: float = c.x if z[2] == "x" else c.z
					if v >= z[0] and v <= z[1]:
						area[k] += tri_area
						verts[k] += 3
						break
	for k in ["-Z", "+Z", "-X", "+X"]:
		print("[door] %s 切片：面积 %8.1f m²，顶点 %7d" % [k, area[k], verts[k]])
	quit(0)
