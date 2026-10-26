class_name FaceFix
extends RefCounted
## 把「贴在脸上的那一层」沿法线推开一点点，解决 z-fighting。
##
## ── 为什么需要 ──
## 爱丽丝的 `Aris_Original_Body` 一个网格上挂了 5 个材质，其中
## `Aris_Original_Face`（脸皮，不透明）和 `Aris_Original_EyeMouth`（眼睛+嘴，`alphaMode = MASK`）
## 是**贴在同一张脸上的两层**，都 `doubleSided`、几何几乎共面。
## 两个面在同一深度上互相抢 → 眼睛/眼睑那一圈会出现「双层线」，用户说的「双眼皮打架」。
##
## ── 为什么是推法线，而不是 render_priority / 关深度测试 ──
## * `render_priority` 只对**半透明**材质有效，MASK（alpha 剪切）走的是不透明队列；
## * 关 `depth_test` 会让眼睛直接盖到头发和手上 —— 换个角度就穿帮。
## 唯一稳的办法是让两层**真的不在同一个深度**上：把上面那层沿法线外推一个极小量。
## 推的量是「网格高度的万分之几」—— 0.8/10000 × 1.7 m ≈ 0.14 mm，肉眼看不出来，
## 但足够让深度值拉开。
##
## 用法：
##   FaceFix.separate_face_layers(model_root)   # 载入模型之后调一次
##
## ⚠️ **带形态键（blend shape）的网格一律跳过。**
##    爱丽丝那 10 块 `Mouth_*` 用的是 `Aris_Original_EyeMouth_Mouth_70x` 材质，
##    名字里带 `EyeMouth`，会被下面的关键字命中；而它们正是靠 `target_0`
##    把自己**整体挪走 0.6 m** 藏起来的（探针实测位移长度 0.6033 m）。
##    `add_surface_from_arrays()` 只搬顶点/法线/UV，**不搬 blend shape** ——
##    重建一次，形态键就没了，10 张嘴会全部贴回脸上。用户报的「多个嘴巴网格重叠」
##    就是这个（实测：FaceFix 之后 10 块 Mouth_* 的 `blend_shapes` 全变 0）。

## 这些材质算「贴在脸上的层」，要往前推
const LAYER_KEYWORDS := ["EyeMouth", "Eyebrow"]


## 返回 {surfaces:int, verts:int, meshes:int, skipped:int} 报告，自检可以读。
static func separate_face_layers(root: Node, ratio := 0.0008) -> Dictionary:
	var report := {"surfaces": 0, "verts": 0, "meshes": 0, "skipped": 0}
	if root == null:
		return report
	for mi in _all_meshes(root):
		var m := mi.mesh
		if not (m is ArrayMesh):
			continue
		# ⚠️ 见文件头：形态键搬不过去，带形态键的网格**绝不能**重建
		if m.get_blend_shape_count() > 0:
			report["skipped"] = int(report["skipped"]) + 1
			continue
		var box := mi.get_aabb()
		var push := maxf(box.size.y * ratio, 0.00001)
		var touched := 0
		var out := ArrayMesh.new()
		for s in m.get_surface_count():
			var mat := m.surface_get_material(s)
			var name := "" if mat == null else mat.resource_name
			var arr := m.surface_get_arrays(s)
			if _is_face_layer(name):
				var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
				if normals.size() == verts.size():
					for i in verts.size():
						verts[i] = verts[i] + normals[i] * push
					arr[Mesh.ARRAY_VERTEX] = verts
					report["verts"] = int(report["verts"]) + verts.size()
					touched += 1
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			out.surface_set_material(out.get_surface_count() - 1, mat)
		if touched > 0:
			mi.mesh = out
			report["meshes"] = int(report["meshes"]) + 1
			report["surfaces"] = int(report["surfaces"]) + touched
	return report


static func _is_face_layer(mat_name: String) -> bool:
	for k in LAYER_KEYWORDS:
		if mat_name.contains(k):
			return true
	return false


## ── 眉毛：同一张脸上叠了 2~3 层「不同表情的眉」，只留最前面那层 ──
##
## 2026-10-26 用户：「角色眉毛部分多重表情叠加了，应该是所有角色都有这个问题」。
## `_probe_brow_islands.gd` 把 `EyeBrow`/`Eyebrow` surface 的顶点按三角形**连通块**
## 切开，量出来（局部坐标，这些模型朝 +Z，z 越大越靠前）：
##
##   Serika  2 块、**1 层**：z 0.785~0.799                ← 正常（左右各一条）
##   Momoi   7 块、**2 层**：z 0.680~0.684 / 0.762~0.777
##   Midori  6 块、**3 层**：z 0.732~0.739 / 0.750~0.753 / 0.769~0.774
##
## 也就是说这些模型把**多个表情的眉毛叠在不同深度上**（原游戏是换网格选表情，
## 导出的 glb 里没人把它们藏起来），于是脸上同时画着 2~3 条眉。
## 出图对照：`_arisu_captures/_fix1026/brow_momoi_0_原样.png`（两条眉清清楚楚）。
##
## 做法：**只保留最靠前那一层**，其余层的顶点**全部塌到保留层的质心** ——
## 塌成零面积三角形就不再渲染，但**顶点数不变、蒙皮数据不动**（比删顶点安全）。
##
## ⚠️ 两条和 `separate_face_layers()` 一样的规矩：
##    ① 带形态键的网格跳过；
##    ② 重建时**每个 surface 的材质都要重新挂回去**，否则整块变白。
##
## 返回 {applied, meshes, layers, collapsed, kept_z}
static func simplify_brows(root: Node, layer_eps := 0.01) -> Dictionary:
	var report := {"applied": false, "meshes": 0, "layers": 0, "collapsed": 0,
		"kept_z": [] as Array}
	if root == null:
		return report
	for mi in _all_meshes(root):
		var am := mi.mesh as ArrayMesh
		if am == null:
			continue
		if am.get_blend_shape_count() > 0:
			continue
		var brow_surf := -1
		for s in am.get_surface_count():
			var mat := am.surface_get_material(s)
			if mat != null and String(mat.resource_name).to_lower().contains("brow"):
				brow_surf = s
				break
		if brow_surf < 0:
			continue
		var islands := _islands(am, brow_surf)
		if islands.size() < 3:
			continue          # 左右各一条（2 块）就是正常的一层，不碰
		# 按 z 中心分层
		var layers := {}
		for i in islands.size():
			var lo: Vector3 = islands[i]["lo"]
			var hi: Vector3 = islands[i]["hi"]
			var key := "%.2f" % snappedf((lo.z + hi.z) * 0.5, layer_eps)
			if not layers.has(key):
				layers[key] = [] as Array
			var g: Array = layers[key]
			g.append(i)
			layers[key] = g
		if layers.size() < 2:
			continue          # 只有一层 → 不用修
		var keys := layers.keys()
		keys.sort()
		var keep_key: String = keys[keys.size() - 1]      # z 最大 = 最靠前
		var keep: Array = layers[keep_key]
		var centre := Vector3.ZERO
		for i in keep:
			centre += ((islands[i]["lo"] as Vector3) + (islands[i]["hi"] as Vector3)) * 0.5
		centre /= float(keep.size())
		# 重建整只网格：只动 brow 那一层，其余 surface 原样搬过去
		var out := ArrayMesh.new()
		for s in am.get_surface_count():
			var mat := am.surface_get_material(s)
			var arr := am.surface_get_arrays(s)
			if s == brow_surf:
				var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var n := 0
				for i in islands.size():
					if keep.has(i):
						continue
					var vi: PackedInt32Array = islands[i]["verts"]
					for k in vi:
						vs[k] = centre
					n += vi.size()
				arr[Mesh.ARRAY_VERTEX] = vs
				report["collapsed"] = int(report["collapsed"]) + n
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			out.surface_set_material(out.get_surface_count() - 1, mat)
		am.set_meta(META_BROWS, true)
		# ⚠️ 赋给 **MeshInstance3D**（`mi`），不是赋给 ArrayMesh 自己 ——
		#    写成 `m.mesh = out`（`m` 已经是 mesh）会报
		#    「Invalid assignment of property or key 'mesh' ... on ArrayMesh」。
		mi.mesh = out
		report["meshes"] = int(report["meshes"]) + 1
		report["layers"] = int(report["layers"]) + layers.size()
		var kz: Array = report["kept_z"]
		kz.append(keys[keys.size() - 1])
		report["kept_z"] = kz
	report["applied"] = int(report["meshes"]) > 0
	return report


const META_BROWS := "face_fix_brows"


## 某只 surface 的顶点按三角形连成的**连通块**。
## 返回 [{verts: PackedInt32Array, lo: Vector3, hi: Vector3}]，按 y 从大到小排。
static func _islands(am: ArrayMesh, surf: int) -> Array:
	var arr := am.surface_get_arrays(surf)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	if vs.is_empty():
		return []
	var parent := PackedInt32Array()
	parent.resize(vs.size())
	for i in vs.size():
		parent[i] = i
	var t := 0
	while t + 2 < idx.size():
		var a := _root(parent, idx[t])
		var b := _root(parent, idx[t + 1])
		var c := _root(parent, idx[t + 2])
		var mn := mini(a, mini(b, c))
		parent[a] = mn
		parent[b] = mn
		parent[c] = mn
		t += 3
	var groups := {}
	for i in vs.size():
		var r := _root(parent, i)
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
	return out


static func _root(p: PackedInt32Array, i: int) -> int:
	while p[i] != i:
		p[i] = p[p[i]]
		i = p[i]
	return i


static func _all_meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		if x is MeshInstance3D and (x as MeshInstance3D).mesh != null:
			out.append(x as MeshInstance3D)
		for c in x.get_children():
			stack.append(c)
	return out
