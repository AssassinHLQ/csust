extends SceneTree
## 探针：房顶碰撞 / 5090 只能在房顶捡 / 放大 3 倍 / 倭瓜优香两套技能 / 牢笼解除。
##
## 用法：
##   godot --path <工程> --script res://scripts/_probe_roof_trap.gd -- --splat=off --bosses=off
##
## 只打印数字和 PASS/FAIL，不出图（出图见 `_probe_trap.gd`）。

var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await _wait(30)
	var p := game.get_node_or_null("Player") as Player
	var pk := game.get_node_or_null("Parkour") as Parkour
	if p == null or pk == null:
		print("!! 缺 Player / Parkour")
		quit(1)
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pk.enabled = false
	_ok(p.max_health == 250.0, "爱丽丝血量 250（实测 %.0f）" % p.max_health)

	var shed := pk.get_node_or_null("Island/Props/Shed") as Node3D
	var gpu := pk.get_node_or_null("Island/Props/Shed/RTX5090") as Rtx5090
	print("[probe] Shed %s" % str(shed.global_position.snappedf(0.01)))
	print("[probe] 5090 %s" % str(gpu.global_position.snappedf(0.01)))
	# ① 尺寸：长边应该 ≈ 1.02 m（原来的 3 倍）
	var holder := gpu.get_child(0) as Node3D
	var mi := holder.get_child(0) as MeshInstance3D
	var mesh_len := maxf(mi.get_aabb().size.x, maxf(mi.get_aabb().size.y, mi.get_aabb().size.z)) \
		* holder.scale.x
	var world_box: AABB = holder.global_transform * mi.get_aabb()
	print("[probe] 5090 世界包围盒 %s / 模型长边 %.2f m" % [
		str(world_box.size.snappedf(0.01)), mesh_len])
	_ok(absf(mesh_len - 1.02) < 0.03, "5090 长边 %.2f m（×3）" % mesh_len)
	_ok(gpu.get_child_count() == 1, "黄色呼吸圈已删（5090 只剩 1 个子节点，实测 %d）" % gpu.get_child_count())

	# ② 屋顶碰撞 + 台阶
	var solid := shed.get_node_or_null("RoofSolid") as StaticBody3D
	_ok(solid != null, "房顶有碰撞盒（RoofSolid）")
	var steps := shed.get_node_or_null("RoofSteps") as StaticBody3D
	var step_tops: Array[float] = []
	if steps != null:
		for c in steps.get_children():
			if c is CollisionShape3D:
				var bx := (c as CollisionShape3D).shape as BoxShape3D
				step_tops.append((c as CollisionShape3D).position.y + bx.size.y * 0.5)
	_ok(step_tops.size() == 3 and step_tops.max() >= 1.45,
		"太阳台阶 3 级，最高 %.2f m（屋顶 2.5，跳 1.26 够）" % (step_tops.max() if not step_tops.is_empty() else -1.0))

	# ③ 站在房顶正上方 → 提示；站在屋檐下 → 没提示
	var gp := gpu.global_position
	var fut := game.get_node_or_null("Parkour/Futures") as ParkourFutures
	var prompt := fut.get_node_or_null("FuturesHUD/Prompt") as Label
	_put(p, gp.x + 2.2, gp.y - 2.5, gp.z + 2.2)     # 屋檐下 2.5 m
	await _wait(300)
	print("[probe] 屋檐下：is_on_floor=%s  提示=「%s」" % [str(p.is_on_floor()),
		prompt.text if prompt != null else "?"])
	var under_ok := prompt == null or prompt.text.strip_edges() == ""
	_ok(under_ok, "站在屋檐下面**收不到**（没有「按 F」提示）")

	_put(p, gp.x + 0.35, gp.y + 0.10, gp.z + 0.35)  # 屋顶上
	await _wait(500)
	print("[probe] 屋顶上：y=%.2f（卡底 %.2f） floor=%s  提示=「%s」" % [
		p.global_position.y, gp.y, str(p.is_on_floor()),
		prompt.text if prompt != null else "?"])
	_ok(p.is_on_floor() and absf(p.global_position.y - gp.y) < 0.15,
		"屋顶能站住（脚底 %.2f vs 卡底 %.2f）" % [p.global_position.y, gp.y])
	_ok(prompt != null and prompt.text.contains("按 F 拾取"), "屋顶上出现「按 F 拾取」")

	# ④ 两次 F → 资产 +59999 / 牢笼 / 倭瓜优香 / 镜头锁定 1 秒
	var a0 := fut.assets_yuan
	await _press_key(KEY_F)
	_ok(prompt != null and prompt.text.contains("真的要拾取吗"), "第一次 F → 二次确认")
	await _press_key(KEY_F)
	await _wait(250)
	var cage := game.get_node_or_null("TrapCage") as Node3D
	var bars := 0
	if cage != null:
		for c in cage.get_children():
			if c is MeshInstance3D:
				bars += 1
	_ok(fut.assets_yuan == a0 + 59999, "资产 +¥59,999（合计 ¥%d）" % fut.assets_yuan)
	_ok(cage != null and bars >= 60, "牢笼更密：%d 根钢条（原来 30）" % bars)

	await _wait(450)
	var boss: Boss = null
	for c in game.get_children():
		if c is Boss and String(c.name).to_lower().contains("squash"):
			boss = c
	_ok(boss != null, "倭瓜优香登场")
	if boss == null:
		quit(1)
		return
	_ok(boss.max_health == 2200.0, "倭瓜优香血量 %.0f" % boss.max_health)
	_ok(boss.respawn_on_death == false, "respawn_on_death = false（不会复活）")
	print("[probe] 镜头锁定 = %s" % str(p.look_locked()))
	var to_boss := (boss.global_position + Vector3(0, 1.6, 0) - p.cam.global_position).normalized()
	print("[probe] 镜头视线·指向倭瓜 = %.2f" % p.camera_forward().dot(to_boss))
	_ok(p.look_locked() and p.camera_forward().dot(to_boss) > 0.75,
		"拾取后镜头强制锁定倭瓜优香（点积 %.2f）" % p.camera_forward().dot(to_boss))

	# ⑤ 技能一：压扁 → 弹起 → 红圈 → 天降 40 伤害 + 强击退
	# 先把人放到岛中央（落点随机 ±3 m，离岛边远一点，测击退时不会掉下去）
	var island := pk.get_node("Island") as Node3D
	var mid := island.global_position + Vector3(0.0, 0.62, 0.0)
	_put(p, mid.x, mid.y, mid.z)
	await _wait(500)
	var saw_mark := false
	var max_y := 0.0
	var mark_pos := Vector3.ZERO
	var t0 := Time.get_ticks_msec()
	var hp0 := p.health
	while Time.get_ticks_msec() - t0 < 7000:
		await process_frame
		if p.global_position.y < 6.0:      # 万一被顶下岛，拉回来继续测
			_put(p, mid.x, mid.y, mid.z)
		max_y = maxf(max_y, boss.global_position.y)
		if boss.call("mark_visible"):
			if not saw_mark:
				saw_mark = true
				mark_pos = (boss.get_node("SlamMark") as Node3D).global_position
				# 站进圈内 2.4 m 处（别站爆心：会被压进 Boss 的碰撞体，击退被吃掉）
				_put(p, mark_pos.x + 2.4, mark_pos.y + 0.05, mark_pos.z)
		if saw_mark and absf(boss.global_position.y - mark_pos.y) < 0.2 and p.health < hp0:
			break
	print("[probe] 技能一：红圈=%s  最高腾空 %.1f m  血量 %.0f → %.0f  速度 %.1f" % [
		str(saw_mark), max_y, hp0, p.health, Vector2(p.velocity.x, p.velocity.z).length()])
	_ok(saw_mark, "技能一亮出红圈（落点在爱丽丝附近）")
	_ok(max_y > 3.0, "倭瓜优香短暂滞空（最高 %.1f m）" % max_y)
	_ok(absf((hp0 - p.health) - 40.0) < 0.5, "天降伤害 40（实测 %.0f）" % (hp0 - p.health))
	_ok(Vector2(p.velocity.x, p.velocity.z).length() > 6.0,
		"天降大力击退（水平速度 %.1f m/s）" % Vector2(p.velocity.x, p.velocity.z).length())

	# ⑥ 技能二：就是原来那套（抬身 + 绿色预警圈涨大）
	#    它只朝**正面 32°** 起手，所以先把人挪到它正前方 6 m（自然玩法里人就是这么站的）
	var front := mid + Vector3(2.5, 0.0, 0.0)
	_put(p, front.x, front.y, front.z)
	await _wait(600)
	var saw_tele := false
	var lifted := 0.0
	var base_y := (boss.get_node("ObjModel") as Node3D).position.y if boss.get_node_or_null("ObjModel") else 0.0
	var tele := boss.get_node_or_null("AttackTelegraph") as MeshInstance3D
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 9000:
		await process_frame
		if p.global_position.y < 6.0:
			_put(p, front.x, front.y, front.z)
		if tele != null and tele.visible:
			saw_tele = true
			var mo := boss.get_node_or_null("ObjModel") as Node3D
			if mo != null:
				lifted = maxf(lifted, mo.position.y - base_y)
	_ok(saw_tele, "技能二：地面预警圈照旧亮起（BossAttacker 默认那套）")
	_ok(lifted > 0.3, "技能二起手整只抬起来（+%.2f m）" % lifted)

	# ⑦ 打死 → 牢笼解除、不复活
	boss.take_damage(99999.0)
	await _wait(1200)
	_ok(game.get_node_or_null("TrapCage") == null, "倭瓜优香倒下 → 牢笼解除（TrapCage 已移除）")
	_ok(boss.health <= 0.0, "血量归零")
	await _wait(7000)
	_ok(boss.health <= 0.0 and boss.visible,
		"等 7 s 也没有复活（血量 %.0f）" % boss.health)
	print("\n[probe] FAIL = %d" % _fail)
	quit(0 if _fail == 0 else 1)


func _put(p: Player, x: float, y: float, z: float) -> void:
	p.global_position = Vector3(x, y, z)
	p.velocity = Vector3.ZERO


func _press_key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	await process_frame
	var up := InputEventKey.new()
	up.keycode = code
	up.physical_keycode = code
	up.pressed = false
	Input.parse_input_event(up)
	await _wait(120)


func _wait(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame


func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("PASS  %s" % msg)
	else:
		_fail += 1
		print("FAIL  %s" % msg)
