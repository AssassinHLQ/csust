extends SceneTree
## 直接解 chunk_0_0.sogdata：打印前几个点的位置，看它是不是「西南那格」。
func _initialize() -> void:
	_run.call_deferred()

func _unlog(v: float) -> float:
	return (-1.0 if v < 0.0 else 1.0) * (exp(absf(v)) - 1.0)

func _run() -> void:
	var z := ZIPReader.new()
	z.open("res://splatdata/campus_chunks/chunk_0_0.sogdata")
	var meta: Dictionary = JSON.parse_string(z.read_file("meta.json").get_string_from_utf8())
	print("[chunk] count=%d" % int(meta["count"]))
	var mins: Array = meta["means"]["mins"]
	var maxs: Array = meta["means"]["maxs"]
	var ml := Image.new(); ml.load_webp_from_buffer(z.read_file("means_l.webp")); ml.convert(Image.FORMAT_RGB8)
	var mu := Image.new(); mu.load_webp_from_buffer(z.read_file("means_u.webp")); mu.convert(Image.FORMAT_RGB8)
	var a := ml.get_data()
	var b := mu.get_data()
	print("[chunk] 图集 %d×%d，数据 %d 字节" % [ml.get_width(), ml.get_height(), a.size()])
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var count := int(meta["count"])
	for i in count:
		var o := i * 3
		var qx := (int(b[o]) << 8) | int(a[o])
		var qy := (int(b[o + 1]) << 8) | int(a[o + 1])
		var qz := (int(b[o + 2]) << 8) | int(a[o + 2])
		var p := Vector3(
			_unlog(float(mins[0]) + (float(maxs[0]) - float(mins[0])) * float(qx) / 65535.0),
			_unlog(float(mins[1]) + (float(maxs[1]) - float(mins[1])) * float(qy) / 65535.0),
			_unlog(float(mins[2]) + (float(maxs[2]) - float(mins[2])) * float(qz) / 65535.0))
		if i < 3:
			print("  点 %d = %s" % [i, str(p.snappedf(0.01))])
		lo = lo.min(p)
		hi = hi.max(p)
	print("[chunk] 全块范围 %s ~ %s" % [str(lo.snappedf(0.01)), str(hi.snappedf(0.01))])
	quit(0)
