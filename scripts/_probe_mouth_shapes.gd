extends SceneTree
## 探针：`Mouth_*` 这 10 块嘴到底是怎么「藏起来」的，以及 `FaceFix` 有没有把它们弄坏。
##
## 三个问题，一次量清楚：
##   1. morph_0 = 1.0 到底是「缩成一点」还是「张嘴」？（直接算 基础顶点 + 形变×权重 的包围盒）
##   2. 嘴用的材质叫什么 —— 会不会被 `FaceFix` 的 `EyeMouth` 关键字命中？
##   3. 走一遍 `FaceFix.separate_face_layers()` 之后，这些网格**还有没有形态键**？
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_mouth_shapes.gd

const MODEL := "res://models/Arisu_ext.glb"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var inst: Node3D = (load(MODEL) as PackedScene).instantiate()
	root.add_child(inst)
	await process_frame

	var mouths := _meshes_named(inst, "Mouth_")
	print("[probe] Mouth_* 网格 %d 块" % mouths.size())
	for mi in mouths:
		_dump(mi)

	print("\n===== 关掉权重：morph_0 = 0 时的实际尺寸 =====")
	for mi in mouths:
		mi.set_blend_shape_value(0, 0.0)
		print("  %-12s -> %s" % [mi.name, _blended_aabb(mi).size.snappedf(0.0001)])
	print("\n===== 打开权重：morph_0 = 1 时的实际尺寸 =====")
	for mi in mouths:
		mi.set_blend_shape_value(0, 1.0)
		print("  %-12s -> %s" % [mi.name, _blended_aabb(mi).size.snappedf(0.0001)])

	# 身体网格上的材质清单：谁带 EyeMouth？
	print("\n===== 带材质名的网格 =====")
	for mi in _all_meshes(inst):
		var mats: Array[String] = []
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			mats.append("<无>" if mat == null else str(mat.resource_name))
		print("  %-24s blend=%d  %s" % [
			mi.name, mi.mesh.get_blend_shape_count(), " | ".join(mats)])

	# FaceFix 之后还剩几个形态键？
	var rep := FaceFix.separate_face_layers(inst)
	print("\n===== FaceFix 之后（推了 %d 个 surface / %d 顶点 / %d 个网格）=====" % [
		int(rep["surfaces"]), int(rep["verts"]), int(rep["meshes"])])
	for mi in _meshes_named(inst, "Mouth_"):
		var n := -1
		var m := mi.mesh
		if m != null:
			n = m.get_blend_shape_count()
		print("  %-12s blend_shapes=%d  surface=%d" % [
			mi.name, n, -1 if m == null else m.get_surface_count()])
	quit(0)


func _dump(mi: MeshInstance3D) -> void:
	var m := mi.mesh
	var mats: Array[String] = []
	for s in m.get_surface_count():
		var mat := m.surface_get_material(s)
		mats.append("<无>" if mat == null else str(mat.resource_name))
	print("  %-12s surface=%d blend_shapes=%d 形态键名=%s 材质=%s 可见=%s" % [
		mi.name, m.get_surface_count(), m.get_blend_shape_count(),
		str(_shape_names(m)), " | ".join(mats), str(mi.visible)])
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var base: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		print("       s%d 顶点 %d  基础包围盒 %s" % [
			s, base.size(), _aabb_of(base).size.snappedf(0.0001)])
		var bs := m.surface_get_blend_shape_arrays(s)
		for k in bs.size():
			var d: PackedVector3Array = bs[k][Mesh.ARRAY_VERTEX]
			var out: PackedVector3Array = []
			out.resize(base.size())
			for i in base.size():
				out[i] = base[i] + (d[i] if i < d.size() else Vector3.ZERO)
			print("         shape%d 顶点 %d  全开包围盒 %s  位移长度 %.4f m" % [
				k, d.size(), _aabb_of(out).size.snappedf(0.0001), _mean_len(d)])


func _blended_aabb(mi: MeshInstance3D) -> AABB:
	var m := mi.mesh
	var out := AABB()
	var first := true
	for s in m.get_surface_count():
		var base: PackedVector3Array = m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		var w := mi.get_blend_shape_value(0) if m.get_blend_shape_count() > 0 else 0.0
		var bs := m.surface_get_blend_shape_arrays(s)
		var v := base
		if bs.size() > 0 and w != 0.0:
			var d: PackedVector3Array = bs[0][Mesh.ARRAY_VERTEX]
			v = []
			v.resize(base.size())
			for i in base.size():
				v[i] = base[i] + (d[i] if i < d.size() else Vector3.ZERO) * w
		var b := _aabb_of(v)
		out = b if first else out.merge(b)
		first = false
	return out


func _shape_names(m: Mesh) -> Array[String]:
	var out: Array[String] = []
	for i in m.get_blend_shape_count():
		out.append(m.get_blend_shape_name(i))
	return out


func _mean_len(arr: PackedVector3Array) -> float:
	if arr.is_empty():
		return 0.0
	var s := 0.0
	for v in arr:
		s += v.length()
	return s / float(arr.size())


func _aabb_of(v: PackedVector3Array) -> AABB:
	if v.is_empty():
		return AABB()
	var out := AABB(v[0], Vector3.ZERO)
	for p in v:
		out = out.expand(p)
	return out


func _meshes_named(n: Node, prefix: String) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for m in _all_meshes(n):
		if m.name.begins_with(prefix):
			out.append(m)
	return out


func _all_meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		if x is MeshInstance3D and (x as MeshInstance3D).mesh != null:
			out.append(x as MeshInstance3D)
		for c in x.get_children():
			stack.append(c)
	return out
