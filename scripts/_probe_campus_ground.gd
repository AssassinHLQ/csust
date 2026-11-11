extends SceneTree
## 量「可见校园的地面」到底在哪个世界高度 —— 用来和碰撞面对齐。
##
## 背景：包围盒能对上，不代表**地面**对上。航拍点云是个曲面薄饼，
## 轴对齐包围盒的 min/max 由倾斜的角点决定，跟「人站的那块地」差好几米。
## 所以这里直接取点云数据，变换到世界空间，只看玩家脚下那一小块的 y 分布。
##
##   _tools/run_shot.sh res://scripts/_probe_campus_ground.gd -- --no-capture
##
## 输出：几个探针点周围 20 m 内点的 y 分位（10%/50%/90%），以及全场的 x 质心
## （顺手验一下碰撞网格有没有被镜像过）。

const OffWin := preload("res://scripts/offscreen_window.gd")

## 和 `_probe_campus_physics.gd` 用同一个点，好直接对比
const SPOTS := [
	Vector3(-20.0, 0.0, -210.0),
	Vector3(0.0, 0.0, -300.0),
	Vector3(-95.0, 0.0, -96.0),
	Vector3(120.0, 0.0, -450.0),
]


func _initialize() -> void:
	if not OS.get_cmdline_user_args().has("--no-capture"):
		push_error("[ground] 缺 --no-capture")
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
	print("[ground] 就绪 %d ms" % (Time.get_ticks_msec() - t0))

	var node: Node3D = campus.get("splat_node")
	var g = node.get("gaussian")
	if g == null:
		push_error("[ground] 拿不到 gaussian")
		quit(1)
		return
	var xyz: PackedVector3Array = g.get("xyz")
	var count := int(g.get("point_count"))
	print("[ground] point_count=%d  xyz.size()=%d" % [count, xyz.size()])
	if xyz.is_empty():
		push_error("[ground] xyz 是空的，这条探针没法用（数据在 point_data_float 里）")
		quit(1)
		return

	# 世界变换 = 节点 global × splat_node.transform
	var xf: Transform3D = node.global_transform
	print("[ground] 世界变换 origin=%s 缩放=%.3f" % [str(xf.origin), xf.basis.get_scale().x])

	# 每 N 个点采一个，够用且快
	var stride := int(maxf(1.0, floor(float(xyz.size()) / 200000.0)))
	print("[ground] 采样步长 %d（约 %d 个点）" % [stride, xyz.size() / stride])

	var cx := 0.0
	var cn := 0
	var buckets: Array = []   # 每个 spot: Array[float]
	for _i in SPOTS.size():
		buckets.append([])
	var lo_all := INF
	var hi_all := -INF
	var _all_y := PackedFloat32Array()

	var i := 0
	while i < xyz.size():
		var w: Vector3 = xf * xyz[i]
		i += stride
		cx += w.x
		cn += 1
		lo_all = minf(lo_all, w.y)
		hi_all = maxf(hi_all, w.y)
		_all_y.append(w.y)
		for si in SPOTS.size():
			var s: Vector3 = SPOTS[si]
			var dx: float = w.x - s.x
			var dz: float = w.z - s.z
			if dx * dx + dz * dz <= 400.0:      # 20 m 半径
				(buckets[si] as Array).append(w.y)

	print("[ground] 全场 y %.2f ~ %.2f；x 质心 %.2f（采样 %d 点）"
		% [lo_all, hi_all, cx / maxf(1.0, float(cn)), cn])

	# ── 全场 y 直方图（1 m 一格）：地面是低端那个**高峰**，
	#    比任何「最小值/百分位」都可靠 —— 树冠和楼顶只是宽尾巴。
	var nbins := int(ceil((hi_all - lo_all) / 1.0)) + 1
	var hist := PackedInt32Array()
	hist.resize(nbins)
	for v in _all_y:
		var bi := int((float(v) - lo_all) / 1.0)
		if bi >= 0 and bi < nbins:
			hist[bi] += 1
	var peak := 0
	for bi in nbins:
		if hist[bi] > hist[peak]:
			peak = bi
	print("[ground] ★ y 直方图峰值在 %.1f m（%d 点，占采样 %.1f%%）"
		% [lo_all + float(peak) + 0.5, hist[peak],
		100.0 * float(hist[peak]) / maxf(1.0, float(_all_y.size()))])
	# 打印峰值附近的分布，方便看清地面有多厚
	var from_b := maxi(0, peak - 6)
	var to_b := mini(nbins - 1, peak + 6)
	var line := ""
	for bi in range(from_b, to_b + 1):
		line += "%.0f:%d " % [lo_all + float(bi) + 0.5, hist[bi]]
	print("[ground] 峰值附近 → %s" % line)
	# 低端 2% 分位（地面下沿）/ 90% 分位（树顶）
	var ys := _all_y.duplicate()
	ys.sort()
	var ny := ys.size()
	if ny > 10:
		print("[ground] 全场分位 y 1%%=%.2f 2%%=%.2f 5%%=%.2f 25%%=%.2f 50%%=%.2f"
			% [float(ys[int(ny * 0.01)]), float(ys[int(ny * 0.02)]), float(ys[int(ny * 0.05)]),
			float(ys[int(ny * 0.25)]), float(ys[int(ny * 0.50)])])

	for si in SPOTS.size():
		var arr: Array = buckets[si]
		if arr.is_empty():
			print("[ground] %s：20 m 内没有点" % str(SPOTS[si]))
			continue
		arr.sort()
		var n := arr.size()
		print("[ground] %s：%d 点  y 10%%=%.2f  50%%=%.2f  90%%=%.2f  min=%.2f max=%.2f"
			% [str(SPOTS[si]), n,
			float(arr[int(n * 0.10)]), float(arr[int(n * 0.50)]),
			float(arr[int(n * 0.90)]), float(arr[0]), float(arr[n - 1])])

	print("[ground] 参考：CampusFloor 顶面 y=-0.02；玩家站那儿")
	print("[ground] 完")
	quit(0)
