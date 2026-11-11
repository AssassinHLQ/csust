extends SceneTree
## 微基准：**每帧搬 N 个静止盒子形状，物理服务器要花多少钱**。
##
## 为什么单独做这个：在大关卡里量不准 —— `next_level.tscn` 自己有上千个碰撞形状，
## `TIME_PHYSICS_PROCESS` 在 0.8~4.2 ms 之间乱跳，开/关 Boss 碰撞的差值被噪声完全淹掉
## （实测三轮回合正负都出现过）。所以这里搭一个**干净的小场景**，
## 只留一个 `StaticBody3D` + N 个 `BoxShape3D`，每帧改它们的 transform
## —— 这正是 `boss.gd::_sync_bone_collisions()` 干的事。
##
## 对照的是用户 2026-11-11 的担心：「ue 里地鸣那个超大巨的碰撞每时每刻都变，卡死带不动」。
## 那个「变」通常是**重新烘焙/重建碰撞体**；这里只是**搬变换**，形状从头到尾不变。
##
##   bash _tools/run_probe.sh res://scripts/_probe_static_shape_cost.gd -- --no-capture

const FRAMES := 900
## 分别测这些形状数：0 = 基准，72 = 第二关三只霸王龙（每只 24 个）。
## 0 和 72 各测两遍（`_a` / `_b`）—— 用来判断差值是真实开销还是噪声。
const COUNTS := [0, 72, 0, 72, 144]

var _body: StaticBody3D
var _shapes: Array[CollisionShape3D] = []
var _t := 0.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("")
	print("========== 每帧搬 N 个静止盒子的物理开销 ==========")
	print("  （一帧 60 fps = 16667 μs；测 %d 帧取平均，先空转 60 帧热身）" % FRAMES)
	print("")
	for n in COUNTS:
		_build(n)
		for i in 60:
			_move_shapes()
			await physics_frame
		var sum := 0.0
		var worst := 0.0
		for i in FRAMES:
			_move_shapes()
			await physics_frame
			var us := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1_000_000.0
			sum += us
			worst = maxf(worst, us)
		print("  %3d 个盒子：平均 %6.1f μs / 帧 ｜ 最差 %6.1f μs（占一帧 %.3f%%）" % [
			n, sum / float(FRAMES), worst, sum / float(FRAMES) / 16667.0 * 100.0])
		_teardown()
	print("")
	print("  ⚠️ 这里只量「搬变换」；形状的 size 一次建好**从不修改**。")
	print("     UE 那边「碰撞每时每刻都变」如果是每帧重建/烘焙碰撞体，成本差着数量级。")
	print("")
	quit(0)


func _build(n: int) -> void:
	_body = StaticBody3D.new()
	_body.collision_layer = 1
	_body.collision_mask = 0
	root.add_child(_body)
	_shapes.clear()
	for i in n:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.8, 0.8, 2.2)
		cs.shape = box
		cs.transform = Transform3D(Basis.IDENTITY, Vector3(i * 1.1, 1.0, 0.0))
		_body.add_child(cs)
		_shapes.append(cs)


func _teardown() -> void:
	if _body != null:
		_body.queue_free()
		_body = null
	_shapes.clear()


## 正是 `_sync_bone_collisions()` 干的事：每帧把每个盒子搬到新姿态
func _move_shapes() -> void:
	if _shapes.is_empty():
		return
	_t += 1.0 / 60.0
	var rot := Basis(Vector3.UP, sin(_t) * 0.5)
	for i in _shapes.size():
		var cs := _shapes[i]
		cs.transform = Transform3D(rot, Vector3(i * 1.1, 1.0 + sin(_t + i) * 0.3, 0.0))
