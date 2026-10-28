extends SceneTree
## 量：长沙理工校园泼溅的地面到底平不平（这份航拍扫描是不是整体带倾角）。
##   _tools/run_probe.sh res://scripts/_probe_campus_plane.gd
## 做法：把内容盒按 x/z 切成 8×8 格，每格取 y 的 5% 分位当「地面」，
## 再对 64 个地面点做最小二乘拟合平面 y = a·x + b·z + c，看坡度角。
## 输出还有每格的 p05/p50/p95，用来判断树冠/建筑的高度层次。

const STEP := 17

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	var campus := level.get_node_or_null("Campus")
	if campus == null:
		print("[plane] 没有 Campus")
		quit(1)
		return
	campus.call("force_start")
	var t0 := Time.get_ticks_msec()
	while not bool(campus.call("is_ready")) and Time.get_ticks_msec() - t0 < 180000:
		await process_frame
	if not bool(campus.call("is_ready")):
		print("[plane] 加载失败")
		quit(1)
		return
	var node := campus.get("splat_node") as Node3D
	var res = node.get("gaussian")
	var xyz: PackedVector3Array = res.get("xyz")
	var xf := node.global_transform
	var box: AABB = campus.call("content_world_aabb")
	print("[plane] 内容盒 pos %s size %s" % [
		str(box.position.snappedf(0.01)), str(box.size.snappedf(0.01))])

	var nx := 8
	var nz := 8
	var ys: Array = []
	var counts := PackedInt32Array()
	ys.resize(nx * nz)
	counts.resize(nx * nz)
	# Array 是引用类型，能直接 append；Packed 数组是值语义，append 会丢
	for i in nx * nz:
		ys[i] = []
	var i := 0
	var taken := 0
	while i < xyz.size():
		var w: Vector3 = xf * xyz[i]
		var ix := int((w.x - box.position.x) / box.size.x * nx)
		var iz := int((w.z - box.position.z) / box.size.z * nz)
		ix = clampi(ix, 0, nx - 1)
		iz = clampi(iz, 0, nz - 1)
		var k := iz * nx + ix
		(ys[k] as Array).append(w.y)
		counts[k] += 1
		taken += 1
		i += STEP
	print("[plane] 采样 %d / %d 点（每 %d 取 1）" % [taken, xyz.size(), STEP])

	var gx := PackedFloat64Array()
	var gz := PackedFloat64Array()
	var gy := PackedFloat64Array()
	print("[plane] 每格 p05 / p50 / p95（m）：")
	for iz in nz:
		var line := ""
		for ix in nx:
			var k := iz * nx + ix
			var arr: Array = ys[k]
			if arr.size() < 50:
				line += "     --      "
				continue
			arr.sort()
			var p05: float = arr[int(arr.size() * 0.05)]
			var p50: float = arr[int(arr.size() * 0.50)]
			var p95: float = arr[int(arr.size() * 0.95)]
			line += " %5.1f/%5.1f/%5.1f" % [p05, p50, p95]
			var cx := box.position.x + (float(ix) + 0.5) / nx * box.size.x
			var cz := box.position.z + (float(iz) + 0.5) / nz * box.size.z
			gx.append(cx)
			gz.append(cz)
			gy.append(p05)
		print("  z%2d |%s" % [iz, line])

	# 最小二乘拟合 y = a·x + b·z + c
	var n := gx.size()
	if n >= 3:
		var sx := 0.0
		var sz := 0.0
		var sy := 0.0
		var sxx := 0.0
		var szz := 0.0
		var sxz := 0.0
		var sxy := 0.0
		var szy := 0.0
		for j in n:
			sx += gx[j]
			sz += gz[j]
			sy += gy[j]
			sxx += gx[j] * gx[j]
			szz += gz[j] * gz[j]
			sxz += gx[j] * gz[j]
			sxy += gx[j] * gy[j]
			szy += gz[j] * gy[j]
		# 3×3 正规方程用克拉默法则解（GDScript 里 Basis 构造容易写错，直接写行列式）
		var d00 := sxx
		var d01 := sxz
		var d02 := sx
		var d10 := sxz
		var d11 := szz
		var d12 := sz
		var d20 := sx
		var d21 := sz
		var d22 := float(n)
		var det := d00 * (d11 * d22 - d12 * d21) \
			- d01 * (d10 * d22 - d12 * d20) \
			+ d02 * (d10 * d21 - d11 * d20)
		var det_a := sxy * (d11 * d22 - d12 * d21) \
			- d01 * (szy * d22 - d12 * sy) \
			+ d02 * (szy * d21 - d11 * sy)
		var det_b := d00 * (szy * d22 - d12 * sy) \
			- sxy * (d10 * d22 - d12 * d20) \
			+ d02 * (d10 * sy - szy * d20)
		var det_c := d00 * (d11 * sy - szy * d21) \
			- d01 * (d10 * sy - szy * d20) \
			+ sxy * (d10 * d21 - d11 * d20)
		var a := det_a / det
		var b := det_b / det
		var c := det_c / det
		var tilt_x := rad_to_deg(atan(a))
		var tilt_z := rad_to_deg(atan(b))
		print("[plane] 地面拟合 y = %.5f·x + %.5f·z + %.2f" % [a, b, c])
		print("[plane] 近似坡度：绕 Z %.2f°（沿 x）/ 绕 X %.2f°（沿 z）"
			% [tilt_x, tilt_z])
		var res_sum := 0.0
		for j in n:
			var e := gy[j] - (a * gx[j] + b * gz[j] + c)
			res_sum += e * e
		print("[plane] 残差 RMS %.2f m" % sqrt(res_sum / n))
	quit(0)
