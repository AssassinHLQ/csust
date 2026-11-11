extends SceneTree
## 量：149 颗 9950X3D 的**每帧**脚本开销（玩家离得很远、根本没在捡的情况）。
##
## 用户 2026-11-11：「单次游戏149捡起一个就删掉一个可以吗,减轻性能开销」。
## 进场景那一次的开销已经量过了（`_probe_cpu_pickup_cost.gd`：476 ms / 596 网格），
## 这里量的是**持续开销** —— 站着不动、离 CPU 很远时，那 149 个 `_physics_process`
## 每帧还在做什么。
##
## 做法：把玩家摆在离 CPU 阵 200 m 外（保证每一颗都会走「太远，直接 return」那条路），
## 连跑 N 个物理帧，报每帧平均耗时。
##
## 用法：
##   bash _tools/run_probe.sh res://scripts/_probe_cpu_frame_cost.gd -- --splat=off

const RunMemory := preload("res://scripts/run_memory.gd")
const CPUS_SCENE := "res://scenes/room609_cpus.tscn"
const FRAMES := 600


func _initialize() -> void:
	_run()


func _run() -> void:
	print("========== 149 颗 CPU 的每帧开销（玩家离 200 m）==========")
	RunMemory.wipe()
	var cpus := (load(CPUS_SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(cpus)
	var player := (load("res://scenes/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	root.add_child(player)
	for _i in 20:
		await physics_frame

	var n := 0
	for c in cpus.get_children():
		if c.has_method("price"):
			n += 1
	player.global_position = Vector3(200.0, 1.0, 200.0)
	for _i in 5:
		await physics_frame

	# 计时：扣掉「空场景」的底噪，只看 CPU 脚本带来的增量
	var t0 := Time.get_ticks_usec()
	for _i in FRAMES:
		await physics_frame
	var with_cpu := float(Time.get_ticks_usec() - t0) / float(FRAMES)
	print("  %d 颗在场上：每物理帧 %.1f μs" % [n, with_cpu])

	cpus.queue_free()
	for _i in 5:
		await physics_frame
	var t1 := Time.get_ticks_usec()
	for _i in FRAMES:
		await physics_frame
	var without := float(Time.get_ticks_usec() - t1) / float(FRAMES)
	print("  一颗都没有：每物理帧 %.1f μs（底噪，含引擎自身）" % without)
	print("  ⇒ CPU 脚本本身占每帧 %.1f μs（149 颗合计）" % (with_cpu - without))
	quit(0)
