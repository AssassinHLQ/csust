extends SceneTree
## 探针：小屋里的灯到底悬在哪儿。
##   godot --path . --script res://scripts/_probe_hut_lamp.gd

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var hut := (load("res://scenes/mesh_hut.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(hut)
	for _i in 20:
		await process_frame

	# 屋顶底面：Roof 中心 5.80、厚 0.20 → 5.70（CSG 里没有 MeshInstance 可量）
	var roof_under := 5.70
	print("屋顶底面 y = %.2f" % roof_under)

	for n in ["HutLamp", "LampCord", "LampPost/Pole", "LampPost/Head"]:
		var mi := hut.get_node_or_null(n) as MeshInstance3D
		if mi == null:
			print("%-14s <没有这个节点>" % n)
			continue
		var a: AABB = mi.global_transform * mi.mesh.get_aabb()
		print("%-14s y %.3f ~ %.3f   到屋顶底面 %+.3f m" % [
			n, a.position.y, a.end.y, roof_under - a.end.y])

	# 灯正下方 4 m 内有没有东西托着？（打不到 = 纯悬空）
	var space := (hut.get_world_3d() as World3D).direct_space_state
	for probe_y in [2.45, 4.55]:
		var from := Vector3(0, probe_y - 0.06, 0)
		var q := PhysicsRayQueryParameters3D.create(from, Vector3(0, probe_y - 4.0, 0))
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			print("y=%.2f 向下 4 m：什么都没有（悬空）" % probe_y)
		else:
			print("y=%.2f 向下打中 %s  @ y = %.3f（落差 %.3f m）" % [
				probe_y, (hit["collider"] as Node).name, hit["position"].y,
				probe_y - hit["position"].y])

	quit()
