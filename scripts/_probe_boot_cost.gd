extends SceneTree
## 量：整个 `game.tscn` 的开局耗时，拆开看是哪一段慢。
##
##   godot --headless --script res://scripts/_probe_boot_cost.gd -- --splat=off --story=off --no-capture

const OffWin := preload("res://scripts/offscreen_window.gd")

const GAME := "res://scenes/game.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _run() -> void:
	await OffWin.apply(self)
	await _wait(2)
	print("[boot] ============ game.tscn 开局耗时 ============")

	# ① load（读盘 + 反序列化成 PackedScene）
	var t0 := Time.get_ticks_usec()
	var ps: PackedScene = load(GAME)
	var t_load := (Time.get_ticks_usec() - t0) / 1000.0
	print("[boot] ① load(game.tscn)          %8.1f ms" % t_load)
	if ps == null:
		print("[boot] !! load 失败")
		quit(1)
		return

	# ② instantiate（建节点树，不跑 _ready）
	t0 = Time.get_ticks_usec()
	var game: Node = ps.instantiate()
	var t_inst := (Time.get_ticks_usec() - t0) / 1000.0
	print("[boot] ② instantiate               %8.1f ms" % t_inst)

	# ③ add_child + _ready（子节点 _ready 在这里跑）
	t0 = Time.get_ticks_usec()
	root.add_child(game)
	var t_enter := (Time.get_ticks_usec() - t0) / 1000.0
	print("[boot] ③ add_child（含 _ready）    %8.1f ms" % t_enter)

	# ④ 头 180 帧 —— 异步加载、切簇、泼溅解码都在这几帧里冒出来
	var slow: Array = []
	t0 = Time.get_ticks_usec()
	for i in 180:
		var f0 := Time.get_ticks_usec()
		await process_frame
		var fms := (Time.get_ticks_usec() - f0) / 1000.0
		if fms > 50.0:
			slow.append([i, fms])
	var t_20 := (Time.get_ticks_usec() - t0) / 1000.0
	print("[boot] ④ 头 180 帧合计            %8.1f ms（平均 %.1f ms/帧）" % [t_20, t_20 / 180.0])
	print("[boot]    其中单帧 >50 ms 的共 %d 帧：" % slow.size())
	for s in slow:
		print("[boot]      第 %3d 帧  %7.1f ms" % [s[0], s[1]])

	print("[boot] ------------------------------------------")
	print("[boot] 合计到「能玩」≈ %.1f ms" % (t_load + t_inst + t_enter + t_20))

	# 数一下场上网格，确认场景真的起来了
	var meshes := 0
	for m in game.find_children("*", "MeshInstance3D", true, false):
		meshes += 1
	print("[boot] 场上 MeshInstance3D = %d" % meshes)
	quit(0)
