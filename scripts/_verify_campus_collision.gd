extends SceneTree
## 校园碰撞对比：新（剪掉贴地层的网格）vs 旧（原始 Poisson 网格）。
##   _tools/run_probe.sh res://scripts/_verify_campus_collision.gd
##
## 同一套指标：
##   · 主路通行：1 m 高四周 0.3 m 打探针，撞到东西的比例
##   · 主路落点：x=-6/0/6、z 每 30 m，从 1.5 m 落下来，看停在哪

const LEVEL := "res://scenes/next_level.tscn"
const OLD_MESH := "res://scenes/campus_collision_mesh.scn"

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var level := (load(LEVEL) as PackedScene).instantiate()
	root.add_child(level)
	await process_frame
	await process_frame
	var campus := level.get_node_or_null("Campus")
	if campus != null:
		campus.set("auto_start", false)
		campus.set_process(false)

	var col := level.get_node_or_null("CampusCollision")
	print("[cmp] 当前碰撞节点 = %s" % (col.name if col != null else "无"))
	await physics_frame
	await _measure(level, "新（剪掉 1 m 以下的贴地层）")

	if col != null:
		col.queue_free()
		await process_frame
	var old := (load(OLD_MESH) as PackedScene).instantiate()
	old.name = "CampusCollision"
	level.add_child(old)
	await process_frame
	await physics_frame
	await _measure(level, "旧（原始 Poisson 网格）")
	quit(0)


func _measure(level: Node, title: String) -> void:
	var col := level.get_node_or_null("CampusCollision")
	var tris := 0
	if col != null:
		for b in col.find_children("*", "CollisionShape3D", true, false):
			var cs := b as CollisionShape3D
			if cs.shape is ConcavePolygonShape3D:
				tris += (cs.shape as ConcavePolygonShape3D).get_faces().size() / 3
	print("[cmp] ── %s：%d 三角 ──" % [title, tris])

	var space: PhysicsDirectSpaceState3D = level.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = 1
	var blocked := 0
	var total := 0
	for x in [-6.0, 0.0, 6.0]:
		var z := -85.0
		while z > -545.0:
			total += 1
			for d in [Vector3(0.3, 0, 0), Vector3(-0.3, 0, 0), Vector3(0, 0, 0.3), Vector3(0, 0, -0.3)]:
				q.from = Vector3(x, 1.0, z)
				q.to = Vector3(x, 1.0, z) + d
				if not space.intersect_ray(q).is_empty():
					blocked += 1
					break
			z -= 5.0
	print("[cmp]   主路 1 m 高被挡：%d / %d（%.1f%%）" % [blocked, total, 100.0 * blocked / total])

	var player := level.get_node_or_null("Player") as CharacterBody3D
	if player == null:
		return
	var ys: Array[float] = []
	for x in [-6.0, 0.0, 6.0]:
		var z := -90.0
		while z > -540.0:
			player.global_position = Vector3(x, 1.5, z)
			player.velocity = Vector3.ZERO
			for i in 40:
				await physics_frame
			ys.append(player.global_position.y)
			z -= 30.0
	ys.sort()
	var near := 0
	var high := 0
	var low := 0
	var mean := 0.0
	for y in ys:
		mean += y
		if absf(y + 0.02) <= 0.1:
			near += 1
		if y > 0.5:
			high += 1
		if y < -0.3:
			low += 1
	print("[cmp]   落点 %d 个：贴平板 %d、离地 >0.5 m %d、陷下去 >0.3 m %d；均值 %.2f  范围 %.2f ~ %.2f"
		% [ys.size(), near, high, low, mean / ys.size(), ys[0], ys[ys.size() - 1]])
