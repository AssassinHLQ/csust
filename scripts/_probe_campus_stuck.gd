extends SceneTree
## 找出**玩家真正卡住的地方**：在校园里铺一层网格，每个点把玩家传送过去、
## 朝四个方向各按一次「前进」，量水平位移。位移 ≈ 0 = 卡住（不是没路，是走不动）。
##
##   godot --path . --headless --script res://scripts/_probe_campus_stuck.gd -- --splat=on
##
## 用户 2026-11-11：「碰撞总是卡住人」，并说「只有某些地方（某栋楼、某个路口）」。
##
## 为什么不用射线：射线只回答「哪里有一堵墙」，回答不了「人走过去会不会被卡住」。
## 卡住往往是胶囊**楔进**凹面网格/薄墙、或者被两个面夹住 —— 只有真跑 CharacterBody3D
## 的 move_and_slide 才测得出来。所以这里直接操场上那个 Player。
##
## 判据：按前进 25 个物理帧，水平位移 < 0.30 m（正常走 ≈ 4~8 m）记作「卡」；
## 另外排除「脚下没地」（向下射线打不到东西）和「起点就在碰撞里」的点。

const LEVEL := "res://scenes/next_level.tscn"
## 网格间距（米）/ 覆盖边长 / 每方向按多久 / 位移小于这个算卡住。
##
## ⚠️ 默认值很慢：`SPAN/STEP = 16`，16×16×4 方向×25 帧 ≈ **25600 个物理帧**，
##    实测 420 秒都跑不完，而结果只在最后才打印 —— 于是「跑了一次啥也没看到」。
##    所以现在可以用命令行覆盖，并且**每扫完一行就打一次进度**：
##      godot --path . --script res://scripts/_probe_campus_stuck.gd -- --step=60 --frames=12
const STEP_DEFAULT := 25.0
const SPAN := 400.0
const FRAMES_DEFAULT := 25
const STUCK_MOVE := 0.30    # 位移小于这个算卡住

var _level: Node3D
var _player: CharacterBody3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_level = (load(LEVEL) as PackedScene).instantiate() as Node3D
	root.add_child(_level)
	await process_frame

	var campus: Node3D = _level.get_node_or_null("Campus")
	if campus == null:
		print("[stuck] 没有 Campus")
		quit(1)
		return
	campus.set("start_delay", 0.0)
	campus.set("low_priority", false)
	campus.set("preload_on_gate", false)
	campus.call("force_start")
	var t0 := Time.get_ticks_msec()
	while not bool(campus.call("is_ready")) and Time.get_ticks_msec() - t0 < 240000:
		await process_frame
	print("[stuck] 泼溅就绪 %d ms" % (Time.get_ticks_msec() - t0))

	_player = _level.get_node_or_null("Player") as CharacterBody3D
	if _player == null:
		print("[stuck] 没有 Player")
		quit(1)
		return
	# 别让玩家被 HUD/剧情干扰
	var tree := _level.get_tree()
	tree.paused = false
	print("[stuck] 玩家 layer=%d mask=%d" % [_player.collision_layer, _player.collision_mask])

	var space := _level.get_world_3d().direct_space_state
	# 命令行覆盖（见文件头那段「为什么加这个」）
	var STEP := STEP_DEFAULT
	var FRAMES := FRAMES_DEFAULT
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--step="):
			STEP = maxf(float(a.substr(7)), 5.0)
		elif a.begins_with("--frames="):
			FRAMES = maxi(int(a.substr(9)), 4)
	print("[stuck] 参数：间距 %.0f m / 每方向 %d 帧" % [STEP, FRAMES])
	var x0 := -SPAN * 0.5
	var z0 := -230.0 - SPAN * 0.5
	var nx := int(SPAN / STEP)
	var checked := 0
	var skipped_air := 0
	var stuck: Array = []
	var ok_moves := 0
	for iz in nx:
		for ix in nx:
			var px := x0 + float(ix) * STEP
			var pz := z0 + float(iz) * STEP
			# 脚下有没有地？
			var dq := PhysicsRayQueryParameters3D.create(
				Vector3(px, 120.0, pz), Vector3(px, -60.0, pz))
			dq.collision_mask = 1
			var dhit := space.intersect_ray(dq)
			if dhit.is_empty():
				skipped_air += 1
				continue
			var gy: float = (dhit["position"] as Vector3).y
			if gy < -3.0 or gy > 40.0:
				skipped_air += 1
				continue
			checked += 1
			var dirs: Array[Vector3] = [Vector3(0, 0, -1), Vector3(0, 0, 1),
				Vector3(1, 0, 0), Vector3(-1, 0, 0)]
			var best_move := 0.0
			for d in dirs:
				_player.global_position = Vector3(px, gy + 1.0, pz)
				_player.velocity = Vector3.ZERO
				await physics_frame
				await physics_frame
				var a := _player.global_position
				# 直接给速度 + move_and_slide（不依赖输入映射，省得受暂停/输入影响）
				for _f in FRAMES:
					_player.velocity = Vector3(d.x * 6.0, _player.velocity.y, d.z * 6.0)
					_player.move_and_slide()
					await physics_frame
				var b := _player.global_position
				var moved := Vector2(b.x - a.x, b.z - a.z).length()
				best_move = maxf(best_move, moved)
				_player.velocity = Vector3.ZERO
			if best_move >= STUCK_MOVE:
				ok_moves += 1
			else:
				stuck.append({"p": Vector3(px, gy, pz), "best": best_move})
		# 每扫完一行就打一次进度（结果在最后，否则长扫描时完全看不到进展）
		print("[stuck] 进度 z=%.0f：已检查 %d、卡住 %d" % [z0 + float(iz) * STEP,
			checked, stuck.size()])

	print("\n[stuck] 网格 %d×%d（间距 %.0f m），有地面的 %d 个，空气/越界跳过 %d 个"
		% [nx, nx, STEP, checked, skipped_air])
	print("[stuck] 能走动 %d 个 / **卡住 %d 个**（四向最好位移 < %.2f m）"
		% [ok_moves, stuck.size(), STUCK_MOVE])
	if not stuck.is_empty():
		print("[stuck] 卡住的位置（最多列 25 个）：")
		var shown := 0
		for s in stuck:
			if shown >= 25:
				break
			var p: Vector3 = s["p"]
			print("[stuck]   (%7.1f, %6.2f, %7.1f)  最好位移 %.2f m" % [p.x, p.y, p.z, float(s["best"])])
			shown += 1
	quit(0)
