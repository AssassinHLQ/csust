extends SceneTree
## headless 校验分块清单：**不需要 GPU、不弹窗口**。
##
##   _tools/run_probe.sh res://scripts/_verify_chunks_manifest.gd
##
## 查四件事：
##   1. 清单里的 bin 路径在 res:// 下真的存在、字节数是 240 的整数倍；
##   2. 每块点数和字节数自洽；
##   3. 按 `campus_ggs._pick_window()` 的规则（玩家所在格 ±1）取窗口，
##      玩家所在格必须在窗口里，且窗口覆盖玩家周围足够大的范围；
##   4. 打印几个机位的窗口，方便和实际画面比对。
##
## ⚠️ headless 下 `campus_ggs` 会直接放弃（没有渲染设备），所以这里**复刻**它的
##    清单解析与选窗逻辑，而不是去实例化它。

const MANIFEST := "res://splatdata/campus_chunks10w/chunks.json"
const OLD := "res://splatdata/campus_chunks10/chunks.json"
const COARSE := "res://campus_ggs_q4.bin"

var _chunks: Array = []


func _initialize() -> void:
	var ok := _run()
	quit(0 if ok else 1)


func _parse_ij(nm: String) -> Dictionary:
	var p := nm.split("_")
	if p.size() != 3:
		return {}
	return {"i": int(p[1]), "j": int(p[2])}


func _pick(pos: Vector3, side: int) -> PackedStringArray:
	var out := PackedStringArray()
	var best := ""
	var best_d := INF
	for c in _chunks:
		var d: Vector3 = (c["center"] as Vector3) - pos
		var dd := d.x * d.x + d.z * d.z
		if dd < best_d:
			best_d = dd
			best = String(c["name"])
	var ij := _parse_ij(best)
	if ij.is_empty():
		return out
	var half := side / 2
	for i in range(int(ij["i"]) - half, int(ij["i"]) + half + 1):
		for j in range(int(ij["j"]) - half, int(ij["j"]) + half + 1):
			var nm := "Chunk_%d_%d" % [i, j]
			for c in _chunks:
				if String(c["name"]) == nm:
					out.append(nm)
					break
	out.sort()
	return out


func _load(path: String) -> bool:
	_chunks.clear()
	if not FileAccess.file_exists(path):
		print("[ck] !! 找不到清单 %s" % path)
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		print("[ck] !! 清单不是字典")
		return false
	var arr: Array = (parsed as Dictionary).get("chunks", [])
	for d in arr:
		var dd: Dictionary = d
		var c: Array = dd.get("center", [0.0, 0.0, 0.0])
		_chunks.append({
			"name": String(dd.get("name", "")),
			"center": Vector3(float(c[0]), float(c[1]), float(c[2])),
			"bin": String(dd.get("bin", "")),
			"bytes": int(dd.get("bytes", 0)),
		})
	return _chunks.size() > 0


func _run() -> bool:
	print("[ck] ══ 新分块（世界坐标）══")
	if not _load(MANIFEST):
		return false

	var missing := 0
	var bad_size := 0
	var total_pts := 0
	var empty := 0
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for c in _chunks:
		var rel := "res://" + String(c["bin"])
		if not FileAccess.file_exists(rel):
			missing += 1
			continue
		var f := FileAccess.open(rel, FileAccess.READ)
		var sz := int(f.get_length())
		f.close()
		if sz != int(c["bytes"]) or sz % 240 != 0:
			bad_size += 1
		if sz == 0:
			empty += 1
		total_pts += sz / 240
		var ct: Vector3 = c["center"]
		lo = Vector3(minf(lo.x, ct.x), minf(lo.y, ct.y), minf(lo.z, ct.z))
		hi = Vector3(maxf(hi.x, ct.x), maxf(hi.y, ct.y), maxf(hi.z, ct.z))

	print("[ck] 块数 %d｜空块 %d｜缺文件 %d｜字节数不符 %d" % [
		_chunks.size(), empty, missing, bad_size])
	print("[ck] 合计 %d 点（全量那份是 6,144,827）" % total_pts)
	print("[ck] 块中心范围 x[%.1f, %.1f] z[%.1f, %.1f]" % [lo.x, hi.x, lo.z, hi.z])

	var ok := missing == 0 and bad_size == 0 and total_pts == 6144827
	if not ok:
		print("[ck] !! 上面有一项不合格")

	# 玩家可能在的位置：广场、东侧、深处、边界
	var spots := [
		{"n": "广场/出生", "p": Vector3(0.0, 1.0, -80.0)},
		{"n": "东侧", "p": Vector3(60.0, 1.0, -150.0)},
		{"n": "深处", "p": Vector3(-40.0, 1.0, -200.0)},
		{"n": "远端", "p": Vector3(0.0, 1.0, -450.0)},
	]
	for s in spots:
		var spot: Dictionary = s
		var pos: Vector3 = spot["p"]
		var win := _pick(pos, 3)
		var own := ""
		var best_d := INF
		for c in _chunks:
			var d: Vector3 = (c["center"] as Vector3) - pos
			var dd := d.x * d.x + d.z * d.z
			if dd < best_d:
				best_d = dd
				own = String(c["name"])
		var has_own := win.has(own)
		# 窗口覆盖范围：按块中心跨度看（x 和 z 各用一个标量，别塞进 Vector3 —— 踩过一次）
		var wx0 := INF
		var wx1 := -INF
		var wz0 := INF
		var wz1 := -INF
		for nm in win:
			for c in _chunks:
				if String(c["name"]) == nm:
					var ct: Vector3 = c["center"]
					wx0 = minf(wx0, ct.x)
					wx1 = maxf(wx1, ct.x)
					wz0 = minf(wz0, ct.z)
					wz1 = maxf(wz1, ct.z)
		print("[ck] %-8s 玩家(%.0f, %.0f) 中心格 %s｜窗口 %d 块｜含本格 %s｜窗口跨度 %.0f×%.0f m" % [
			String(spot["n"]), pos.x, pos.z, own, win.size(), str(has_own),
			wx1 - wx0, wz1 - wz0])
		if not has_own:
			ok = false
			print("[ck]   !! 窗口里没有玩家所在格")

	print("[ck] ══ 老分块（旧尺度，仅供对照）══")
	if _load(OLD):
		var olo := Vector3(INF, INF, INF)
		var ohi := Vector3(-INF, -INF, -INF)
		for c in _chunks:
			var ct2: Vector3 = c["center"]
			olo = Vector3(minf(olo.x, ct2.x), minf(olo.y, ct2.y), minf(olo.z, ct2.z))
			ohi = Vector3(maxf(ohi.x, ct2.x), maxf(ohi.y, ct2.y), maxf(ohi.z, ct2.z))
		print("[ck] 老块中心范围 x[%.1f, %.1f] z[%.1f, %.1f]（应明显比上面小）" % [
			olo.x, ohi.x, olo.z, ohi.z])

	print("[ck] 粗层 bin：%s（%s）" % [
		COARSE, "存在" if FileAccess.file_exists(COARSE) else "**缺**"])
	print("[ck] %s" % ("全部通过" if ok else "**有不合格项**"))
	return ok
