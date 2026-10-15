extends SceneTree
## 对比「AABB 口径」与「骨架口径」的身高，确认哪个才是可信的度量。
##
## 运行：
##   & $godot --headless --path <_arisu_learn> --script res://scripts/_probe_height_metric.gd

const FILES := [
	"res://models/companions/Kei.glb",
	"res://models/companions/Kei_ext.glb",
	"res://models/companions/Mika.glb",
	"res://models/companions/Yuuka.glb",
	"res://models/companions/Noa.glb",
]


func _init() -> void:
	_run()


func _run() -> void:
	print("=== 身高度量口径对比 ===")
	print("%-42s %10s %10s" % ["模型", "AABB 口径", "骨架口径"])
	for path in FILES:
		if not ResourceLoader.exists(path):
			print("  !! 找不到 %s" % path)
			continue
		var scene: Node = load(path).instantiate()
		root.add_child(scene)
		await process_frame
		var aabb_h := _aabb_height(scene)
		var skel_h := _skel_height(scene)
		print("%-42s %10.3f %10.3f" % [path.get_file(), aabb_h, skel_h])
		scene.queue_free()
		await process_frame
	print("")
	print("=== 完毕 ===")
	quit(0)


func _aabb_height(node: Node3D) -> float:
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


## 骨架口径：所有骨头世界位置在 Y 上的跨度（对蒙皮模型才反映真实身高）
func _skel_height(node: Node3D) -> float:
	var sk: Skeleton3D = null
	for s in _all(node, "Skeleton3D"):
		sk = s as Skeleton3D
		if sk.find_bone("Bip001 Pelvis") >= 0 or sk.get_bone_count() > 50:
			break
	if sk == null or sk.get_bone_count() == 0:
		return -1.0
	var lo := 1e9
	var hi := -1e9
	for i in sk.get_bone_count():
		var p: Vector3 = sk.global_transform * sk.get_bone_global_pose(i).origin
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	return hi - lo


func _all(node: Node, cls: String) -> Array:
	var out := []
	if node.is_class(cls):
		out.append(node)
	for c in node.get_children():
		out.append_array(_all(c, cls))
	return out
