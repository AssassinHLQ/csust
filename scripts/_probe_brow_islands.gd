extends SceneTree
## 拆眉毛：把 `EyeBrow` 这个 surface 里的**连通块**分出来，看清楚脸上到底有几条眉。
##   godot --path . --script res://scripts/_probe_brow_islands.gd -- --splat=off
##
## 背景（用户 2026-10-26）：「角色眉毛部分多重表情叠加了，应该是所有角色都有这个问题」。
## `_probe_face_layers.gd` 量到 Momoi 的 `EyeBrow` surface 只有 50 个顶点，但**纵向跨
## 0.108 m**（Midori 同样一条是 0.056）—— 八成正脸图里那「两条眉」都在这一个 surface 上。
## 本探针：
##   ① 用并查集把该 surface 的顶点按三角形连成**连通块**，逐块报包围盒；
##   ② 出图对照：原样 / 整块藏掉 / 只留第 k 块（其余顶点塌成一点 = 零面积三角形，不渲染）。
##      「塌成一点」不删顶点，所以蒙皮数据不动 —— 用在这个场景最稳。

const OUT := "_arisu_captures/_fix1026"
var _out_abs := ""


func _initialize() -> void:
	_run.call_deferred()


func _shot(cam: Camera3D, nm: String) -> void:
	cam.make_current()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [_out_abs, nm])


## 并查集
func _find(p: PackedInt32Array, i: int) -> int:
	while p[i] != i:
		p[i] = p[p[i]]
		i = p[i]
	return i


## 把某个 surface 按三角形连通块切开。返回 [{verts:PackedInt32Array, lo:Vector3, hi:Vector3}]
func _islands(am: ArrayMesh, surf: int) -> Array:
	var arr := am.surface_get_arrays(surf)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var parent := PackedInt32Array()
	parent.resize(vs.size())
	for i in vs.size():
		parent[i] = i
	if idx.size() >= 3:
		var t := 0
		while t + 2 < idx.size():
			var a := _find(parent, idx[t])
			var b := _find(parent, idx[t + 1])
			var c := _find(parent, idx[t + 2])
			var m := mini(a, mini(b, c))
			parent[a] = m
			parent[b] = m
			parent[c] = m
			t += 3
	var groups := {}
	for i in vs.size():
		var r := _find(parent, i)
		if not groups.has(r):
			groups[r] = PackedInt32Array()
		var g: PackedInt32Array = groups[r]
		g.append(i)
		groups[r] = g
	var out: Array = []
	for k in groups:
		var g2: PackedInt32Array = groups[k]
		var lo := Vector3(1e9, 1e9, 1e9)
		var hi := Vector3(-1e9, -1e9, -1e9)
		for i in g2:
			var v := vs[i]
			lo = Vector3(minf(lo.x, v.x), minf(lo.y, v.y), minf(lo.z, v.z))
			hi = Vector3(maxf(hi.x, v.x), maxf(hi.y, v.y), maxf(hi.z, v.z))
		out.append({"verts": g2, "lo": lo, "hi": hi})
	out.sort_custom(func(x, y): return float(x["hi"].y) > float(y["hi"].y))
	return out


func _find_brow_surface(node: Node3D) -> Array:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not (m.mesh is ArrayMesh):
			continue
		var am := m.mesh as ArrayMesh
		for s in am.get_surface_count():
			var mat := am.surface_get_material(s)
			if mat != null and String(mat.resource_name).to_lower().contains("brow"):
				return [m, am, s]
	return []


## 只留第 keep 块：其余块的顶点**全部塌到该块质心**
func _keep_island(am: ArrayMesh, surf: int, islands: Array, keep: int) -> void:
	var arr := am.surface_get_arrays(surf)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var centre: Vector3 = (islands[keep]["lo"] as Vector3 + islands[keep]["hi"] as Vector3) * 0.5
	for i in islands.size():
		if i == keep:
			continue
		for vi in (islands[i]["verts"] as PackedInt32Array):
			vs[vi] = centre
	arr[Mesh.ARRAY_VERTEX] = vs
	am.clear_surfaces()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	# ⚠️ `clear_surfaces()` 之后 material 要重新挂回去，否则整块变白
	#    （调用方在外面重新 set，见 `_run`）


func _run() -> void:
	root.size = Vector2i(900, 700)
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(game)
	for _i in 130:
		await process_frame
	paused = false
	var out := ProjectSettings.globalize_path("res://").path_join("..").simplify_path() \
		.path_join(OUT)
	DirAccess.make_dir_recursive_absolute(out)
	_out_abs = out
	for c in game.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
	for c in game.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false

	var targets: Array = []
	for nm in ["CompanionMomoi", "CompanionMidori", "Shop/ClerkSerika"]:
		var nd := game.get_node_or_null(nm) as Node3D
		if nd != null:
			targets.append([nm.replace("/", "_"), nd])
	var cam := Camera3D.new()
	cam.near = 0.01
	cam.far = 400.0
	root.add_child(cam)

	for t in targets:
		var nd := t[1] as Node3D
		var hit := _find_brow_surface(nd)
		if hit.is_empty():
			print("\n── %s：找不到 Eyebrow surface" % String(t[0]))
			continue
		var m := hit[0] as MeshInstance3D
		var am := hit[1] as ArrayMesh
		var surf := int(hit[2])
		var mat := am.surface_get_material(surf)
		var isl := _islands(am, surf)
		print("\n── %s：`%s` 第 %d 个 surface（材质 %s），连通块 %d 块"
			% [String(t[0]), String(m.name), surf,
				"—" if mat == null else String(mat.resource_name), isl.size()])
		for i in isl.size():
			var lo: Vector3 = isl[i]["lo"]
			var hi: Vector3 = isl[i]["hi"]
			print("    块 %d：顶点 %3d  y %+.3f~%+.3f（高 %.3f）  x %+.3f~%+.3f  z %+.3f~%+.3f"
				% [i, (isl[i]["verts"] as PackedInt32Array).size(),
					lo.y, hi.y, hi.y - lo.y, lo.x, hi.x, lo.z, hi.z])

	# 只对 Momoi 出对照图（她的眉最典型）
	var momoi := game.get_node_or_null("CompanionMomoi") as Node3D
	if momoi == null:
		print("\n[错误] 没有 CompanionMomoi")
		quit(1)
		return
	var skels := momoi.find_children("*", "Skeleton3D", true, false)
	var head := Vector3.ZERO
	if not skels.is_empty():
		var skel := skels[0] as Skeleton3D
		for i in skel.get_bone_count():
			var bn := skel.get_bone_name(i)
			if bn == "Bip001 Head" or bn.to_lower().ends_with("head"):
				head = skel.global_transform * skel.get_bone_global_pose(i).origin
				break
	# 她的正脸在 −Z 侧（`face_CompanionMomoi_N.png` 是正脸）
	cam.fov = 26.0
	cam.global_position = head + Vector3(0.0, 0.03, -0.62)
	cam.look_at(head + Vector3(0, -0.02, 0), Vector3.UP)
	await _shot(cam, "brow_momoi_0_原样")

	var hit2 := _find_brow_surface(momoi)
	var m2 := hit2[0] as MeshInstance3D
	var am2 := hit2[1] as ArrayMesh
	var surf2 := int(hit2[2])
	var mat2 := am2.surface_get_material(surf2)
	var isl2 := _islands(am2, surf2)

	# ② 整块藏掉
	var invisible := StandardMaterial3D.new()
	invisible.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	invisible.albedo_color = Color(1, 1, 1, 0)
	invisible.no_depth_test = true
	am2.surface_set_material(surf2, invisible)
	for _f in 3:
		await process_frame
	await _shot(cam, "brow_momoi_1_整块藏掉")
	am2.surface_set_material(surf2, mat2)

	# ③ 一层一层单独留：按「连通块的 z 中心」分组，每组单独出一张
	var planes := {}
	for i in isl2.size():
		var zc: float = ((isl2[i]["lo"] as Vector3).z + (isl2[i]["hi"] as Vector3).z) * 0.5
		var key := "%.3f" % snappedf(zc, 0.01)
		if not planes.has(key):
			planes[key] = []
		var arr2: Array = planes[key]
		arr2.append(i)
		planes[key] = arr2
	var keys := planes.keys()
	keys.sort()
	print("\n她的眉毛一共有 %d 个「深度层」：%s" % [keys.size(), ", ".join(keys)])
	for ki in keys.size():
		var keep_set: Array = planes[keys[ki]]
		# 把不属于这一层的块塌到本层第一块的质心
		var arr3 := am2.surface_get_arrays(surf2)
		var vs3: PackedVector3Array = arr3[Mesh.ARRAY_VERTEX]
		var c: Vector3 = ((isl2[keep_set[0]]["lo"] as Vector3)
			+ (isl2[keep_set[0]]["hi"] as Vector3)) * 0.5
		for i in isl2.size():
			if keep_set.has(i):
				continue
			for vi in (isl2[i]["verts"] as PackedInt32Array):
				vs3[vi] = c
		arr3[Mesh.ARRAY_VERTEX] = vs3
		am2.clear_surfaces()
		am2.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr3)
		am2.surface_set_material(0, mat2)
		for _f in 3:
			await process_frame
		await _shot(cam, "brow_momoi_2_只留第%d层_z%s" % [ki, String(keys[ki])])

	print("\n（第 1 张 = 原样；第 2 张 = 整块藏掉；之后 = 每层单独留一张）")
	print("对照就知道哪一层是「正常表情」，其余层是要藏掉的变体")
	print("\n[截图] %s" % out)
	quit(0)
