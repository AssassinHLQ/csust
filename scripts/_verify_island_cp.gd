extends SceneTree
## 验：结束平台存档点固定在台面上；摔落复活后站在大平台上，不会生成到板子底下。
##   godot --path . --headless --script res://scripts/_verify_island_cp.gd
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var lvl := (load("res://scenes/parkour.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(lvl)
	var player := (load("res://scenes/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	root.add_child(player)
	for _i in 20:
		await physics_frame

	# ① 半空 / 没落地 → 不存档
	player.global_position = Vector3(-590.95, 12.0, -9.5)
	player.velocity = Vector3.ZERO
	for _i in 10:
		await physics_frame
	var early: Vector3 = lvl.get("_island_cp")
	print("[island] 半空时存档点 = %s（期望 inf，不记半空坐标）" % str(early))

	# ② 落到台面 → 记死的大平台安全点（不是玩家踩到的那一点）
	player.global_position = Vector3(-590.95, 8.6, -9.5)
	player.velocity = Vector3.ZERO
	for _i in 60:
		await physics_frame
	var cp: Vector3 = lvl.get("_island_cp")
	var consts0: Dictionary = lvl.get_script().get_script_constant_map()
	var center: Vector3 = consts0.get("ISLAND_CENTER", Vector3.ZERO)
	var top_y := float(consts0.get("ISLAND_TOP_Y", 8.0))
	var inside := absf(cp.x - center.x) < 7.0 and absf(cp.z - center.z) < 7.0
	print("[island] 站上平台 = %s  y=%.2f" % [
		str(player.is_on_floor()), player.global_position.y])
	print("[island] 存档点 = %s（期望 (-587.50, 8.08, -8.50)）" % str(cp.snappedf(0.01)))
	print("[island] 存档点在台面上 = %s（y %.2f ≥ %.2f）、在平台内 = %s" % [
		str(cp.y >= top_y), cp.y, top_y, str(inside)])

	# ③ 摔下去 → 被救回存档点，并且是**站着**的（不会继续往下掉）
	player.global_position = Vector3(-300.0, 0.0, 0.0)
	player.velocity = Vector3.ZERO
	lvl.call("_rescue")
	for _i in 45:
		await physics_frame
	var after: Vector3 = player.global_position
	print("[island] 复活后位置 = %s  y=%.2f  on_floor=%s（期望 y ≈ 8.0、on_floor=true）" % [
		str(after.snappedf(0.01)), after.y, str(player.is_on_floor())])
	print("[island] 结论：%s" % ("OK 站在大平台上" if after.y > top_y - 0.1 and player.is_on_floor()
		else "FAIL 又生成到平台下面了"))

	var sb = load("res://scripts/squash_boss.gd").new()
	var consts: Dictionary = sb.get_script().get_script_constant_map()
	print("[squash] 技能数 = %d（期望 4）  interval=%.2f  start_delay=%.2f  windup=%.2f" % [
		int(consts.get("SKILL_COUNT", -1)), float(sb.get("attack_interval")),
		float(sb.get("attack_start_delay")), float(sb.get("windup_time"))])
	for fn in ["_skill_slam", "_skill_dash", "_skill_quake"]:
		print("[squash] %s 存在 = %s" % [fn, str(sb.has_method(fn))])
	sb.free()
	quit(0)
