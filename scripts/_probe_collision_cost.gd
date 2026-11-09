extends SceneTree
## 量：开一局到底在碰撞上花多少时间。
##
## 对比三件事：
##   ① 加载「烘好的碰撞场景」esports_collision_baked.tscn  —— 现在走的路
##   ② 只 load 屋壳 GLB（不含碰撞）                       —— 参照
##   ③ 旧版运行时建盒子（760 个 BoxShape3D + CollisionShape3D）—— 被淘汰的那条路
##
##   godot --headless --script res://scripts/_probe_collision_cost.gd -- --no-capture

const BAKED := "res://scenes/esports_collision_baked.tscn"
const ROOM := "res://scenes/esports_room.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	await _wait(2)
	print("[cost] ================ 碰撞开销实测 ================")

	# ① 加载烘好的碰撞场景（现在运行时真正做的事）
	var t0 := Time.get_ticks_usec()
	var ps: PackedScene = load(BAKED)
	var t_load := (Time.get_ticks_usec() - t0) / 1000.0
	if ps == null:
		print("[cost] !! load 失败")
		quit(1)
		return

	t0 = Time.get_ticks_usec()
	var inst: Node = ps.instantiate()
	root.add_child(inst)
	await process_frame
	var t_inst := (Time.get_ticks_usec() - t0) / 1000.0
	print("[cost] ① 烘好的碰撞场景：load %.1f ms + instantiate %.1f ms = 合计 %.1f ms"
		% [t_load, t_inst, t_load + t_inst])

	var body := inst.find_child("AutoCol", true, false) as StaticBody3D
	var n := 0 if body == null else body.get_child_count()
	print("[cost]    形状 %d 个 —— **已经是成品，运行时一个都不用建**" % n)

	# ② 屋壳 GLB 参照
	t0 = Time.get_ticks_usec()
	var room_ps: PackedScene = load(ROOM)
	var t_room := (Time.get_ticks_usec() - t0) / 1000.0
	print("[cost] ② 屋壳场景 esports_room.tscn：load %.1f ms（含碰撞实例，合并算在里面）" % t_room)

	# ③ 旧版运行时建盒子（这里照旧版的做法现场建一遍，做对照）
	# ⚠️ 这个数**只量了「建节点」本身**，不含旧版真正贵的那一步 ——
	#    旧版要把家具按 0.6 m 体素切开，逐个格子做「这里有没有三角面」的测试，
	#    那段才是 575 ms 的来源（见 esports_collision.gd 顶部注释）。
	#    所以下面这个数**不能**拿来对比新旧开销，只说明「纯建节点」也不便宜。
	var dummy := Node3D.new()
	root.add_child(dummy)
	t0 = Time.get_ticks_usec()
	var dbody := StaticBody3D.new()
	dummy.add_child(dbody)
	for i in 760:
		var sh := BoxShape3D.new()
		sh.size = Vector3(1, 1, 1)
		var cs := CollisionShape3D.new()
		cs.shape = sh
		dbody.add_child(cs)
	await process_frame
	var t_build := (Time.get_ticks_usec() - t0) / 1000.0
	print("[cost] ③ 单纯建 760 个空盒子节点：%.1f ms（**不含**旧版的体素切割，不能拿来比新旧）" % t_build)

	print("[cost] ================ 结论 ================")
	print("[cost] 开一局在碰撞上花的钱 = ① 的 %.1f ms（加载一个普通场景文件）" % (t_load + t_inst))
	print("[cost] 「烘」是离线工具，只在改完 esports_parts.json 后手动跑一次，不参与开游戏")
	quit(0)
