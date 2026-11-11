extends SceneTree
## 验证：`campus_ggs.gd` 的**分块 SOG 运行时路径**（解码 + 变换 + 缓存 + 拼窗口）。
##
## 这条路径不需要渲染设备：`_make_bundle()` 之前的每一步都是纯数据/文件操作，
## 所以 headless 就能真跑。真正要出图的那部分留给后面带窗口的探针。
##
##   & <godot> --headless --path . --script res://scripts/_verify_campus_window.gd
##
## 查 7 件事：
##   ① 清单解析：97 块 / 共享调色板 / 相似变换 scale=75 / 粗层条目
##   ② `_pick_window()` 能在玩家周围选出 3×3
##   ③ 后台线程真把窗口拼出来了，字节数 = 9 块点数合计 × 240
##   ④ 窗口的 min/max 落在旧 `campus_ggs.bin` 的全局盒内（没跑偏、没散架）
##   ⑤ 每块都在 exe 旁边 `_cache/campus_<指纹>/` 里落了 raw 缓存
##   ⑥ 同一窗口第二次拼：**字节完全一致**（sha256）且明显更快（走缓存）
##   ⑦ 粗层能后台解出来并落到缓存

const CampusGGS := preload("res://scripts/campus_ggs.gd")
const CacheDir := preload("res://scripts/cache_dir.gd")

const MANIFEST := "res://splatdata/campus_sog/chunks.json"
const BYTES_PER_SPLAT := 240
## 旧 campus_ggs.bin 的实测包围盒（_tools/_diag_full_bin_stats.py）
const REF_MIN := Vector3(-324.1546, -47.858, -594.1249)
const REF_MAX := Vector3(384.3565, 78.8267, -45.8818)

var _pass := 0
var _fail := 0
var node: Node3D


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String, detail := "") -> void:
	if ok:
		_pass += 1
		print("  [PASS] %s%s" % [label, ("  " + detail) if detail != "" else ""])
	else:
		_fail += 1
		print("  [FAIL] %s%s" % [label, ("  " + detail) if detail != "" else ""])


## 等后台写线程落地（`_write_done` 是 worker 线程写的，用锁读）。
func _wait_write() -> bool:
	var t0 := Time.get_ticks_msec()
	while node._write_thread != null:
		node._write_mutex.lock()
		var done: bool = node._write_done
		node._write_mutex.unlock()
		if done:
			return true
		OS.delay_msec(20)
		if Time.get_ticks_msec() - t0 > 300000:
			return false
	return false


func _box_of(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var n := int(f.get_length() / BYTES_PER_SPLAT)
	# 一次读进来再按偏移解码（逐点 seek 太慢；sequential get_float 又会读到协方差上去）
	var buf := f.get_buffer(n * BYTES_PER_SPLAT)
	f.close()
	var mn := Vector3(INF, INF, INF)
	var mx := Vector3(-INF, -INF, -INF)
	for i in n:
		var off := i * BYTES_PER_SPLAT
		var p := Vector3(buf.decode_float(off), buf.decode_float(off + 4), buf.decode_float(off + 8))
		mn = mn.min(p)
		mx = mx.max(p)
	return {"count": n, "min": mn, "max": mx}


func _run() -> void:
	print("========== campus_ggs 分块 SOG 运行时路径验证 ==========")

	node = CampusGGS.new()
	root.add_child(node)
	# headless 下 `_ready()` 会立刻让路（没有渲染设备），正好只测数据路径
	node.chunks_json = MANIFEST

	# ---- ① 清单 ----
	var ok: bool = node._load_manifest()
	_check(ok, "清单解析成功")
	_check(node._chunk_list.size() >= 90, "分块数量合理（>=90）",
		"实际 %d" % node._chunk_list.size())
	_check(node._palette.size() > 1024 * 1024, "共享调色板已读入",
		"%.2f MB" % (float(node._palette.size()) / 1048576.0))
	_check(absf(node._frame_scale - 75.0) < 0.01, "相似变换 scale≈75",
		"%.4f" % node._frame_scale)
	_check(node._frame_origin.distance_to(Vector3(-30.9941, 7.1741, -281.642)) < 0.01,
		"相似变换 origin 与清单一致", str(node._frame_origin.snappedf(0.001)))
	_check(node._coarse_sog != "" and node._coarse_points == 1536207,
		"粗层条目", "%s / %d 点" % [node._coarse_sog.get_file(), node._coarse_points])
	_check(not node._cache_subdir.is_empty(), "缓存子目录名带清单指纹",
		node._cache_subdir)

	# ---- ② 选窗口 ----
	# 挑**点数最多**的那块当中心：最坏情况才是要量的情况
	var target := Vector3.ZERO
	var target_name := ""
	var densest := 0
	for c in node._chunk_list:
		if int(c["points"]) > densest:
			densest = int(c["points"])
			target = c["center"]
			target_name = String(c["name"])
	var fake := Node3D.new()
	root.add_child(fake)
	fake.global_position = target
	node.player = fake
	var names: PackedStringArray = node._pick_window()
	_check(names.size() == 9, "在最密块 %s 处选出 3×3 窗口" % target_name, ", ".join(names))
	var expect_pts := 0
	for nm in names:
		expect_pts += int(node._chunk_entry(nm)["points"])
	_check(expect_pts > 0, "窗口点数合计 %d（%.0f MB）"
		% [expect_pts, float(expect_pts) * 240.0 / 1048576.0])

	# ---- ③ 第一次拼（走解码 + 变换）----
	# ⚠️ 先把这 9 块的缓存删掉，否则第二次跑这个探针时「第一次」也是缓存命中，
	#    「第二次比第一次快」这条断言就会变成 430ms < 430ms 而误报失败。
	var wiped := 0
	for nm in names:
		var ce: Dictionary = node._chunk_entry(nm)
		var cp: String = node._chunk_cache_path(ce)
		if cp != "" and FileAccess.file_exists(cp):
			DirAccess.remove_absolute(cp)
			wiped += 1
	print("[3] 第一次拼窗口（解码 + 变换）；已清掉 %d 个旧缓存" % wiped)
	var t0 := Time.get_ticks_msec()
	_check(node._start_window_write(names), "后台线程起得来")
	if not _wait_write():
		_check(false, "第一次拼窗口超时")
		quit(1)
		return
	node._poll_window_write()
	var first_ms := Time.get_ticks_msec() - t0
	var path_a: String = node._bin_path
	var size_a := 0
	if FileAccess.file_exists(path_a):
		size_a = int(FileAccess.open(path_a, FileAccess.READ).get_length())
	_check(size_a == expect_pts * BYTES_PER_SPLAT,
		"窗口 bin 字节数 = 点数 × 240", "%d vs %d" % [size_a, expect_pts * BYTES_PER_SPLAT])

	# ---- ④ 包围盒 ----
	var box := _box_of(path_a)
	var mn: Vector3 = box.get("min", Vector3.ZERO)
	var mx: Vector3 = box.get("max", Vector3.ZERO)
	print("    窗口 min %s   max %s" % [str(mn.snappedf(0.1)), str(mx.snappedf(0.1))])
	_check(int(box.get("count", 0)) == expect_pts, "窗口点数与清单一致")
	_check(mn.x >= REF_MIN.x - 0.5 and mn.y >= REF_MIN.y - 0.5 and mn.z >= REF_MIN.z - 0.5,
		"窗口 min 在校园盒内")
	_check(mx.x <= REF_MAX.x + 0.5 and mx.y <= REF_MAX.y + 0.5 and mx.z <= REF_MAX.z + 0.5,
		"窗口 max 在校园盒内")
	_check((mx - mn).length() > 1.0, "包围盒不是退化的", "对角 %.1f m" % (mx - mn).length())

	# ---- ⑤ 缓存 ----
	var missing: PackedStringArray = PackedStringArray()
	for nm in names:
		var e: Dictionary = node._chunk_entry(nm)
		var cp: String = node._chunk_cache_path(e)
		if cp.is_empty() or not FileAccess.file_exists(cp):
			missing.append(nm)
			continue
		if int(FileAccess.open(cp, FileAccess.READ).get_length()) != int(e["points"]) * BYTES_PER_SPLAT:
			missing.append(nm + "(长度不对)")
	_check(missing.is_empty(), "9 块都落了 raw 缓存", "缺：%s" % ", ".join(missing))
	print("    缓存目录 %s" % CacheDir.dir_for(node._cache_subdir))

	# ---- ⑥ 第二次拼：应当字节一致且快得多 ----
	print("[6] 第二次拼同一窗口（应当全程走缓存）…")
	var sha_a := FileAccess.get_sha256(path_a)
	var t1 := Time.get_ticks_msec()
	node._start_window_write(names)
	if not _wait_write():
		_check(false, "第二次拼窗口超时")
		quit(1)
		return
	node._poll_window_write()
	var second_ms := Time.get_ticks_msec() - t1
	var path_b: String = node._bin_path
	var sha_b := FileAccess.get_sha256(path_b)
	_check(path_a != path_b, "两次写到不同 slot（双缓冲没坏）")
	_check(sha_a == sha_b, "两次结果 sha256 完全一致",
		"%s vs %s" % [sha_a.substr(0, 12), sha_b.substr(0, 12)])
	print("    第一次 %d ms（解码+变换+写盘）｜第二次 %d ms（纯缓存读取）" % [first_ms, second_ms])
	_check(second_ms < first_ms, "第二次更快", "%d ms < %d ms" % [second_ms, first_ms])

	# ---- ⑦ 粗层后台准备 ----
	# 同样先删缓存，否则量到的是「纯读盘」，不是真实的首次解码耗时。
	# ⚠️ `_coarse_cache` 只有 `_start_coarse_prep()` 里才会填（headless 下 `_ready`
	#    提前让路），所以这里自己算一遍，别拿空串去比对。
	node._coarse_cache = CacheDir.file_for(node._cache_subdir, "coarse.bin")
	if node._coarse_cache != "" and FileAccess.file_exists(node._coarse_cache):
		DirAccess.remove_absolute(node._coarse_cache)
		print("[7] 已清掉粗层旧缓存")
	print("[7] 粗层后台解码（1,536,207 点）…")
	var t2 := Time.get_ticks_msec()
	node._start_coarse_prep()
	var t2end := Time.get_ticks_msec() + 300000
	while node._coarse_thread != null and Time.get_ticks_msec() < t2end:
		node._poll_coarse_prep()
		if node._coarse_thread == null:
			break
		OS.delay_msec(50)
	var coarse_ms := Time.get_ticks_msec() - t2
	if node._coarse_thread != null:
		_check(false, "粗层解码超时")
	else:
		_check(node._coarse_path != "" and FileAccess.file_exists(node._coarse_path),
			"粗层落到缓存", node._coarse_path.get_file())
		var csz := 0
		if FileAccess.file_exists(node._coarse_path):
			csz = int(FileAccess.open(node._coarse_path, FileAccess.READ).get_length())
		_check(csz == 1536207 * BYTES_PER_SPLAT, "粗层字节数正确",
			"%d（%.0f MB）" % [csz, float(csz) / 1048576.0])
		_check(node._coarse_total == 1536207, "粗层点数写回", str(node._coarse_total))
		print("    粗层耗时 %d ms" % coarse_ms)

	print()
	print("========== %d 通过 / %d 失败 ==========" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
