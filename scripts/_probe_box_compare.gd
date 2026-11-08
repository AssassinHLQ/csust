extends SceneTree
## 量每个墙盒：`BoxShape3D.size` vs 变换后的真实世界 AABB。
##
## 怀疑点：`WallZNegB` 带 90° 旋转，`size` 和 `basis.get_scale()` 相乘算出来的
## 不是真实世界尺寸。`splat_scene.gd::_room_xz_from_walls()` 就是这么算的，
## 而 `_probe_wall_inner.gd` 用的是 `Transform3D * AABB(...)`（正确做法），
## 两者差了 1.24 m。这里把每个盒子的两种算法并排列出来对账。

const SCENE := "res://scenes/game.tscn"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load(SCENE) as PackedScene
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame

	var col: Node = scene.get_node_or_null("Room609/RoomCollision")
	print("[cmp] %-12s %-22s %-22s %-22s" % ["名字", "size", "scale 算法(x_min,x_max)", "真实 AABB(x_min,x_max)"])
	var lo_bad := Vector2(INF, INF)
	var hi_bad := Vector2(-INF, -INF)
	var lo_good := Vector2(INF, INF)
	var hi_good := Vector2(-INF, -INF)
	for c in col.get_children():
		var cs := c as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		var raw: Vector3 = (cs.shape as BoxShape3D).size
		var g := cs.global_transform
		var scale := g.basis.get_scale()

		# 算法 A（splat_scene 用的）：size * 0.5 * get_scale()
		var xs_a := raw * 0.5 * scale
		var ctr := g.origin
		var ax_min := ctr.x - xs_a.x
		var ax_max := ctr.x + xs_a.x
		var az_min := ctr.z - xs_a.z
		var az_max := ctr.z + xs_a.z

		# 算法 B（正确）：Transform3D * AABB
		var b: AABB = g * AABB(-raw * 0.5, raw)

		print("[cmp] %-12s %-22s (%.3f, %.3f)        (%.3f, %.3f)" % [
			cs.name, str(raw),
			ax_min, ax_max,
			b.position.x, b.position.x + b.size.x])
		print("[cmp]      旋转? basis=%s" % str(g.basis))

		lo_bad = lo_bad.min(Vector2(ax_min, az_min))
		hi_bad = hi_bad.max(Vector2(ax_max, az_max))
		lo_good = lo_good.min(Vector2(b.position.x, b.position.z))
		hi_good = hi_good.max(Vector2(b.position.x + b.size.x, b.position.z + b.size.z))

	print("[cmp] ----")
	print("[cmp] 算法 A（scale 相乘）: x %.3f~%.3f  z %.3f~%.3f" % [lo_bad.x, hi_bad.x, lo_bad.y, hi_bad.y])
	print("[cmp] 算法 B（Transform*AABB）: x %.3f~%.3f  z %.3f~%.3f" % [lo_good.x, hi_good.x, lo_good.y, hi_good.y])
	print("[cmp] 完成")
	quit(0)
