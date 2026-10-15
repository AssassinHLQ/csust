extends SceneTree
## 排序可行性探针：一次跑完决定「怎么治转身延迟」所需的全部数字。
##
## 三个问题：
##   1. 逐高斯计数排序到底多慢？（已知约 812 ms / 278 万点）
##   2. **源数据里相邻的高斯在空间上挨着吗？** 如果挨着（很多导出器会按
##      Morton/Z 序重排点），那就可以只排「每 128 个高斯一组」的组顺序，
##      排序量直接少 128 倍 —— 延迟从 810 ms 掉到 <10 ms，一步到位。
##      判据：相邻两点平均距离 ÷ 随机两点平均距离。远小于 1 = 有局部性。
##   3. 组级排序实测多少 ms？
##
## 用法：
##   godot --headless --path . --script res://scripts/_probe_sort_cost.gd
##   godot --headless --path . --script res://scripts/_probe_sort_cost.gd -- --sog=res://splatdata/room609.sogdata

const Sorter := preload("res://addons/gdgs/runtime/render/raster/raster_sorter.gd")
const SogRuntime := preload("res://scripts/sog_runtime.gd")

const GROUP := 128


func _initialize() -> void:
	var source := "res://splatdata/room609.sogdata"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sog="):
			source = a.substr(6)

	print("=== 排序成本 / 源顺序局部性 ===")
	var xyz := _load_xyz(source)
	if xyz.is_empty():
		print("  合成数据（没给 --sog 或加载失败）")
		xyz = _synth(2787908)
	var n := xyz.size()
	print("  点数 %d，源尺寸 %s" % [n, str(_size_of(xyz).snappedf(0.01))])

	# --- 1. 局部性 ---
	_localism(xyz)

	# --- 2. 逐高斯排序耗时 ---
	var dir := Vector3(0.3, 0.1, 0.95).normalized()
	var order := PackedFloat32Array()
	var t0 := Time.get_ticks_usec()
	Sorter.sort_into(xyz, dir, order, n)
	var t1 := Time.get_ticks_usec()
	Sorter.sort_into(xyz, dir, order, n)
	var t2 := Time.get_ticks_usec()
	print("  逐高斯排序：首跑 %.0f ms，稳态 %.0f ms" % [
		(t1 - t0) / 1000.0, (t2 - t1) / 1000.0])

	# --- 3. 组顺序排序：后端实际走的那条路 ---
	# 建质心是**一次性**的（第一次排序时在工作线程里做），排序是**每次重排**都做。
	print("  组宽   组数      建质心(一次)  排序(每次)   相对逐高斯")
	for g in [128, 32, 16]:
		var t3 := Time.get_ticks_usec()
		var cents := Sorter.block_centroids(xyz, g)
		var t4 := Time.get_ticks_usec()
		var gorder := PackedFloat32Array()
		Sorter.sort_into(cents, dir, gorder, cents.size())
		var t5 := Time.get_ticks_usec()
		Sorter.sort_into(cents, dir, gorder, cents.size())
		var t6 := Time.get_ticks_usec()
		print("  %-6d %-9d %-13.1f %-12.2f %6.0f 倍" % [
			g, cents.size(), (t4 - t3) / 1000.0,
			(t6 - t5) / 1000.0, maxf((t2 - t1), 1.0) / maxf((t6 - t5), 1.0)])
	quit()


## 局部性判据：相邻点平均距离 ÷ 随机点对平均距离。
## 远小于 1 ⇒ 源顺序在空间上连续 ⇒ 组级排序可行。
func _localism(xyz: PackedVector3Array) -> void:
	var n := xyz.size()
	if n < GROUP * 4:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 991
	var samples := mini(60000, n - 1)
	var d_adj := 0.0
	for _s in samples:
		var i := rng.randi_range(0, n - 2)
		d_adj += xyz[i].distance_to(xyz[i + 1])
	d_adj /= float(samples)

	var d_rand := 0.0
	var rsamples := 40000
	for _s in rsamples:
		var a := rng.randi_range(0, n - 1)
		var b := rng.randi_range(0, n - 1)
		d_rand += xyz[a].distance_to(xyz[b])
	d_rand /= float(rsamples)

	# 组内离散度：每组 128 点的质心到成员的平均距离，对比全局随机基线。
	var groups := n / GROUP
	var gsamples := mini(4000, groups)
	var d_spread := 0.0
	for _s in gsamples:
		var g := rng.randi_range(0, groups - 1)
		var lo := g * GROUP
		var acc := Vector3.ZERO
		for i in range(lo, lo + GROUP):
			acc += xyz[i]
		var c := acc / float(GROUP)
		var s := 0.0
		for i in range(lo, lo + GROUP):
			s += c.distance_to(xyz[i])
		d_spread += s / float(GROUP)
	d_spread /= float(gsamples)

	print("  相邻点平均距离   %.6f" % d_adj)
	print("  随机点对平均距离 %.6f" % d_rand)
	print("  相邻/随机 = %.5f  （≪1 才有局部性）" % (d_adj / maxf(d_rand, 1e-9)))
	print("  组内平均离散度   %.6f（对比随机点对 %.6f，比值 %.5f）" % [
		d_spread, d_rand, d_spread / maxf(d_rand, 1e-9)])


func _load_xyz(source: String) -> PackedVector3Array:
	if source == "" or not FileAccess.file_exists(source):
		return PackedVector3Array()
	var t := Time.get_ticks_msec()
	var res: Dictionary = SogRuntime.load_sog(source, {"cache": "auto"})
	if not bool(res.get("ok", false)):
		print("  加载失败：%s" % str(res.get("message", "")))
		return PackedVector3Array()
	var g: Resource = res["resource"]
	print("  加载 %s：%d 点，%.1f s（缓存 %s）" % [
		source.get_file(), int(g.get("point_count")),
		(Time.get_ticks_msec() - t) / 1000.0, str(res.get("from_cache", false))])
	return g.get("xyz")


func _synth(n: int) -> PackedVector3Array:
	var xyz := PackedVector3Array()
	xyz.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260211
	for i in range(n):
		xyz[i] = Vector3(
			rng.randf_range(-8.5, 8.5), rng.randf_range(-1.8, 1.8), rng.randf_range(-8.5, 8.5))
	return xyz


func _size_of(xyz: PackedVector3Array) -> Vector3:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for p in xyz:
		lo = lo.min(p)
		hi = hi.max(p)
	return hi - lo
