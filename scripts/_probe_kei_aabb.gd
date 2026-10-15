extends SceneTree
## 逐个网格对比 Kei.glb / Kei_ext.glb 的包围盒，找出「视觉高度 1.71 → 0.59」是哪来的。
##
## 运行：
##   & $godot --headless --path <_arisu_learn> --script res://scripts/_probe_kei_aabb.gd

const FILES := ["res://models/companions/Kei.glb", "res://models/companions/Kei_ext.glb"]


func _init() -> void:
	_run()


func _run() -> void:
	print("=== 逐网格包围盒对比（Kei）===")
	for path in FILES:
		var packed: PackedScene = load(path)
		var scene: Node = packed.instantiate()
		root.add_child(scene)
		await process_frame
		print("")
		print(path)
		var merged := AABB()
		var first := true
		for m in _all_mesh(scene):
			var vi := m as VisualInstance3D
			var b: AABB = vi.get_aabb()
			var gt := vi.global_transform
			var wb: AABB = gt * b
			var sz := wb.size
			var pos := wb.position
			print("  %-26s visible=%-5s 局部尺寸 %s  世界尺寸 %s  世界中心 %s  scale=%s" % [
				vi.name, str(vi.visible),
				_v(b.size), _v(sz), _v(pos + sz * 0.5), _v(gt.basis.get_scale())])
			if vi.visible and sz.length() > 0.0001:
				merged = wb if first else merged.merge(wb)
				first = false
		print("  >>> 合并世界 AABB：尺寸 %s  中心 %s" % [
			_v(merged.size), _v(merged.position + merged.size * 0.5)])
		scene.queue_free()
		await process_frame
	print("")
	print("=== 完毕 ===")
	quit(0)


func _v(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]


func _all_mesh(node: Node) -> Array:
	var out := []
	if node is VisualInstance3D and not (node is Skeleton3D) and not (node is BoneAttachment3D):
		out.append(node)
	for c in node.get_children():
		out.append_array(_all_mesh(c))
	return out
