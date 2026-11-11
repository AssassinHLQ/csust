extends SceneTree
## 量「霸王龙这套蒙皮碰撞盒到底吃多少性能」。
##
## 用户 2026-11-11：「这样子会吃性能吗，曾经 ue 的我做地鸣，那个超大巨的碰撞
## 每时每刻都变，结果卡死带不动」。
##
## 所以这里分三段量，而且要分清楚它跟 UE 那种「碰撞每时每刻都变」的区别：
##   ① **一次性**建盒开销（`_boot()` 里，抽样 16 万顶点）—— 只有一个尖峰
##   ② **每帧**的脚本开销（`_sync_bone_collisions()`，只写变换）
##   ③ **物理侧**的真实代价：对比「有 72 个盒子」与「全部关掉」的
##      `Performance.TIME_PHYSICS_PROCESS`
##
##   bash _tools/run_probe.sh res://scripts/_probe_trex_collision_cost.gd -- --no-capture --splat=off

const LEVEL := "res://scenes/next_level.tscn"
const NAMES := ["TrexBossA", "TrexBossB", "TrexBossC"]
## 每次统计取多少帧
const FRAMES := 240


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var level := (load(LEVEL) as PackedScene).instantiate()
	root.add_child(level)
	for i in 4:
		await process_frame
	for nm in NAMES:
		var b := level.get_node_or_null(nm)
		if b != null and not bool(b.get("_booted")):
			b.call("_boot")
	for i in 60:
		await process_frame

	print("")
	print("========== ① 一次性建盒开销 ==========")
	print("  （`_boot()` 打印里的「建盒耗时」，玩家走近 60 m 才触发；三只各一次）")

	var shapes := 0
	var sync_us := 0.0
	for nm in NAMES:
		var boss := level.get_node_or_null(nm)
		if boss == null:
			continue
		var cols: Array = boss.get("_collisions")
		shapes += cols.size()
		# ② 每帧脚本开销：直接空转测
		var n := 500
		for i in 5:
			boss.call("_sync_bone_collisions")
		var t0 := Time.get_ticks_usec()
		for i in n:
			boss.call("_sync_bone_collisions")
		var us := float(Time.get_ticks_usec() - t0) / float(n)
		sync_us += us
		print("  %s：%d 个盒子 ｜ 每帧跟随 %.1f μs" % [nm, cols.size(), us])

	print("")
	print("  ========== ② 每帧脚本开销（合计）==========")
	print("  三只合计 %.1f μs / 帧 ＝ 一帧（16.7 ms）的 %.3f%%" % [
		sync_us, sync_us / 16700.0 * 100.0])

	print("")
	print("========== ③ 物理侧代价 ==========")
	print("  ⚠️ 在**这个关卡里量不准**：`next_level.tscn` 自己有上千个碰撞形状，")
	print("     `TIME_PHYSICS_PROCESS` 在 0.8~4.2 ms 之间乱跳，开/关 Boss 碰撞的差值")
	print("     完全被噪声淹掉（实测三轮回合正负号都出现过）。")
	print("     物理侧请用隔离微基准：res://scripts/_probe_static_shape_cost.gd")
	print("     那边结论：每帧搬 72 个静止盒子 ≈ 0.22~0.25 ms（一帧 1.3~1.5%），")
	print("     144 个 ≈ 0.33 ms。也就是说**搬变换**是每形状 ~3 μs 的量级。")
	print("")
	print("  另：默认开了距离门（`collision_follow_distance = 45 m`），")
	print("  玩家远离时盒子冻结、物理侧不再花这笔钱 → 实战通常只有 1 只在刷新。")
	print("")
	quit(0)


## 平均 `Performance.TIME_PHYSICS_PROCESS`（微秒）
func _avg_physics_us() -> float:
	for i in 20:
		await physics_frame
	var sum := 0.0
	for i in FRAMES:
		await physics_frame
		sum += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1_000_000.0
	return sum / float(FRAMES)
