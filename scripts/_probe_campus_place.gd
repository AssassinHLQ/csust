extends SceneTree
## 量校园泼溅节点的**真实世界包围盒**，找出「什么都看不见」的几何原因。
##
## 要判断的三件事：
##   ① `content_world_aabb()` 的地面（position.y）是不是注释里说的 −0.02
##   ② `_remember_room_xz()` 算出来的高度窗口有没有把 `global_transform` 算进去
##   ③ `splat_node.transform` 与节点 `global_transform` 各是什么
##
##   _tools/run_shot.sh res://scripts/_probe_campus_place.gd -- --no-capture

const OffWin := preload("res://scripts/offscreen_window.gd")


func _initialize() -> void:
	if not OS.get_cmdline_user_args().has("--no-capture"):
		push_error("[place] 缺 --no-capture，拒绝运行")
		quit(2)
		return
	_run.call_deferred()


func _run() -> void:
	await OffWin.apply(self, Vector2i(960, 540))
	var safe0: Array = OffWin.is_safe()
	if not bool(safe0[0]):
		push_error("[place] 窗口没挪到屏幕外：%s" % str(safe0[1]))
		quit(2)
		return

	var ps := load("res://scenes/next_level.tscn") as PackedScene
	var level := ps.instantiate()
	root.add_child(level)
	await process_frame

	var campus: Node3D = level.get_node_or_null("Campus")
	if campus == null:
		push_error("[place] 缺 Campus")
		quit(1)
		return
	campus.set("start_delay", 0.0)
	campus.set("low_priority", false)
	campus.call("force_start")

	var t0 := Time.get_ticks_msec()
	while not bool(campus.call("is_ready")) and Time.get_ticks_msec() - t0 < 240000:
		await process_frame
	print("[place] 就绪 %d ms" % (Time.get_ticks_msec() - t0))

	var cmin: Vector3 = campus.get("content_min")
	var cmax: Vector3 = campus.get("content_max")
	print("[place] 源空间 content_min = %s  content_max = %s  尺寸 = %s"
		% [str(cmin), str(cmax), str(cmax - cmin)])

	var aabb: AABB = campus.call("content_world_aabb")
	print("[place] 世界包围盒 pos = %s  end = %s  尺寸 = %s"
		% [str(aabb.position), str(aabb.end), str(aabb.size)])
	print("[place] content_top_y() = %.3f" % float(campus.call("content_top_y")))

	var gt: Transform3D = campus.global_transform
	print("[place] 节点 global_transform origin = %s" % str(gt.origin))
	print("[place] 节点 basis 缩放 = %.4f / yaw-ish = %s"
		% [gt.basis.get_scale().x, str(gt.basis.get_euler() * 180.0 / PI)])

	var node: Node3D = campus.get("splat_node")
	if node != null:
		print("[place] splat_node.transform origin = %s  basis 缩放 = %.4f"
			% [str(node.transform.origin), node.transform.basis.get_scale().x])
		print("[place] 两者合成 origin = %s" % str((gt * node.transform).origin))

	# 房间判据用的东西（`_remember_room_xz()` 的结果）
	print("[place] _room_xz = %s  is_walls = %s" % [
		str(campus.get("_room_xz")), str(campus.get("_room_xz_is_walls"))])
	print("[place] _room_y_lo = %.3f  _room_y_hi = %.3f" % [
		float(campus.get("_room_y_lo")), float(campus.get("_room_y_hi"))])

	# 玩家实际站位
	var player := level.get_node_or_null("Player") as Node3D
	print("[place] 玩家出生 = %s" % str(player.global_position))
	var floor_node := level.get_node_or_null("CampusFloor") as Node3D
	if floor_node != null:
		print("[place] CampusFloor origin = %s" % str(floor_node.global_position))

	# 用「真实世界盒」对照一遍：玩家的 y 到底在不在内容里
	print("[place] 结论：内容地面 y = %.3f，内容顶 y = %.3f" % [aabb.position.y, aabb.end.y])
	print("[place] 完")
	quit(0)
