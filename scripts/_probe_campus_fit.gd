extends SceneTree
## 拟合校园点云的**地面平面**，反解出节点该用的 `Transform3D`。
##
## 为什么必须压平：`CampusFloor` 是一块**平的**碰撞板（y −0.52~−0.02）。
## 可见校园只要有残余倾角，就会一头埋进地里、另一头浮在空中 ——
## 用户看到的就是「走着走着碰撞不见了」（其实是他走在板子下面 / 上面）。
##
## 做法：
##   ① 按 8 m 网格取每格**第 5 百分位**的 y 当「地面」（树冠是宽尾巴，取高分会歪）
##   ② 最小二乘拟合 y = a·x + b·z + c
##   ③ 求把法线转回 +Y 的旋转 Rc，再算竖向平移 dy，让地面落在 −0.02
##   ④ 直接打印能粘进 `next_level.tscn` 的 `Transform3D(...)` 字面量
##
##   _tools/run_shot.sh res://scripts/_probe_campus_fit.gd -- --no-capture

const OffWin := preload("res://scripts/offscreen_window.gd")
const CELL := 8.0
const MIN_PTS := 120


func _initialize() -> void:
	if not OS.get_cmdline_user_args().has("--no-capture"):
		push_error("[fit] 缺 --no-capture")
		quit(2)
		return
	_run.call_deferred()


func _run() -> void:
	await OffWin.apply(self, Vector2i(960, 540))
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	await process_frame

	var campus: Node3D = level.get_node_or_null("Campus")
	campus.set("start_delay", 0.0)
	campus.set("low_priority", false)
	campus.call("force_start")
	var t0 := Time.get_ticks_msec()
	while not bool(campus.call("is_ready")) and Time.get_ticks_msec() - t0 < 240000:
		await process_frame
	print("[fit] 就绪 %d ms" % (Time.get_ticks_msec() - t0))

	var node: Node3D = campus.get("splat_node")
	var g = node.get("gaussian")
	var xyz: PackedVector3Array = g.get("xyz")
	var xf: Transform3D = node.global_transform
	print("[fit] 当前 world origin=%s 缩放=%.3f 角度=%s"
		% [str(xf.origin), xf.basis.get_scale().x, str(xf.basis.get_euler() * 180.0 / PI)])
	print("[fit] 节点 global origin=%s" % str(campus.global_transform.origin))

	# ① 分格取 5% 分位
	var stride := int(maxf(1.0, floor(float(xyz.size()) / 400000.0)))
	var cells := {}
	var i := 0
	while i < xyz.size():
		var w: Vector3 = xf * xyz[i]
		i += stride
		var key := Vector2i(int(floor(w.x / CELL)), int(floor(w.z / CELL)))
		if not cells.has(key):
			cells[key] = []
		(cells[key] as Array).append(w.y)
	print("[fit] 采样步长 %d，格子 %d 个" % [stride, cells.size()])

	var xs: Array[float] = []
	var zs: Array[float] = []
	var ys: Array[float] = []
	for key in cells:
		var arr: Array = cells[key]
		if arr.size() < MIN_PTS:
			continue
		arr.sort()
		xs.append((float(key.x) + 0.5) * CELL)
		zs.append((float(key.y) + 0.5) * CELL)
		ys.append(float(arr[int(float(arr.size()) * 0.05)]))
	var n := xs.size()
	print("[fit] 有效格 %d 个（每格 ≥%d 点）" % [n, MIN_PTS])
	if n < 8:
		push_error("[fit] 有效格太少，没法拟合")
		quit(1)
		return

	# ② 最小二乘 y = a·x + b·z + c
	var sx := 0.0
	var sz := 0.0
	var sy := 0.0
	var sxx := 0.0
	var szz := 0.0
	var sxz := 0.0
	var sxy := 0.0
	var szy := 0.0
	for k in n:
		var x := xs[k]
		var z := zs[k]
		var y := ys[k]
		sx += x
		sz += z
		sy += y
		sxx += x * x
		szz += z * z
		sxz += x * z
		sxy += x * y
		szy += z * y
	# 正规方程（3×3）
	var m := [
		[sxx, sxz, sx],
		[sxz, szz, sz],
		[sx, sz, float(n)],
	]
	var rhs := [sxy, szy, sy]
	var sol := _solve3(m, rhs)
	if sol.is_empty():
		push_error("[fit] 正规方程奇异")
		quit(1)
		return
	var a: float = sol[0]     # dy/dx
	var b: float = sol[1]     # dy/dz
	var c: float = sol[2]
	print("[fit] 拟合 y = %.5f·x + %.5f·z + %.3f" % [a, b, c])
	print("[fit] ⇒ 倾角 绕Z %.3f°、绕X %.3f°（要消掉的就是这两个）"
		% [rad_to_deg(atan(a)), rad_to_deg(-atan(b))])

	# ③ 把法线转回 +Y 的旋转
	var nrm := Vector3(-a, 1.0, -b).normalized()
	var rc := Basis()
	if nrm.dot(Vector3.UP) < 0.999999:
		var axis := nrm.cross(Vector3.UP)
		if axis.length_squared() > 1e-12:
			rc = Basis(axis.normalized(), nrm.angle_to(Vector3.UP))
	print("[fit] Rc 欧拉 = %s" % str(rc.get_euler() * 180.0 / PI))

	# ④ 算新变换：绕节点自身 origin 旋转，再竖向平移让地面落到 −0.02
	var p: Vector3 = campus.global_transform.origin
	var b_old: Basis = node.global_transform.basis
	var o_old: Vector3 = node.global_transform.origin
	var b_new: Basis = rc * b_old
	# world' = Rc*(world − P) + P + dy·Y
	var o_new: Vector3 = rc * (o_old - p) + p
	# 用地面格点估旋转后的地面高度（中位）
	var gy: Array[float] = []
	for k in n:
		var w := Vector3(xs[k], ys[k], zs[k])
		gy.append((rc * (w - p) + p).y)
	gy.sort()
	var g_med: float = gy[int(float(gy.size()) * 0.5)]
	var dy: float = -0.02 - g_med
	o_new.y += dy
	print("[fit] 旋转后地面中位 y=%.3f ⇒ 竖向平移 dy=%.3f" % [g_med, dy])

	# 参考：整体 y 的分布（压平前后）
	var resid: Array[float] = []
	for k in n:
		resid.append(ys[k] - (a * xs[k] + b * zs[k] + c))
	resid.sort()
	print("[fit] 拟合残差 5%%/50%%/95%% = %.2f / %.2f / %.2f m"
		% [resid[int(float(resid.size()) * 0.05)], resid[int(float(resid.size()) * 0.5)],
		resid[int(float(resid.size()) * 0.95)]])

	var e: Vector3 = b_new.get_euler() * 180.0 / PI
	print("[fit] === 粘进 scenes/next_level.tscn（Campus 节点）===")
	print("[fit] transform = Transform3D(%.6f, %.6f, %.6f, %.6f, %.6f, %.6f, %.6f, %.6f, %.6f, %.4f, %.4f, %.4f)"
		% [b_new.x.x, b_new.x.y, b_new.x.z, b_new.y.x, b_new.y.y, b_new.y.z,
		b_new.z.x, b_new.z.y, b_new.z.z, o_new.x, o_new.y, o_new.z])
	print("[fit] （新欧拉 %s）" % str(e))
	print("[fit] 完")
	quit(0)


## 3×3 线性方程：高斯消元（带主元）
func _solve3(mm: Array, rr: Array) -> Array:
	var a := []
	for r in 3:
		a.append([mm[r][0], mm[r][1], mm[r][2], rr[r]])
	for col in 3:
		var piv := col
		for r in range(col + 1, 3):
			if absf(a[r][col]) > absf(a[piv][col]):
				piv = r
		if absf(a[piv][col]) < 1e-12:
			return []
		var tmp = a[col]
		a[col] = a[piv]
		a[piv] = tmp
		for r in range(col + 1, 3):
			var f: float = a[r][col] / a[col][col]
			for k in range(col, 4):
				a[r][k] -= f * a[col][k]
	var out := [0.0, 0.0, 0.0]
	for r in range(2, -1, -1):
		var s: float = a[r][3]
		for k in range(r + 1, 3):
			s -= a[r][k] * out[k]
		out[r] = s / a[r][r]
	return out
