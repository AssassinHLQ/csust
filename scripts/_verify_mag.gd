extends SceneTree
## 验完这轮三个需求（等待逻辑按「状态」而不是「帧数」，避免 headless 低帧率误判）：
##   1. 开局是标准越肩视角：镜头在角色背后，视线指向靶区
##   2. 弹匣 60 发
##   3. 按住左键打空 → 自动换弹 → 换完自动继续射
##
## 用法：godot --path <工程> --script res://scripts/_verify_mag.gd

var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game: Node = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	await _wait(20)

	var player: Player = game.get_node("Player")
	var weapon: Weapon = game.get_node("Player/Weapon")
	var skel: Skeleton3D = game.get_node("Player/Arisu/Model/Aris_Original_Mesh/bone_root/Bip001/Skeleton3D")

	print("========== 1. 开局：镜头应在角色背后，角色面朝靶区 ==========")
	var face := _face(skel)
	var to_cam := _flat(player.cam.global_position - player.global_position).normalized()
	var dot := face.dot(to_cam)
	print("  角色 %s   相机 %s" % [
		str(player.global_position.snappedf(0.1)), str(player.cam.global_position.snappedf(0.1))])
	print("  脸 %s   「角色→相机」%s   点积 %+.2f" % [
		str(face.snappedf(0.01)), str(to_cam.snappedf(0.01)), dot])
	_check(dot < -0.7, "开局镜头在角色背后（看不到正脸）")
	var arena := Vector3(0.0, 0.0, -1.0)
	print("  相机视线 %s   与靶区方向(-Z)点积 %+.2f" % [
		str(_flat(player.camera_forward()).normalized().snappedf(0.01)),
		_flat(player.camera_forward()).normalized().dot(arena)])
	_check(_flat(player.camera_forward()).normalized().dot(arena) > 0.9,
		"开局相机视线指向靶区（-Z），一进场就看得见靶子")
	_check(face.dot(arena) > 0.7, "开局角色面朝靶区（背对镜头）")

	var out_dir := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_spawn")
	if not DirAccess.dir_exists_absolute(out_dir):
		DirAccess.make_dir_recursive_absolute(out_dir)
	await RenderingServer.frame_post_draw
	game.get_viewport().get_texture().get_image().save_png("%s/spawn_default.png" % out_dir)
	print("  已存 spawn_default.png")

	print("\n========== 2. 弹匣容量 ==========")
	print("  magazine_size = %d   current_ammo = %d" % [weapon.magazine_size, weapon.current_ammo])
	_check(weapon.magazine_size == 60, "弹匣 60 发")

	print("\n========== 3. 按住左键打空 → 自动换弹 → 自动续射 ==========")
	# 站到 Target1 前方并让准星压在它身上：相机绕角归零（视线 -Z）、
	# 角色朝向 = _yaw + PI（背对镜头、面朝 -Z）
	player.global_position = Vector3(6, 0.05, -4)
	player._yaw = 0.0
	player.rig.rotation.y = 0.0
	player._facing_yaw = player._yaw + PI
	player.model_root.rotation.y = player._yaw + PI
	player._pitch = -0.02
	await _wait(25)
	print("  调试：相机前方 = %s   枪口 = %s" % [
		str(player.camera_forward().snappedf(0.01)),
		str(weapon.muzzle.global_position.snappedf(0.01))])
	var hp_before := (game.get_node("Target1") as Target).health
	weapon.current_ammo = weapon.magazine_size
	weapon._cooldown = 0.0
	weapon.fire_interval = 0.05
	# 关掉散布，让「连发期间是否命中」变成确定性判定；
	# 散布打开时 6 m 处的散布圈约 0.17 m，打不死 100 血。
	weapon.spread_hip = 0.0
	weapon.spread_aim = 0.0

	weapon.trigger_down()
	print("  trigger_down → _trigger = %s" % str(weapon._trigger))
	print("  连发前：spring.rotation.x = %.3f  相机前方 = %s" % [
		player.spring.rotation.x, str(player.camera_forward().snappedf(0.01))])

	# 逐发打印落点（只打前 5 发 + 中间几发，避免刷屏）
	var shot_watch := {"n": 0}
	weapon.fired.connect(func(_i: int) -> void:
		shot_watch["n"] = int(shot_watch["n"]) + 1
		var n := int(shot_watch["n"])
		if n <= 5 or n == 30 or n == 60:
			var cam2 := player.cam
			var o := cam2.global_position + cam2.global_transform.basis * weapon.muzzle_offset
			var d := player.camera_forward()
			var sp := player.get_world_3d().direct_space_state
			var q := PhysicsRayQueryParameters3D.create(o, o + d * 100.0)
			q.exclude = [player.get_rid()]
			var h := sp.intersect_ray(q)
			print("    第 %2d 发: 起点 %s 方向 %s → %s" % [
				n, str(o.snappedf(0.01)), str(d.snappedf(0.01)),
				("命中 " + str(h.collider)) if h else "空"]) )

	# 阶段 A：等弹药真的掉到 0，同时追踪靶子最低血量
	# （靶子 100 血、每发 18，第 1 发就打死了，4 秒后还会重生 —— 所以必须看过程最低值）
	var guard := 0
	var min_hp := 999.0
	var saw_dead := false
	while guard < 4000:
		await process_frame
		guard += 1
		var t := game.get_node("Target1") as Target
		if t.health < min_hp:
			min_hp = t.health
		if t._dead:
			saw_dead = true
		if weapon.current_ammo <= 0 and not weapon.is_reloading():
			break
	print("  弹药归零（第 %d 帧）  _trigger = %s" % [guard, str(weapon._trigger)])
	print("  连发后：spring.rotation.x = %.3f  相机前方 = %s" % [
		player.spring.rotation.x, str(player.camera_forward().snappedf(0.01))])
	print("  靶子过程最低血量 = %.0f   出现过击毁状态 = %s" % [min_hp, str(saw_dead)])
	_check(weapon.current_ammo <= 0, "60 发全部打完（current_ammo=%d）" % weapon.current_ammo)

	# 阶段 B：等自动换弹被触发
	var saw_reload := false
	guard = 0
	while guard < 600:
		await process_frame
		guard += 1
		if weapon.is_reloading():
			saw_reload = true
			break
	print("  自动换弹触发 = %s（第 %d 帧）  _trigger = %s" % [
		str(saw_reload), guard, str(weapon._trigger)])
	_check(saw_reload, "打空后自动进入换弹（没让玩家手动按 R）")
	_check(weapon._trigger, "换弹期间左键仍是「按住」状态")

	# 阶段 C：等换弹结束
	guard = 0
	while guard < 1500:
		await process_frame
		guard += 1
		if not weapon.is_reloading():
			break
	print("  换弹结束（第 %d 帧）  弹药 = %d / %d" % [
		guard, weapon.current_ammo, weapon.magazine_size])
	_check(weapon.current_ammo == weapon.magazine_size, "换弹后满弹")
	_check(weapon._trigger, "换弹结束时左键仍按住")

	# 阶段 D：不松手，看是否自动续射
	var shots_a := weapon._shot_index
	guard = 0
	while guard < 300:
		await process_frame
		guard += 1
		if weapon._shot_index > shots_a:
			break
	var gained := weapon._shot_index - shots_a
	print("  换弹后未松手，%d 帧内又打了 %d 发" % [guard, gained])
	_check(gained > 0, "换完弹自动继续射击（不用再点一次鼠标）")

	# 阶段 E：松开后应停火
	weapon.trigger_up()
	await _wait(30)
	var s1 := weapon._shot_index
	await _wait(80)
	_check(weapon._shot_index == s1, "松开左键后停火（%d 发 → %d 发）" % [s1, weapon._shot_index])

	print("\n  靶子过程最低血量 %.0f（开场 %.0f）  出现过击毁 = %s" % [
		min_hp, hp_before, str(saw_dead)])
	_check(min_hp < hp_before, "连发期间弹道正确命中靶子（血量掉到 %.0f）" % min_hp)
	print("\n================ 结果 ================")
	print("失败 %d 项" % _fail)
	quit(1 if _fail > 0 else 0)


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  [PASS] ", label)
	else:
		print("  [FAIL] ", label)
		_fail += 1


func _face(skel: Skeleton3D) -> Vector3:
	var xf := skel.global_transform
	var h: Vector3 = xf * skel.get_bone_global_pose(skel.find_bone("Bip001 Head")).origin
	var l: Vector3 = skel.get_bone_global_pose(skel.find_bone("Bip001 eye_L")).origin
	var r: Vector3 = skel.get_bone_global_pose(skel.find_bone("Bip001 eye_R")).origin
	var e: Vector3 = xf * ((l + r) * 0.5)
	return _flat(e - h).normalized()


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _wait(n: int) -> void:
	for _i in maxi(n, 1):
		await process_frame
