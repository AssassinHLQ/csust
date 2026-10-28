extends SceneTree
## 把校园泼溅的**世界坐标**点云导出成 PLY，喂给 collider-forge / 3dgs_collider.exe。
##   _tools/run_probe.sh res://scripts/_export_campus_ply.gd -- [--step=4] [--out=C:/...]
##
## 坐标：直接用场景里 splat_node 的 global_transform（含 3 倍缩放/校平/平移），
## 所以 collider-forge 生成的碰撞网格回到 Godot 里就是世界坐标，不用再对位。
## 过滤：地面以下 1 m、55 m 以上、以及地板矩形之外的点都丢掉（Poisson 怕离群）。

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var step := 4
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join("_arisu_captures").path_join("campus_world.ply")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--step="):
			step = maxi(1, int(a.substr(7)))
		elif a.begins_with("--out="):
			out = a.substr(6)

	var level := (load("res://scenes/next_level.tscn") as PackedScene).instantiate()
	root.add_child(level)
	var campus := level.get_node("Campus")
	campus.call("force_start")
	var t0 := Time.get_ticks_msec()
	while not bool(campus.call("is_ready")) and Time.get_ticks_msec() - t0 < 180000:
		await process_frame
	if not bool(campus.call("is_ready")):
		print("[ply] 加载失败")
		quit(1)
		return
	var node := campus.get("splat_node") as Node3D
	var res = node.get("gaussian")
	var xyz: PackedVector3Array = res.get("xyz")
	var xf := node.global_transform
	var box: AABB = campus.call("content_world_aabb")
	var lo := Vector3(box.position.x + 0.5, -1.0, box.position.z + 0.5)
	var hi := Vector3(box.position.x + box.size.x - 0.5, 55.0,
		box.position.z + box.size.z - 0.5)
	print("[ply] 采样 step=%d，保留 y∈[%.1f, %.1f]，xy 盒 %s..%s"
		% [step, lo.y, hi.y, str(Vector2(lo.x, lo.z)), str(Vector2(hi.x, hi.z))])

	var pts := PackedFloat32Array()
	var i := 0
	while i < xyz.size():
		var w: Vector3 = xf * xyz[i]
		if w.y >= lo.y and w.y <= hi.y \
				and w.x >= lo.x and w.x <= hi.x and w.z >= lo.z and w.z <= hi.z:
			pts.append(w.x)
			pts.append(w.y)
			pts.append(w.z)
		i += step
	var n := pts.size() / 3
	print("[ply] %d / %d 点 → %s" % [n, xyz.size(), out])

	var f := FileAccess.open(out, FileAccess.WRITE)
	if f == null:
		print("[ply] 打不开输出：%s" % out)
		quit(1)
		return
	var header := "ply\nformat binary_little_endian 1.0\nelement vertex %d\nproperty float x\nproperty float y\nproperty float z\nend_header\n" % n
	f.store_buffer(header.to_utf8_buffer())
	f.store_buffer(pts.to_byte_array())
	f.close()
	var size := FileAccess.get_file_as_bytes(out).size()
	print("[ply] 写好了：%.1f MB" % (float(size) / 1048576.0))
	quit(0)
