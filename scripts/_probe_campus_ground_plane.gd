extends SceneTree
## 判断校园地面是「平的」还是「有起伏的」：从预览点云每 10 m 取最低面，拟合平面 + 二次面。
##   _tools/run_probe.sh res://scripts/_probe_campus_ground_plane.gd
##
## 输出：平面倾角/RMS；二次面（x²、z²、xz）的 RMS 是否明显更小（= 真有坡/山包）。

const LEVEL := "res://scenes/next_level.tscn"
const CELL := 10.0
const LOW := 0.05      # 每格取 5% 分位当「最低面」
const CAP := 8.0       # 只看 y < 8 的点（排除楼顶/树冠）
const MIN_PTS := 20

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var lvl := (load(LEVEL) as PackedScene).instantiate()
	var campus := lvl.get_node("Campus") as Node3D
	var prev := campus.get_node_or_null("CampusPreview")
	var mi: MeshInstance3D = null
	for c in prev.get_children():
		if c is MeshInstance3D:
			mi = c
			break
	var arrays := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	# 预览点是 Campus 局部空间：世界 = Campus.transform * 预览局部
	var ctf: Transform3D = campus.transform
	var xf: Transform3D = ctf * mi.transform
	lvl.free()

	var cells := {}
	for v in verts:
		var p := xf * v
		if p.y > CAP:
			continue
		var k := Vector2i(int(floor(p.x / CELL)), int(floor(p.z / CELL)))
		var arr = cells.get(k)
		if arr == null:
			cells[k] = [p.y]
		else:
			arr.append(p.y)

	var xs: Array[float] = []
	var zs: Array[float] = []
	var ys: Array[float] = []
	for k in cells:
		var arr: Array = cells[k]
		if arr.size() < MIN_PTS:
			continue
		arr.sort()
		xs.append((float(k.x) + 0.5) * CELL)
		zs.append((float(k.y) + 0.5) * CELL)
		ys.append(arr[int(LOW * (arr.size() - 1))])
	var n := xs.size()
	print("[plane] 有效格子 %d" % n)
	if n < 30:
		quit(1)
		return

	# 平面最小二乘
	var sx := 0.0; var sz := 0.0; var sy := 0.0
	var sxx := 0.0; var szz := 0.0; var sxz := 0.0
	var sxy := 0.0; var szy := 0.0
	for i in n:
		sx += xs[i]; sz += zs[i]; sy += ys[i]
		sxx += xs[i] * xs[i]; szz += zs[i] * zs[i]; sxz += xs[i] * zs[i]
		sxy += xs[i] * ys[i]; szy += zs[i] * ys[i]
	var sol := _solve3([[sxx, sxz, sx], [sxz, szz, sz], [sx, sz, float(n)]], [sxy, szy, sy])
	var a: float = sol[0]
	var b: float = sol[1]
	var c: float = sol[2]
	var rms := 0.0
	var res: Array[float] = []
	for i in n:
		var pred := a * xs[i] + b * zs[i] + c
		var e := ys[i] - pred
		res.append(e)
		rms += e * e
	rms = sqrt(rms / n)
	res.sort()
	print("[plane] 平面：y = %.5f·x + %.5f·z + %.3f   倾角 x %.3f°  z %.3f°"
		% [a, b, c, rad_to_deg(atan(a)), rad_to_deg(atan(b))])
	print("[plane] 残差 RMS %.3f m  P5 %+.3f  P95 %+.3f  （越小越平）"
		% [rms, res[int(0.05 * (n - 1))], res[int(0.95 * (n - 1))]])

	# 二次面：y = a x + b z + c + d x² + e z² + f xz
	var m2 := [[0.0, 0.0, 0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
		[0.0, 0.0, 0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
		[0.0, 0.0, 0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]]
	var v2 := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	for i in n:
		var f := [xs[i], zs[i], 1.0, xs[i] * xs[i], zs[i] * zs[i], xs[i] * zs[i]]
		for r in 6:
			v2[r] += f[r] * ys[i]
			for q in 6:
				m2[r][q] += f[r] * f[q]
	var sol2 := _solve6(m2, v2)
	if sol2.size() == 6:
		var rms2 := 0.0
		for i in n:
			var pred: float = sol2[0] * xs[i] + sol2[1] * zs[i] + sol2[2] \
				+ sol2[3] * xs[i] * xs[i] + sol2[4] * zs[i] * zs[i] + sol2[5] * xs[i] * zs[i]
			rms2 += pow(ys[i] - pred, 2.0)
		rms2 = sqrt(rms2 / n)
		print("[plane] 二次面 RMS %.3f m（比平面小 %.0f%% → 起伏是真的）"
			% [rms2, 100.0 * (1.0 - rms2 / maxf(rms, 0.001))])
		var edge_x: float = sol2[3] * 280.0 * 280.0 + sol2[0] * 280.0
		var edge_z: float = sol2[4] * 240.0 * 240.0 + sol2[1] * 240.0
		print("[plane] 二次项：x² %.3e  z² %.3e  xz %.3e；边缘相对中心抬升 %.2f / %.2f m"
			% [sol2[3], sol2[4], sol2[5], edge_x, edge_z])
	quit(0)


func _solve3(m: Array, v: Array) -> Array:
	var det: float = m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) \
		- m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) \
		+ m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0])
	if absf(det) < 1e-9:
		return [0.0, 0.0, 0.0]
	var out: Array = []
	for col in 3:
		var mm: Array = [m[0].duplicate(), m[1].duplicate(), m[2].duplicate()]
		for row in 3:
			mm[row][col] = v[row]
		var d: float = mm[0][0] * (mm[1][1] * mm[2][2] - mm[1][2] * mm[2][1]) \
			- mm[0][1] * (mm[1][0] * mm[2][2] - mm[1][2] * mm[2][0]) \
			+ mm[0][2] * (mm[1][0] * mm[2][1] - mm[1][1] * mm[2][0])
		out.append(d / det)
	return out


## 6x6 高斯消元（列主元）
func _solve6(m: Array, v: Array) -> Array:
	var a: Array = []
	for r in 6:
		a.append((m[r] as Array).duplicate())
		a[r].append(v[r])
	for col in 6:
		var piv := col
		for r in range(col + 1, 6):
			if absf(a[r][col]) > absf(a[piv][col]):
				piv = r
		if absf(a[piv][col]) < 1e-12:
			return []
		if piv != col:
			var t = a[piv]; a[piv] = a[col]; a[col] = t
		var d: float = a[col][col]
		for cc in range(col, 7):
			a[col][cc] = float(a[col][cc]) / d
		for r in range(0, 6):
			if r == col:
				continue
			var f: float = a[r][col]
			if absf(f) < 1e-15:
				continue
			for cc in range(col, 7):
				a[r][cc] = float(a[r][cc]) - f * float(a[col][cc])
	var out: Array = []
	for r in 6:
		out.append(a[r][6])
	return out
