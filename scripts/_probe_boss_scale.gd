extends SceneTree
## 诊断：这个 FBX 的真实尺度到底是多少（用顶点量，不信任 get_aabb），
## 以及模型的朝向、骨骼是否真的在动。
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_boss_scale.gd

const SCENE := "res://models/boss/优香霸王龙.fbx"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	await process_frame

	print("================ 1. 各节点的缩放 ================")
	print("  根 %s scale = %s" % [scene.name, str(scene.scale.snappedf(0.0001))])
	for m in _all(scene, "Node3D"):
		var n := m as Node3D
		var s := n.global_transform.basis.get_scale()
		if absf(s.x - 1.0) > 0.001 or absf(s.y - 1.0) > 0.001 or absf(s.z - 1.0) > 0.001:
			print("  %-24s global scale = %s" % [n.name, str(s.snappedf(0.0001))])

	print("\n================ 2. 顶点实测包围盒（按 mesh 节点的 global transform）================")
	var total := AABB()
	var first := true
	for m in _all(scene, "MeshInstance3D"):
		var mi := m as MeshInstance3D
		if mi.mesh == null or not (mi.mesh is ArrayMesh):
			continue
		var box := AABB()
		var has := false
		var n_verts := 0
		var am := mi.mesh as ArrayMesh
		for s in am.get_surface_count():
			var arr := am.surface_get_arrays(s)
			if arr.size() <= Mesh.ARRAY_VERTEX or arr[Mesh.ARRAY_VERTEX] == null:
				continue
			var verts := arr[Mesh.ARRAY_VERTEX] as PackedVector3Array
			n_verts += verts.size()
			var step := maxi(1, verts.size() / 4000)
			var i := 0
			while i < verts.size():
				var w: Vector3 = mi.global_transform * verts[i]
				if has:
					box = box.expand(w)
				else:
					box = AABB(w, Vector3.ZERO)
					has = true
				i += step
		if has:
			print("  %-24s 顶点 %6d  世界包围盒 size %s" % [
				mi.name, n_verts, str(box.size.snappedf(0.01))])
			total = box if first else total.merge(box)
			first = false
	print("\n  合并后 size = %s" % str(total.size.snappedf(0.01)))
	print("  合并后 范围 y %.2f … %.2f   x %.2f … %.2f   z %.2f … %.2f" % [
		total.position.y, total.position.y + total.size.y,
		total.position.x, total.position.x + total.size.x,
		total.position.z, total.position.z + total.size.z])
	var h := maxf(total.size.y, 0.0001)
	print("  → 若目标是 6 m 高的 Boss：scale = %.4f" % (6.0 / h))

	print("\n================ 3. 骨骼姿势（原始值）===============")
	var skel := (_all(scene, "Skeleton3D")[0]) as Skeleton3D
	print("  Skeleton3D global scale = %s" % str(skel.global_transform.basis.get_scale().snappedf(0.0001)))
	print("  骨骼数 = %d" % skel.get_bone_count())
	for i in [0, 1, 2, 3, 4, 5, 10, 40, 72]:
		if i < skel.get_bone_count():
			var p := skel.get_bone_global_pose(i).origin
			print("    [%2d] %-22s pose.origin = %s" % [
				i, skel.get_bone_name(i), str(p.snappedf(0.01))])
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for i in skel.get_bone_count():
		var p2 := skel.get_bone_global_pose(i).origin
		lo = lo.min(p2)
		hi = hi.max(p2)
	print("  骨骼包围盒（骨架本地）size = %s" % str((hi - lo).snappedf(0.01)))
	print("  ⚠️ 若这里是 0，说明骨骼没被求值（需要 skeleton 在树里且已经 process 过）")

	quit(0)


func _all(node: Node, cls: String) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.is_class(cls):
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out
