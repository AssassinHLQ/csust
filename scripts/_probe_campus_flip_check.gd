extends SceneTree
## 判定校园泼溅到底有没有「上下颠倒」——量的是**点云相对地面层的质量分布**。
##
##   godot --path . --headless --script res://scripts/_probe_campus_flip_check.gd -- --flip=on
##   godot --path . --headless --script res://scripts/_probe_campus_flip_check.gd -- --flip=off
##
## 为什么这么判：`use_default_orientation = true` 是
## `GaussianSplatNodeScript.get_model_orientation_correction()`，把模型绕 **Z 转 180°**
## ⇒ (x, y) → (−x, −y)。如果这一下不该有，那么楼和树会**挂在地面层下面**：
## 玩家看到的只有一张地面，往上看什么都没有 —— 用户把这叫「倒过来了」。
##
## 判据（绕开倾斜角点和离群椭球的干扰，只看质量）：
##   ① 用 1 m 直方图找**地面层**（点最多那一格）；
##   ② 数「地面层上方 ≥ +2 m」和「下方 ≤ −2 m」的点各多少；
##   ③ 正常的校园：上方（楼、树）应该远多于下方；颠倒：反过来。
## 另外逐点打印 4 个已知地点的上下分布，便于和人眼观感对照。

const SPOTS := [
	Vector3(-20.0, 0.0, -210.0),
	Vector3(0.0, 0.0, -300.0),
	Vector3(-95.0, 0.0, -96.0),
	Vector3(120.0, 0.0, -450.0),
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var flip := true
	for a in args:
		if a == "--flip=off":
			flip = false
		elif a == "--flip=on":
			flip = true
	print("=== flip=%s ===" % ("on" if flip else "off"))

	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	await process_frame

	var campus: Node3D = level.get_node_or_null("Campus")
	if campus == null:
		print("[FAIL] 没有 Campus")
		quit(1)
		return
	campus.set("use_default_orientation", flip)
	campus.set("start_delay", 0.0)
	campus.set("low_priority", false)
	campus.set("preload_on_gate", false)
	campus.call("force_start")
	var t0 := Time.get_ticks_msec()
	while not bool(campus.call("is_ready")) and Time.get_ticks_msec() - t0 < 240000:
		await process_frame
	print("  就绪 %d ms" % (Time.get_ticks_msec() - t0))

	var node: Node3D = campus.get("splat_node")
	if node == null:
		print("[FAIL] splat_node 是 null")
		quit(1)
		return
	var g = node.get("gaussian")
	if g == null:
		print("[FAIL] 拿不到 gaussian")
		quit(1)
		return
	var xyz: PackedVector3Array = g.get("xyz")
	if xyz.is_empty():
		print("[FAIL] xyz 空")
		quit(1)
		return

	var xf: Transform3D = node.global_transform
	print("  world_scale=%.1f  node.origin=%s  缩放=%.2f"
		% [float(campus.get("world_scale")), str(xf.origin.snappedf(0.01)), xf.basis.get_scale().x])

	var stride := int(maxf(1.0, floor(float(xyz.size()) / 300000.0)))
	var n := 0
	var ymin := INF
	var ymax := -INF
	# 1 m 直方图（先租后细）
	var hist := {}
	var ys := PackedFloat32Array()
	var ws := PackedVector3Array()
	for i in range(0, xyz.size(), stride):
		var w: Vector3 = xf * xyz[i]
		ys.append(w.y)
		ws.append(w)
		ymin = minf(ymin, w.y)
		ymax = maxf(ymax, w.y)
		var bin := int(floor(w.y))
		hist[bin] = int(hist.get(bin, 0)) + 1
		n += 1
	print("  采样 %d 点（步长 %d），y 范围 %.1f ~ %.1f" % [n, stride, ymin, ymax])

	# 地面层 = 点最多的那一格
	var best_bin := 0
	var best_n := -1
	for b in hist.keys():
		var c := int(hist[b])
		if c > best_n:
			best_n = c
			best_bin = int(b)
	var ground := float(best_bin) + 0.5
	print("  地面层（直方图峰值）y ≈ %.2f m，占 %.1f%% 的点" % [ground, 100.0 * best_n / maxf(1.0, n)])

	# 上下质量
	var above := 0
	var below := 0
	var above_big := 0
	var below_big := 0
	for y in ys:
		if y >= ground + 2.0:
			above += 1
			if y >= ground + 6.0:
				above_big += 1
		elif y <= ground - 2.0:
			below += 1
			if y <= ground - 6.0:
				below_big += 1
	print("  地面层 +2 m 以上: %d 点（其中 +6 m 以上 %d）" % [above, above_big])
	print("  地面层 −2 m 以下: %d 点（其中 −6 m 以下 %d）" % [below, below_big])
	var total_sided := maxf(1.0, float(above + below))
	print("  → 上方占 %.1f%%，下方占 %.1f%%" % [100.0 * above / total_sided, 100.0 * below / total_sided])
	if above > below * 2:
		print("  → 判定：**方向正常**（楼和树长在地面之上）")
	elif below > above * 2:
		print("  → 判定：**上下颠倒**（楼和树挂在地面之下）")
	else:
		print("  → 判定：**分不清**（上下差不多，需要看图）")

	# 逐地点：±20 m 内、按地面层算上下
	print("\n  各地点上下分布（水平 20 m 内）：")
	for spot in SPOTS:
		var a := 0
		var b := 0
		var lo := INF
		var hi := -INF
		for i in ws.size():
			var w: Vector3 = ws[i]
			if Vector2(w.x - spot.x, w.z - spot.z).length() > 20.0:
				continue
			if w.y >= ground + 2.0:
				a += 1
			elif w.y <= ground - 2.0:
				b += 1
			lo = minf(lo, w.y)
			hi = maxf(hi, w.y)
		print("    %s：上 %d / 下 %d   局部 y %.1f~%.1f"
			% [str(spot.snappedf(1.0)), a, b, lo, hi])

	quit(0)
