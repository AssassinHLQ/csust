extends SceneTree
## 量画室609 的真实水平范围与门框位置，给「出门就释放」定判据。
##
##   _tools/run_shot.sh res://scripts/_probe_room_bounds.gd
##
## 打印：
##   ① `splat_aabb`（点云整体，源空间）过 `_local_basis()` + `_resolve_offset()` 之后的世界 XZ
##   ② `content_min/max`（裁剪后内容）的世界 XZ —— 更接近「真实房间」
##   ③ 场景里 `Room609/RoomCollision` 那几个墙碰撞盒的世界 AABB（门就在 z- 面）
##   ④ 玩家出生点 / 场景门位置，用来核对判据会不会误伤

const SCENE := "res://scenes/game.tscn"


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	var t := create_timer(240.0, true)
	t.timeout.connect(func():
		print("[bounds] !! 看门狗超时")
		quit(1))
	_run.call_deferred()


func _run() -> void:
	print("[bounds] 载入 %s" % SCENE)
	var packed := load(SCENE) as PackedScene
	if packed == null:
		print("[bounds] !! 载入失败")
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene

	# 等泼溅节点建好（Room609 的 _finish() 里会 _remember_room_xz()）
	var room: Node = scene.get_node_or_null("Room609")
	if room == null:
		print("[bounds] !! 找不到 Room609")
		quit(1)
		return

	print("[bounds] Room609 脚本=%s" % str(room.get_script()))
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 180000:
		await process_frame
		if room.get("splat_node") != null:
			break
	print("[bounds] 泼溅节点就绪耗时 %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))

	# ① / ② 源空间盒子 → 世界
	var basis: Basis = room.call("_local_basis")
	var offset: Vector3 = room.call("_resolve_offset")
	print("[bounds] basis=%s  offset=%s" % [str(basis.get_scale()), str(offset)])

	var saabb: AABB = room.get("splat_aabb")
	_dump_world_xz("① splat_aabb（点云整体）", saabb, basis, offset)

	var cmin: Vector3 = room.get("content_min")
	var cmax: Vector3 = room.get("content_max")
	if cmax.x > cmin.x:
		_dump_world_xz("② content（裁剪后内容）", AABB(cmin, cmax - cmin), basis, offset)

	# ③ 墙碰撞盒
	var col: Node = room.get_node_or_null("RoomCollision")
	if col != null:
		print("[bounds] ── 碰撞盒世界 AABB ──")
		for c in col.get_children():
			if c is CollisionShape3D:
				var cs := c as CollisionShape3D
				var sh := cs.shape
				if sh is BoxShape3D:
					var sz: Vector3 = (sh as BoxShape3D).size
					var g := cs.global_transform
					var half := sz * 0.5 * g.basis.get_scale()
					var ctr := g.origin
					print("[bounds]   %-12s 中心 (%.2f, %.2f, %.2f)  尺寸 (%.2f, %.2f, %.2f)  范围 x %.2f~%.2f  z %.2f~%.2f" % [
						cs.name, ctr.x, ctr.y, ctr.z, half.x * 2.0, half.y * 2.0, half.z * 2.0,
						ctr.x - half.x, ctr.x + half.x, ctr.z - half.z, ctr.z + half.z])

	# ④ 玩家 & 门
	var p := get_first_node_in_group("player") as Node3D
	if p == null:
		p = scene.get_node_or_null("Player") as Node3D
	if p != null:
		print("[bounds] 玩家出生点 %s" % str(p.global_position))

	for n in get_nodes_in_group("scene_gate"):
		if n is Node3D:
			var n3 := n as Node3D
			print("[bounds] 场景门 %s @ %s → %s" % [
				n3.name, str(n3.global_position), str(n3.get("target_scene"))])

	print("[bounds] 当前 _room_xz = %s" % str(room.get("_room_xz")))
	print("[bounds] hide_inside_aabb = %s" % str(room.get("hide_inside_aabb")))
	print("[bounds] unload_outside_room = %s" % str(room.get("unload_outside_room")))
	print("[bounds] 完成")
	quit(0)


func _dump_world_xz(tag: String, a: AABB, basis: Basis, offset: Vector3) -> void:
	if a.size == Vector3.ZERO:
		print("[bounds] %s：空" % tag)
		return
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for i in 8:
		var corner := a.position + Vector3(
			a.size.x * float(i & 1),
			a.size.y * float((i >> 1) & 1),
			a.size.z * float((i >> 2) & 1))
		var w := basis * corner + offset
		lo = lo.min(w)
		hi = hi.max(w)
	print("[bounds] %s  世界 x %.2f~%.2f（宽 %.2f）  z %.2f~%.2f（深 %.2f）  y %.2f~%.2f" % [
		tag, lo.x, hi.x, hi.x - lo.x, lo.z, hi.z, hi.z - lo.z, lo.y, hi.y])
