extends SceneTree
## 查：电竞房有没有碰撞、能不能挡住人。
##
##   ① 盒子里数：地板 / 天花板 / 四面墙 / 家具各建了多少
##   ② 从外面往墙里打一条射线 —— 必须命中
##   ③ 从房间正中间往外打 —— 必须命中墙
##   ④ 从门口（本地 +Z 那头）往里打 —— 必须**穿过去**（门得能进）
##
##   & godot --script res://scripts/_verify_esports_collision.gd -- --splat=off --story=off

var _fails := 0


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	if ok:
		print("[colv] OK   %s" % what)
	else:
		_fails += 1
		print("[colv] FAIL %s" % what)


func _run() -> void:
	await _wait(3)

	var room: Node3D = load("res://scenes/esports_room.tscn").instantiate()
	root.add_child(room)
	room.global_position = Vector3(52, 0.01, 13)
	await _wait(30)

	# ── ① 数盒子 ──
	var body := room.get_node_or_null("AutoCol") as StaticBody3D
	_check(body != null, "AutoCol（碰撞体）已建立")
	if body == null:
		print("[colv] 结果：失败（没有碰撞体）")
		quit(1)
		return

	var boxes := 0
	var aabb := AABB()
	var first := true
	for c in body.get_children():
		var cs := c as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		var bs := cs.shape as BoxShape3D
		var a := AABB(cs.global_position - bs.size * 0.5, bs.size)
		aabb = a if first else aabb.merge(a)
		first = false
		boxes += 1
	print("[colv] 盒子数 = %d，总范围 %s" % [boxes, str(aabb)])
	_check(boxes >= 10, "盒子数够（%d 个，至少 10）" % boxes)
	_check(boxes >= 6, "外壳 6 个盒子在（地板/天花板/四面墙）")

	# ── ② 从外面往墙里打 ──
	var space := room.get_world_3d().direct_space_state
	var center := room.global_position + Vector3(0, 1.7, 0)

	# 从 -X 外面 8 米处，朝房间中心
	var hit := _ray(space, center + Vector3(-8, 0, 0), center)
	_check(hit.size() > 0, "从外面（-X）打向房间：命中墙 %s" % _hit_str(hit))

	# ── ③ 从正中间往外打（四个方向）──
	var dirs := {
		"+X": Vector3(6, 0, 0),
		"-X": Vector3(-6, 0, 0),
		"+Z": Vector3(0, 0, 9),
		"-Z": Vector3(0, 0, -9),
	}
	for k in dirs.keys():
		var h := _ray(space, center, center + (dirs[k] as Vector3))
		_check(h.size() > 0, "从房间中心朝 %s 打：命中墙" % k)
	# 往下打（地板）
	var hd := _ray(space, center, center + Vector3(0, -3, 0))
	_check(hd.size() > 0, "从房间中心朝下打：命中地板")

	# ── ④ 门口那一头（本地 +Z）应该能走进来 ──
	# 实测门在本地 +Z（那侧墙面只有 3.0 m²，-Z 侧 66.5 m²）
	#
	# ⚠️ 判断「能不能进门」不能只看射线有没有命中 —— 门洞通了之后，射线会继续
	#    打到**房间里的家具**上。所以要看命中点的 z：落在墙位置（z_wall）附近才算被墙挡。
	var z_wall := center.z + 8.42          # +Z 那面墙的世界 z
	var door_outside := center + Vector3(0, 0, 11.0)
	var hz := _ray(space, door_outside, center)
	if hz.is_empty():
		_check(true, "门洞（+Z 正中）畅通，射线一路打到房间中心")
	else:
		var pz: float = (hz["position"] as Vector3).z
		var blocked_by_wall := absf(pz - z_wall) < 0.5
		print("[colv] 门洞射线命中 z=%.2f（墙在 z=%.2f）" % [pz, z_wall])
		_check(not blocked_by_wall, "门洞（+Z 正中）没被墙挡住（命中点在屋内 z=%.2f）" % pz)

	# 门墩：往 X 偏 4.6 米（超过门洞半宽 1.2），应该撞在墙上
	var hp := _ray(space, center + Vector3(4.6, 0, 11.0), center + Vector3(4.6, 0, 0))
	var hp_ok := false
	if hp.size() > 0:
		hp_ok = absf((hp["position"] as Vector3).z - z_wall) < 0.5
	_check(hp_ok, "门墩（+Z 偏 4.6 m）撞在墙上：%s" % _hit_str(hp))

	# 门楣：实测门楣盒子的世界 y 范围是 [2.71, 3.61]（见 _dump_esports_boxes 的输出），
	# 所以取世界 y = 3.0 打一条。
	# ⚠️ 注意 `center` 的 y 已经是「地面 + 1.7」，别在它上面再加高度。
	var y_lintel := 3.0
	var hl_from := Vector3(center.x, y_lintel, center.z + 11.0)
	var hl_to := Vector3(center.x, y_lintel, center.z)
	var hl := _ray(space, hl_from, hl_to)
	var hl_ok := false
	if hl.size() > 0:
		hl_ok = absf((hl["position"] as Vector3).z - z_wall) < 0.5
	_check(hl_ok, "门楣（+Z、世界 y=3.0）撞在墙上：%s" % _hit_str(hl))

	print("[colv] 结果：%s（%d 项不合格）" % ["全过" if _fails == 0 else "有失败", _fails])
	quit(0 if _fails == 0 else 1)


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	q.collide_with_areas = false
	return space.intersect_ray(q)


func _hit_str(h: Dictionary) -> String:
	if h.is_empty():
		return "<未命中>"
	return "命中 %s @ %s" % [str(h.get("collider")), str((h["position"] as Vector3).snappedf(0.01))]
