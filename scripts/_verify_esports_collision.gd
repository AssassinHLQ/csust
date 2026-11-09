extends SceneTree
## 查电竞房碰撞的**实际状态**：盒子数量 + 射线实测。
##
##   godot --path . --headless --script res://scripts/_verify_esports_collision.gd
##
## ⚠️ 重点查一件事：2026-11-09 本喵给电竞房加了三档 LOD
##    （`esports_lod.gd` 会实例化 `HighModel` / `MidModel`），
##    而 `esports_collision.gd` 是用 `find_children("*", "MeshInstance3D")`
##    **遍历全部网格**的 —— 现在会同时扫到三档、**碰撞盒数量 ×3**。
##    这个脚本把它量出来。

const GAME := "res://scenes/game.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := (load(GAME) as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	for _i in 20:
		await process_frame

	var room := game.get_node_or_null("EsportsRoom") as Node3D
	if room == null:
		print("[ecol] !! 没有 EsportsRoom")
		quit(1)
		return

	# ① 三档网格数
	for nm in ["Room", "Lod/HighModel", "Lod/MidModel"]:
		var n := room.get_node_or_null(nm)
		if n == null:
			print("[ecol] %-16s 不存在" % nm)
			continue
		print("[ecol] %-16s 网格 %3d 个  visible=%s" % [
			nm, n.find_children("*", "MeshInstance3D", true, false).size(),
			str((n as Node3D).visible)])

	# ② 碰撞盒数量
	var boxes := 0
	var bodies := 0
	for c in room.get_children():
		if not (c is StaticBody3D and String(c.name).begins_with("AutoCol")):
			continue
		bodies += 1
		boxes += c.get_children().size()
	print("[ecol] AutoCol 碰撞体 %d 个，共 %d 个形状" % [bodies, boxes])
	# 顺带看 `esports_collision.gd` 自己报的数
	print("[ecol] （上面日志里 `[EsportsCol] 共建 N 个盒子碰撞` 是脚本自报）")

	# ③ 射线实测：墙 / 地 / 门
	var space := room.get_world_3d().direct_space_state
	var pos := room.global_position
	print("[ecol] EsportsRoom 世界位置 %s 旋转 %s" % [
		str(pos.snappedf(0.01)), str(room.global_rotation_degrees.snappedf(0.1))])
	# 用房间自己的世界包围盒算采样点
	var box := AABB()
	var first := true
	var low := room.get_node_or_null("Room")
	if low != null:
		for m in low.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			if mi.mesh == null:
				continue
			var a: AABB = mi.global_transform * mi.mesh.get_aabb()
			box = a if first else box.merge(a)
			first = false
	print("[ecol] 房间世界 AABB pos=%s size=%s" % [
		str(box.position.snappedf(0.01)), str(box.size.snappedf(0.01))])
	var c := box.position + box.size * 0.5

	# 地面：从中心上方朝下
	var g := space.intersect_ray(PhysicsRayQueryParameters3D.create(
		Vector3(c.x, c.y + 1.0, c.z), Vector3(c.x, box.position.y - 1.0, c.z), 1))
	print("[ecol] 地面射线 → %s" % ("空（会掉下去！）" if g.is_empty()
		else "命中 y=%.2f %s" % [(g.get("position") as Vector3).y, g.get("collider")]))

	# 天花板：朝上
	var up := space.intersect_ray(PhysicsRayQueryParameters3D.create(
		Vector3(c.x, c.y + 1.0, c.z), Vector3(c.x, box.position.y + box.size.y + 2.0, c.z), 1))
	print("[ecol] 天花板射线 → %s" % ("空" if up.is_empty() else "命中 %s" % up.get("collider")))

	# 四面墙：从中心朝外
	var dirs := {
		"西": Vector3(-1, 0, 0), "东": Vector3(1, 0, 0),
		"南": Vector3(0, 0, -1), "北": Vector3(0, 0, 1),
	}
	for k in dirs:
		var d: Vector3 = dirs[k]
		var reach := maxf(box.size.x, box.size.z) + 2.0
		var h := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			Vector3(c.x, c.y, c.z), Vector3(c.x, c.y, c.z) + d * reach, 1))
		print("[ecol] %s墙射线 → %s" % [k, "空（能穿出去！）" if h.is_empty()
			else "命中 %s" % h.get("collider")])

	# ④ **可走性**：在胸口高度 y=0.9 铺 0.5 m 网格，看有多少点被碰撞占住
	#    使用者 2026-11-09：「碰撞错了」——大 AABB 盒把房间中间堵死，人走不进去。
	print("[ecol] ── 可走性（y=0.9 胸口高度，0.5 m 网格）──")
	var free_n := 0
	var hit_n := 0
	var x := box.position.x
	while x <= box.position.x + box.size.x:
		var z := box.position.z
		while z <= box.position.z + box.size.z:
			var p := Vector3(x, 0.9, z)
			var q := PhysicsPointQueryParameters3D.new()
			q.position = p
			q.collision_mask = 1
			var found := space.intersect_point(q)
			if found.is_empty():
				free_n += 1
			else:
				hit_n += 1
			z += 0.5
		x += 0.5
	var total := free_n + hit_n
	print("[ecol]   可走 %d / %d = %.0f%%（被占 %d）" % [
		free_n, total, 100.0 * float(free_n) / maxf(float(total), 1.0), hit_n])

	print("[ecol] 完成")
	quit(0)
