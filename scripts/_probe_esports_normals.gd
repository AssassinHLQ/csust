extends SceneTree
## 查：GLB 里的网格法线到底朝内还是朝外。
## 做法：对每个网格，取三角面重心 + 法线，看「重心 → 法线方向」是否指向包围盒外。
## 若绝大多数网格的外向占比 < 40%，说明法线整体反了。
##
##   & godot --script res://scripts/_probe_esports_normals.gd -- --splat=off --story=off

const SCENE := "res://scenes/esports_room.tscn"


func _initialize() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-4000, -4000))
	_run.call_deferred()


func _run() -> void:
	for _i in 2:
		await process_frame
	var room: Node3D = load(SCENE).instantiate()
	root.add_child(room)
	for _i in 6:
		await process_frame

	var total_faces := 0
	var outward := 0
	var inward := 0
	var degenerate := 0
	var rows := []

	for mi in room.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not (m.mesh is ArrayMesh):
			continue
		var am := m.mesh as ArrayMesh
		var box := am.get_aabb()
		var bc := box.get_center()
		var s := box.size
		var ext := maxf(s.x, maxf(s.y, s.z))
		for si in am.get_surface_count():
			var arr := am.surface_get_arrays(si)
			var verts = arr[Mesh.ARRAY_VERTEX]
			var norms = arr[Mesh.ARRAY_NORMAL]
			var idx = arr[Mesh.ARRAY_INDEX]
			if verts == null or idx == null:
				continue
			if norms == null:
				degenerate += (idx as PackedInt32Array).size() / 3
				continue
			var n_out := 0
			var n_in := 0
			var n := (idx as PackedInt32Array).size() / 3
			# 每 7 个面采 1 个，够统计
			var step := maxi(1, n / 4000)
			for f in range(0, n, step):
				var i0 := (idx as PackedInt32Array)[f * 3]
				var i1 := (idx as PackedInt32Array)[f * 3 + 1]
				var i2 := (idx as PackedInt32Array)[f * 3 + 2]
				var v0: Vector3 = (verts as PackedVector3Array)[i0]
				var v1: Vector3 = (verts as PackedVector3Array)[i1]
				var v2: Vector3 = (verts as PackedVector3Array)[i2]
				var cen := (v0 + v1 + v2) / 3.0
				var nrm: Vector3 = (norms as PackedVector3Array)[i0]
				if nrm.length_squared() < 1e-12:
					n_in += 1
					continue
				nrm = nrm.normalized()
				# 从盒子中心指向面的方向
				var outward_dir := cen - bc
				if outward_dir.length() < ext * 0.02:
					continue
				if nrm.dot(outward_dir.normalized()) > 0.0:
					n_out += 1
				else:
					n_in += 1
			total_faces += n_out + n_in
			outward += n_out
			inward += n_in
			if n_out + n_in > 0:
				rows.append([m.name, n_out, n_in, 100.0 * n_out / float(n_out + n_in)])

	# 只打印最异常的 15 件（外向占比最低、面数最多的）
	rows.sort_custom(func(a, b):
		var ra = a[3]
		var rb = b[3]
		if absf(ra - rb) > 1.0:
			return ra < rb
		return (a[1] + a[2]) > (b[1] + b[2]))

	print("======== NORMAL AUDIT ========")
	print("[norm] sampled_faces=%d  outward=%d  inward=%d  no_normal=%d"
		% [total_faces, outward, inward, degenerate])
	if total_faces > 0:
		print("[norm] OUTWARD RATIO = %.1f%%" % (100.0 * outward / float(total_faces)))
	print("-------- worst 18 meshes (lowest outward ratio) --------")
	for r in rows.slice(0, 18):
		print("[norm] %-46s out=%-6d in=%-6d out%%=%.1f" % [r[0], r[1], r[2], r[3]])
	print("-------- best 8 meshes --------")
	for r in rows.slice(maxi(0, rows.size() - 8)):
		print("[norm] %-46s out=%-6d in=%-6d out%%=%.1f" % [r[0], r[1], r[2], r[3]])

	quit(0)
