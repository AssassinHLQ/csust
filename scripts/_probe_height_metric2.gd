extends SceneTree
## 量三个候选口径，找出一个「与节点朝向、与当前姿态都无关」的身高度量。
##   1. AABB 口径（原来的）
##   2. 骨架 rest 骨头在**骨架局部空间**的 Y 跨度   ← 候选
##   3. 骨架当前姿态在世界空间的 Y 跨度
##
## 运行：
##   & $godot --headless --path <_arisu_learn> --script res://scripts/_probe_height_metric2.gd

const FILES := [
	"res://models/companions/Kei.glb",
	"res://models/companions/Kei_ext.glb",
	"res://models/companions/Mika.glb",
	"res://models/companions/Yuuka.glb",
	"res://models/companions/Noa.glb",
	"res://models/companions/Momoi.glb",
	"res://models/companions/Midori.glb",
	"res://models/companions/Yuzu.glb",
]


func _init() -> void:
	_run()


func _run() -> void:
	print("=== 身高度量口径对比 ===")
	print("%-16s %10s %14s %14s %8s" % ["模型", "AABB", "骨架rest局部", "骨架世界", "骨头数"])
	for path in FILES:
		if not ResourceLoader.exists(path):
			continue
		var scene: Node = load(path).instantiate()
		root.add_child(scene)
		await process_frame
		var sk := _best(scene)
		var n := 0
		if sk != null:
			n = sk.get_bone_count()
		print("%-16s %10.3f %14.3f %14.3f %8d" % [
			path.get_file(), _aabb(scene), _rest_local(sk), _posed_world(sk), n])
		scene.queue_free()
		await process_frame
	print("")
	print("=== 完毕 ===")
	quit(0)


func _aabb(node: Node3D) -> float:
	var to_local := node.global_transform.affine_inverse()
	var out := AABB()
	var first := true
	for m in _all(node, "VisualInstance3D"):
		var vi := m as VisualInstance3D
		if not vi.visible:
			continue
		var b: AABB = to_local * (vi.global_transform * vi.get_aabb())
		if b.size.length() <= 0.0001:
			continue
		out = b if first else out.merge(b)
		first = false
	return out.size.y


func _rest_local(sk: Skeleton3D) -> float:
	if sk == null or sk.get_bone_count() == 0:
		return -1.0
	var lo := 1e9
	var hi := -1e9
	for i in sk.get_bone_count():
		var p := sk.get_bone_rest(i).origin
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	return hi - lo


func _posed_world(sk: Skeleton3D) -> float:
	if sk == null or sk.get_bone_count() == 0:
		return -1.0
	var lo := 1e9
	var hi := -1e9
	for i in sk.get_bone_count():
		var p: Vector3 = sk.global_transform * sk.get_bone_global_pose(i).origin
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	return hi - lo


func _best(node: Node) -> Skeleton3D:
	var best: Skeleton3D = null
	for s in _all(node, "Skeleton3D"):
		var sk := s as Skeleton3D
		if best == null or sk.get_bone_count() > best.get_bone_count():
			best = sk
	return best


func _all(node: Node, cls: String) -> Array:
	var out := []
	if node.is_class(cls):
		out.append(node)
	for c in node.get_children():
		out.append_array(_all(c, cls))
	return out
