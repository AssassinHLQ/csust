extends SceneTree
## 探针：只量「抽点 → 凸包」这一步有多慢，不跑整套自检。
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_collision_time.gd -- <模型...>


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var paths: Array = OS.get_cmdline_user_args()
	if paths.is_empty():
		print("!! 请给模型路径")
		quit(1)
		return
	for p in paths:
		var path := String(p)
		if not ResourceLoader.exists(path):
			print("!! 没有 %s" % path)
			continue
		var inst: Node3D = (load(path) as PackedScene).instantiate()
		root.add_child(inst)
		await process_frame
		var meshes: Array[MeshInstance3D] = []
		var stack: Array[Node] = [inst]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
				meshes.append(n as MeshInstance3D)
			for c in n.get_children():
				stack.append(c)
		var t0 := Time.get_ticks_msec()
		var faces := 0
		var parts := 0
		for mi in meshes:
			var pts := _sample(mi.mesh, 600)
			if pts.size() < 8:
				continue
			var hull := ConvexPolygonShape3D.new()
			hull.set_points(pts)
			faces += hull.get_faces().size() / 3
			parts += 1
		var dt := Time.get_ticks_msec() - t0
		print("[time] %-46s 网格 %2d  凸包 %2d  面 %5d  用时 %4d ms" % [
			path.get_file(), meshes.size(), parts, faces, dt])
		inst.queue_free()
		await process_frame
	quit(0)


func _sample(mesh: Mesh, budget: int) -> PackedVector3Array:
	var verts := PackedVector3Array()
	if mesh is ArrayMesh:
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			var v = arr[Mesh.ARRAY_VERTEX]
			if v != null:
				verts.append_array(v)
	var out := PackedVector3Array()
	if verts.is_empty():
		return out
	var stride := maxi(1, verts.size() / maxi(budget, 1))
	var i := 0
	while i < verts.size():
		out.append(verts[i])
		i += stride
	out.append(verts[verts.size() - 1])
	return out
