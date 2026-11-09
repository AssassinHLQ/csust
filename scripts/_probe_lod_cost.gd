extends SceneTree
## 量：电竞房 LOD 在**开局**吃掉多少时间。
##
## 背景：esports_lod.gd::_build_lod() 在 `_ready` 里把三档模型全实例化
##   high 233.9 MB / mid 100.6 MB / low 45.4 MB = 380 MB
## 而电竞房开局 `visible = false`（要在芹香那儿买完才现身）。
##
##   godot --headless --script res://scripts/_probe_lod_cost.gd -- --no-capture

const ROOM := "res://scenes/esports_room.tscn"
const LOW := "res://models/esports_room/esports_room.glb"
const MID := "res://models/esports_room/esports_room_mid.glb"
const HIGH := "res://models/esports_room/esports_room_high.glb"


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	await _wait(2)
	print("[lod] ============ 电竞房开局开销 ============")

	# ① 三档各自 load 的耗时（PackedScene 进内存）
	for item in [[LOW, "low 45.4MB"], [MID, "mid 100.6MB"], [HIGH, "high 233.9MB"]]:
		var t0 := Time.get_ticks_usec()
		var ps: PackedScene = load(item[0])
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		print("[lod] load %-16s %7.1f ms%s" % [item[1], ms, "" if ps != null else "  !! 失败"])

	# ② 整间房 scene 的 load（含 low + 碰撞）
	var t0 := Time.get_ticks_usec()
	var room_ps: PackedScene = load(ROOM)
	var t_load := (Time.get_ticks_usec() - t0) / 1000.0
	print("[lod] load %-16s %7.1f ms" % ["esports_room.tscn", t_load])

	# ③ instantiate —— 这一步会触发 Lod._ready() -> _build_lod()，
	#    把 mid + high 同步 load 进来
	for run in 2:
		var inst: Node = room_ps.instantiate()
		var t1 := Time.get_ticks_usec()
		root.add_child(inst)
		# 等 LOD 脚本那句 `await process_frame` 过去
		await _wait(3)
		var t_inst := (Time.get_ticks_usec() - t1) / 1000.0
		var lod := inst.get_node_or_null("Lod")
		var n_children := 0 if lod == null else lod.get_child_count()
		print("[lod] 第 %d 次 instantiate + _ready：%7.1f ms  （Lod 挂上了 %d 个子模型）"
			% [run + 1, t_inst, n_children])
		# 数一下内存里有多少网格实例
		var meshes := 0
		for m in inst.find_children("*", "MeshInstance3D", true, false):
			meshes += 1
		print("[lod]     这间房一共 %d 个 MeshInstance3D" % meshes)
		inst.queue_free()
		await _wait(2)

	print("[lod] ============ 结论 ============")
	print("[lod] 开局就算电竞房还没买，三档模型也会全部加载（380 MB）")
	quit(0)
