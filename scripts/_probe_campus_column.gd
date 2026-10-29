extends SceneTree
## 在几个坐标上打「竖向点云直方图」，看清地面到底在几米、头顶是不是树冠。
##   _tools/run_probe.sh res://scripts/_probe_campus_column.gd

const VENUE := "res://scenes/campus_venue.tscn"
const LEVEL := "res://scenes/next_level.tscn"
const SPOTS := [
	Vector2(0, -85), Vector2(0, -110), Vector2(0, -160), Vector2(0, -250),
	Vector2(0, -400), Vector2(0, -540), Vector2(40, -240), Vector2(-60, -350),
]
const R := 3.0
const BIN := 0.5

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var lvl := (load(LEVEL) as PackedScene).instantiate()
	var ctf: Transform3D = (lvl.get_node("Campus") as Node3D).transform
	lvl.free()

	var venue := (load(VENUE) as PackedScene).instantiate()
	root.add_child(venue)
	venue.set("world_scale", 75.0)
	venue.set("crop_enabled", true)
	venue.set("crop_margin", 0.5)
	venue.set("crop_max_scale", 0.5)
	venue.call("force_start")
	var t0 := Time.get_ticks_msec()
	while not bool(venue.call("is_ready")) and Time.get_ticks_msec() - t0 < 180000:
		await process_frame
	var node := venue.get("splat_node") as Node3D
	var res = node.get("gaussian")
	var xyz: PackedVector3Array = res.get("xyz")
	var xf: Transform3D = ctf * node.transform

	for s in SPOTS:
		var hist := {}
		var n := 0
		var lowest := INF
		for i in xyz.size():
			var p := xf * xyz[i]
			if absf(p.x - s.x) > R or absf(p.z - s.y) > R:
				continue
			n += 1
			lowest = minf(lowest, p.y)
			var b := int(floor(p.y / BIN))
			hist[b] = int(hist.get(b, 0)) + 1
		var line := ""
		var bins: Array = hist.keys()
		bins.sort()
		for b in bins:
			if b < -3 or b > 22:
				continue
			line += "%s:%d  " % [str(snappedf(float(b) * BIN, 0.1)), int(hist[b])]
		print("[col] (%.0f, %.0f)  点 %d  最低 %.2f" % [s.x, s.y, n, lowest])
		print("      %s" % line)
	quit(0)
