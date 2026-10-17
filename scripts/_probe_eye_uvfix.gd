extends SceneTree
## 探针：**不渲染**，只量「右眼 UV 重映射」有没有落到左眼那张图上。
##
## 判据（可量化、不需要看图）：
##   修之前：右眼组的 UV 质心 u_R 比左眼组小 0.05~0.07；
##   修之后：每个右眼顶点的 u 被改成 `uL + uR − u`，于是**该组的 u 质心 == 左眼组**。
## 所以「修完右组质心 == 左组质心（差 < 1e-4）」就是这条修法生效的硬证据。
##
## 用法：godot --headless --path <工程> --script res://scripts/_probe_eye_uvfix.gd

const MODEL := "res://models/Arisu_ext.glb"
const BODY := "Aris_Original_Body_001"
const MIN_W := 0.2


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var inst: Node3D = (load(MODEL) as PackedScene).instantiate()
	root.add_child(inst)
	await process_frame
	var body := _find_mesh(inst, BODY)
	if body == null:
		print("!! 没找到 %s" % BODY)
		quit(1)
		return

	var before := _centroids(body)
	_print_table("修之前", before)

	var rep := EyeUvFix.mirror_right_eye_uvs(inst)
	print("\n[eyeuv] 报告：mesh=%d surface=%d vert=%d skipped=%d" % [
		int(rep["meshes"]), int(rep["surfaces"]), int(rep["verts"]), int(rep["skipped"])])
	for p in rep["pairs"]:
		print("   %-24s ← %-24s  Δu=%+.4f" % [String(p["l"]), String(p["r"]), float(p["dx"])])

	var after := _centroids(body)
	_print_table("修之后", after)

	print("\n[eyeuv] 判定：右侧各组的 u 质心应该**等于**左组")
	var ok := 0
	var bad := 0
	for k in after:
		var s := String(k)
		if not s.contains("_R") or not s.to_lower().contains("eye"):
			continue
		var l := s.replace("_R", "_L")
		if not after.has(l):
			continue
		var d := absf(float(after[s].x) - float(after[l].x))
		if d < 0.0001:
			ok += 1
		else:
			bad += 1
			print("   ✗ %-24s u=%.4f   vs %-24s u=%.4f   差 %.4f" % [
				s, float(after[s].x), l, float(after[l].x), d])
	print("   ✓ 对齐 %d 组，✗ 没对齐 %d 组" % [ok, bad])
	quit(0 if bad == 0 and ok >= 3 else 1)


func _centroids(body: MeshInstance3D) -> Dictionary:
	var skin := body.skin
	var m := body.mesh as ArrayMesh
	var acc := {}
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bs: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var ws: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var ts: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		if bs.is_empty() or ws.is_empty() or ts.is_empty():
			continue
		var per := bs.size() / maxi(vs.size(), 1)
		for v in vs.size():
			for k in per:
				var idx := v * per + k
				if idx >= bs.size() or ws[idx] < MIN_W:
					continue
				var bn := String(skin.get_bind_name(bs[idx]))
				if bn.is_empty():
					continue
				if not acc.has(bn):
					acc[bn] = Vector3.ZERO
				var a: Vector3 = acc[bn]
				acc[bn] = a + Vector3(ts[v].x, ts[v].y, 1.0)
	var out := {}
	for bn in acc:
		var a: Vector3 = acc[bn]
		out[bn] = Vector2(a.x / maxf(a.z, 1.0), a.y / maxf(a.z, 1.0))
	return out


func _print_table(tag: String, c: Dictionary) -> void:
	print("\n===== %s：眼睛各组的 UV 质心 =====" % tag)
	var keys := c.keys()
	keys.sort()
	for k in keys:
		var s := String(k)
		if not s.to_lower().contains("eye"):
			continue
		print("  %-24s (%.4f, %.4f)" % [s, float(c[k].x), float(c[k].y)])


func _find_mesh(n: Node, name_: String) -> MeshInstance3D:
	if n is MeshInstance3D and String(n.name) == name_:
		return n as MeshInstance3D
	for c in n.get_children():
		var r := _find_mesh(c, name_)
		if r != null:
			return r
	return null
