extends SceneTree
## 探针：把 scenes/game.tscn 当主场景真跑起来，回答「为什么进去动不了 / 鼠标没捕获」。
##
## 打印：鼠标模式 / 是否暂停 / Esc 菜单是否开着 / 玩家位置，然后**真的按 1 秒 W**
## 看位移 —— 动不了的话这里就露馅了。
##
## ⚠️ 故意**不加 `--splat=off`**：加了的话 `splat_scene.gd::_disable_placed_collision()`
##    会把房间里手摆的碰撞全部关掉，测出来的是「一间没有墙的房间」，撞墙卡住这种情况
##    根本测不到（本喵第一版就用了 --splat=off，白测一轮）。
##
## 用法：
##   godot --path . --script res://scripts/_probe_gameplay_input.gd

const GAME := "res://scenes/game.tscn"

var _root_node: Node = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ps: PackedScene = load(GAME)
	_root_node = ps.instantiate()
	root.add_child(_root_node)
	await _frames(10)

	var player: Node3D = _root_node.get_node_or_null("Player")
	if player == null:
		push_error("[gp] 没有 Player")
		quit(1)
		return
	var room: Node3D = _root_node.get_node_or_null("Room609")
	var menu: Node = _root_node.get_node_or_null("SettingsMenu")
	var col: Node = room.get_node_or_null("RoomCollision") if room != null else null

	# 等泼溅加载完（房间碰撞的开关跟它走）
	var t0 := Time.get_ticks_msec()
	while room != null and not bool(room.call("is_ready")) and Time.get_ticks_msec() - t0 < 40000:
		await _frames(6)
	print("[gp] 泼溅就绪 = %s（等了 %d ms）" % [
		str(room.call("is_ready")) if room != null else "无 Room609", Time.get_ticks_msec() - t0])

	print("[gp] ── 开局状态 ──")
	print("[gp]   Input.mouse_mode = %d（2 = CAPTURED，0 = VISIBLE）" % Input.mouse_mode)
	print("[gp]   get_tree().paused = %s" % str(paused))
	print("[gp]   Esc 菜单 is_open = %s" % (str(menu.get("is_open")) if menu != null else "无 SettingsMenu"))
	print("[gp]   玩家位置 = %s" % str(player.global_position.snappedf(0.01)))
	if col != null:
		var layers := 0
		for ch in col.get_children():
			var cs := ch as CollisionShape3D
			if cs != null:
				layers |= (col as CollisionObject3D).collision_layer
		print("[gp]   RoomCollision 的 collision_layer = %d（0 = 被 _disable_placed_collision 关了）"
			% (col as CollisionObject3D).collision_layer)
	else:
		print("[gp]   没有 RoomCollision")

	# 物理查询：以玩家所在的胶囊位置问一下有没有别的碰撞体压着
	var space := player.get_world_3d().direct_space_state
	var probe := CapsuleShape3D.new()
	probe.radius = 0.3
	probe.height = 1.7
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = probe
	q.transform = Transform3D(Basis.IDENTITY, player.global_position + Vector3.UP * 0.85)
	q.collision_mask = 0xFFFFFFFF
	var hits := space.intersect_shape(q, 16)
	var names: Array[String] = []
	for h in hits:
		var n: Node = h["collider"]
		names.append("%s(%s)" % [n.name, n.get_class()])
	print("[gp]   出生点胶囊压到的碰撞体 %d 个：%s" % [hits.size(), str(names)])

	# ── 真的按 W ──
	print("[gp] ── 按住 W 一秒 ──")
	var before: Vector3 = player.global_position
	Input.action_press("move_forward")
	var t1 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t1 < 1000:
		await process_frame
	Input.action_release("move_forward")
	await _frames(5)
	var moved: Vector3 = player.global_position - before
	print("[gp]   位移 = %s，长度 %.3f m" % [str(moved.snappedf(0.01)), moved.length()])
	if moved.length() < 0.3:
		print("[gp]   ⚠️ 几乎没动 —— 玩家被卡住了")
	else:
		print("[gp]   ✅ 能动")

	print("[gp] ── 真按 A 一秒（横移，验第二个方向）──")
	before = player.global_position
	Input.action_press("move_left")
	var t2 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t2 < 1000:
		await process_frame
	Input.action_release("move_left")
	await _frames(5)
	moved = player.global_position - before
	print("[gp]   位移 = %s，长度 %.3f m %s" % [
		str(moved.snappedf(0.01)), moved.length(), "✅" if moved.length() >= 0.3 else "⚠️ 又没动"])

	quit(0)


func _frames(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
