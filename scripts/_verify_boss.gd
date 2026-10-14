extends SceneTree
## 验「霸王龙优香木桩」：
##   1. 模型修复到位（保留蒙皮 / 隐藏挂件 / 绑贴图 / 按骨架归一化）
##   2. 有碰撞盒，子弹射线真的能打中
##   3. 受击扣血 + 闪白；打光了会倒下、并按 respawn_time 站起来
##   4. 渲图：出生点视角、近距离 3/4、与 Arisu 同框看尺寸
##
## 用法（要真渲染）：godot --path <工程> --script res://scripts/_verify_boss.gd -- --splat=off

var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(30)

	var player: Player = game.get_node("Player")
	var boss: Boss = game.get_node("Boss")
	print("========== 1. 模型修复 ==========")
	var meshes := _all(boss, "MeshInstance3D")
	var visible := 0
	var hidden := 0
	var textured := 0
	var surface_total := 0
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.visible:
			visible += 1
			var am := mi.mesh as ArrayMesh
			for s in am.get_surface_count():
				surface_total += 1
				var mat := am.surface_get_material(s)
				if mat is StandardMaterial3D and (mat as StandardMaterial3D).albedo_texture != null:
					textured += 1
		else:
			hidden += 1
	print("  可见网格 %d / 隐藏 %d   表面 %d（其中已绑贴图 %d）" % [
		visible, hidden, surface_total, textured])
	print("  骨骼数 = %d   归一化尺寸 = %s   目标身高 %.2f m" % [
		boss.bone_count, str(boss.visual_size.snappedf(0.01)), boss.height])
	_check(visible == 4, "保留了 4 个身体部件")
	_check(hidden == 5, "隐藏了 5 个挂件")
	_check(textured == surface_total and surface_total > 0, "所有表面都绑了贴图")
	_check(boss.bone_count == 73, "骨架 73 根骨还在（保留蒙皮）")
	_check(absf(boss.visual_size.y - boss.height) < 0.05,
		"身高归一化到 %.2f m（实测 %.2f）" % [boss.height, boss.visual_size.y])
	# 脚底与水平居中
	var model: Node3D = boss.model
	var skel := _all(model, "Skeleton3D")[0] as Skeleton3D
	var box := _bone_box(skel)
	print("  世界包围盒 pos %s size %s" % [
		str(box.position.snappedf(0.01)), str(box.size.snappedf(0.01))])
	_check(absf(box.position.y) < 0.05, "脚底在 y = 0（实测 %.3f）" % box.position.y)
	_check(absf(box.get_center().x - boss.global_position.x) < 0.05,
		"水平居中到节点原点")
	print("  尺寸对比：Arisu 约 1.7 m，所以这只约 %.1f 个 Arisu 高、%.1f m 长" % [
		boss.visual_size.y / 1.7, boss.visual_size.z])

	print("\n========== 2. 碰撞与射线 ==========")
	var shape := boss.get_node_or_null("Collision") as CollisionShape3D
	_check(shape != null and shape.shape is BoxShape3D, "存在盒型碰撞体")
	if shape and shape.shape is BoxShape3D:
		print("  碰撞盒 size = %s  位置 %s" % [
			str((shape.shape as BoxShape3D).size.snappedf(0.01)),
			str(shape.position.snappedf(0.01))])
	# 从玩家朝 Boss 打一条射线，看物理世界认不认
	var from := Vector3(0, 1.5, 6)
	var to: Vector3 = boss.global_position + Vector3(0, boss.visual_size.y * 0.5, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	print("  射线 %s → %s  命中 %s" % [
		str(from.snappedf(0.1)), str(to.snappedf(0.1)),
		str(hit.get("collider")) if hit else "空"])
	_check(hit.size() > 0 and hit.get("collider") == boss, "子弹射线能打到 Boss 本体")

	print("\n========== 3. 受击 / 倒下 / 重生 ==========")
	var hp0 := boss.health
	var mat := _first_material(boss)
	var base: Color = mat.albedo_color if mat else Color.WHITE
	boss.take_damage(120.0)
	var flashed: Color = mat.albedo_color if mat else Color.WHITE
	print("  受击前 %d → 受击后 %d   材质色从 %s 变到 %s" % [
		int(hp0), int(boss.health), str(base), str(flashed)])
	_check(boss.health < hp0, "扣了血")
	_check(flashed != base, "受击瞬间闪白")
	await _wait(30)
	_check(absf(boss.health_ratio() - (boss.health / boss.max_health)) < 0.001, "血量比例正确")

	boss.respawn_time = 0.25
	boss.take_damage(boss.health)
	await _wait(20)
	var col := boss.get_node_or_null("Collision") as CollisionShape3D
	print("  打光后：碰撞 disabled = %s" % str(col.disabled))
	_check(col.disabled, "倒下后碰撞体关闭")
	# 扑倒是 0.55 s 的补间，headless 每帧只推进几毫秒，要按时间等
	var guard := 0
	while guard < 600 and absf(boss.model.rotation.x) < 0.5:
		await process_frame
		guard += 1
	print("  等待 %d 帧后模型横滚 = %.1f°" % [guard, rad_to_deg(boss.model.rotation.x)])
	_check(absf(boss.model.rotation.x) > 0.3,
		"模型扑倒（%.1f 度）" % rad_to_deg(boss.model.rotation.x))
	await _wait(400)
	print("  等待重生后：血量 %d / %d  碰撞 disabled = %s  横滚 %.1f°" % [
		int(boss.health), int(boss.max_health), str(col.disabled),
		rad_to_deg(boss.model.rotation.x)])
	_check(boss.health == boss.max_health, "重新站起来且满血")
	_check(not col.disabled, "碰撞体恢复")

	print("\n========== 4. 渲图 ==========")
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_boss")
	DirAccess.make_dir_recursive_absolute(out)

	# ① 出生点默认视角
	player.global_position = Vector3(0, 0.05, 6)
	player._yaw = 0.0
	player._facing_yaw = PI
	player.model_root.rotation.y = PI
	player._pitch = -0.04
	await _wait(40)
	await _shot(out.path_join("60_spawn_view.png"))

	# ② 站到 Boss 正前方同框（看尺寸关系）
	player.global_position = boss.global_position + Vector3(-7.5, 0.05, 0.0)
	player._yaw = -PI * 0.5
	player.rig.rotation.y = player._yaw
	player._facing_yaw = player._yaw + PI
	player.model_root.rotation.y = player._facing_yaw
	player._pitch = -0.10
	await _wait(40)
	await _shot(out.path_join("61_scale_with_arisu.png"))

	# ③ 近距离 3/4
	player.global_position = boss.global_position + Vector3(-6.0, 0.05, 5.0)
	player._yaw = rad_to_deg(0.0)
	player._yaw = -PI * 0.75
	player.rig.rotation.y = player._yaw
	player._facing_yaw = player._yaw + PI
	player.model_root.rotation.y = player._facing_yaw
	player._pitch = -0.06
	await _wait(40)
	await _shot(out.path_join("62_closeup.png"))

	print("\n================ 结果 ================")
	print("失败 %d 项" % _fail)
	quit(1 if _fail > 0 else 0)


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("  [img] %s" % path)


func _first_material(boss: Boss) -> StandardMaterial3D:
	for m in _all(boss, "MeshInstance3D"):
		var mi := m as MeshInstance3D
		if not mi.visible or mi.mesh == null:
			continue
		var am := mi.mesh as ArrayMesh
		for s in am.get_surface_count():
			var mat := am.surface_get_material(s)
			if mat is StandardMaterial3D:
				return mat as StandardMaterial3D
	return null


func _bone_box(skel: Skeleton3D) -> AABB:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for i in skel.get_bone_count():
		var p: Vector3 = skel.global_transform * skel.get_bone_global_pose(i).origin
		lo = lo.min(p)
		hi = hi.max(p)
	return AABB(lo, hi - lo)


func _all(node: Node, cls: String) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n == null:
			continue
		if n.is_class(cls):
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  [PASS] ", label)
	else:
		print("  [FAIL] ", label)
		_fail += 1


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
