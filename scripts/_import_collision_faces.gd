extends SceneTree
## 把 Python 处理过的原始三角形（float32 三元组序列）变成碰撞场景 .scn。
##   _tools/run_probe.sh res://scripts/_import_collision_faces.gd -- --in=C:/.../faces.f32 --out=res://scenes/xxx.scn [--cut=1.0] [--max-ny=1.0] [--force]
##
## --cut  ：三角形最高顶点低于这个值就删（米，世界坐标；0 = 不删）
## --max-ny：只留 |法线 y| ≤ 这个值的三角形（1 = 全留）

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var in_path := "C:/Users/WY157/Desktop/GODOT/_arisu_captures/collision_faces_plane.f32"
	var out_path := "res://scenes/campus_collision_mesh_tight.scn"
	var cut := 0.0
	var max_ny := 1.0
	var force := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--in="):
			in_path = a.substr(5)
		elif a.begins_with("--out="):
			out_path = a.substr(6)
		elif a.begins_with("--cut="):
			cut = float(a.substr(6))
		elif a.begins_with("--max-ny="):
			max_ny = float(a.substr(9))
		elif a == "--force":
			force = true
	if FileAccess.file_exists(out_path) and not force:
		print("[imp] %s 已存在；覆盖请加 -- --force" % out_path)
		quit(0)
		return
	if not FileAccess.file_exists(in_path):
		print("[imp] 找不到 %s" % in_path)
		quit(1)
		return
	var bytes := FileAccess.get_file_as_bytes(in_path)
	var n := bytes.size() / 12
	if n % 3 != 0:
		print("[imp] 文件不是 3 的倍数")
		quit(1)
		return
	var f32 := bytes.to_float32_array()
	var total := f32.size() / 3
	if total % 3 != 0:
		print("[imp] 数组不是 3 的倍数")
		quit(1)
		return
	var faces := PackedVector3Array()
	faces.resize(total)
	for i in total:
		faces[i] = Vector3(f32[i * 3], f32[i * 3 + 1], f32[i * 3 + 2])

	var keep := PackedVector3Array()
	var dropped_cut := 0
	var dropped_ny := 0
	var i := 0
	while i + 2 < faces.size():
		var a: Vector3 = faces[i]
		var b: Vector3 = faces[i + 1]
		var c: Vector3 = faces[i + 2]
		var top := maxf(a.y, maxf(b.y, c.y))
		if cut > 0.0 and top < cut:
			dropped_cut += 1
		else:
			var ny := absf((b - a).cross(c - a).normalized().y)
			if ny > max_ny:
				dropped_ny += 1
			else:
				keep.append(a); keep.append(b); keep.append(c)
		i += 3
	print("[imp] 读 %d 三角 → 留 %d（贴地删 %d / 斜面删 %d）"
		% [total / 3, keep.size() / 3, dropped_cut, dropped_ny])

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(keep)
	var body := StaticBody3D.new()
	body.name = "CampusCollision"
	var cs := CollisionShape3D.new()
	cs.name = "Collision"
	cs.shape = shape
	body.add_child(cs)
	var root_node := Node3D.new()
	root_node.name = "CampusCollision"
	root_node.add_child(body)
	_own(root_node, root_node)
	var ps := PackedScene.new()
	var err := ps.pack(root_node)
	if err != OK:
		print("[imp] pack 失败 %d" % err)
		quit(1)
		return
	err = ResourceSaver.save(ps, out_path)
	print("[imp] %s ← %d 三角（%.1f MB）err=%d"
		% [out_path, keep.size() / 3,
			float(FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(out_path)).size()) / 1048576.0, err])
	quit(0)


func _own(n: Node, root_node: Node) -> void:
	for c in n.get_children():
		c.owner = root_node
		_own(c, root_node)
