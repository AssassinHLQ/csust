extends SceneTree
## 量电竞房双层床下铺睡龛：床垫面 / 上铺板底 / 净高（顶点聚类，世界坐标）。
## 床格范围取烘焙盒 P0329（上铺板） footprint：x 53.90~54.66 / z 10.17~11.40。
##   _tools/run_probe.sh res://scripts/_probe_esports_bed_niche.gd

const LEVEL := "res://scenes/game.tscn"
const CELL := AABB(Vector3(53.85, 0.4, 10.15), Vector3(0.85, 2.2, 1.30))


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var level := (load(LEVEL) as PackedScene).instantiate() as Node3D
	root.add_child(level)
	for i in 20:
		await process_frame
	var room := level.get_node_or_null("EsportsRoom") as Node3D
	room.visible = true
	for i in 10:
		await process_frame
	var glb := room.get_node_or_null("Room")
	var bins := {}
	for mi in glb.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m == null or m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var vs := (m.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]) as PackedVector3Array
			for v in vs:
				var w: Vector3 = m.global_transform * v
				if not CELL.has_point(w):
					continue
				var k := snappedf(w.y, 0.002)
				if not bins.has(k):
					bins[k] = {"n": 0, "x0": INF, "x1": -INF, "z0": INF, "z1": -INF}
				var b: Dictionary = bins[k]
				b["n"] = int(b["n"]) + 1
				b["x0"] = minf(float(b["x0"]), w.x)
				b["x1"] = maxf(float(b["x1"]), w.x)
				b["z0"] = minf(float(b["z0"]), w.z)
				b["z1"] = maxf(float(b["z1"]), w.z)
	var planes: Array = []
	for k in bins:
		var b: Dictionary = bins[k]
		if int(b["n"]) >= 4 and float(b["x1"]) - float(b["x0"]) > 0.25 \
				and float(b["z1"]) - float(b["z0"]) > 0.25:
			planes.append([float(k), int(b["n"]), float(b["x0"]), float(b["x1"]),
				float(b["z0"]), float(b["z1"])])
	planes.sort()
	for p in planes:
		print("PLANE y=%.3f n=%d x %.3f~%.3f z %.3f~%.3f" % p)
	quit(0)