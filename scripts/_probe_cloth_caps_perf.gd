extends SceneTree
## 实测 Godot 4.7 的 `SoftBody3D` 能不能拿来当布（窗帘 / 被面），以及**代价**。
##
## 为什么不用 `Cloth`：Godot 3 有个 `Cloth` 节点，**4.x 删掉了**，4.x 只剩 `SoftBody3D`。
## 所以「能不能做布料模拟」实际上是问「SoftBody3D 顶不顶得住」。
##
## ⚠️ 两处**踩过的坑**（第一版探针就栽在这，别重犯）：
##   1. `PlaneMesh` 是**水平**面（躺在 XZ 上，所有顶点 y=0）。按「y 最大的那一排」去钉
##      边，会把整块布全钉死 —— 第一版打印出来「钉住 196 / 196」，布一动不动。
##      正确做法：沿 **z** 找边界那一排（相当于布从这根杆上挂下来）。
##   2. headless 的物理时钟是 60 Hz，`await physics_frame` 一轮就是 16.67 ms，
##      **真实开销被墙钟盖住**（第一版三档全是 16.6 ms，看不出差别）。
##      正确做法：把 `physics_ticks_per_second` 拉高、`Engine.max_fps = 0`，
##      让物理成为瓶颈，这时每帧耗时才是软体自己的代价。
##
## 用法：_tools/run_probe.sh res://scripts/_probe_cloth_caps_perf.gd
## ⚠️ headless 里 `RenderingServer` 是空壳，所以这里只验**物理**；影像侧代价要真渲染才算数。

const SETTLE := 10
const SAMPLE := 200
const TICK_HZ := 600


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	# 让物理而不是墙钟成为瓶颈（否则每帧固定 16.67 ms，什么都测不出来）
	Engine.max_fps = 0
	Engine.physics_ticks_per_second = TICK_HZ
	print("[cloth] Godot %s" % Engine.get_version_info()["string"])
	print("[cloth] Cloth 节点：%s（Godot 3 的节点，4.x 已删）"
		% ("有" if ClassDB.class_exists("Cloth") else "没有"))
	print("[cloth] 计时条件：max_fps=0、physics_ticks_per_second=%d、样本 %d 帧"
		% [TICK_HZ, SAMPLE])

	var base_ms := await _time_frames(SAMPLE)
	print("[cloth] 空场景基线：%.4f ms / 物理帧" % base_ms)

	for n in [12, 24, 48]:
		var sb := SoftBody3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(2.0, 2.0)
		pm.subdivide_width = n
		pm.subdivide_depth = n
		sb.mesh = pm
		sb.total_mass = 1.0
		# 压力系数给 0 才是「布」，不然是「气球」
		sb.pressure_coefficient = 0.0
		sb.linear_stiffness = 0.5
		sb.damping_coefficient = 0.05
		sb.simulation_precision = 5
		root.add_child(sb)

		var verts: PackedVector3Array = pm.get_mesh_arrays()[Mesh.ARRAY_VERTEX]
		var count := verts.size()
		# 沿着 z 找最边上那一排钉住（布从这根杆挂下来）
		var max_z := -INF
		for v in verts:
			max_z = maxf(max_z, v.z)
		var pinned := 0
		for i in count:
			if verts[i].z >= max_z - 0.001:
				sb.set_point_pinned(i, true)
				pinned += 1

		for _i in SETTLE:
			await physics_frame
		var low_before := _lowest_point(sb, count)

		var t0 := Time.get_ticks_usec()
		for _i in SAMPLE:
			await physics_frame
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / float(SAMPLE)

		var low_after := _lowest_point(sb, count)
		print("[cloth] %2d×%2d：顶点 %5d、钉住 %3d → %.4f ms/物理帧（比基线 +%.4f）；"
			% [n, n, count, pinned, ms, ms - base_ms]
			+ "最低点 y %.3f → %.3f（下垂 %.3f m）"
			% [low_before, low_after, low_before - low_after])

		sb.queue_free()
		for _i in 5:
			await physics_frame

	quit()


func _lowest_point(sb: SoftBody3D, count: int) -> float:
	var lo := INF
	for i in count:
		# ⚠️ `get_point_transform()` 返回的是 **Vector3**（点的位置），不是 Transform3D
		var p: Vector3 = sb.get_point_transform(i)
		lo = minf(lo, p.y)
	return lo


func _time_frames(frames: int) -> float:
	var t0 := Time.get_ticks_usec()
	for _i in frames:
		await physics_frame
	return float(Time.get_ticks_usec() - t0) / 1000.0 / float(frames)
