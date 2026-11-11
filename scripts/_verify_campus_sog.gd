extends SceneTree
## 验证：校园分块 SOG 能不能**逐点还原**出旧 `.bin` 的世界坐标。
##
## 背景见 `tools/fit_campus_frame.py` / `tools/make_campus_sog_manifest.py`。
## 本探针只碰 `SogRuntime`，不需要 RenderingDevice，所以 headless 就能跑：
##   & <godot> --headless --path . --script res://scripts/_verify_campus_sog.gd
##
## 查 6 件事：
##   ① 清单能读、97 块 + 粗层都在
##   ② 共享调色板是**必需**的：传了能解、不传必须失败（否则说明块里偷偷带了）
##   ③ 最大那块解码点数与清单一致
##   ④ 变换后每个点反解回去，必须落在**自己那一格**里（变换与网格自洽）
##   ⑤ 全部 97 块解码+变换，全局点数/均值/包围盒 vs 旧 `campus_ggs.bin` 的实测值
##   ⑥ 解码与变换各花多少毫秒（决定要不要落盘缓存）

const SogRuntime := preload("res://scripts/sog_runtime.gd")

const MANIFEST := "res://splatdata/campus_sog/chunks.json"
const BYTES_PER_SPLAT := 240

## `campus_ggs.bin` 的实测统计（_tools/_diag_full_bin_stats.py，2026-11-11）
const REF_COUNT := 6144827
const REF_MEAN := Vector3(-31.4332, 7.1347, -281.6979)
const REF_MIN := Vector3(-324.1546, -47.858, -594.1249)
const REF_MAX := Vector3(384.3565, 78.8267, -45.8818)

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String, detail := "") -> void:
	if ok:
		_pass += 1
		print("  [PASS] %s%s" % [label, ("  " + detail) if detail != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s%s" % [label, ("  " + detail) if detail != "" else ""])


func _v3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## 位置 p_w = A*p + origin；协方差 C_w = A*C*Aᵀ（A 已含 scale，别再乘 scale²）。
## 直接展开成标量运算：逐点建 Basis/Vector3 会分配对象，6 百万点会被拖死。
static func _transform_blob(blob: PackedByteArray, count: int, m: PackedFloat32Array, o: Vector3) -> void:
	var m00 := m[0]; var m01 := m[1]; var m02 := m[2]
	var m10 := m[3]; var m11 := m[4]; var m12 := m[5]
	var m20 := m[6]; var m21 := m[7]; var m22 := m[8]
	for i in count:
		var off := i * BYTES_PER_SPLAT
		var px := blob.decode_float(off)
		var py := blob.decode_float(off + 4)
		var pz := blob.decode_float(off + 8)
		blob.encode_float(off, m00 * px + m01 * py + m02 * pz + o.x)
		blob.encode_float(off + 4, m10 * px + m11 * py + m12 * pz + o.y)
		blob.encode_float(off + 8, m20 * px + m21 * py + m22 * pz + o.z)

		var c00 := blob.decode_float(off + 16)
		var c01 := blob.decode_float(off + 20)
		var c02 := blob.decode_float(off + 24)
		var c11 := blob.decode_float(off + 28)
		var c12 := blob.decode_float(off + 32)
		var c22 := blob.decode_float(off + 36)
		var d00 := m00 * c00 + m01 * c01 + m02 * c02
		var d01 := m00 * c01 + m01 * c11 + m02 * c12
		var d02 := m00 * c02 + m01 * c12 + m02 * c22
		var d10 := m10 * c00 + m11 * c01 + m12 * c02
		var d11 := m10 * c01 + m11 * c11 + m12 * c12
		var d12 := m10 * c02 + m11 * c12 + m12 * c22
		var d20 := m20 * c00 + m21 * c01 + m22 * c02
		var d21 := m20 * c01 + m21 * c11 + m22 * c12
		var d22 := m20 * c02 + m21 * c12 + m22 * c22
		blob.encode_float(off + 16, d00 * m00 + d01 * m01 + d02 * m02)
		blob.encode_float(off + 20, d00 * m10 + d01 * m11 + d02 * m12)
		blob.encode_float(off + 24, d00 * m20 + d01 * m21 + d02 * m22)
		blob.encode_float(off + 28, d10 * m10 + d11 * m11 + d12 * m12)
		blob.encode_float(off + 32, d10 * m20 + d11 * m21 + d12 * m22)
		blob.encode_float(off + 36, d20 * m20 + d21 * m21 + d22 * m22)


func _run() -> void:
	print("========== 校园分块 SOG 还原验证 ==========")

	# ---- ① 清单 ----
	var man_text := FileAccess.get_file_as_string(MANIFEST)
	if man_text.is_empty():
		print("读不到 %s" % MANIFEST)
		quit(1)
		return
	var man: Dictionary = JSON.parse_string(man_text)
	var chunks: Array = man.get("chunks", [])
	var grid: Dictionary = man.get("grid", {})
	var frame: Dictionary = man.get("frame", {})
	print("[1] 清单：%d 块，网格 %s × %s" % [chunks.size(), grid.get("nx"), grid.get("nz")])
	_check(chunks.size() >= 90, "细层块数合理（>=90）", "实际 %d" % chunks.size())
	_check(man.has("coarse"), "粗层条目在")

	var axes: Array = frame.get("axes", [])
	if axes.size() != 3:
		print("frame.axes 不合法")
		quit(1)
		return
	var basis := Basis(_v3(axes[0]), _v3(axes[1]), _v3(axes[2]))
	var origin := _v3(frame.get("origin", [0, 0, 0]))
	var scale := float(frame.get("scale", 1.0))
	print("    变换：scale=%.4f origin=%s" % [scale, str(origin.snappedf(0.001))])

	# ---- ② 共享调色板 ----
	var pal_path := "res://" + String(man.get("centroids", ""))
	var palette := FileAccess.get_file_as_bytes(pal_path)
	_check(palette.size() > 1024 * 1024, "共享调色板读到了",
		"%s  %.2f MB" % [pal_path.get_file(), float(palette.size()) / 1048576.0])

	# 挑点数最多的那块
	var biggest: Dictionary = {}
	for c in chunks:
		if biggest.is_empty() or int(c["points"]) > int(biggest["points"]):
			biggest = c
	var big_path := "res://" + String(biggest["sog"])
	print("[2] 最大块 %s：%d 点" % [biggest["name"], int(biggest["points"])])

	var with_pal := SogRuntime.load_sog(big_path, {
		"cache": "off", "center": Vector3.ZERO, "centroids": palette})
	_check(bool(with_pal.get("ok", false)), "传共享调色板 → 解码成功",
		"count=%s / %d" % [with_pal.get("count"), int(biggest["points"])])
	_check(int(with_pal.get("count", 0)) == int(biggest["points"]), "点数与清单一致")

	var no_pal := SogRuntime.load_sog(big_path, {"cache": "off", "center": Vector3.ZERO})
	_check(not bool(no_pal.get("ok", false)), "不传调色板 → 必须失败（证明块里真没带）",
		String(no_pal.get("message", "")))

	if not bool(with_pal.get("ok", false)):
		print("解码都没过，后面没法验了")
		quit(1)
		return

	# ---- ③ 变换后每个点应当落在自己那一格 ----
	var nx := int(grid["nx"]); var nz := int(grid["nz"])
	var box_min := _v3(grid["box_min"]); var box_max := _v3(grid["box_max"])
	var cell := Vector3((box_max.x - box_min.x) / nx, box_max.y - box_min.y, (box_max.z - box_min.z) / nz)
	var i := int(biggest["i"]); var j := int(biggest["j"])
	var cell_lo := Vector3(box_min.x + i * cell.x, box_min.y, box_min.z + j * cell.z)
	var cell_hi := cell_lo + Vector3(cell.x, cell.y, cell.z)

	var blob: PackedByteArray = with_pal["resource"].get("point_data_byte")
	var count := int(biggest["points"])
	var m := PackedFloat32Array([
		basis.x.x, basis.y.x, basis.z.x,
		basis.x.y, basis.y.y, basis.z.y,
		basis.x.z, basis.y.z, basis.z.z])
	var inv := basis.inverse()
	var outside := 0
	var worst := 0.0
	for k in count:
		var off := k * BYTES_PER_SPLAT
		var p := Vector3(blob.decode_float(off), blob.decode_float(off + 4), blob.decode_float(off + 8))
		var pw := basis * p + origin
		var back := inv * (pw - origin)
		if back.distance_to(p) > 1e-3:
			outside += 1
		var over := Vector3(
			maxf(0.0, maxf(cell_lo.x - back.x, back.x - cell_hi.x)),
			maxf(0.0, maxf(cell_lo.y - back.y, back.y - cell_hi.y)),
			maxf(0.0, maxf(cell_lo.z - back.z, back.z - cell_hi.z)))
		worst = maxf(worst, over.length())
	_check(outside == 0, "A 与其逆自洽（往返误差 < 1 mm）", "异常 %d 点" % outside)
	_check(worst < 0.05, "全部点落在自己那一格里", "越界最大 %.4f m" % worst)

	# ---- ④ 全量解码 + 变换 ----
	print("[3] 全量 97 块：解码 + 变换 …")
	var t_dec := 0
	var t_tr := 0
	var total := 0
	# ⚠️ 必须用 float（Godot 里是双精度）而不是 Vector3 累加：
	#    Vector3 的分量是 float32，把 6 百万个 ~-282 的数累加到 ~-1.7e9 上，
	#    每次加法都被量化到 128 的整数倍，均值会漂几米 —— 那是**测量误差**，
	#    不是数据错。第一版就是这么误报的。
	var sx := 0.0
	var sy := 0.0
	var sz := 0.0
	var mn := Vector3(INF, INF, INF)
	var mx := Vector3(-INF, -INF, -INF)
	for c in chunks:
		var t0 := Time.get_ticks_msec()
		var r: Dictionary = SogRuntime.load_sog("res://" + String(c["sog"]), {
			"cache": "off", "center": Vector3.ZERO, "centroids": palette})
		t_dec += Time.get_ticks_msec() - t0
		if not bool(r.get("ok", false)):
			_check(false, "解码 %s" % String(c["name"]), String(r.get("message", "")))
			continue
		var b: PackedByteArray = r["resource"].get("point_data_byte")
		var n := int(c["points"])
		var t1 := Time.get_ticks_msec()
		_transform_blob(b, n, m, origin)
		t_tr += Time.get_ticks_msec() - t1
		for k in n:
			var off := k * BYTES_PER_SPLAT
			var p := Vector3(b.decode_float(off), b.decode_float(off + 4), b.decode_float(off + 8))
			sx += p.x
			sy += p.y
			sz += p.z
			mn = mn.min(p)
			mx = mx.max(p)
		total += n

	print("    解码 %d ms｜变换 %d ms｜共 %.1f s" % [t_dec, t_tr, float(t_dec + t_tr) / 1000.0])
	_check(total == REF_COUNT, "总点数 %d" % REF_COUNT, "实际 %d" % total)
	if total > 0:
		var mean := Vector3(sx, sy, sz) / float(total)
		print("    均值 %s（参考 %s）" % [str(mean.snappedf(0.001)), str(REF_MEAN)])
		print("    min  %s（参考 %s）" % [str(mn.snappedf(0.001)), str(REF_MIN)])
		print("    max  %s（参考 %s）" % [str(mx.snappedf(0.001)), str(REF_MAX)])
		_check(mean.distance_to(REF_MEAN) < 0.05, "全局均值吻合（< 5 cm）",
			"差 %.4f m" % mean.distance_to(REF_MEAN))
		_check(mn.distance_to(REF_MIN) < 0.05, "全局 min 吻合", "差 %.4f m" % mn.distance_to(REF_MIN))
		_check(mx.distance_to(REF_MAX) < 0.05, "全局 max 吻合", "差 %.4f m" % mx.distance_to(REF_MAX))

	# ---- ⑤ 粗层 ----
	var coarse: Dictionary = man["coarse"]
	var cr: Dictionary = SogRuntime.load_sog("res://" + String(coarse["sog"]), {
		"cache": "off", "center": Vector3.ZERO, "centroids": palette})
	_check(bool(cr.get("ok", false)), "粗层解码成功",
		"count=%s / %d" % [cr.get("count"), int(coarse["points"])])

	print()
	print("========== %d 通过 / %d 失败 ==========" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
