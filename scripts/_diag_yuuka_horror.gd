extends SceneTree
## 诊断：Yuuka.glb 里到底有什么（骨骼 / 动画 / 材质 / 贴图 / 包围盒）。
##
##   godot --headless --path . --script res://scripts/_diag_yuuka_horror.gd
##
## 写这个是为了定「优香-恐怖」怎么做：
##   · 有没有 AnimationPlayer → 能不能用 Normal_Idle / Normal_Attack_* / Vital_Death；
##   · 材质是不是 StandardMaterial3D、贴图在不在（决定换血红色方案）；
##   · 骨架包围盒多大（`Boss` 按骨架归一化身高）。

const MODEL := "res://models/companions/Yuuka.glb"


func _initialize() -> void:
	var res := load(MODEL)
	if res == null:
		print("!! 加载失败：%s" % MODEL)
		quit(1)
		return
	var root: Node = (res as PackedScene).instantiate()
	get_root().add_child(root)

	print("=== 节点树 ===")
	_dump(root, 0)

	print("\n=== AnimationPlayer ===")
	for ap in _find(root, "AnimationPlayer"):
		var p := ap as AnimationPlayer
		var names := p.get_animation_list()
		print("  %s：%d 条，autoplay=「%s」" % [p.get_path(), names.size(), p.autoplay])
		for n in names:
			print("    %-24s %.2f s" % [n, p.get_animation(n).length])

	print("\n=== 材质 ===")
	for mi in _find(root, "MeshInstance3D"):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var am := m.mesh as ArrayMesh
		for s in am.get_surface_count():
			var mat := am.surface_get_material(s)
			if mat is StandardMaterial3D:
				var sm := mat as StandardMaterial3D
				print("  %-16s surf %d  mat=%-40s tex=%s  transp=%d" % [
					m.name, s, sm.resource_name,
					(sm.albedo_texture.resource_path if sm.albedo_texture != null else "（无）"),
					sm.transparency])
			else:
				print("  %-16s surf %d  mat=%s" % [m.name, s,
					mat.get_class() if mat != null else "（空）"])

	print("\n=== 包围盒 ===")
	for skel in _find(root, "Skeleton3D"):
		var sk := skel as Skeleton3D
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for b in sk.get_bone_count():
			var p := sk.global_transform * sk.get_bone_global_pose(b).origin
			lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
			hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
		print("  骨架 %s：%d 骨  AABB %s ~ %s  尺寸 %s" % [
			sk.name, sk.get_bone_count(), str(lo.snappedf(0.01)),
			str(hi.snappedf(0.01)), str((hi - lo).snappedf(0.01))])

	var aabb := AABB()
	var first := true
	for mi in _find(root, "MeshInstance3D"):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var b: AABB = m.global_transform * m.mesh.get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
	if not first:
		print("  网格 AABB：%s  尺寸 %s" % [str(aabb.position.snappedf(0.01)),
			str(aabb.size.snappedf(0.01))])
	quit(0)


func _dump(n: Node, depth: int) -> void:
	print("%s%s (%s)" % ["  ".repeat(depth), n.name, n.get_class()])
	for c in n.get_children():
		_dump(c, depth + 1)


func _find(n: Node, cls: String) -> Array[Node]:
	var out: Array[Node] = []
	if n.is_class(cls):
		out.append(n)
	for c in n.get_children():
		out.append_array(_find(c, cls))
	return out
