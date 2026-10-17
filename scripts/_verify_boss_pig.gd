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

	print("\n========== 5. HUD 血条组 ==========")
	# ⚠️ 血条**按名字取**，不要靠遍历顺序。
	#    `_all()` 是拿栈做的深度遍历，弹出来是**倒序**（bars[0] 会是 BossBar1）；
	#    本喵试过 `bars.sort_custom(func(a,b): return a.name < b.name)`，
	#    实测**没生效**（顺序照旧是反的），于是把「打霸王龙掉的是飞猪那条」
	#    误判成了游戏的 bug。按名字取既明确又顺便验了命名约定。
	#
	# ⚠️ 现在**行号本身也会变**：默认场上只有飞猪优香（row 0），
	#    `-- --bosses=all` 才是 7 位（飞猪/霸王龙/倭瓜/霍德/佩洛洛斯拉/比纳/哥利亚）。
	#    所以这里先建「名字 → 条」的表，完全不假设行序。
	var bars := {}
	var bar_count := 0
	for i in 16:
		var b := hud.get_node_or_null("BossBar%d" % i) as ProgressBar
		var n := hud.get_node_or_null("BossName%d" % i) as Label
		if b == null or n == null:
			continue
		bar_count += 1
		bars[n.text] = b
		print("  第 %d 行「%s」→ %.2f" % [i + 1, n.text, b.value])
	var want := 0
	for ch in game.get_children():
		if ch is Boss:
			want += 1
	_check(bar_count == want, "HUD 上正好有 %d 条血条（BossBar0..），和场上 Boss 数一致" % want)
	for nm in ["飞猪优香", "霸王龙优香", "倭瓜优香", "霍德", "佩洛洛斯拉"]:
		_check(bars.has(nm), "HUD 上有「%s」那条（名字行只写名字，不带血量数字）" % nm)
	var trex_bar: ProgressBar = bars.get("霸王龙优香")
	var pig_bar: ProgressBar = bars.get("飞猪优香")
	_check(pig_bar != null and absf(pig_bar.value - 1.0) < 0.001,
		"飞猪血条在重生后回到满格（%.2f）" % (pig_bar.value if pig_bar else -1.0))

	# 打霸王龙 300 → 只有它那条掉
	var pig_hp := pig.health
	trex.take_damage(300.0)
	await _steps(3)
	print("  打霸王龙 300：霸王龙条 %.3f  飞猪条 %.3f" % [
		trex_bar.value if trex_bar else -1.0, pig_bar.value if pig_bar else -1.0])
	_check(pig.health == pig_hp and pig_bar != null and absf(pig_bar.value - 1.0) < 0.001,
		"打霸王龙完全不影响飞猪那条")
	# ⚠️ 这里原先断言名字文本里带 "2700"。换成 Minecraft 风格后名字行**只写名字**、
	#    不再显示血量数字（见 hud.gd 的 _add_boss_row），所以改成直接对着 Boss 的
	#    真实 `health` 比 —— 不抠文本，还顺便挡住「同伴偷偷帮打」造成的数值漂移。
	_check(trex_bar != null and trex_bar.value < 0.999
			and absf(trex_bar.value - trex.health / trex.max_health) < 0.001,
		"霸王龙那条血条跟着它自己走（%.3f，血 %d/%d）" % [
			trex_bar.value if trex_bar else -1.0, int(trex.health), int(trex.max_health)])

	# 再打飞猪 180 → 只动飞猪那条
	var trex_hp := trex.health
	var trex_ratio := trex_bar.value if trex_bar else 0.0
	pig.take_damage(180.0)
	await _steps(3)
	print("  再打飞猪 180：霸王龙条 %.3f  飞猪条 %.3f" % [
		trex_bar.value if trex_bar else -1.0, pig_bar.value if pig_bar else -1.0])
	_check(trex.health == trex_hp and trex_bar != null
			and absf(trex_bar.value - trex_ratio) < 0.001,
		"打飞猪完全不影响霸王龙那条")
	_check(pig_bar != null and pig_bar.value < 0.999
			and absf(pig_bar.value - pig.health / pig.max_health) < 0.001,
		"飞猪那条血条跟着飞猪走（%.3f，血 %d/%d）" % [
			pig_bar.value if pig_bar else -1.0, int(pig.health), int(pig.max_health)])

	print("\n========== 6. 飞猪现在也会攻击 ==========")
	# 飞猪原来只是木桩（boss.gd），这一轮换成了 pig_boss.gd（骚扰型）。
	# 机制和霸王龙共用 boss_attacker.gd，但**参数必须明显不同** ——
	# 否则「重击型 / 骚扰型」就只是说法上的区别了。
	_check(pig.has_method("_attack"), "飞猪挂了攻击脚本（不再是纯木桩）")
	var p_radius := float(pig.get("attack_radius"))
	var t_radius := float(trex.get("attack_radius"))
	var p_cd := float(pig.get("attack_interval"))
	var t_cd := float(trex.get("attack_interval"))
	var p_dmg := float(pig.get("attack_damage"))
	var t_dmg := float(trex.get("attack_damage"))
	print("  飞猪：  圈 %.1f m  冷却 %.1f s  伤害 %.0f" % [p_radius, p_cd, p_dmg])
	print("  霸王龙：圈 %.1f m  冷却 %.1f s  伤害 %.0f" % [t_radius, t_cd, t_dmg])
	_check(p_radius < t_radius, "飞猪的圈更小（%.1f < %.1f）" % [p_radius, t_radius])
	_check(p_cd < t_cd, "飞猪的冷却更短（%.1f < %.1f）" % [p_cd, t_cd])
	_check(p_dmg < t_dmg, "飞猪单次伤害更低（%.0f < %.0f）" % [p_dmg, t_dmg])

	# 实打实打一下：把玩家放进飞猪的预警圈，看掉不掉血、飞不飞。
	# 顺带把 facing() 打出来 —— 攻击是朝这个方向放的，它朝哪直接决定能不能打到你。
	print("  飞猪位置 %s   facing() = %s" % [
		str(pig.global_position.snappedf(0.1)), str(pig.facing().snappedf(0.01))])
	(trex as Node).set_process(false)     # 别让霸王龙同时插一脚
	player.set_physics_process(false)     # 冻住摩擦，击退才量得准
	(pig as Node).set_process(false)      # 手动驱动，避免 _process 抢跑
	pig.set("windup_time", 0.12)
	var reach := float(pig.get("attack_reach"))
	player.global_position = pig.global_position + pig.facing() * reach
	player.health = player.max_health
	player.velocity = Vector3.ZERO
	pig.call("_attack", player)
	_check((pig.get_node("AttackTelegraph") as MeshInstance3D).visible, "飞猪起手时露出预警圈")
	await _wait_seconds(0.4)
	print("  玩家 HP 100 → %.0f" % player.health)
	_check(player.health < player.max_health, "站在飞猪预警圈里会掉血")
	_check(player.velocity.length() > 0.1, "飞猪命中也会击退")
	_check(not (pig.get_node("AttackTelegraph") as MeshInstance3D).visible, "结算后收起预警圈")

	print("\n========== 7. 渲图 ==========")
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

	print("\n========== 8. 第四、第五位 Boss（霍德 / 佩洛洛斯拉）==========")
	# 这两位和前面三位共用 `boss_attacker.gd`，所以这里重点验**它们自己的特点**：
	#   霍德   = 圈套在自己脚下（reach 0）+ 全向 + 最慢
	#   佩洛     = 起手最快 + 圈最小
	var hod := game.get_node_or_null("BossHod") as Boss
	var pero := game.get_node_or_null("BossPeroro") as Boss
	_check(hod != null and pero != null, "场景里有 BossHod 与 BossPeroro")
	if hod != null and pero != null:
		print("  霍德：%s  身高 %.2f m  骨 %d（按%s量）" % [
			hod.display_name, hod.visual_size.y, hod.bone_count, hod.measure_kind])
		print("  佩洛洛斯拉：%s  身高 %.2f m  骨 %d（按%s量）" % [
			pero.display_name, pero.visual_size.y, pero.bone_count, pero.measure_kind])
		_check(hod.display_name == "霍德", "第四位叫霍德")
		_check(pero.display_name == "佩洛洛斯拉", "第五位叫佩洛洛斯拉")
		_check(hod.model != null and pero.model != null, "两个模型都载入了")
		_check(hod.measure_kind == "骨架" and hod.bone_count > 100,
			"霍德按骨架量（164 骨）")
		_check(pero.measure_kind == "骨架" and pero.bone_count > 30,
			"佩洛洛斯拉按骨架量（47 骨）")
		_check(absf(hod.visual_size.y - hod.height) < 0.05,
			"霍德身高归一化到 %.2f m" % hod.height)
		_check(absf(pero.visual_size.y - pero.height) < 0.05,
			"佩洛洛斯拉身高归一化到 %.2f m" % pero.height)

		# 贴图：这两个的材质**每个面都要绑上**，有一面空着就是漏了 texture_map 的键
		for b in [hod, pero]:
			var boss2 := b as Boss
			var bare := 0
			var total := 0
			for m in _all(boss2.model, "MeshInstance3D"):
				var mi := m as MeshInstance3D
				var am := mi.mesh as ArrayMesh
				if am == null:
					continue
				for s in am.get_surface_count():
					var smat := am.surface_get_material(s)
					if smat is StandardMaterial3D:
						total += 1
						if (smat as StandardMaterial3D).albedo_texture == null:
							bare += 1
			print("  %s：%d 个贴图槽位，%d 个空着" % [boss2.display_name, total, bare])
			_check(total > 0 and bare == 0,
				"%s 的每个材质面都绑上了贴图（%d/%d）" % [boss2.display_name, total - bare, total])

		# 霍德：圈心就在自己脚下，而且是全向
		_check(is_zero_approx(float(hod.get("attack_reach"))),
			"霍德的预警圈套在自己脚下（reach = %.1f）" % float(hod.get("attack_reach")))
		_check(absf(float(hod.get("attack_half_angle_degrees")) - 180.0) < 0.1,
			"霍德全向起手（半角 180°）")
		# ⚠️ 起手时间不能拿飞猪比：§6 为了快速驱动，已经把它的 `windup_time`
		#    改成了 0.12。这里改用霸王龙的 0.9 s 当基准（它没被改过）。
		_check(float(hod.get("windup_time")) > float(trex.get("windup_time")),
			"霍德起手比霸王龙还慢（%.2f > %.2f s）" % [
				float(hod.get("windup_time")), float(trex.get("windup_time"))])
		_check(float(hod.get("attack_radius")) > float(trex.get("attack_radius")),
			"霍德的圈比霸王龙还大（%.1f > %.1f m）" % [
				float(hod.get("attack_radius")), float(trex.get("attack_radius"))])

		# 佩洛洛斯拉：起手最快、圈最小
		# 同上：基准用霸王龙（0.9 s），不用被 §6 改过的飞猪。
		_check(float(pero.get("windup_time")) < float(trex.get("windup_time")),
			"佩洛洛斯拉起手全场最快（%.2f < %.2f s）" % [
				float(pero.get("windup_time")), float(trex.get("windup_time"))])
		_check(float(pero.get("attack_radius")) < float(pig.get("attack_radius")),
			"佩洛洛斯拉的圈最小（%.1f < %.1f m）" % [
				float(pero.get("attack_radius")), float(pig.get("attack_radius"))])
		var visible_emotion := 0
		for m in _all(pero.model, "MeshInstance3D"):
			var mi := m as MeshInstance3D
			if mi.name.begins_with("Perorozilla_Emotion_") and mi.visible:
				visible_emotion += 1
		_check(visible_emotion == 1,
			"佩洛洛斯拉只留 1 张表情变体（实测 %d 张，5 张全开会糊成一团）" % visible_emotion)

		# 实打实打一下霍德：站在它脚下（圈心）应该掉血；退到圈外不该掉
		var hod_telegraph := hod.get_node_or_null("AttackTelegraph") as MeshInstance3D
		_check(hod_telegraph != null, "霍德有预警圈节点")
		if hod_telegraph != null:
			(hod as Node).set_process(false)      # 手动驱动，避免 _process 抢跑
			hod.set("windup_time", 0.12)
			player.set_physics_process(false)
			player.global_position = hod.global_position + Vector3(1.0, 0.05, 1.0)
			player.health = player.max_health
			player.velocity = Vector3.ZERO
			hod.call("_attack", player)
			_check(hod_telegraph.visible, "霍德起手时露出预警圈")
			await _wait_seconds(0.4)
			print("  站在霍德脚下：玩家 HP 100 → %.0f" % player.health)
			_check(player.health < player.max_health, "站在霍德圈里会掉血（全向）")
			_check(player.velocity.length() > 0.1, "霍德命中会击退")
			_check(not hod_telegraph.visible, "霍德结算后收起预警圈")

			# 圈外（但在发现距离内）不该掉血 —— 和另外三位同一条铁律
			player.global_position = hod.global_position \
				+ Vector3(float(hod.get("attack_radius")) + 2.0, 0.05, 0.0)
			player.health = player.max_health
			player.velocity = Vector3.ZERO
			hod.call("_attack", player)
			await _wait_seconds(0.4)
			print("  退到霍德圈外：玩家 HP = %.0f" % player.health)
			_check(is_equal_approx(player.health, player.max_health),
				"站在霍德圈外不掉血（预警圈 = 伤害区）")

	print("\n========== 9. 第六、第七位 Boss（比纳 / 哥利亚，备用库）==========")
	# 这两位**不在主场景里**（默认场上只有飞猪优香，太挤），
	# 躺在 `scenes/bosses_standby.tscn`，靠 `-- --bosses=all` 上场。
	var bina := game.get_node_or_null("BossBina") as Boss
	var goli := game.get_node_or_null("BossGoliath") as Boss
	_check(bina != null and goli != null, "备用库里多了比纳与哥利亚")
	if bina != null and goli != null:
		print("  比纳：%s  身高 %.2f m  骨 %d  尺寸 %s" % [
			bina.display_name, bina.visual_size.y, bina.bone_count,
			str(bina.visual_size.snappedf(0.01))])
		print("  哥利亚：%s  身高 %.2f m  骨 %d  尺寸 %s" % [
			goli.display_name, goli.visual_size.y, goli.bone_count,
			str(goli.visual_size.snappedf(0.01))])
		_check(bina.display_name == "比纳" and goli.display_name == "哥利亚", "名字对上")
		_check(bina.measure_kind == "骨架" and bina.bone_count > 30, "比纳按骨架量（44 骨）")
		_check(goli.measure_kind == "骨架" and goli.bone_count > 20, "哥利亚按骨架量（34 骨）")
		var bare := 0
		var total := 0
		for b in [bina, goli]:
			for m in _all((b as Boss).model, "MeshInstance3D"):
				var mi := m as MeshInstance3D
				var am := mi.mesh as ArrayMesh
				if am == null:
					continue
				for s in am.get_surface_count():
					var smat := am.surface_get_material(s)
					if smat is StandardMaterial3D:
						total += 1
						if (smat as StandardMaterial3D).albedo_texture == null:
							bare += 1
		_check(total > 0 and bare == 0,
			"两位的每个材质面都绑了贴图（%d/%d）" % [total - bare, total])
		_check(float(bina.get("attack_half_angle_degrees")) > 60.0,
			"比纳是全场最宽的扇形（%.0f°）" % float(bina.get("attack_half_angle_degrees")))
		_check(float(goli.get("attack_reach")) >= 10.0,
			"哥利亚的圈落在 %.1f m 外（全场最远）" % float(goli.get("attack_reach")))

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
