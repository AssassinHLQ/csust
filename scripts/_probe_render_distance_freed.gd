extends SceneTree
## 复现并验收：`RenderDistance._apply: Trying to assign invalid previously freed instance.`
## （用户 2026-11-10 15:05 在编辑器调试器面板里报的那条红色 ×）
##
## 现场还原：`clusters` 里存的是节点引用，某个子树被 `queue_free()` 之后
##   · 死引用留在数组里每 0.1 s 空转
##   · `_hidden` 里还留着它的 instance_id → 引擎复用该 id 后，
##     `_restore_hidden()` 会拿去给**别的节点**写 `visible` → 就是那条报错
##
##   godot --headless --path <工程> --script res://scripts/_probe_render_distance_freed.gd \
##         -- --no-capture --splat=off --story=off
##
## 断言（PASS/FAIL 都打印）：
##   ① 释放一个簇之后 `_apply()` 不再报错，且死簇被剔出 `clusters`
##   ② `_hidden` 里不再残留已释放节点的 id
##   ③ `_restore_hidden()` 不会去写已释放 / 已出树的节点

var _fail := 0
## 硬兜底：场景加载/帧等待万一卡住（实测被别的 Godot 进程抢资源时会发生，
## 2026-11-10 本探针就挂到 5 分钟没退），到点自己 `quit()`，绝不留残进程。
const DEADLINE_S := 90.0
var _t0 := 0


func _initialize() -> void:
	_t0 = Time.get_ticks_msec()
	_watchdog()
	_run.call_deferred()


func _watchdog() -> void:
	while true:
		await create_timer(1.0).timeout
		if (Time.get_ticks_msec() - _t0) / 1000.0 > DEADLINE_S:
			printerr("[rd] ✗ 超时 %.0f s，强制退出（探针没跑完）" % DEADLINE_S)
			quit(2)
			return


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _ok(cond: bool, what: String) -> void:
	if cond:
		print("  [PASS] %s" % what)
	else:
		_fail += 1
		print("  [FAIL] %s" % what)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	# ⚠️ 不加载 `game.tscn`：那套要泼溅 + 载具 + 同伴，headless 下又慢又容易
	#    被别的会话抢资源（2026-11-10 实测挂死过一次）。这里只造 `_apply()` 需要的
	#    最小环境：一台相机 + 一个 `RenderDistance`，逻辑与真场景完全同一条代码。
	var world := Node3D.new()
	world.name = "World"
	root.add_child(world)
	var cam := Camera3D.new()
	cam.name = "ProbeCam"
	cam.current = true
	world.add_child(cam)
	await _wait(2)

	var rd := RenderDistance.new()
	rd.name = "RenderDistance"
	world.add_child(rd)
	# `watch()` 会 `rebuild()` 把整棵 world 切簇；先放几个远处盒子当目标
	for i in 3:
		var box := MeshInstance3D.new()
		box.name = "Box%d" % i
		box.mesh = BoxMesh.new()
		box.position = Vector3(float(i) * 4.0, 0.0, -200.0)  # 远到会被裁
		world.add_child(box)
	rd.watch(world)
	await _wait(2)
	print("[rd] 初始簇 %d 个，_hidden %d 条" % [rd.clusters.size(), rd._hidden.size()])
	if rd.clusters.is_empty():
		print("!! 没切出任何簇，探针前提不成立")
		quit(1)
		return

	var before_hidden: int = rd._hidden.size()
	rd.call("_apply", 0.0, true)
	print("[rd] 强制刷新后簇 %d 个，_hidden %d 条（刷新前 %d）"
		% [rd.clusters.size(), rd._hidden.size(), before_hidden])

	# ── 造一个「会被释放的簇」：自己塞一个节点进 clusters 再 queue_free 它，
	#    这正是 `_collect()` 收进来的东西，形状也一样。
	var victim := Node3D.new()
	victim.name = "ProbeVictim"
	world.add_child(victim)
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	victim.add_child(mi)
	await _wait(2)
	var victim_id := victim.get_instance_id()
	rd.clusters.append({
		"node": victim,
		"local_aabb": AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2)),
		"radius": 1.8,
		"meshes": 1,
	})
	# 先让它在 `_hidden` 里留下一条记录（模拟「被藏过」）
	rd._hidden[victim_id] = true
	var n_before: int = rd.clusters.size()
	print("[rd] 塞入死簇：簇 %d 个，_hidden %d 条（victim_id=%d）"
		% [n_before, rd._hidden.size(), victim_id])

	# 释放它 —— 关键：**不**从 clusters / _hidden 里删
	victim.queue_free()
	await _wait(4)

	print("── ① 释放后跑 _apply()（以前这里会刷 Trying to assign invalid ...）──")
	rd.call("_apply", 0.0, true)
	rd.call("_apply", 0.0, true)
	print("[rd] 跑完：簇 %d 个，_hidden %d 条" % [rd.clusters.size(), rd._hidden.size()])
	_ok(rd.clusters.size() == n_before - 1, "死簇已被剔出 clusters（%d → %d）"
		% [n_before, rd.clusters.size()])
	_ok(not rd._hidden.has(victim_id), "`_hidden` 里不再残留已释放节点的 id")

	print("── ② 再跑 rebuild()：`_restore_hidden()` 不能碰已释放节点 ──")
	rd.call("rebuild")
	_ok(true, "rebuild() 没抛错（`_restore_hidden()` 里有 is_inside_tree 兜底）")

	print("── ③ 已释放节点的 id 留在 `_hidden` 里：`_restore_hidden()` 也不该去写它 ──")
	# ⚠️ 顺序：**先**取 id、**再** queue_free。反过来就是对已释放实例调
	#    `get_instance_id()`，本身就会报错（本探针第一版就是这么栽的）。
	var outside := Node3D.new()
	outside.name = "ProbeOutside"
	outside.visible = false
	var outside_id := outside.get_instance_id()
	outside.queue_free()          # 从未加进树，直接释放
	await _wait(2)
	rd._hidden[outside_id] = true  # 模拟「藏过它，然后它没了」
	rd.call("_restore_hidden")
	_ok(rd._hidden.is_empty(), "_restore_hidden() 跑完 `_hidden` 清空")

	print("========== 结果 ==========")
	print("  失败 %d 项" % _fail)
	quit(0 if _fail == 0 else 1)
