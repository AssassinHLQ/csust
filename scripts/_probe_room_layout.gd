extends SceneTree
## 探针：把任意 .sog 当成**点云**渲出来（不看高斯椭球，只看结构）。
##
## 为什么需要它：GDGS 的光栅化是视角相关的 —— 俯拍重建的高斯都是扁椭球，
## 从侧面看会被拉成长条拖影，根本看不出房间/校园的结构（第六节 §6.4）。
## 本探针只取每个点的**位置 + SH DC 颜色**，用小方块画出来，于是
## 「这团数据到底是什么形状、哪个方向是上、正面朝哪」一目了然。
##
## 用法：
##   godot --path <工程> --script res://scripts/_probe_room_layout.gd -- \
##         --sog=res://splatdata/room609.sogdata --scale=1 --max=500000
## 输出：…/_arisu_captures/_room/*.png

const SogRuntime := preload("res://scripts/sog_runtime.gd")
const BYTES_PER_SPLAT := 240
const SH_C0 := 0.28209479177387814

var _scale := 1.0
var _max_points := 500000
var _min_opacity := 0.15
var _cube := 0.025
var _source := ""
var _cache := "auto"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sog="):
			_source = a.substr(6)
		elif a.begins_with("--scale="):
			_scale = float(a.substr(8))
		elif a.begins_with("--max="):
			_max_points = int(a.substr(6))
		elif a.begins_with("--opacity="):
			_min_opacity = float(a.substr(10))
		elif a.begins_with("--cube="):
			_cube = float(a.substr(7))
		elif a.begins_with("--cache="):
			_cache = a.substr(8)

	root.size = Vector2i(1280, 720)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.12, 0.17)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.01
	cam.far = 20000.0
	root.add_child(cam)
	cam.make_current()

	var source := _source if _source != "" else SogRuntime.find_source()
	print("[room] source = %s" % source)
	var t0 := Time.get_ticks_msec()
	var loaded: Dictionary = SogRuntime.load_sog(source, {"cache": _cache})
	if not bool(loaded.get("ok", false)):
		push_error("加载失败：%s" % str(loaded.get("message", loaded)))
		quit(1)
		return
	var res: Resource = loaded["resource"]
	var count := int(res.get("point_count"))
	print("[room] 点数 = %d  加载 %.1f s  缓存命中 = %s" % [
		count, (Time.get_ticks_msec() - t0) / 1000.0, str(loaded.get("from_cache", false))])

	var bytes: PackedByteArray = res.get("point_data_byte")
	var stats := _analyze(bytes, count)
	_report(stats)
	_measure(bytes, count, stats)

	var mesh := BoxMesh.new()
	mesh.size = Vector3(_cube, _cube, _cube)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	var picked := _pick(bytes, count, stats)
	var pos: PackedVector3Array = picked["pos"]
	var cols: PackedColorArray = picked["col"]
	mm.instance_count = pos.size()
	print("[room] 画 %d 个点（上限 %d，不透明度 ≥ %.2f）" % [
		pos.size(), _max_points, _min_opacity])
	var s := _scale
	for i in pos.size():
		mm.set_instance_transform(i, Transform3D(Basis(), pos[i] * s))
		mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Points"
	mmi.multimesh = mm
	mmi.material_override = mat
	var bmin: Vector3 = stats["min"] * s
	var bmax: Vector3 = stats["max"] * s
	var pad := (bmax - bmin) * 3.0
	mmi.custom_aabb = AABB(bmin - pad - Vector3.ONE, (bmax - bmin) + pad * 2.0 + Vector3.ONE * 2.0)
	root.add_child(mmi)
	await process_frame
	await process_frame

	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_room")
	DirAccess.make_dir_recursive_absolute(out)

	var c := (bmin + bmax) * 0.5
	var size := bmax - bmin
	var horiz := maxf(size.x, size.z)
	var views := [
		["top", c + Vector3(0.001, horiz * 1.35, 0.0), c, Vector3.UP],
		["front_Z", c + Vector3(0.0, size.y * 0.35, horiz * 1.15), c, Vector3.UP],
		["back_NZ", c + Vector3(0.0, size.y * 0.35, -horiz * 1.15), c, Vector3.UP],
		["right_PX", c + Vector3(horiz * 1.15, size.y * 0.35, 0.0), c, Vector3.UP],
		["left_NX", c + Vector3(-horiz * 1.15, size.y * 0.35, 0.0), c, Vector3.UP],
		["iso_30", c + Vector3(0.7, 0.6, 0.7).normalized() * horiz * 1.5, c, Vector3.UP],
		["iso_top", c + Vector3(0.5, 1.4, 0.5).normalized() * horiz * 1.5, c, Vector3.UP],
		["up_Z", c + Vector3(0.0, 0.0, horiz * 1.4), c, Vector3.RIGHT],
		["up_X", c + Vector3(horiz * 1.4, 0.0, 0.0), c, Vector3.BACK],
	]
	for v in views:
		cam.global_position = v[1]
		cam.look_at(v[2], v[3])
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		img.save_png(out.path_join("%s.png" % v[0]))
		print("  [img] %-10s 相机 %s" % [v[0], str((v[1] as Vector3).snappedf(0.1))])

	print("[room] 输出目录：%s" % out)
	quit(0)


## 抽样统计：分位数包围盒 + 每根轴的直方图（用来看「哪根轴是房间的高度」）
func _analyze(bytes: PackedByteArray, count: int) -> Dictionary:
	var step := maxi(1, count / 200000)
	var xs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	var zs := PackedFloat32Array()
	var i := 0
	while i < count:
		var o := i * BYTES_PER_SPLAT
		xs.append(bytes.decode_float(o))
		ys.append(bytes.decode_float(o + 4))
		zs.append(bytes.decode_float(o + 8))
		i += step
	xs.sort()
	ys.sort()
	zs.sort()
	var n := xs.size()
	var lo := int(n * 0.001)
	var hi := mini(int(n * 0.999), n - 1)
	return {
		"n": n,
		"min": Vector3(xs[lo], ys[lo], zs[lo]),
		"max": Vector3(xs[hi], ys[hi], zs[hi]),
		"xs": xs, "ys": ys, "zs": zs,
		"lo": lo, "hi": hi,
	}


## 量出「房间坐标系」：地面在哪个 y、房间矩形相对世界轴偏转多少度、
## 地板的长宽、墙有多高、以及离群 floaters 有多少。
func _measure(bytes: PackedByteArray, count: int, st: Dictionary) -> void:
	var lo := float(st["lo"])
	var mn: Vector3 = st["min"]
	var mx: Vector3 = st["max"]
	var step := maxi(1, count / 500000)

	# ---- 1. y 直方图（40 桶）找地面：地板是一张平面，在直方图里是尖峰 ----
	var bins := 40
	var hist := PackedInt32Array()
	hist.resize(bins)
	var i := 0
	var y_min := mn.y
	var y_max := mx.y
	var y_span := maxf(y_max - y_min, 1e-6)
	while i < count:
		var y := bytes.decode_float(i * BYTES_PER_SPLAT + 4)
		if y >= y_min and y <= y_max:
			hist[clampi(int((y - y_min) / y_span * bins), 0, bins - 1)] += 1
		i += step
	var peak := 0
	for b in bins:
		if hist[b] > hist[peak]:
			peak = b
	var floor_y := y_min + (float(peak) + 0.5) / bins * y_span
	print("[room] y 直方图峰值桶 %d/%d（桶宽 %.3f）→ 地面 y ≈ %.3f" % [
		peak, bins, y_span / bins, floor_y])
	# 数值化打印，看是「单峰地板」还是「双峰（桌面 + 地板）」
	for b in bins:
		if hist[b] > 0:
			print("[room]   y %+.3f ~ %+.3f : %d %s" % [
				y_min + float(b) / bins * y_span,
				y_min + float(b + 1) / bins * y_span,
				hist[b], "#".repeat(mini(int(float(hist[b]) / maxf(float(hist[peak]), 1.0) * 30.0), 30))])

	# ---- 2. 地面附近的点在 XZ 上的主轴（房间矩形偏转）----
	#
	# ⚠️ 必须先按稳健盒裁掉 floaters：它们位置远（|x| 能到 12 以上）、又在各个高度，
	#    不裁的话「地面带」里会混进远处的离群点，拟合出的地板会变成 25 × 39 m。
	var band := maxf(y_span / bins, 0.05)
	var box_lo := mn - Vector3.ONE * 0.3
	var box_hi := mx + Vector3.ONE * 0.3
	var xs := PackedFloat32Array()
	var zs := PackedFloat32Array()
	var sxx := 0.0
	var sxz := 0.0
	var szz := 0.0
	var mean := Vector2.ZERO
	var wall_top := -INF
	var wall_n := 0
	var far_n := 0
	var far_max_scale := 0.0
	i = 0
	while i < count:
		var o := i * BYTES_PER_SPLAT
		var p := Vector3(
			bytes.decode_float(o), bytes.decode_float(o + 4), bytes.decode_float(o + 8))
		var inside := p.x >= box_lo.x and p.x <= box_hi.x \
			and p.y >= box_lo.y and p.y <= box_hi.y \
			and p.z >= box_lo.z and p.z <= box_hi.z
		if not inside:
			far_n += 1
			far_max_scale = maxf(far_max_scale, cov_scale(bytes, o))
		elif absf(p.y - floor_y) <= band * 0.6:
			xs.append(p.x)
			zs.append(p.z)
			mean += Vector2(p.x, p.z)
		elif p.y > floor_y + band:
			wall_top = maxf(wall_top, p.y)
			wall_n += 1
		i += step
	var n := xs.size()
	if n < 16:
		print("[room] 地面点太少（%d），跳过主轴拟合" % n)
		return
	mean /= float(n)
	for k in n:
		var dx := xs[k] - mean.x
		var dz := zs[k] - mean.y
		sxx += dx * dx
		sxz += dx * dz
		szz += dz * dz
	sxx /= float(n)
	sxz /= float(n)
	szz /= float(n)
	# 2×2 协方差主轴：θ = ½·atan2(2·Sxz, Sxx − Szz)
	var angle := 0.5 * atan2(2.0 * sxz, sxx - szz)
	var dir := Vector2(sin(angle), cos(angle))      # 主轴方向（XZ 平面）
	var side := Vector2(dir.y, -dir.x)              # 与主轴垂直
	var a_lo := INF
	var a_hi := -INF
	var b_lo := INF
	var b_hi := -INF
	for k in n:
		var dx := xs[k] - mean.x
		var dz := zs[k] - mean.y
		var a := dx * dir.x + dz * dir.y
		var b := dx * side.x + dz * side.y
		a_lo = minf(a_lo, a)
		a_hi = maxf(a_hi, a)
		b_lo = minf(b_lo, b)
		b_hi = maxf(b_hi, b)
	var mid := mean + dir * ((a_lo + a_hi) * 0.5) + side * ((b_lo + b_hi) * 0.5)
	print("[room] 地面点 %d 个（±%.2f 带内），主轴偏角 = %.2f°（相对 +Z）" % [
		n, band * 0.6, rad_to_deg(angle)])
	print("[room] 地板：%.2f × %.2f（沿主轴 / 垂直轴）" % [a_hi - a_lo, b_hi - b_lo])
	print("[room] 地板中心（源坐标）= (%.3f, %.3f, %.3f)" % [mid.x, floor_y, mid.y])
	print("[room] 地面之上：点到 y=%.3f（高 %.2f），%d 点" % [
		wall_top, wall_top - floor_y, wall_n])
	print("[room] 离群 floaters：%d / %d 点（抽样 %d 步），最大椭球尺度 ≈ %.2f 源单位" % [
		far_n, count / step, step, far_max_scale])

	_height_map(bytes, count, st, mid, dir, side, floor_y, a_lo, a_hi, b_lo, b_hi)


## 从地板平面正上方看一张「高度图」：每个格子填该格内最高的点（相对地面，
## 每 0.2 源单位算一级，0~9，'.' = 空格子）。
##
## 用途：一眼看出墙在不在（四周一圈高格）、家具多高（中间成片的中等格）、
## 以及**有没有一根孤立的柱子** —— 那就是被扫进去站着的人。
func _height_map(bytes: PackedByteArray, count: int, _st: Dictionary,
		mid: Vector2, dir: Vector2, side: Vector2, floor_y: float,
		a_lo: float, a_hi: float, b_lo: float, b_hi: float) -> void:
	const N := 14
	var cells := PackedFloat32Array()
	cells.resize(N * N)
	var span_a := maxf(a_hi - a_lo, 1e-6)
	var span_b := maxf(b_hi - b_lo, 1e-6)
	var i := 0
	var step := maxi(1, count / 800000)
	var box_lo: Vector3 = _st["min"] - Vector3.ONE * 0.3
	var box_hi: Vector3 = _st["max"] + Vector3.ONE * 0.3
	while i < count:
		var o := i * BYTES_PER_SPLAT
		var p := Vector3(
			bytes.decode_float(o), bytes.decode_float(o + 4), bytes.decode_float(o + 8))
		if p.x >= box_lo.x and p.x <= box_hi.x and p.y >= box_lo.y and p.y <= box_hi.y \
				and p.z >= box_lo.z and p.z <= box_hi.z and p.y > floor_y:
			var dx := p.x - mid.x
			var dz := p.z - mid.y
			var u := (dx * dir.x + dz * dir.y - a_lo) / span_a
			var v := (dx * side.x + dz * side.y - b_lo) / span_b
			var ci := clampi(int(u * N), 0, N - 1)
			var cj := clampi(int(v * N), 0, N - 1)
			var k := cj * N + ci
			cells[k] = maxf(cells[k], p.y - floor_y)
		i += step
	var tallest := 0.0
	var tallest_cell := Vector2i.ZERO
	for cj in N:
		var line := ""
		for ci in N:
			var h := cells[cj * N + ci]
			if h > tallest:
				tallest = h
				tallest_cell = Vector2i(ci, cj)
			line += "." if h <= 0.02 else str(mini(int(h / 0.2), 9))
		print("[room] 高度图 %s" % line)
	print("[room] 最高点 %.2f 源单位（相对地面），在格子 %s（每级 0.2）" % [
		tallest, str(tallest_cell)])


## 从协方差对角线（点数据 [4]、[7]、[9] 三个 float）估椭球尺度
func cov_scale(bytes: PackedByteArray, off: int) -> float:
	var worst := 0.0
	for f in [4, 7, 9]:
		worst = maxf(worst, sqrt(maxf(bytes.decode_float(off + f * 4), 0.0)))
	return worst


func _report(st: Dictionary) -> void:
	var mn: Vector3 = st["min"]
	var mx: Vector3 = st["max"]
	var size := mx - mn
	print("[room] 内容 1‰~99.9‰ = min %s  max %s" % [
		str(mn.snappedf(0.01)), str(mx.snappedf(0.01))])
	print("[room] 内容尺寸 = %s" % str(size.snappedf(0.01)))
	var axes := [["X", st["xs"], mn.x, mx.x], ["Y", st["ys"], mn.y, mx.y], ["Z", st["zs"], mn.z, mx.z]]
	for a in axes:
		var arr: PackedFloat32Array = a[1]
		var lo := float(a[2])
		var hi := float(a[3])
		var puts := PackedInt32Array()
		puts.resize(16)
		var n := st["n"] as int
		for i in n:
			var t := (arr[i] - lo) / maxf(hi - lo, 1e-6)
			var b := clampi(int(t * 16.0), 0, 15)
			puts[b] += 1
		var line := ""
		var peak := 0
		for v in puts:
			peak = maxi(peak, v)
		for v in puts:
			var bars := int(round(float(v) / maxf(float(peak), 1.0) * 24.0))
			line += "%s" % ("█".repeat(bars) if bars > 0 else "·")
			line += " "
		print("[room] %s 分布 %s" % [a[0], line])


## 挑点：丢掉过透明、位置越界的离群 floaters，再等距抽样到 _max_points
func _pick(bytes: PackedByteArray, count: int, st: Dictionary) -> Dictionary:
	var mn: Vector3 = st["min"]
	var mx: Vector3 = st["max"]
	var margin := (mx - mn) * 0.6 + Vector3.ONE * 0.5
	var lo := mn - margin
	var hi := mx + margin
	var step := maxi(1, count / maxi(_max_points, 1))
	var pos := PackedVector3Array()
	var cols := PackedColorArray()
	var i := 0
	var dropped_opacity := 0
	var dropped_far := 0
	while i < count:
		var o := i * BYTES_PER_SPLAT
		var p := Vector3(
			bytes.decode_float(o), bytes.decode_float(o + 4), bytes.decode_float(o + 8))
		var alpha := bytes.decode_float(o + 40)
		if alpha < _min_opacity:
			dropped_opacity += 1
		elif p.x < lo.x or p.x > hi.x or p.y < lo.y or p.y > hi.y or p.z < lo.z or p.z > hi.z:
			dropped_far += 1
		else:
			pos.append(p)
			cols.append(Color(
				clampf(0.5 + SH_C0 * bytes.decode_float(o + 48), 0.0, 1.0),
				clampf(0.5 + SH_C0 * bytes.decode_float(o + 52), 0.0, 1.0),
				clampf(0.5 + SH_C0 * bytes.decode_float(o + 56), 0.0, 1.0)))
		i += step
	print("[room] 抽样步长 %d：丢透明 %d、丢越界 %d、留下 %d" % [
		step, dropped_opacity, dropped_far, pos.size()])
	return {"pos": pos, "col": cols}
