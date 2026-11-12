extends SceneTree
## 验收：电竞房那个柜子**人能不能真走进去**（真物理推，不是射线）。
##
## 用户 2026-11-12：「这个电竞房柜子要可以进去」。
## 柜子原来被 `P0057_0..7` 八个实心盒填满，`esports_collision.gd::_open_cabinet()`
## 挖掉下面三层、保留柜顶、补两侧薄墙。
##
## 判据（和 `_verify_esports_door_walk.gd` 一样只信真物理）：
##   从柜子前后各 1.5 m 处朝柜内推，玩家最终是否**进到柜子的 z 范围里**。
##
##   godot --path . --script res://scripts/_verify_esports_cabinet_walk.gd -- --splat=off --story=off

const OFF := preload("res://scripts/offscreen_window.gd")
const CABINET_MESH := "M_Scene_-_Root"
const PUSH_FRAMES := 90

var _pass := 0
var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await OFF.apply(self, Vector2i(1280, 720))
	for _i in 3:
		await process_frame
	print("═══ 电竞房柜子 · 真物理能进验收 ═══\n")

	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	root.add_child(game)
	for _f in 150:
		await process_frame
	paused = false
	for _f in 30:
		await process_frame

	var room := game.get_node_or_null("EsportsRoom") as Node3D
	var player := game.get("_player") as CharacterBody3D
	_check(room != null, "场景里有 EsportsRoom")
	_check(player != null, "拿得到玩家")
	if room == null or player == null:
		_summary()
		quit(1)
		return
	room.visible = true
	for _f in 5:
		await process_frame

	# 柜子的世界包围盒
	var cab := AABB()
	var found := false
	var glb := room.get_node_or_null("Room")
	for mi in glb.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m == null or m.mesh == null or String(m.name) != CABINET_MESH:
			continue
		var b: AABB = m.global_transform * m.mesh.get_aabb()
		cab = b if not found else cab.merge(b)
		found = true
	_check(found, "找得到柜子网格 %s" % CABINET_MESH)
	if not found:
		_summary()
		quit(1)
		return
	print("柜子 x %.2f~%.2f  y %.2f~%.2f  z %.2f~%.2f\n"
		% [cab.position.x, cab.end.x, cab.position.y, cab.end.y,
			cab.position.z, cab.end.z])

	# 柜子里的实心盒应该已经被禁用：数一下「还活着且落在柜内」的盒子
	var auto_col := room.get_node_or_null("BakedCollision/AutoCol") as Node3D
	var alive_inside := 0
	var ceiling_top := -999.0
	for c in auto_col.get_children():
		var cs := c as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D) or cs.disabled:
			continue
		var half: Vector3 = cs.global_basis.get_scale().abs() \
			* (cs.shape as BoxShape3D).size * 0.5
		var cb := AABB(cs.global_position - half, half * 2.0)
		if cb.position.x >= cab.position.x - 0.02 and cb.end.x <= cab.end.x + 0.02 \
				and cb.position.z >= cab.position.z - 0.02 and cb.end.z <= cab.end.z + 0.02 \
				and cb.position.y >= cab.position.y - 0.02 and cb.end.y <= cab.end.y + 0.02:
			# 比柜内净高还大的盒子才算「还堵着」；矮的是我们补的侧墙
			if cb.size.y > 0.6 and minf(cb.size.x, cb.size.z) > 0.3:
				alive_inside += 1
				ceiling_top = maxf(ceiling_top, cb.end.y)
	_check(alive_inside <= 2, "柜内只剩柜顶层（实心盒剩 %d 个）" % alive_inside)

	# 前后各推一次
	var cx := cab.get_center().x
	var cz := cab.get_center().z
	var z_lo := cab.position.z
	var z_hi := cab.end.z
	# ⚠️ 只测**正面（-Z）**能进；+Z 那侧紧贴着房间的墙 `P0003_0`（z 19.48~19.71）——
	#    柜子背面是墙，那一侧本来就进不去，测它没有意义（第一版当成失败项，是判据错）。
	#    改成测「侧面横推进不去」，用来验证补的那两片薄墙真的挡住了。
	player.global_position = Vector3(cx, 0.9, z_lo - 1.5)
	player.velocity = Vector3.ZERO
	await _wait(12)
	var inside := 0
	for _f in PUSH_FRAMES:
		player.velocity = Vector3(0, player.velocity.y, 3.0)
		player.move_and_slide()
		await physics_frame
		var p := player.global_position
		if p.z > z_lo + 0.05 and p.z < z_hi - 0.05:
			inside += 1
	var p2 := player.global_position
	print("② %-26s 推进后 z=%.2f（柜内 z %.2f~%.2f）  柜内帧数 %d"
		% ["正面（-Z）推进", p2.z, z_lo, z_hi, inside])
	_check(inside >= 5, "正面（-Z）能走进柜子")

	# 侧面横推：应该被薄墙挡住，进不到柜内
	player.global_position = Vector3(cab.end.x + 1.2, 0.9, cz)
	player.velocity = Vector3.ZERO
	await _wait(12)
	var side_in := 0
	for _f in PUSH_FRAMES:
		player.velocity = Vector3(-3.0, player.velocity.y, 0)
		player.move_and_slide()
		await physics_frame
		var p := player.global_position
		if p.x < cab.end.x - 0.10 and p.x > cab.position.x + 0.10:
			side_in += 1
	print("② %-26s 推进后 x=%.2f（柜内 x %.2f~%.2f）  柜内帧数 %d"
		% ["侧面（+X）横推", player.global_position.x, cab.position.x, cab.end.x, side_in])
	_check(side_in == 0, "侧面被薄墙挡住（横推进不去）")

	# 出图：柜子正面 + 柜内视角
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("_esports_cabinet")
	DirAccess.make_dir_recursive_absolute(out)
	var cam := Camera3D.new()
	cam.far = 200.0
	game.add_child(cam)
	for shot in [
		{"n": "front", "p": Vector3(cx + 3.2, 1.7, cz - 4.2), "t": Vector3(cx, 1.4, cz)},
		{"n": "inside", "p": Vector3(cx, 1.6, cz - 0.1), "t": Vector3(cx, 1.3, cz + 2.0)},
	]:
		cam.fov = 62.0
		cam.global_position = shot["p"]
		cam.look_at(shot["t"], Vector3.UP)
		cam.make_current()
		await _wait(6)
		cam.make_current()
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out.path_join("%s.png" % String(shot["n"])))
			print("  [img] %s" % out.path_join("%s.png" % String(shot["n"])))
	_summary()
	quit(0)


func _wait(n: int) -> void:
	for _i in n:
		await process_frame


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
		print("  ✓ %s" % what)
	else:
		_fail += 1
		print("  ✗ %s" % what)


func _summary() -> void:
	print("\n═══ 通过 %d / 失败 %d ═══" % [_pass, _fail])
