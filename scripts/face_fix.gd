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


## ── 眉毛：同一张脸上叠了多层「不同表情的眉」，只留最前面那层 ──
##
## 2026-10-26 用户：「角色眉毛部分多重表情叠加了，应该是所有角色都有这个问题」。
## `_probe_brow_islands.gd` 把 Eyebrow surface 的顶点按三角形**连通块**切开量出来。
##
## ⚠️⚠️ 2026-10-26 深夜修正：**第一版判据是错的，把爱丽丝的眉毛删成了白色**。
##
##    第一版按「z 中心 `snappedf(0.01)` 分组」判层。但同一层眉毛会被切成很多**碎片**
##    （爱丽丝 16 块、`z` 全挤在 0.092~0.104），四舍五入到 0.01 之后被分成好几组，
##    于是「只留最靠前那组」把**同一层的大部分碎片**都压掉了 —— 脸上只剩下反光发白的
##    那一小块，用户看到的就是「爱丽丝变成白色眉毛」。
##
##    实测（`_probe_brow_layers.gd`，把所有块按 z 排序看**相邻间隙**）：
##
##      | 角色 | 块数 | 相邻块最大间隙 | 真实层数 |
##      |---|---|---|---|
##      | 爱丽丝 | 16 | **+0.0000**（全部互相重叠）| 1 |
##      | 小雪 | 2 | -0.0164 | 1 |
##      | 优香 | 2 | -0.0109 | 1 |
##      | 诺亚 | 4 | -0.0166 | 1 |
##      | 小桃 | 7 | +0.0000（修复前的 2 层已处理）| 1 |
##      | 小绿 | 6 | +0.0000 | 1 |
##      | 芹香 | 2 | ≤ 0 | 1 |
##      | 柚子 / 凯伊 | — | — | 1 |
##
##    也就是说：**只有真正「两层分开」的才需要删**，间隙是唯一的判据 ——
##    同一层的碎片 z 范围一定互相重叠（间隙 ≤ 0），不同层隔着厘米级。
##    修复前的 Momoi 间隙是 **7.8 cm**（z 0.680 那层 vs 0.770 那层）。
##
## 做法（两条都改）：
##   ① 判层改成「按 z 排序后，相邻块间隙 > `LAYER_GAP` 才算新的一层」；
##      只有 ≤ 1 层就**完全不动**（爱丽丝/小雪/优香/诺亚/芹香全部走这条）。
##   ② 删的方式改成**从索引里去掉那些块的三角形**，不再「把顶点塌到一点」——
##      塌平之后每个顶点的**骨骼权重不同**，蒙皮一动又把它们拉开，
##      结果就是用户看到的「残留细线」。去掉索引是彻底不画。
##
## ⚠️ 两条和 `separate_face_layers()` 一样的规矩：
##    ① 带形态键的网格跳过；
##    ② 重建时**每个 surface 的材质都要重新挂回去**，否则整块变白。

## ── 眉毛叠层去重：**已停用**（函数留着当记录，不在任何地方调用）──
##
## 2026-10-26 用户：「角色眉毛部分多重表情叠加了，应该是所有角色都有这个问题」
## → 本喵当天做了三版，**三版都栽在同一个地方**，最后撤销：
##
##   v1 按「z 中心 snappedf(0.01)」分层 → 爱丽丝 16 块被切成多层、删掉一半
##      ⇒ **白眉**（用户当天实拍）。
##   v2 改成「按 z 排序、相邻间隙 > 0.02 才算新层」，且只删索引不塌顶点
##      → 爱丽丝的眉毛在**局部 z 的 −0.11 和 +0.10 各有一组**，间隙 5.8 cm 仍然
##        被判成两层 ⇒ 还是白眉，只是这次剩 107 个三角形（原 168）。
##   v3 改成「先按局部 x 的符号分成左右，再各自按 z 切层」
##      → 爱丽丝的**左右眉本身是沿 z 分居两侧、x 都在 0 附近**，左右分组无效，
##        照样切两层 ⇒ 还是白眉。
##
## 根因：**「同侧眉毛的叠层」和「左右两条眉」在几何上长一个样** ——
## 都是「两组互不连通的、z 相隔几厘米的平面片」。只靠几何分不出来。
##
## 真要区分，得换判据（比如两组之间的**顶点数/形状是否互为镜像**，或者拿贴图 UV
## 比对「是不是同一个表情」）。在看到更硬的证据之前**不做**，宁可不改。
##
## ⚠️ 所以下面这些常量目前**没有调用者**，留着是为了记下当时的错误判据，
##    别再照着它们重写一遍。
const LAYER_GAP := 0.05
const MIN_BLOCKS_PER_LAYER := 2
const SIDE_EPS := 0.005


## 返回 {applied, meshes, layers, dropped_tris, kept_z}
static func simplify_brows(root: Node) -> Dictionary:
	var report := {"applied": false, "meshes": 0, "layers": 0, "dropped_tris": 0,
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
		var arr := am.surface_get_arrays(brow_surf)
		var islands := _islands_from(arr)
		if islands.size() < 2:
			continue
		# ① **按「左右两侧分别切层」**。
		#
		# ⚠️⚠️ 2026-10-26 第三次修：前两版都在「按 z 全排序切层」上栽了。
		#    诊断（`_diag_arislayer.gd`）把爱丽丝那 16 块按 z 排出来：
		#
		#      块 1/8/9/13/15/10/11/12  → z **−0.111 ~ −0.032**   （8 块）
		#      块 3/14/4/5/6/2/7/0     → z **+0.027 ~ +0.103**   （8 块）
		#      两组之间隔着 **5.8 cm**，按 z 排就是「2 层」→ 删掉一半 → **白眉**。
		#
		#    但那两组**不是上下叠的同一侧眉毛，而是左右两条**：这些模型的局部坐标里，
		#    左右眉分别落在 z 的两侧（不是 x）。所以「按 z 切层」从根上是错的。
		#
		#    正确判据：先把块按**局部 x 的符号**分成左/右两组，**每组内部**再按 z 切层。
		#    真正的「叠层」（小桃修复前 z 0.680 vs 0.770）是**同一侧**上出现两条，
		#    左右分组之后依然能分出来；而「左右两条」各自只剩一层，不会被误删。
		var sides := {}
		for i in islands.size():
			var cx: float = ((islands[i]["lo"] as Vector3).x + (islands[i]["hi"] as Vector3).x) * 0.5
			var key := "L" if cx < -SIDE_EPS else ("R" if cx > SIDE_EPS else "C")
			if not sides.has(key):
				sides[key] = [] as Array
			var sg: Array = sides[key]
			sg.append(i)
			sides[key] = sg
		# 每侧各自按 z 切层；只要**任一侧**出现 2 层以上才动手
		var layers: Array = []          # 每项 = 该层的块索引数组
		var max_layers := 0
		var side_layers := {}
		for key in sides:
			var group: Array = sides[key]
			var order: Array = []
			for i in group:
				order.append(i)
			order.sort_custom(func(a, b):
				return float(islands[a]["lo"].z) < float(islands[b]["lo"].z))
			var stacks: Array = []
			var cur: Array = []
			var cur_hi := -1e9
			for i in order:
				var lo: float = (islands[i]["lo"] as Vector3).z
				var hi: float = (islands[i]["hi"] as Vector3).z
				if not cur.is_empty() and lo - cur_hi > LAYER_GAP:
					stacks.append(cur)
					cur = []
					cur_hi = -1e9
				cur.append(i)
				cur_hi = maxf(cur_hi, hi)
			if not cur.is_empty():
				stacks.append(cur)
			side_layers[key] = stacks
			max_layers = maxi(max_layers, stacks.size())
		if max_layers < 2:
			continue          # 两侧都只有一层 → 一个顶点都不动
		# ② 每一侧**只留最靠前那层**（z 最大），其余层的**索引**整段去掉
		var drop_verts := {}
		for key in side_layers:
			var stacks: Array = side_layers[key]
			if stacks.size() < 2:
				continue
			for li in stacks.size() - 1:
				for i in (stacks[li] as Array):
					for vi in (islands[i]["verts"] as PackedInt32Array):
						drop_verts[vi] = true
			layers.append(stacks[stacks.size() - 1])
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var kept := PackedInt32Array()
		var drop_tris := 0
		var t := 0
		while t + 2 < idx.size():
			var a := idx[t]
			var b := idx[t + 1]
			var c := idx[t + 2]
			if drop_verts.has(a) or drop_verts.has(b) or drop_verts.has(c):
				drop_tris += 1
			else:
				kept.append(a)
				kept.append(b)
				kept.append(c)
			t += 3
		if drop_tris == 0:
			continue
		arr[Mesh.ARRAY_INDEX] = kept
		# 重建整只网格（只换 brow 那一层的索引，其余 surface 原样搬）
		var out := ArrayMesh.new()
		for s in am.get_surface_count():
			var mat2 := am.surface_get_material(s)
			var a2 := arr if s == brow_surf else am.surface_get_arrays(s)
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a2)
			out.surface_set_material(out.get_surface_count() - 1, mat2)
		out.set_meta(META_BROWS, true)
		mi.mesh = out
		report["meshes"] = int(report["meshes"]) + 1
		report["layers"] = int(report["layers"]) + layers.size()
		report["dropped_tris"] = int(report["dropped_tris"]) + drop_tris
		var names: Array = report.get("mesh_names", [])
		names.append("%s[%d层,删%d三角]" % [String(mi.name), layers.size(), drop_tris])
		report["mesh_names"] = names
		var kz: Array = report["kept_z"]
		kz.append(snappedf((islands[(layers[layers.size() - 1] as Array)[0]]["lo"] as Vector3).z,
			0.001))
		report["kept_z"] = kz
	report["applied"] = int(report["meshes"]) > 0
	return report


const META_BROWS := "face_fix_brows"


## 某只 surface 的顶点按三角形连成的**连通块**（从 `surface_get_arrays()` 的结果直接算）。
## 返回 [{verts: PackedInt32Array, lo: Vector3, hi: Vector3}]。
##
## ⚠️ **只看被索引引用到的顶点**。`simplify_brows()` 是「只删索引、不删顶点」——
##    删完之后剩下的顶点里会有一批**不再被任何三角形引用**的孤儿点，
##    它们各自成一个单点集合，会让块数暴涨（实测爱丽丝 16 → 96）、
##    而且每个孤儿点的 z 各不相同，于是被误判成「很多层」。
##    这一段就是那个坑的补丁。
static func _islands_from(arr: Array) -> Array:
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
	# 只收集**被索引引用到的**顶点（孤儿点不算块，见上面 ⚠️）
	var used := {}
	for t3 in idx:
		used[t3] = true
	var groups := {}
	for i in used:
		var r := _root(parent, int(i))
		if not groups.has(r):
			groups[r] = PackedInt32Array()
		var g: PackedInt32Array = groups[r]
		g.append(int(i))
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
