extends SceneTree
## 验第二位 Boss「飞猪优香」（models/boss_pig/猪猪优香.fbx，作者：一个睿智）：
##   1. **没有骨架**的静态模型也要能量对尺寸：2.6 m 高、脚底 y=0、水平居中
##   2. 4 个材质各自的贴图绑对了（人眼对照 ref/author_render_1.png）
##   3. 本体朝向确认（鼻子在 +Z、尾巴在 −Z），节点朝 +X 面向场地中心
##   4. 碰撞盒 + 子弹射线能打中
##   5. 受击闪白 / 扣血 / 倒下 / 重生（和霸王龙同一套契约）
##   6. HUD 双血条：两位 Boss 各一条、互不串台
##   7. 没挡住「玩家 → Target1」那条自检弹道（霸王龙当初就是栽在这条上）
##   8. 渲图
##
## 用法（要真渲染）：godot --path <工程> --script res://scripts/_verify_boss_pig.gd -- --splat=off

var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1600, 900)
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _steps(30)

	var player: Player = game.get_node("Player")
	var pig: Boss = game.get_node("BossPig")
	var trex: Boss = game.get_node("Boss")
	var hud: CanvasLayer = game.get_node("HUD")

	print("========== 0. 两位 Boss 同时在场 ==========")
	_check(trex != null and pig != null, "霸王龙优香与飞猪优香都在场")
	var apart := trex.global_position.distance_to(pig.global_position)
	print("  霸王龙 %s   飞猪 %s   相距 %.1f m" % [
		str(trex.global_position.snappedf(0.1)), str(pig.global_position.snappedf(0.1)), apart])
	_check(apart > 20.0, "两位相距 %.1f m（不重叠）" % apart)

	print("\n========== 1. 静态网格定尺寸 ==========")
	var meshes := _all(pig, "MeshInstance3D")
	var visible := 0
	var surfaces := 0
	var mapping := {}
	for m in meshes:
		var mi := m as MeshInstance3D
		if not mi.visible:
			continue
		visible += 1
		var am := mi.mesh as ArrayMesh
		for s in am.get_surface_count():
			surfaces += 1
			var mat := am.surface_get_material(s)
			if mat is StandardMaterial3D:
				var sm := mat as StandardMaterial3D
				if sm.albedo_texture != null:
					mapping[sm.resource_name] = sm.albedo_texture.resource_path.get_file()
	print("  可见网格 %d   表面 %d   材质→贴图 %d 条" % [visible, surfaces, mapping.size()])
	for k in mapping.keys():
		print("      %-26s → %s" % [k, mapping[k]])
	print("  测量方式 = %s   骨骼数 = %d   归一化尺寸 = %s（目标身高 %.2f m）" % [
		pig.measure_kind, pig.bone_count, str(pig.visual_size.snappedf(0.01)), pig.height])
	_check(visible == 4, "4 个网格全显示（身体/鼻子/尾巴/光环）")
	_check(pig.measure_kind == "网格", "走的是网格包围盒这条路（确认没有骨架）")
	_check(pig.bone_count == 0, "确认没有骨骼（纯静态）")
	_check(mapping.get("材质", "") == "pig_untitled1.png",
		"身体「材质」→ pig_untitled1.png（实测 %s）" % mapping.get("材质", "（无）"))
	_check(mapping.get("材质.001", "") == "pig_nose.png",
		"鼻子「材质.001」→ pig_nose.png（实测 %s）" % mapping.get("材质.001", "（无）"))
	_check(mapping.get("材质.002", "") == "pig_tail.png",
		"尾巴「材质.002」→ pig_tail.png（实测 %s）" % mapping.get("材质.002", "（无）"))
	_check(mapping.get("Yuuka_Original_Halo_0Mat", "") == "pig_halo.png",
		"光环「Yuuka_Original_Halo_0Mat」→ pig_halo.png（实测 %s）" % mapping.get("Yuuka_Original_Halo_0Mat", "（无）"))
	_check(absf(pig.visual_size.y - pig.height) < 0.05,
		"身高归一化到 %.2f m（实测 %.2f）" % [pig.height, pig.visual_size.y])

	var box := _mesh_box(pig)
	print("  父空间包围盒 pos %s  size %s" % [
		str(box.position.snappedf(0.01)), str(box.size.snappedf(0.01))])
	_check(absf(box.position.y) < 0.05, "脚底落在 y = 0（实测 %.3f）" % box.position.y)
	_check(absf(box.get_center().x) < 0.05 and absf(box.get_center().z) < 0.05,
		"水平居中到节点原点（x=%.2f z=%.2f）" % [box.get_center().x, box.get_center().z])

	print("\n========== 2. 朝向 ==========")
	var nose := _mesh_box_named(pig, "立方体_001")
	var tail := _mesh_box_named(pig, "贝塞尔曲线")
	print("  鼻子中心 z = %.2f   尾巴中心 z = %.2f   节点朝向 = %s" % [
		nose.get_center().z, tail.get_center().z, str(pig.facing().snappedf(0.01))])
	_check(nose.get_center().z > 1.0, "鼻子在 +Z 侧（%.2f m）→ 本体朝 +Z" % nose.get_center().z)
	_check(tail.get_center().z < -1.0, "尾巴在 −Z 侧（%.2f m）" % tail.get_center().z)
	_check(pig.facing().x > 0.9, "节点朝 +X（面向场地中心）")

	print("\n========== 3. 碰撞与射线 ==========")
	var shape := pig.get_node_or_null("Collision") as CollisionShape3D
	_check(shape != null and shape.shape is BoxShape3D, "存在盒型碰撞体")
	if shape and shape.shape is BoxShape3D:
		print("  碰撞盒 size = %s  位置 %s" % [
			str((shape.shape as BoxShape3D).size.snappedf(0.01)),
			str(shape.position.snappedf(0.01))])
	var from := Vector3(0, 1.5, 6)
	var to: Vector3 = pig.global_position + Vector3(0, 1.0, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = false
	q.collision_mask = 0xFFFFFFFF & ~Companion.LAYER
	q.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	print("  射线 %s → %s  命中 %s" % [
		str(from.snappedf(0.1)), str(to.snappedf(0.1)),
		str(hit.get("collider")) if hit else "空"])
	_check(hit.size() > 0 and hit.get("collider") == pig, "子弹射线能打到飞猪本体")

	# 回归：霸王龙当初放在 x=9 时吃掉了这条弹道，飞猪也不能犯
	var target1: Target = game.get_node("Target1")
	var q1 := PhysicsRayQueryParameters3D.create(Vector3(6, 1.2, -4), Vector3(6, 1.2, -10))
	q1.collide_with_areas = false
	q1.collision_mask = 0xFFFFFFFF & ~Companion.LAYER
	var h1 := player.get_world_3d().direct_space_state.intersect_ray(q1)
	print("  回归弹道 %s → %s  命中 %s" % [
		str(Vector3(6, 1.2, -4)), str(Vector3(6, 1.2, -10)),
		str(h1.get("collider")) if h1 else "空"])
	_check(h1.size() > 0 and h1.get("collider") == target1,
		"没挡住「玩家(6,−4) → Target1(6,−10)」那条自检弹道")

	print("\n========== 4. 受击 / 闪白 / 倒下 / 重生 ==========")
	var mat := _first_material(pig)
	var base: Color = mat.albedo_color if mat else Color.WHITE
	var hp0 := pig.health
	pig.take_damage(120.0)
	var flashed: Color = mat.albedo_color if mat else Color.WHITE
	print("  血量 %d → %d   材质色 %s → %s" % [int(hp0), int(pig.health), str(base), str(flashed)])
	_check(pig.health < hp0, "扣了血")
	_check(flashed != base, "受击瞬间闪白")
	await _steps(20)

	pig.respawn_time = 0.25
	pig.take_damage(pig.health)
	await _steps(20)
	var col := pig.get_node_or_null("Collision") as CollisionShape3D
	_check(col.disabled, "倒下后碰撞体关闭")
	var guard := 0
	while guard < 600 and absf(pig.model.rotation.x) < 0.5:
		await process_frame
		guard += 1
	print("  等待 %d 帧后模型横滚 = %.1f°" % [guard, rad_to_deg(pig.model.rotation.x)])
	_check(absf(pig.model.rotation.x) > 0.3, "模型扑倒（%.1f 度）" % rad_to_deg(pig.model.rotation.x))
	# 等重生用**真实时间**而不是帧数：补间是按时间推进的，
	# 帧率一高「等 400 帧」可能只过了 0.4 s，补间还没跑完就断言会假红。
	await _wait_seconds(2.0)
	print("  重生后：血量 %d / %d  碰撞 disabled = %s  横滚 %.1f°" % [
		int(pig.health), int(pig.max_health), str(col.disabled),
		rad_to_deg(pig.model.rotation.x)])
	_check(pig.health == pig.max_health, "重新站起来且满血")
	_check(not col.disabled, "碰撞体恢复")

	print("\n========== 5. HUD 双血条 ==========")
	# ⚠️ 血条**按名字取**，不要靠遍历顺序。
	#    `_all()` 是拿栈做的深度遍历，弹出来是**倒序**（bars[0] 会是 BossBar1）；
	#    本喵试过 `bars.sort_custom(func(a,b): return a.name < b.name)`，
	#    实测**没生效**（顺序照旧是反的），于是把「打霸王龙掉的是飞猪那条」
	#    误判成了游戏的 bug。按名字取既明确又顺便验了命名约定。
	var bar0 := hud.get_node_or_null("BossBar0") as ProgressBar
	var bar1 := hud.get_node_or_null("BossBar1") as ProgressBar
	var n0 := hud.get_node_or_null("BossName0") as Label
	var n1 := hud.get_node_or_null("BossName1") as Label
	var bar_count := 0
	for n in _all(hud, "ProgressBar"):
		if (n as ProgressBar).name.begins_with("BossBar"):
			bar_count += 1
	print("  BossBar 数量 = %d" % bar_count)
	print("  第 1 行「%s」→ %.2f" % [n0.text if n0 else "（无）", bar0.value if bar0 else -1.0])
	print("  第 2 行「%s」→ %.2f" % [n1.text if n1 else "（无）", bar1.value if bar1 else -1.0])
	_check(bar_count == 2 and bar0 != null and bar1 != null,
		"HUD 上正好有 BossBar0 / BossBar1 两条血条")
	_check(n0 != null and n0.text.begins_with("霸王龙优香"), "第 1 行是霸王龙优香")
	_check(n1 != null and n1.text.begins_with("飞猪优香"), "第 2 行是飞猪优香")
	_check(absf(bar1.value - 1.0) < 0.001,
		"飞猪血条在重生后回到满格（%.2f）" % bar1.value)

	# 打霸王龙 300 → 第 1 行掉到 0.90，第 2 行纹丝不动
	var pig_hp := pig.health
	trex.take_damage(300.0)
	await _steps(3)
	print("  打霸王龙 300：第 1 行 %.3f「%s」  第 2 行 %.3f「%s」" % [
		bar0.value, n0.text, bar1.value, n1.text])
	_check(pig.health == pig_hp and absf(bar1.value - 1.0) < 0.001, "打霸王龙完全不影响飞猪那条")
	_check(bar0.value < 0.999 and n0.text.contains("2700"),
		"第 1 行同步到 2700/3000（血条 %.3f）" % bar0.value)

	# 再打飞猪 180 → 只动第 2 行
	var trex_hp := trex.health
	pig.take_damage(180.0)
	await _steps(3)
	print("  再打飞猪 180：第 1 行 %.3f「%s」  第 2 行 %.3f「%s」" % [
		bar0.value, n0.text, bar1.value, n1.text])
	_check(trex.health == trex_hp and absf(bar0.value - 0.9) < 0.01, "打飞猪完全不影响霸王龙那条")
	_check(bar1.value < 0.999 and n1.text.contains("1620"),
		"第 2 行同步到 1620/1800（血条 %.3f）" % bar1.value)

	print("\n========== 6. 渲图 ==========")
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_boss")
	DirAccess.make_dir_recursive_absolute(out)

	# ① 出生点视角：飞猪在左、霸王龙在右，两位同框
	player.global_position = Vector3(0, 0.05, 6)
	player._yaw = 0.0
	player.rig.rotation.y = 0.0
	player._facing_yaw = PI
	player.model_root.rotation.y = PI
	player._pitch = -0.02
	await _steps(40)
	await _shot(out.path_join("93_pig_from_spawn.png"))

	# ② 正面近景（猪朝 +X，所以站到它 +X 侧回头看它）
	player.global_position = pig.global_position + Vector3(6.5, 0.05, 0.0)
	player._yaw = PI * 0.5
	player.rig.rotation.y = player._yaw
	player._facing_yaw = player._yaw + PI
	player.model_root.rotation.y = player._facing_yaw
	player._pitch = -0.05
	await _steps(40)
	await _shot(out.path_join("94_pig_front.png"))

	# ③ 3/4 视角 —— 与作者原渲染图（models/boss_pig/ref/author_render_1.png）同角度对照
	player.global_position = pig.global_position + Vector3(6.0, 0.05, 3.2)
	player._yaw = 1.08
	player.rig.rotation.y = player._yaw
	player._facing_yaw = player._yaw + PI
	player.model_root.rotation.y = player._facing_yaw
	player._pitch = -0.08
	await _steps(40)
	await _shot(out.path_join("95_pig_three_quarter.png"))

	print("\n================ 结果 ================")
	print("失败 %d 项" % _fail)
	quit(1 if _fail > 0 else 0)


# --- 工具 ---

func _mesh_box(boss: Boss) -> AABB:
	var to_local := boss.global_transform.affine_inverse()
	var out := AABB()
	var first := true
	for m in _all(boss, "MeshInstance3D"):
		var mi := m as MeshInstance3D
		if not mi.visible or mi.mesh == null:
			continue
		var b: AABB = to_local * (mi.global_transform * mi.get_aabb())
		if b.size.length() <= 0.0001:
			continue
		out = b if first else out.merge(b)
		first = false
	return out


func _mesh_box_named(boss: Boss, substr: String) -> AABB:
	for m in _all(boss, "MeshInstance3D"):
		var mi := m as MeshInstance3D
		if mi.mesh == null or not mi.name.contains(substr):
			continue
		var to_local := boss.global_transform.affine_inverse()
		return to_local * (mi.global_transform * mi.get_aabb())
	return AABB()


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


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("  [img] %s" % path)


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


func _steps(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame


## 按真实时间等（帧数在高帧率下等不出真实秒数）
func _wait_seconds(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await process_frame
